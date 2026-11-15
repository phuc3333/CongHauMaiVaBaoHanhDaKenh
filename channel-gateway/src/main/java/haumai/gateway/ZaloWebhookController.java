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
import org.springframework.data.redis.connection.stream.MapRecord;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.domain.Range;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.http.MediaType;
import org.springframework.web.client.RestClient;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;
import jakarta.servlet.http.HttpServletRequest;

import java.nio.charset.StandardCharsets;
import java.io.IOException;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.time.OffsetDateTime;
import java.time.ZoneOffset;
import java.util.HexFormat;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@RestController
@RequestMapping("/api/v1/zalo")
public class ZaloWebhookController {
    private static final Logger log = LoggerFactory.getLogger(ZaloWebhookController.class);
    private static final String USER_TEXT_EVENT = "user_send_text";
    private static final Pattern NAME = Pattern.compile("(?im)^\\s*(?:ho\\s*ten|họ\\s*tên)\\s*:\\s*(.+?)\\s*$");
    private static final Pattern PHONE = Pattern.compile("(?im)^\\s*(?:so\\s*dien\\s*thoai|số\\s*điện\\s*thoại|phone)\\s*:\\s*(.+?)\\s*$");
    private static final Pattern SERIAL = Pattern.compile("(?im)^\\s*(?:serial|so\\s*serial)\\s*:\\s*(.+?)\\s*$");
    private static final Pattern DESCRIPTION = Pattern.compile("(?ims)^\\s*(?:mo\\s*ta\\s*loi|mô\\s*tả\\s*lỗi)\\s*:\\s*(.+?)\\s*$");

    @Value("${hau-mai.zalo.app-id:}")
    private String configuredAppId;

    @Value("${hau-mai.zalo.webhook-secret:}")
    private String webhookSecret;

    @Value("${hau-mai.zalo.demo-enabled:false}")
    private boolean demoEnabled;

    private final StringRedisTemplate redisTemplate;
    private final ObjectMapper objectMapper;
    private final RestClient restClient;
    private final int serverPort;

    public ZaloWebhookController(
        StringRedisTemplate redisTemplate,
        ObjectMapper objectMapper,
        RestClient.Builder restClientBuilder,
        @Value("${server.port:8081}") int serverPort
    ) {
        this.redisTemplate = redisTemplate;
        this.objectMapper = objectMapper;
        this.restClient = restClientBuilder.build();
        this.serverPort = serverPort;
    }

    @PostMapping("/webhook")
    public ResponseEntity<WebhookResponse> receive(
        @RequestHeader(value = "X-ZEvent-Signature", required = false) String signature,
        @RequestBody byte[] requestBody
    ) {
        if (configuredAppId == null || configuredAppId.isBlank()
            || webhookSecret == null || webhookSecret.isBlank()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Zalo webhook chưa được cấu hình");
        }

        String rawBody = new String(requestBody, StandardCharsets.UTF_8);
        JsonNode event;
        try {
            event = objectMapper.readTree(requestBody);
        } catch (IOException ex) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Webhook body không phải JSON hợp lệ", ex);
        }

