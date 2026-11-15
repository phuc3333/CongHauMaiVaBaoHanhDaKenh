package haumai.core.service;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import haumai.contract.ChannelStreams;
import haumai.contract.OutboundChannelMessage;
import haumai.core.repository.ConversationRepository;
import haumai.core.repository.HoSoWorkflowRepository;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;

@Service
public class ConversationService {
    private final ConversationRepository repository;
    private final StringRedisTemplate redis;
    private final ObjectMapper objectMapper;
    private final HoSoWorkflowRepository workflowRepository;
    private final CaseStatusPolicy statusPolicy;
    private final SlaService slaService;

    public ConversationService(ConversationRepository repository, StringRedisTemplate redis,
                               ObjectMapper objectMapper, HoSoWorkflowRepository workflowRepository,
                               CaseStatusPolicy statusPolicy, SlaService slaService) {
        this.repository = repository;
        this.redis = redis;
        this.objectMapper = objectMapper;
        this.workflowRepository = workflowRepository;
        this.statusPolicy = statusPolicy;
        this.slaService = slaService;
    }

    public List<ConversationMessage> conversationMessages(Long id) {
        return repository.conversationMessages(id).stream().map(row -> new ConversationMessage(
            row.get("huong_tin").toString(), row.get("noi_dung").toString(),
            row.get("trang_thai_gui").toString(), row.get("thoi_gian").toString())).toList();
    }

    public List<ConversationSummary> unlinkedConversations() {
        return repository.unlinkedConversations().stream().map(row -> new ConversationSummary(
            ((Number) row.get("id")).longValue(), row.get("ma_kenh").toString(),
            row.get("ma_nguoi_dung_kenh").toString(),
            row.get("ho_so_id") == null ? null : ((Number) row.get("ho_so_id")).longValue(),
            (String) row.get("tin_moi_nhat"), row.get("cap_nhat_luc").toString())).toList();
    }

    public List<ConversationMessage> caseMessages(Long id) {
        return repository.caseMessages(id).stream().map(row -> new ConversationMessage(
            row.get("huong_tin").toString(), row.get("noi_dung").toString(),
            row.get("trang_thai_gui").toString(), row.get("thoi_gian").toString())).toList();
    }

    @Transactional
    public CreatedCase createCase(Long conversationId, String name, String phone,
                                  String description, String serial) {
        OffsetDateTime now = OffsetDateTime.now(ZoneId.of("Asia/Ho_Chi_Minh"));
        ConversationRepository.CreatedCase created = repository.createCaseFromConversation(conversationId,
            required(name, "Họ tên"), required(phone, "Số điện thoại"),
            required(description, "Mô tả lỗi"), blankToNull(serial),
            now);
        String status = workflowRepository.findCaseStatus(created.caseId());
        if ("MOI".equals(status)) {
            statusPolicy.requireAllowed(status, "DANG_XAC_MINH");
            workflowRepository.transitionSystem(created.caseId(), "DANG_XAC_MINH",
                "Hồ sơ mới được đưa vào bước xác minh.", now);
            slaService.onCaseTransition(created.caseId(), status, "DANG_XAC_MINH", now);
        }
        return new CreatedCase(created.caseId(), created.caseNumber());
    }

    @Transactional
    public String replyToConversation(Long conversationId, String content, String username) {
        String message = validateMessage(content);
        Long employeeId = repository.activeCskhId(username);
        ConversationRepository.ReplyTarget target = repository.createConversationReply(
            conversationId, employeeId, message, OffsetDateTime.now(ZoneId.of("Asia/Ho_Chi_Minh")));
        enqueue(new OutboundChannelMessage(null, target.channel(), target.recipient(), message,
            target.messageId()));
        return target.channel();
    }

    @Transactional
    public void replyToCase(Long caseId, String channel, String content, String username) {
        String message = validateMessage(content);
        if (!"FACEBOOK".equals(channel) && !"ZALO".equals(channel)) {
            throw new IllegalArgumentException("Kênh phản hồi không được hỗ trợ");
        }
        Long employeeId = repository.activeCskhId(username);
        ConversationRepository.ReplyTarget target = repository.createCaseReply(caseId, employeeId,
            message, channel, OffsetDateTime.now(ZoneId.of("Asia/Ho_Chi_Minh")));
        enqueue(new OutboundChannelMessage(target.messageId(), target.channel(), target.recipient(), message));
    }

    private void enqueue(OutboundChannelMessage message) {
        try {
            String payload = objectMapper.writeValueAsString(message);
            if (redis.opsForStream().add(ChannelStreams.OUTBOUND_REQUESTS,
                Map.of("payload", payload)) == null) {
                throw new IllegalStateException("Redis chưa nhận được phản hồi");
            }
        } catch (JsonProcessingException ex) {
            throw new IllegalStateException("Không thể chuyển phản hồi thành JSON", ex);
        }
    }

    private static String validateMessage(String content) {
        String value = content == null ? "" : content.trim();
        if (value.isEmpty() || value.length() > 2000) {
            throw new IllegalArgumentException("Nội dung phải từ 1 đến 2000 ký tự.");
        }
        return value;
    }

    private static String required(String value, String label) {
        if (value == null || value.isBlank()) throw new IllegalArgumentException(label + " không được để trống");
        return value.trim();
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }

    public record ConversationMessage(String direction, String content, String status, String time) {}
    public record ConversationSummary(Long id, String channel, String senderId, Long caseId,
                                      String preview, String updatedAt) {}
    public record CreatedCase(Long caseId, String caseNumber) {}
}
