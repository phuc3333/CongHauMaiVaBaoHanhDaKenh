package haumai.core.messaging;

import haumai.contract.ChannelStreams;
import haumai.core.service.OutboundResultService;
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

@Component
public class OutboundChannelResultConsumer {
    private static final Logger log = LoggerFactory.getLogger(OutboundChannelResultConsumer.class);
    private static final String GROUP = "warranty-core-outbound-results";
    private static final String CONSUMER = "warranty-core-local";

    private final StringRedisTemplate redisTemplate;
    private final OutboundResultService resultService;
    private volatile boolean groupReady;

    public OutboundChannelResultConsumer(StringRedisTemplate redisTemplate, OutboundResultService resultService) {
        this.redisTemplate = redisTemplate;
        this.resultService = resultService;
    }

    @Scheduled(fixedDelay = 1000)
    public void poll() {
        if (!ensureGroup()) return;
        Consumer consumer = Consumer.from(GROUP, CONSUMER);
        var options = StreamReadOptions.empty().count(10);
        List<MapRecord<String, Object, Object>> pending = redisTemplate.opsForStream().read(
            consumer, options,
            StreamOffset.create(ChannelStreams.OUTBOUND_RESULTS, ReadOffset.from("0"))
        );
        List<MapRecord<String, Object, Object>> records = pending == null || pending.isEmpty()
            ? redisTemplate.opsForStream().read(
                consumer, options,
                StreamOffset.create(ChannelStreams.OUTBOUND_RESULTS, ReadOffset.lastConsumed())
            )
            : pending;
        if (records != null) records.forEach(this::process);
    }

    private boolean ensureGroup() {
        if (groupReady) return true;
        try {
            if (!Boolean.TRUE.equals(redisTemplate.hasKey(ChannelStreams.OUTBOUND_RESULTS))) return false;
            redisTemplate.opsForStream().createGroup(
                ChannelStreams.OUTBOUND_RESULTS, ReadOffset.from("0-0"), GROUP
            );
            groupReady = true;
            return true;
        } catch (DataAccessException ex) {
            if (hasCauseMessage(ex, "BUSYGROUP")) {
                groupReady = true;
                return true;
            }
            log.warn("Chưa tạo được consumer group kết quả gửi; sẽ thử lại", ex);
            return false;
        }
    }

    private void process(MapRecord<String, Object, Object> record) {
        try {
            var values = record.getValue();
            String conversationMessage = String.valueOf(values.getOrDefault("tinNhanCuocTroChuyenId", ""));
            String trangThai = String.valueOf(values.get("trangThai"));
            String maKenh = String.valueOf(values.getOrDefault("maKenh", "ZALO"));
            boolean conversationReply = !conversationMessage.isBlank();
            long messageId = conversationReply
                ? Long.parseLong(conversationMessage)
                : Long.parseLong(String.valueOf(values.get("tinNhanId")));
            String externalId = String.valueOf(values.getOrDefault("maTinNhaCungCap", ""));
            resultService.record(messageId, trangThai, externalId, maKenh, conversationReply);
            redisTemplate.opsForStream().acknowledge(
                ChannelStreams.OUTBOUND_RESULTS, GROUP, record.getId()
            );
            log.info("Đã cập nhật trạng thái phản hồi {} id={} thành {}",
                conversationMessage.isBlank() ? "tin_nhan" : "hội thoại", conversationMessage.isBlank()
                    ? values.get("tinNhanId") : conversationMessage, trangThai);
        } catch (Exception ex) {
            log.error("Chưa xử lý được kết quả gửi Redis {}", record.getId().getValue(), ex);
        }
    }

    private static boolean hasCauseMessage(Throwable error, String text) {
        for (Throwable cause = error; cause != null; cause = cause.getCause()) {
            if (cause.getMessage() != null && cause.getMessage().contains(text)) return true;
        }
        return false;
    }
}
