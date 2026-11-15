package haumai.gateway;

import com.fasterxml.jackson.databind.JsonNode;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

import java.util.Map;
import java.util.UUID;

@Component
@ConditionalOnProperty(name = "hau-mai.zalo.sender", havingValue = "real")
public class RealZaloSender implements ZaloSender {
    private static final String SEND_MESSAGE_URL = "https://openapi.zalo.me/v3.0/oa/message/cs";

    private final RestClient restClient;
    private final String accessToken;

    public RealZaloSender(
        RestClient.Builder restClientBuilder,
        @Value("${hau-mai.zalo.access-token:}") String accessToken
    ) {
        this.restClient = restClientBuilder.build();
        this.accessToken = accessToken;
    }

    @Override
    public SendResult sendText(String userId, String text) {
        if (accessToken == null || accessToken.isBlank()) {
            throw new ResponseStatusException(HttpStatus.SERVICE_UNAVAILABLE, "Chưa cấu hình Zalo OA access token");
        }
        JsonNode response = restClient.post()
            .uri(SEND_MESSAGE_URL)
            .header("access_token", accessToken)
            .contentType(MediaType.APPLICATION_JSON)
            .body(Map.of(
                "recipient", Map.of("user_id", userId),
                "message", Map.of("text", text)
            ))
            .retrieve()
            .body(JsonNode.class);

        if (response == null || response.path("error").asInt(-1) != 0) {
            throw new ResponseStatusException(HttpStatus.BAD_GATEWAY, "Zalo OA không xác nhận gửi tin nhắn");
        }
        String messageId = response.path("data").path("message_id").asText(UUID.randomUUID().toString());
        return new SendResult("ZALO_OA", messageId);
    }
}
