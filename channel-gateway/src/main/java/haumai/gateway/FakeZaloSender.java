package haumai.gateway;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.data.redis.connection.stream.RecordId;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

import java.time.Instant;
import java.util.Map;
import java.util.UUID;

@Component
@ConditionalOnProperty(name = "hau-mai.zalo.sender", havingValue = "fake", matchIfMissing = true)
public class FakeZaloSender implements ZaloSender {
    public static final String OUTBOX_STREAM = "warranty:zalo:outbox";

    private final StringRedisTemplate redisTemplate;

    public FakeZaloSender(StringRedisTemplate redisTemplate) {
        this.redisTemplate = redisTemplate;
    }

    @Override
    public SendResult sendText(String userId, String text) {
        String messageId = "fake-zalo-" + UUID.randomUUID();
        RecordId streamId = redisTemplate.opsForStream().add(
            OUTBOX_STREAM,
            Map.of(
                "provider", "FAKE_ZALO",
                "recipientId", userId,
                "messageId", messageId,
                "text", text,
                "sentAt", Instant.now().toString()
            )
        );
        return new SendResult("FAKE_ZALO", streamId == null ? messageId : streamId.getValue());
    }
}
