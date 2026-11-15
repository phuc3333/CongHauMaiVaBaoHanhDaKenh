package haumai.core.service;

import haumai.contract.InboundChannelReply;
import haumai.core.repository.InboundReplyRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Isolation;
import org.springframework.transaction.annotation.Transactional;

@Service
public class InboundReplyService {
    private final InboundReplyRepository repository;
    public InboundReplyService(InboundReplyRepository repository) { this.repository = repository; }
    @Transactional(isolation = Isolation.SERIALIZABLE)
    public StoredReply store(InboundChannelReply message) {
        if (message == null || message.maKenh() == null || message.maTinGoc() == null
                || message.maNguoiDungKenh() == null || message.noiDung() == null || message.noiDung().isBlank())
            throw new IllegalArgumentException("Tin nhắn đến thiếu kênh, mã tin, định danh hoặc nội dung");
        String channel = message.maKenh().toUpperCase(java.util.Locale.ROOT);
        if (!"FACEBOOK".equals(channel) && !"ZALO".equals(channel))
            throw new IllegalArgumentException("Luồng chat chưa hỗ trợ kênh " + channel);
        if (message.maTinGoc().isBlank() || message.maNguoiDungKenh().isBlank())
            throw new IllegalArgumentException("Tin nhắn đến thiếu mã tin hoặc định danh người gửi");
        if (!repository.isChannelEnabled(channel))
            throw new IllegalStateException("Kênh " + channel + " chưa được cấu hình hoặc đang tắt");

        message = normalized(message, channel);

        InboundReplyRepository.ExistingMessage existing = repository.findExisting(channel, message.maTinGoc().trim());
        if (existing != null)
            return new StoredReply(existing.caseId(), existing.caseNumber(), "DA_TON_TAI");

        InboundReplyRepository.LinkFacts link = repository.findLinkFacts(channel, message.maNguoiDungKenh().trim());
        if (link == null) return new StoredReply(null, null, "CHUA_CO_DINH_DANH");
        if (link.openCaseCount() == 0) return new StoredReply(null, null, "KHONG_CO_HO_SO_MO");
        if (link.openCaseCount() > 1) return new StoredReply(null, null, "NHIEU_HO_SO_MO");

        boolean saved = repository.saveClassifiedMessage(message, link.caseId(), channel);
        if (!saved) {
            existing = repository.findExisting(channel, message.maTinGoc().trim());
            if (existing != null) return new StoredReply(existing.caseId(), existing.caseNumber(), "DA_TON_TAI");
        }
        return new StoredReply(link.caseId(), link.caseNumber(), saved ? "DA_GHI_NHAN" : "DA_TON_TAI");
    }
    public void saveConversation(InboundChannelReply message, Long caseId) {
        repository.saveConversation(normalized(message, message.maKenh().toUpperCase(java.util.Locale.ROOT)), caseId);
    }
    public void saveForFollowUp(InboundChannelReply message, String reason) {
        repository.saveForFollowUp(normalized(message, message.maKenh().toUpperCase(java.util.Locale.ROOT)), reason);
    }

    private static InboundChannelReply normalized(InboundChannelReply message, String channel) {
        return new InboundChannelReply(channel, message.maTinGoc().trim(), message.maNguoiDungKenh().trim(),
            message.noiDung().trim(), message.nhanLuc());
    }

    public record StoredReply(Long caseId, String caseNumber, String result) {}
}
