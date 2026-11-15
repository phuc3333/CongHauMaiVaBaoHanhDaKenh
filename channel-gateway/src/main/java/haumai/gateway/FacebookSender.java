package haumai.gateway;

public interface FacebookSender {
    SendResult sendText(String userId, String text);

    record SendResult(String provider, String messageId) {
    }
}