        String appId = text(event, "app_id");
        String timestamp = text(event, "timestamp");
        if (!configuredAppId.equals(appId) || timestamp == null || timestamp.isBlank()) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "App ID hoặc timestamp không hợp lệ");
        }
        if (!isValidSignature(signature, appId, rawBody, timestamp, webhookSecret)) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "Chữ ký webhook Zalo không hợp lệ");
        }

        String eventName = text(event, "event_name");
        if (!USER_TEXT_EVENT.equals(eventName)) {
            return ResponseEntity.ok(new WebhookResponse("ignored", eventName));
        }

        JsonNode sender = event.path("sender");
        JsonNode messageNode = event.path("message");
        String userId = text(sender, "id");
        String messageId = text(messageNode, "msg_id");
        String messageText = text(messageNode, "text");
        if (userId == null || userId.isBlank() || messageId == null || messageId.isBlank()
            || messageText == null || messageText.isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Webhook thiếu sender, msg_id hoặc text");
        }

        String hoTen = findField(NAME, messageText);
        String soDienThoai = findField(PHONE, messageText);
        String serial = findField(SERIAL, messageText);
        String noiDung = findField(DESCRIPTION, messageText);
        long epochMillis;
        try {
            epochMillis = Long.parseLong(timestamp);
        } catch (NumberFormatException ex) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "Timestamp webhook không hợp lệ", ex);
        }

        OffsetDateTime receivedAt = OffsetDateTime.ofInstant(Instant.ofEpochMilli(epochMillis), ZoneOffset.UTC);
        if (hoTen == null || soDienThoai == null || noiDung == null) {
            InboundChannelReply reply = new InboundChannelReply("ZALO", messageId, userId, messageText, receivedAt);
            try {
                String replyPayload = objectMapper.writeValueAsString(reply);
                RecordId replyStreamId = redisTemplate.opsForStream().add(
                    ChannelStreams.INBOUND_REPLIES, Map.of("payload", replyPayload)
                );
                if (replyStreamId == null) {
                    throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Redis chưa nhận được tin nhắn Zalo");
                }
                log.info("Đã đưa tin nhắn Zalo {} vào luồng hội thoại với ID {}", messageId, replyStreamId.getValue());
                return ResponseEntity.ok(new WebhookResponse("accepted", USER_TEXT_EVENT));
            } catch (JsonProcessingException ex) {
                throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "Không thể chuẩn hóa tin nhắn Zalo", ex);
            }
        }

        InboundChannelMessage inbound = new InboundChannelMessage(
            "ZALO", messageId, userId, hoTen, soDienThoai, null, serial, noiDung, receivedAt
        );

        String payload;
        try {
            payload = objectMapper.writeValueAsString(inbound);
        } catch (JsonProcessingException ex) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "Không thể chuẩn hóa webhook Zalo", ex);
        }

        RecordId streamId = redisTemplate.opsForStream().add(
            ChannelStreams.INBOUND_REQUESTS,
            Map.of("payload", payload)
        );
        if (streamId == null) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Redis chưa nhận được message Zalo");
        }

        log.info("Đã đưa tin nhắn Zalo {} vào Redis Stream với ID {}", messageId, streamId.getValue());
        return ResponseEntity.ok(new WebhookResponse("queued", streamId.getValue()));
    }

    @PostMapping("/demo")
    public ResponseEntity<DemoResponse> submitDemo(
        @RequestBody DemoRequest request,
        HttpServletRequest servletRequest
    ) {
        if (!demoEnabled || !isLocalDemoRequest(servletRequest)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
        if (request == null || blank(request.hoTen()) || blank(request.soDienThoai())
            || blank(request.moTaLoi())) {
            throw new ResponseStatusException(
                HttpStatus.BAD_REQUEST,
                "Cần nhập họ tên, số điện thoại và mô tả lỗi"
            );
        }

        String timestamp = Long.toString(System.currentTimeMillis());
        String messageId = "demo-zalo-" + UUID.randomUUID();
        String demoUserId = demoUserId(request.soDienThoai());
        StringBuilder messageText = new StringBuilder()
            .append("Họ tên: ").append(request.hoTen().trim()).append('\n')
            .append("Số điện thoại: ").append(request.soDienThoai().trim()).append('\n');
        if (!blank(request.serial())) {
            messageText.append("Serial: ").append(request.serial().trim()).append('\n');
        }
        messageText.append("Mô tả lỗi: ").append(request.moTaLoi().trim());

        Map<String, Object> event = Map.of(
            "app_id", configuredAppId,
            "sender", Map.of("id", demoUserId),
            "recipient", Map.of("id", "zalo-demo-oa-local"),
            "event_name", USER_TEXT_EVENT,
            "message", Map.of("text", messageText.toString(), "msg_id", messageId),
            "timestamp", timestamp
        );

        String rawBody;
        try {
            rawBody = objectMapper.writeValueAsString(event);
        } catch (JsonProcessingException ex) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "Không tạo được webhook demo", ex);
        }

        String signature = "mac=" + HexFormat.of().formatHex(
            sha256(configuredAppId + rawBody + timestamp + webhookSecret)
        );
        ResponseEntity<WebhookResponse> response = restClient.post()
            .uri("http://127.0.0.1:" + serverPort + "/api/v1/zalo/webhook")
            .header("X-ZEvent-Signature", signature)
            .contentType(MediaType.APPLICATION_JSON)
            .body(rawBody)
            .retrieve()
            .toEntity(WebhookResponse.class);
        WebhookResponse body = response.getBody();
        return ResponseEntity.status(response.getStatusCode()).body(
            new DemoResponse(body == null ? "queued" : body.status(),
                body == null ? "" : body.detail(), messageId)
        );
    }

    @PostMapping("/demo/chat")
    public ResponseEntity<DemoResponse> submitDemoChat(
        @RequestBody DemoChatRequest request,
        HttpServletRequest servletRequest
    ) {
        if (!demoEnabled || !isLocalDemoRequest(servletRequest)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
        if (request == null || blank(request.text()) || request.text().trim().length() > 2000
            || blank(request.soDienThoai())) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST,
                "Tin nhắn cần từ 1 đến 2000 ký tự và cần nhập số điện thoại ở form bên trái");
        }

        String timestamp = Long.toString(System.currentTimeMillis());
        String messageId = "demo-zalo-chat-" + UUID.randomUUID();
        String demoUserId = demoUserId(request.soDienThoai());
        Map<String, Object> event = Map.of(
            "app_id", configuredAppId,
            "sender", Map.of("id", demoUserId),
            "recipient", Map.of("id", "zalo-demo-oa-local"),
            "event_name", USER_TEXT_EVENT,
            "message", Map.of(
                "text", "Số điện thoại: " + request.soDienThoai().trim()
                    + "\n" + request.text().trim(),
                "msg_id", messageId
            ),
            "timestamp", timestamp
        );

        String rawBody;
        try {
            rawBody = objectMapper.writeValueAsString(event);
        } catch (JsonProcessingException ex) {
            throw new ResponseStatusException(HttpStatus.INTERNAL_SERVER_ERROR, "Không tạo được webhook chat demo", ex);
        }
        String signature = "mac=" + HexFormat.of().formatHex(
            sha256(configuredAppId + rawBody + timestamp + webhookSecret)
        );
        ResponseEntity<WebhookResponse> response = restClient.post()
            .uri("http://127.0.0.1:" + serverPort + "/api/v1/zalo/webhook")
            .header("X-ZEvent-Signature", signature)
            .contentType(MediaType.APPLICATION_JSON)
            .body(rawBody)
            .retrieve()
            .toEntity(WebhookResponse.class);
        WebhookResponse body = response.getBody();
        return ResponseEntity.status(response.getStatusCode()).body(
            new DemoResponse(body == null ? "accepted" : body.status(),
                body == null ? "" : body.detail(), messageId)
        );
    }

    @GetMapping("/demo/outbox")
    public ResponseEntity<java.util.List<Map<Object, Object>>> getDemoOutbox(
        HttpServletRequest servletRequest,
        @org.springframework.web.bind.annotation.RequestParam(required = false) String recipientId,
        @org.springframework.web.bind.annotation.RequestParam(required = false) String soDienThoai
    ) {
        if (!demoEnabled || !isLocalDemoRequest(servletRequest)) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
        java.util.List<MapRecord<String, Object, Object>> records = redisTemplate.opsForStream()
            .reverseRange(FakeZaloSender.OUTBOX_STREAM, Range.unbounded());
        java.util.List<Map<Object, Object>> messages = records == null ? java.util.List.of()
            : records.stream().map(MapRecord::getValue)
                .filter(value -> {
                    String expectedRecipient = !blank(recipientId) ? recipientId
                        : !blank(soDienThoai) ? demoUserId(soDienThoai) : null;
                    return expectedRecipient == null
                        || expectedRecipient.equals(String.valueOf(value.get("recipientId")));
                })
                .limit(50).toList();
        return ResponseEntity.ok(messages);
    }

    private static boolean isLocalDemoRequest(HttpServletRequest request) {
        if (request.getHeader("CF-Connecting-IP") != null) return false;
        String host = request.getServerName();
        return "localhost".equalsIgnoreCase(host) || "127.0.0.1".equals(host);
    }

    private static boolean isValidSignature(
        String suppliedSignature,
        String appId,
        String rawBody,
        String timestamp,
        String secret
    ) {
        if (suppliedSignature == null || suppliedSignature.isBlank()) {
            return false;
        }
        String suppliedMac = suppliedSignature.trim().replaceFirst("(?i)^mac\\s*=\\s*", "");
        String signedData = appId + rawBody + timestamp + secret;
        byte[] expected = sha256(signedData);
        byte[] supplied = suppliedMac.toLowerCase(java.util.Locale.ROOT).getBytes(StandardCharsets.US_ASCII);
        return MessageDigest.isEqual(HexFormat.of().formatHex(expected).getBytes(StandardCharsets.US_ASCII), supplied);
    }

    private static byte[] sha256(String value) {
        try {
            return MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
        } catch (NoSuchAlgorithmException impossible) {
            throw new IllegalStateException("SHA-256 is unavailable", impossible);
        }
    }

    private static String text(JsonNode node, String field) {
        JsonNode value = node == null ? null : node.get(field);
        return value == null || value.isNull() ? null : value.asText();
    }

    private static boolean blank(String value) {
        return value == null || value.isBlank();
    }

    private static String demoUserId(String phone) {
        String digits = phone == null ? "" : phone.replaceAll("[^0-9]", "");
        if ("0900000000".equals(digits)) return "zalo-demo-user-001";
        return "zalo-demo-user-" + HexFormat.of().formatHex(sha256(digits)).substring(0, 16);
    }

    private static String findField(Pattern pattern, String body) {
        Matcher matcher = pattern.matcher(body == null ? "" : body);
        return matcher.find() ? safeText(matcher.group(1), 5000) : null;
    }

    private static String safeText(String value, int maxLength) {
        if (value == null) {
            return "";
        }
        String trimmed = value.trim();
        return trimmed.length() > maxLength ? trimmed.substring(0, maxLength) : trimmed;
    }

    public record WebhookResponse(String status, String detail) {
    }

    public record DemoRequest(String hoTen, String soDienThoai, String serial, String moTaLoi) {
    }

    public record DemoChatRequest(String text, String soDienThoai) {
    }

    public record DemoResponse(String status, String streamId, String messageId) {
    }

}
