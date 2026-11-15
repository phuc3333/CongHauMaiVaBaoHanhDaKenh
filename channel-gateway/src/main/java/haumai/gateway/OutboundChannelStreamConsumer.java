package haumai.gateway;

import com.fasterxml.jackson.databind.ObjectMapper;
import haumai.contract.ChannelStreams;
import haumai.contract.OutboundChannelMessage;
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
public class OutboundChannelStreamConsumer {
    private static final Logger log = LoggerFactory.getLogger(OutboundChannelStreamConsumer.class);
    private static final String GROUP = "channel-gateway-outbound";
    private static final String CONSUMER = "channel-gateway-local";

    private final StringRedisTemplate redisTemplate;
    private final ObjectMapper objectMapper;
    private final ZaloSender zaloSender;
    private final FacebookSender facebookSender;
    private volatile boolean groupReady;

    public OutboundChannelStreamConsumer(
        StringRedisTemplate redisTemplate,
        ObjectMapper objectMapper,
        ZaloSender zaloSender,
        FacebookSender facebookSender
    ) {
        this.redisTemplate = redisTemplate;
        this.objectMapper = objectMapper;
        this.zaloSender = zaloSender;
        this.facebookSender = facebookSender;
    }

    @Scheduled(fixedDelay = 1000)
    public void poll() {
        if (!ensureGroup()) {
            return;
        }
        Consumer consumer = Consumer.from(GROUP, CONSUMER);
        var options = StreamReadOptions.empty().count(10);
        List<MapRecord<String, Object, Object>> pending = redisTemplate.opsForStream().read(
            consumer, options,
            StreamOffset.create(ChannelStreams.OUTBOUND_REQUESTS, ReadOffset.from("0"))
        );
        List<MapRecord<String, Object, Object>> records = pending == null || pending.isEmpty()
            ? redisTemplate.opsForStream().read(
                consumer, options,
                StreamOffset.create(ChannelStreams.OUTBOUND_REQUESTS, ReadOffset.lastConsumed())
            )
            : pending;
        if (records != null) {
            records.forEach(this::process);
        }
    }

    private boolean ensureGroup() {
        if (groupReady) return true;
        try {
            if (!Boolean.TRUE.equals(redisTemplate.hasKey(ChannelStreams.OUTBOUND_REQUESTS))) return false;
            redisTemplate.opsForStream().createGroup(
                ChannelStreams.OUTBOUND_REQUESTS, ReadOffset.from("0-0"), GROUP
            );
            groupReady = true;
            return true;
        } catch (DataAccessException ex) {
            if (hasCauseMessage(ex, "BUSYGROUP")) {
                groupReady = true;
                return true;
            }
            log.warn("Chưa tạo được consumer group gửi tin; sẽ thử lại", ex);
            return false;
        }
    }

    private void process(MapRecord<String, Object, Object> record) {
        Object raw = record.getValue().get("payload");
        Long tinNhanId = null;
        Long conversationMessageId = null;
        String status;
        String providerMessageId = "";
        String error = "";
        String channel = "";
        try {
            if (raw == null) throw new IllegalArgumentException("Stream record thiếu payload");
            OutboundChannelMessage message = objectMapper.readValue(raw.toString(), OutboundChannelMessage.class);
            tinNhanId = message.tinNhanId();
            conversationMessageId = message.tinNhanCuocTroChuyenId();
            channel = message.maKenh() == null ? "" : message.maKenh().toUpperCase(java.util.Locale.ROOT);
            if ("ZALO".equals(channel)) {
                ZaloSender.SendResult sent = zaloSender.sendText(message.maNguoiDungKenh(), message.noiDung());
                status = "DA_GUI";
                providerMessageId = sent.messageId();
                log.info("Đã gửi phản hồi Zalo cho tin nhắn DB id={} qua {}", tinNhanId, sent.provider());
            } else if ("FACEBOOK".equals(channel)) {
                FacebookSender.SendResult sent = facebookSender.sendText(message.maNguoiDungKenh(), message.noiDung());
                status = "DA_GUI";
                providerMessageId = sent.messageId();
                log.info("Đã gửi phản hồi Facebook cho tin nhắn DB id={} qua {}", tinNhanId, sent.provider());
            } else {
                throw new IllegalArgumentException("Chưa hỗ trợ gửi qua kênh " + channel);
            }
        } catch (Exception ex) {
            status = "THAT_BAI";
            error = ex.getMessage() == null ? ex.getClass().getSimpleName() : ex.getMessage();
            if (error.length() > 500) error = error.substring(0, 500);
            log.error("Không gửi được phản hồi Zalo outbox {}", record.getId().getValue(), ex);
        }

        try {
            redisTemplate.opsForStream().add(
                ChannelStreams.OUTBOUND_RESULTS,
                Map.of(
                    "tinNhanId", tinNhanId == null ? "" : tinNhanId.toString(),
                    "tinNhanCuocTroChuyenId", conversationMessageId == null ? "" : conversationMessageId.toString(),
                    "maKenh", channel,
                    "trangThai", status,
                    "maTinNhaCungCap", providerMessageId,
                    "loi", error
                )
            );
            redisTemplate.opsForStream().acknowledge(
                ChannelStreams.OUTBOUND_REQUESTS, GROUP, record.getId()
            );
        } catch (DataAccessException ex) {
            log.error("Không lưu được kết quả gửi cho outbox {}; sẽ thử lại", record.getId().getValue(), ex);
        }
    }

    private static boolean hasCauseMessage(Throwable error, String text) {
        for (Throwable cause = error; cause != null; cause = cause.getCause()) {
            if (cause.getMessage() != null && cause.getMessage().contains(text)) return true;
        }
        return false;
    }
}
