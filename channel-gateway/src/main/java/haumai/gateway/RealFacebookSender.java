package haumai.gateway;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.client.RestClient;
import org.springframework.web.server.ResponseStatusException;

import java.util.Map;

import static org.springframework.http.HttpStatus.BAD_GATEWAY;
import static org.springframework.http.HttpStatus.SERVICE_UNAVAILABLE;

@Component
public class RealFacebookSender implements FacebookSender {
    private final RestClient restClient;
    private final ObjectMapper objectMapper;
    private final String pageId;
    private final String pageAccessToken;
    private final String graphApiVersion;

    public RealFacebookSender(
        RestClient.Builder restClientBuilder,
        ObjectMapper objectMapper,
        @Value("${hau-mai.facebook.page-id:}") String pageId,
        @Value("${hau-mai.facebook.page-access-token:}") String pageAccessToken,
        @Value("${hau-mai.facebook.graph-api-version:v26.0}") String graphApiVersion
    ) {
        this.restClient = restClientBuilder.baseUrl("https://graph.facebook.com").build();
        this.objectMapper = objectMapper;
        this.pageId = pageId;
        this.pageAccessToken = pageAccessToken;
        this.graphApiVersion = graphApiVersion;
    }

    @Override
    public SendResult sendText(String userId, String text) {
        if (blank(pageId) || blank(pageAccessToken)) {
            throw new ResponseStatusException(SERVICE_UNAVAILABLE, "Chưa cấu hình Facebook Page ID và Page Access Token");
        }
        if (blank(userId) || blank(text)) {
            throw new IllegalArgumentException("Thiếu Facebook user ID hoặc nội dung phản hồi");
        }

        String rawResponse = restClient.post()
            .uri("/{version}/{pageId}/messages", graphApiVersion, pageId)
            .header(HttpHeaders.AUTHORIZATION, "Bearer " + pageAccessToken)
            .contentType(MediaType.APPLICATION_JSON)
            .body(Map.of(
                "recipient", Map.of("id", userId),
                "message", Map.of("text", text)
            ))
            .retrieve()
            .body(String.class);

        JsonNode response = null;
        if (!blank(rawResponse)) {
            try {
                response = objectMapper.readTree(rawResponse);
            } catch (JsonProcessingException ex) {
                // Meta has already returned HTTP 2xx, so an unrecognized body
                // must not turn a message that was accepted into a false failure.
            }
        }
        if (response != null && response.has("error")) {
            throw new ResponseStatusException(BAD_GATEWAY, "Meta trả về lỗi khi gửi tin Messenger");
        }
        // A successful HTTP 2xx means the Send API accepted the message. Meta may
        // omit a provider message ID in some successful responses; do not report
        // an accepted message as failed or encourage staff to send it twice.
        String messageId = response == null ? "" : response.path("message_id").asText("");
        return new SendResult("FACEBOOK_MESSENGER", messageId);
    }

    private static boolean blank(String value) {
        return value == null || value.isBlank();
    }
}
