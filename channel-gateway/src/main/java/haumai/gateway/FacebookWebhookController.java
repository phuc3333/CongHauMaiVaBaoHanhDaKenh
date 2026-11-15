package haumai.gateway;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import haumai.contract.ChannelStreams;
import haumai.contract.InboundChannelMessage;
import haumai.contract.InboundChannelReply;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.connection.stream.RecordId;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.HexFormat;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@RestController
@RequestMapping("/api/v1/facebook/webhook")
public class FacebookWebhookController {
    private static final Logger log = LoggerFactory.getLogger(FacebookWebhookController.class);
    private static final String DEAD_LETTER_STREAM = "warranty:inbound:dead-letter";
    private static final Pattern NAME = Pattern.compile("(?im)^\\s*(?:ho\\s*ten|họ\\s*tên)\\s*:\\s*(.+?)\\s*$");
    private static final Pattern PHONE = Pattern.compile("(?im)^\\s*(?:so\\s*dien\\s*thoai|số\\s*điện\\s*thoại|phone)\\s*:\\s*(.+?)\\s*$");
    private static final Pattern SERIAL = Pattern.compile("(?im)^\\s*(?:serial|so\\s*serial)\\s*:\\s*(.+?)\\s*$");
    private static final Pattern DESCRIPTION = Pattern.compile("(?ims)^\\s*(?:mo\\s*ta\\s*loi|mô\\s*tả\\s*lỗi)\\s*:\\s*(.+?)\\s*$");

    @Value("${hau-mai.facebook.verify-token:}")
    private String verifyToken;

    @Value("${hau-mai.facebook.app-secret:}")
    private String appSecret;

    @Value("${hau-mai.facebook.page-id:}")
    private String pageId;

    private final StringRedisTemplate redisTemplate;
    private final ObjectMapper objectMapper;

    public FacebookWebhookController(StringRedisTemplate redisTemplate, ObjectMapper objectMapper) {
        this.redisTemplate = redisTemplate;
        this.objectMapper = objectMapper;
    }

    @GetMapping(produces = MediaType.TEXT_PLAIN_VALUE)
    public ResponseEntity<String> verify(
        @RequestParam(name = "hub.mode", required = false) String mode,
        @RequestParam(name = "hub.verify_token", required = false) String suppliedToken,
        @RequestParam(name = "hub.challenge", required = false) String challenge
    ) {
        if (blank(verifyToken) || !"subscribe".equals(mode) || blank(challenge)
            || !constantTimeEquals(verifyToken, suppliedToken)) {
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body("Verification failed");
        }
        return ResponseEntity.ok(challenge);
    }

