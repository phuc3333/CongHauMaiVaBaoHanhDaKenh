package haumai.gateway;

public interface ZaloSender {
    SendResult sendText(String userId, String text);

    record SendResult(String provider, String messageId) {
    }
}
