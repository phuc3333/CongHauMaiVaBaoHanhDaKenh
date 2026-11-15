package haumai.core.service;

import haumai.contract.InboundChannelMessage;
import haumai.core.repository.InboundChannelRepository;
import haumai.core.repository.HoSoWorkflowRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.OffsetDateTime;
import java.time.ZoneId;

@Service
public class InboundChannelService {
    private final InboundChannelRepository repository;
    private final SlaService slaService;
    private final HoSoWorkflowRepository workflowRepository;
    private final CaseStatusPolicy statusPolicy;
    public InboundChannelService(InboundChannelRepository repository, SlaService slaService,
                                 HoSoWorkflowRepository workflowRepository, CaseStatusPolicy statusPolicy) {
        this.repository = repository; this.slaService = slaService;
        this.workflowRepository = workflowRepository; this.statusPolicy = statusPolicy;
    }
    @Transactional
    public InboundChannelRepository.CreationResult createCase(InboundChannelMessage message) {
        if (message == null || message.maKenh() == null || message.maTinGoc() == null) {
            throw new IllegalArgumentException("Tin nhắn đầu vào thiếu kênh hoặc mã tin nhắn");
        }
        var created = repository.createCase(message);
        OffsetDateTime receivedAt = message.nhanLuc() == null
            ? OffsetDateTime.now(ZoneId.of("Asia/Ho_Chi_Minh")) : message.nhanLuc();
        String status = workflowRepository.findCaseStatus(created.caseId());
        if ("MOI".equals(status)) {
            statusPolicy.requireAllowed(status, "DANG_XAC_MINH");
            workflowRepository.transitionSystem(created.caseId(), "DANG_XAC_MINH",
                "Hồ sơ mới được đưa vào bước xác minh.", receivedAt);
            slaService.onCaseTransition(created.caseId(), status, "DANG_XAC_MINH", receivedAt);
        } else if ("DANG_XAC_MINH".equals(status)) {
            slaService.deferRepairUntilAssignment(created.caseId(), receivedAt);
        }
        return created;
    }
}
