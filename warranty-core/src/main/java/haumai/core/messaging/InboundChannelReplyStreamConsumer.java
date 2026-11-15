package haumai.core.messaging;

import com.fasterxml.jackson.databind.ObjectMapper;
import haumai.contract.ChannelStreams;
import haumai.contract.InboundChannelReply;
import haumai.core.service.InboundReplyService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.data.redis.connection.stream.Consumer;
import org.springframework.data.redis.connection.stream.MapRecord;
import org.springframework.data.redis.connection.stream.ReadOffset;
import org.springframework.data.redis.connection.stream.StreamOffset;
import org.springframework.data.redis.connection.stream.StreamReadOptions;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

@Component
public class InboundChannelReplyStreamConsumer {
    private static final Logger log = LoggerFactory.getLogger(InboundChannelReplyStreamConsumer.class);
    private static final String GROUP = "warranty-core-inbound-replies";
    private static final String CONSUMER = "warranty-core-local";
    private static final String DEAD_LETTER_STREAM = "warranty:inbound:dead-letter";
    private static final String RETRY_HASH = "warranty:inbound:reply-retry-count";
    private static final long MAX_ATTEMPTS = 5;

    private final StringRedisTemplate redisTemplate;
    private final ObjectMapper objectMapper;
    private final InboundReplyService inboundReplyService;
    private volatile boolean groupReady;

    public InboundChannelReplyStreamConsumer(
        StringRedisTemplate redisTemplate,
        ObjectMapper objectMapper,
        InboundReplyService inboundReplyService
    ) {
        this.redisTemplate = redisTemplate;
        this.objectMapper = objectMapper;
        this.inboundReplyService = inboundReplyService;
    }

    @Scheduled(fixedDelay = 1000)
    public void poll() {
        if (!ensureGroup()) return;
        Consumer consumer = Consumer.from(GROUP, CONSUMER);
        var options = StreamReadOptions.empty().count(10);
        List<MapRecord<String, Object, Object>> pending = redisTemplate.opsForStream().read(
            consumer, options,
            StreamOffset.create(ChannelStreams.INBOUND_REPLIES, ReadOffset.from("0"))
        );
        List<MapRecord<String, Object, Object>> records = pending == null || pending.isEmpty()
            ? redisTemplate.opsForStream().read(
                consumer, options,
                StreamOffset.create(ChannelStreams.INBOUND_REPLIES, ReadOffset.lastConsumed())
            )
            : pending;
        if (records != null) records.forEach(this::process);
    }

    private boolean ensureGroup() {
        if (groupReady) return true;
        try {
            if (!Boolean.TRUE.equals(redisTemplate.hasKey(ChannelStreams.INBOUND_REPLIES))) return false;
            redisTemplate.opsForStream().createGroup(
                ChannelStreams.INBOUND_REPLIES, ReadOffset.from("0-0"), GROUP
            );
            groupReady = true;
            log.info("Đã tạo Redis consumer group {} cho stream {}", GROUP, ChannelStreams.INBOUND_REPLIES);
            return true;
        } catch (DataAccessException ex) {
            if (hasCauseMessage(ex, "BUSYGROUP")) {
                groupReady = true;
                return true;
            }
            log.warn("Chưa tạo được consumer group tin nhắn tiếp theo; sẽ thử lại", ex);
            return false;
        }
    }

    private void process(MapRecord<String, Object, Object> record) {
        String recordId = record.getId().getValue();
        Object raw = record.getValue().get("payload");
        String payload = raw == null ? null : raw.toString();
        try {
            if (payload == null || payload.isBlank()) throw new IllegalArgumentException("Stream record thiếu payload");
            InboundChannelReply message = objectMapper.readValue(payload, InboundChannelReply.class);
            String channel = message.maKenh().toUpperCase(java.util.Locale.ROOT);
            InboundReplyService.StoredReply result = inboundReplyService.store(message);
            inboundReplyService.saveConversation(message, result.caseId());
            if ("KHONG_CO_HO_SO_MO".equals(result.result()) || "NHIEU_HO_SO_MO".equals(result.result())
                || "CHUA_CO_DINH_DANH".equals(result.result())) {
                inboundReplyService.saveForFollowUp(message, result.result());
                acknowledge(record);
                log.info("Đã lưu tin {} {} vào danh sách chờ bổ sung [{}]",
                    channel, message.maTinGoc(), result.result());
                return;
            }
            if (!"DA_GHI_NHAN".equals(result.result()) && !"DA_TON_TAI".equals(result.result())) {
                moveToDeadLetter(record, recordId, payload,
                    "Procedure trả về kết quả không nhận diện: " + result.result());
                return;
            }

            acknowledge(record);
            log.info("Đã ghi nhận tin nhắn {} {} vào hồ sơ {} (id={}) [{}]",
                channel, message.maTinGoc(), result.caseNumber(), result.caseId(), result.result());
        } catch (Exception ex) {
            Long attempts = redisTemplate.opsForHash().increment(RETRY_HASH, recordId, 1);
            long attemptCount = attempts == null ? 1 : attempts;
            log.error("Lỗi lưu tin nhắn hội thoại Redis {} lần thử {}/{}",
                recordId, attemptCount, MAX_ATTEMPTS, ex);
            if (attemptCount >= MAX_ATTEMPTS) {
                moveToDeadLetter(record, recordId, payload,
                    ex.getMessage() == null ? ex.getClass().getSimpleName() : ex.getMessage());
            }
        }
    }

    private void acknowledge(MapRecord<String, Object, Object> record) {
        redisTemplate.opsForStream().acknowledge(ChannelStreams.INBOUND_REPLIES, GROUP, record.getId());
        redisTemplate.opsForHash().delete(RETRY_HASH, record.getId().getValue());
    }

    private void moveToDeadLetter(
        MapRecord<String, Object, Object> record,
        String recordId,
        String payload,
        String reason
    ) {
        redisTemplate.opsForStream().add(
            DEAD_LETTER_STREAM,
                Map.of("sourceId", recordId, "source", "CHANNEL_REPLY",
                    "payload", payload == null ? "" : payload,
                    "error", reason == null ? "Lỗi không xác định" : reason)
        );
        redisTemplate.opsForStream().acknowledge(ChannelStreams.INBOUND_REPLIES, GROUP, record.getId());
        redisTemplate.opsForHash().delete(RETRY_HASH, recordId);
        log.warn("Tin nhắn hội thoại {} đã chuyển dead-letter: {}", recordId, reason);
    }

    private static boolean hasCauseMessage(Throwable error, String text) {
        for (Throwable cause = error; cause != null; cause = cause.getCause()) {
            if (cause.getMessage() != null && cause.getMessage().contains(text)) return true;
        }
        return false;
    }

}