    @PostMapping(consumes = MediaType.APPLICATION_JSON_VALUE, produces = MediaType.APPLICATION_JSON_VALUE)
    public ResponseEntity<WebhookResponse> receive(
        @RequestHeader(value = "X-Hub-Signature-256", required = false) String signature,
        @RequestBody byte[] requestBody
    ) {
        if (blank(appSecret)) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Facebook webhook chưa được cấu hình");
        }
        String rawBody = new String(requestBody, StandardCharsets.UTF_8);
        if (!isValidSignature(signature, rawBody, appSecret)) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Chữ ký webhook Facebook không hợp lệ");
        }

        JsonNode event;
        try {
            event = objectMapper.readTree(requestBody);
        } catch (IOException ex) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Webhook body không phải JSON hợp lệ", ex);
        }
        if (!"page".equals(text(event, "object"))) {
            return ResponseEntity.ok(new WebhookResponse("ignored", 0));
        }

        int queued = 0;
        JsonNode entries = event.path("entry");
        if (entries.isArray()) {
            for (JsonNode entry : entries) {
                String entryPageId = text(entry, "id");
                if (!blank(pageId) && !pageId.equals(entryPageId)) {
                    log.warn("Bỏ qua Facebook webhook của Page khác, pageId={}", entryPageId);
                    continue;
                }
                JsonNode messaging = entry.path("messaging");
                if (!messaging.isArray()) continue;
                for (JsonNode item : messaging) {
                    queued += processMessage(item);
                }
            }
        }
        return ResponseEntity.ok(new WebhookResponse("accepted", queued));
    }

    private int processMessage(JsonNode item) {
        JsonNode message = item.path("message");
        if (!message.isObject() || message.path("is_echo").asBoolean(false)) return 0;
        String senderId = text(item.path("sender"), "id");
        String messageId = text(message, "mid");
        String body = text(message, "text");
        if (blank(senderId) || blank(messageId) || blank(body)) return 0;

        long epochMillis;
        try {
            epochMillis = Long.parseLong(text(item, "timestamp"));
        } catch (RuntimeException ex) {
            redisTemplate.opsForStream().add(
                DEAD_LETTER_STREAM,
                Map.of("sourceId", messageId, "source", "FACEBOOK", "error", "Timestamp không hợp lệ")
            );
            return 0;
        }
        OffsetDateTime receivedAt = OffsetDateTime.ofInstant(Instant.ofEpochMilli(epochMillis), ZoneOffset.UTC);

        String hoTen = findField(NAME, body);
        String soDienThoai = findField(PHONE, body);
        String serial = findField(SERIAL, body);
        String noiDung = findField(DESCRIPTION, body);
        if (blank(hoTen) || blank(soDienThoai) || blank(noiDung)) {
            return queueReply(messageId, senderId, body, receivedAt);
        }

        InboundChannelMessage inbound = new InboundChannelMessage(
            "FACEBOOK", messageId, senderId, hoTen, soDienThoai, null, serial, noiDung,
            receivedAt
        );
        try {
            String payload = objectMapper.writeValueAsString(inbound);
            RecordId streamId = redisTemplate.opsForStream().add(
                ChannelStreams.INBOUND_REQUESTS,
                Map.of("payload", payload)
            );
            if (streamId == null) {
                throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Redis chưa nhận được message Facebook");
            }
            log.info("Đã đưa tin nhắn Facebook {} vào Redis Stream với ID {}", messageId, streamId.getValue());
            return 1;
        } catch (JsonProcessingException ex) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "Không thể chuẩn hóa webhook Facebook", ex);
        }
    }

    private int queueReply(String messageId, String senderId, String body, OffsetDateTime receivedAt) {
        try {
            String payload = objectMapper.writeValueAsString(new InboundChannelReply(
                "FACEBOOK", messageId, senderId, body.trim(), receivedAt
            ));
            RecordId streamId = redisTemplate.opsForStream().add(
                ChannelStreams.INBOUND_REPLIES,
                Map.of("payload", payload)
            );
            if (streamId == null) {
                throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Redis chưa nhận được tin nhắn Facebook");
            }
            log.info("Đã đưa tin nhắn tiếp theo Facebook {} vào Redis Stream với ID {}", messageId, streamId.getValue());
            return 1;
        } catch (JsonProcessingException ex) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "Không thể chuẩn hóa tin nhắn Facebook", ex);
        }
    }

    private static boolean isValidSignature(String signature, String rawBody, String secret) {
        if (blank(signature) || !signature.startsWith("sha256=")) return false;
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            String expected = "sha256=" + HexFormat.of().formatHex(mac.doFinal(rawBody.getBytes(StandardCharsets.UTF_8)));
            return constantTimeEquals(expected, signature.trim().toLowerCase(java.util.Locale.ROOT));
        } catch (Exception ex) {
            throw new IllegalStateException("Không thể xác minh chữ ký Facebook", ex);
        }
    }

    private static boolean constantTimeEquals(String first, String second) {
        if (first == null || second == null) return false;
        return MessageDigest.isEqual(
            first.getBytes(StandardCharsets.UTF_8), second.getBytes(StandardCharsets.UTF_8)
        );
    }

    private static String text(JsonNode node, String field) {
        JsonNode value = node == null ? null : node.get(field);
        return value == null || value.isNull() ? null : value.asText();
    }

    private static String findField(Pattern pattern, String body) {
        Matcher matcher = pattern.matcher(body == null ? "" : body);
        if (!matcher.find()) return null;
        String value = matcher.group(1).trim();
        return value.length() > 5000 ? value.substring(0, 5000) : value;
    }

    private static boolean blank(String value) {
        return value == null || value.isBlank();
    }

    public record WebhookResponse(String status, int queued) {
    }
}
