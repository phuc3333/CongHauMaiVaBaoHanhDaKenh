package haumai.core.service;

import haumai.core.repository.OutboundResultRepository;
import org.springframework.stereotype.Service;

@Service
public class OutboundResultService {
    private final OutboundResultRepository repository;
    public OutboundResultService(OutboundResultRepository repository) { this.repository=repository; }
    public void record(long messageId, String status, String externalId, String channel, boolean conversation) {
        if (!"DA_GUI".equals(status) && !"THAT_BAI".equals(status))
            throw new IllegalArgumentException("Trạng thái gửi không hợp lệ");
        repository.update(messageId,status,externalId,channel,conversation);
    }
}
