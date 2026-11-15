package haumai.core.messaging;

import com.fasterxml.jackson.databind.ObjectMapper;
import haumai.contract.ChannelStreams;
import haumai.contract.InboundChannelMessage;
import haumai.core.repository.InboundChannelRepository;
import haumai.core.service.InboundChannelService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.data.redis.connection.stream.Consumer;
import org.springframework.data.redis.connection.stream.MapRecord;
import org.springframework.data.redis.connection.stream.ReadOffset;
import org.springframework.data.redis.connection.stream.RecordId;
import org.springframework.data.redis.connection.stream.StreamOffset;
import org.springframework.data.redis.connection.stream.StreamReadOptions;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import java.time.Duration;
import java.util.List;
import java.util.Map;

@Component
public class InboundChannelStreamConsumer {
    private static final Logger log = LoggerFactory.getLogger(InboundChannelStreamConsumer.class);
    private static final String GROUP = "warranty-core";
    private static final String CONSUMER = "warranty-core-local";
    private static final String DEAD_LETTER_STREAM = "warranty:inbound:dead-letter";
    private static final String RETRY_HASH = "warranty:inbound:retry-count";
    private static final long MAX_ATTEMPTS = 5;

    private final StringRedisTemplate redisTemplate;
    private final ObjectMapper objectMapper;
    private final InboundChannelService inboundService;
    private volatile boolean groupReady;

    public InboundChannelStreamConsumer(
        StringRedisTemplate redisTemplate,
        ObjectMapper objectMapper,
        InboundChannelService inboundService
    ) {
        this.redisTemplate = redisTemplate;
        this.objectMapper = objectMapper;
        this.inboundService = inboundService;
    }

    @Scheduled(fixedDelay = 1000)
    public void poll() {
        if (!ensureConsumerGroup()) {
            return;
        }

        Consumer consumer = Consumer.from(GROUP, CONSUMER);
        var options = StreamReadOptions.empty().count(10);

        // Read this consumer's pending entries first so an app restart can resume them.
        List<MapRecord<String, Object, Object>> pending = redisTemplate.opsForStream().read(
            consumer,
            options,
            StreamOffset.create(ChannelStreams.INBOUND_REQUESTS, ReadOffset.from("0"))
        );
        if (pending != null && !pending.isEmpty()) {
            pending.forEach(this::process);
            return;
        }

        List<MapRecord<String, Object, Object>> fresh = redisTemplate.opsForStream().read(
            consumer,
            options,
            StreamOffset.create(ChannelStreams.INBOUND_REQUESTS, ReadOffset.lastConsumed())
        );
        if (fresh != null) {
            fresh.forEach(this::process);
        }
    }

    private boolean ensureConsumerGroup() {
        if (groupReady) {
            return true;
        }
        try {
            if (!Boolean.TRUE.equals(redisTemplate.hasKey(ChannelStreams.INBOUND_REQUESTS))) {
                return false;
            }
            redisTemplate.opsForStream().createGroup(
                ChannelStreams.INBOUND_REQUESTS,
                ReadOffset.from("0-0"),
                GROUP
            );
            groupReady = true;
            log.info("Đã tạo Redis consumer group {} cho stream {}", GROUP, ChannelStreams.INBOUND_REQUESTS);
            return true;
        } catch (DataAccessException ex) {
            if (hasCauseMessage(ex, "BUSYGROUP")) {
                groupReady = true;
                log.info("Redis consumer group {} đã tồn tại cho stream {}; tiếp tục tiêu thụ",
                    GROUP, ChannelStreams.INBOUND_REQUESTS);
                return true;
            }
            log.warn("Chưa tạo được Redis consumer group; sẽ thử lại", ex);
            return false;
        }
    }

    private static boolean hasCauseMessage(Throwable error, String text) {
        for (Throwable cause = error; cause != null; cause = cause.getCause()) {
            if (cause.getMessage() != null && cause.getMessage().contains(text)) {
                return true;
            }
        }
        return false;
    }

    private void process(MapRecord<String, Object, Object> record) {
        String recordId = record.getId().getValue();
        Object rawPayload = record.getValue().get("payload");
        String payload = rawPayload == null ? null : rawPayload.toString();
        try {
            if (payload == null || payload.isBlank()) {
                throw new IllegalArgumentException("Redis Stream record thiếu payload");
            }
            InboundChannelMessage message = objectMapper.readValue(payload, InboundChannelMessage.class);
            InboundChannelRepository.CreationResult result = inboundService.createCase(message);

            // The procedure commits before control returns here; ACK only after that succeeds.
            redisTemplate.opsForStream().acknowledge(
                ChannelStreams.INBOUND_REQUESTS,
                GROUP,
                record.getId()
            );
            redisTemplate.opsForHash().delete(RETRY_HASH, recordId);
            log.info(
                "Đã xử lý message {} thành hồ sơ {} (id={})",
                recordId,
                result.caseNumber(),
                result.caseId()
            );
        } catch (Exception ex) {
            Long attempts = redisTemplate.opsForHash().increment(RETRY_HASH, recordId, 1);
            long attemptCount = attempts == null ? 1 : attempts;
            log.error("Lỗi xử lý message Redis {} lần thử {}/{}", recordId, attemptCount, MAX_ATTEMPTS, ex);

            if (attemptCount >= MAX_ATTEMPTS) {
                moveToDeadLetter(record, recordId, payload, ex);
            }
        }
    }

    private void moveToDeadLetter(
        MapRecord<String, Object, Object> record,
        String recordId,
        String payload,
        Exception cause
    ) {
        try {
            redisTemplate.opsForStream().add(
                DEAD_LETTER_STREAM,
                Map.of(
                    "sourceId", recordId,
                    "payload", payload == null ? "" : payload,
                    "error", safeError(cause)
                )
            );
            redisTemplate.opsForStream().acknowledge(
                ChannelStreams.INBOUND_REQUESTS,
                GROUP,
                record.getId()
            );
            redisTemplate.opsForHash().delete(RETRY_HASH, recordId);
            log.error("Đã chuyển message {} sang dead-letter stream {}", recordId, DEAD_LETTER_STREAM);
        } catch (Exception deadLetterError) {
            log.error("Không chuyển được message {} sang dead-letter; giữ pending để thử lại", recordId, deadLetterError);
        }
    }

    private static String safeError(Exception cause) {
        String message = cause.getMessage();
        if (message == null || message.isBlank()) {
            return cause.getClass().getSimpleName();
        }
        return message.length() > 1000 ? message.substring(0, 1000) : message;
    }

}
