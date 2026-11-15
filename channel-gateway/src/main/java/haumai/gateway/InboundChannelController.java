package haumai.gateway;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import haumai.contract.ChannelStreams;
import haumai.contract.InboundChannelMessage;
import org.springframework.data.redis.connection.stream.RecordId;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.security.MessageDigest;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.Set;

@RestController
@RequestMapping("/api/v1/channel")
public class InboundChannelController {
    private static final Set<String> SUPPORTED_CHANNELS =
        Set.of("WEBSITE", "FACEBOOK", "ZALO");

    private final StringRedisTemplate redisTemplate;
    private final ObjectMapper objectMapper;
    private final String ingestSecret;

    public InboundChannelController(
        StringRedisTemplate redisTemplate,
        ObjectMapper objectMapper,
        @Value("${hau-mai.channel.ingest-secret:}") String ingestSecret
    ) {
        this.redisTemplate = redisTemplate;
        this.objectMapper = objectMapper;
        this.ingestSecret = ingestSecret;
    }

    @PostMapping("/messages")
    public ResponseEntity<QueuedResponse> receive(
        @RequestHeader(value = "X-Channel-Ingest-Secret", required = false) String suppliedSecret,
        @RequestBody InboundChannelMessage incoming
    ) {
        if (ingestSecret == null || ingestSecret.isBlank() || suppliedSecret == null
            || !MessageDigest.isEqual(
                ingestSecret.getBytes(StandardCharsets.UTF_8),
                suppliedSecret.getBytes(StandardCharsets.UTF_8)
            )) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND);
        }
        InboundChannelMessage message = validateAndNormalize(incoming);
        String payload;
        try {
            payload = objectMapper.writeValueAsString(message);
        } catch (JsonProcessingException ex) {
            throw new ResponseStatusException(
                HttpStatus.INTERNAL_SERVER_ERROR,
                "Không thể chuyển message sang JSON",
                ex
            );
        }

        RecordId recordId = redisTemplate.opsForStream().add(
            ChannelStreams.INBOUND_REQUESTS,
            Map.of("payload", payload)
        );
        if (recordId == null) {
            throw new ResponseStatusException(
                HttpStatus.SERVICE_UNAVAILABLE,
                "Redis chưa nhận được message"
            );
        }

        return ResponseEntity.accepted().body(
            new QueuedResponse("queued", ChannelStreams.INBOUND_REQUESTS, recordId.getValue())
        );
    }

    private InboundChannelMessage validateAndNormalize(InboundChannelMessage incoming) {
        if (incoming == null) {
            throw badRequest("Nội dung message không được để trống");
        }

        String maKenh = trimToNull(incoming.maKenh());
        if (maKenh == null) {
            throw badRequest("Thiếu mã kênh");
        }
        maKenh = maKenh.toUpperCase();
        if (!SUPPORTED_CHANNELS.contains(maKenh)) {
            throw badRequest("Mã kênh không được hỗ trợ");
        }

        String maTinGoc = trimToNull(incoming.maTinGoc());
        String maNguoiDungKenh = trimToNull(incoming.maNguoiDungKenh());
        String hoTen = trimToNull(incoming.hoTen());
        String soDienThoai = trimToNull(incoming.soDienThoai());
        String noiDung = trimToNull(incoming.noiDung());

        if (hoTen == null || soDienThoai == null || noiDung == null) {
            throw badRequest("Cần có họ tên, số điện thoại và nội dung yêu cầu");
        }
        if (!"WEBSITE".equals(maKenh)
            && (maTinGoc == null || maNguoiDungKenh == null)) {
            throw badRequest(
                "Kênh Facebook/Zalo cần mã tin nhắn và mã người dùng gốc"
            );
        }

        OffsetDateTime nhanLuc = incoming.nhanLuc() == null
            ? OffsetDateTime.now(ZoneId.of("Asia/Ho_Chi_Minh"))
            : incoming.nhanLuc();

        return new InboundChannelMessage(
            maKenh,
            maTinGoc,
            maNguoiDungKenh,
            hoTen,
            soDienThoai,
            trimToNull(incoming.email()),
            trimToNull(incoming.serial()),
            noiDung,
            nhanLuc
        );
    }

    private static String trimToNull(String value) {
        if (value == null || value.isBlank()) {
            return null;
        }
        return value.trim();
    }

    private static ResponseStatusException badRequest(String message) {
        return new ResponseStatusException(HttpStatus.BAD_REQUEST, message);
    }

    public record QueuedResponse(String status, String stream, String streamId) {
    }
}
