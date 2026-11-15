package haumai.core.service;

import haumai.core.repository.KyThuatVienRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
public class KyThuatVienService {
    private final KyThuatVienRepository repository;
    private final CaseStatusPolicy statusPolicy;
    private final SlaService slaService;

    public KyThuatVienService(KyThuatVienRepository repository, CaseStatusPolicy statusPolicy, SlaService slaService) {
        this.repository = repository;
        this.statusPolicy = statusPolicy;
        this.slaService = slaService;
    }

    public List<Map<String, Object>> workFor(String username) {
        return repository.findWork(repository.findTechnicianId(username));
    }

    public Map<Long, List<Map<String, Object>>> slaByCase() {
        return repository.findSla().stream().collect(Collectors.groupingBy(
            row -> ((Number) row.get("ho_so_id")).longValue()));
    }

    @Transactional
    public void accept(Long assignmentId, String username) {
        Long technicianId = repository.findTechnicianId(username);
        var assignment = repository.assignmentFacts(assignmentId);
        if (!assignment.active() || !technicianId.equals(assignment.technicianId()))
            throw new IllegalStateException("Phân công không còn hiệu lực hoặc không thuộc kỹ thuật viên này");
        if (!"CHO_PHAN_CONG".equals(assignment.caseStatus()))
            throw new IllegalStateException("Hồ sơ không còn ở trạng thái chờ tiếp nhận");
        statusPolicy.requireAllowed(assignment.caseStatus(), "DANG_SUA_CHUA");
        if (!"DA_NHAN_THIET_BI".equals(assignment.progressStatus()))
            throw new IllegalStateException("Hồ sơ đã được tiếp nhận");
        OffsetDateTime now = OffsetDateTime.now(ZoneId.of("Asia/Ho_Chi_Minh"));
        repository.accept(assignmentId, now);
        repository.transition(assignment.caseId(), "DANG_SUA_CHUA", technicianId,
            "Kỹ thuật viên tiếp nhận sửa chữa", now);
        slaService.onCaseTransition(assignment.caseId(), assignment.caseStatus(), "DANG_SUA_CHUA", now);
    }

    @Transactional
    public void complete(Long assignmentId, String username) {
        Long technicianId = repository.findTechnicianId(username);
        var assignment = repository.assignmentFacts(assignmentId);
        if (!assignment.active() || !technicianId.equals(assignment.technicianId()))
            throw new IllegalStateException("Phân công không còn hiệu lực hoặc không thuộc kỹ thuật viên này");
        if (!"DANG_SUA_CHUA".equals(assignment.caseStatus()) || !"DANG_SUA_CHUA".equals(assignment.progressStatus()))
            throw new IllegalStateException("Chỉ hoàn thành khi hồ sơ đang sửa chữa");
        statusPolicy.requireAllowed(assignment.caseStatus(), "DA_SUA_XONG");
        OffsetDateTime now = OffsetDateTime.now(ZoneId.of("Asia/Ho_Chi_Minh"));
        repository.complete(assignment.caseId(), assignmentId, now);
        repository.transition(assignment.caseId(), "DA_SUA_XONG", technicianId,
            "Đã hoàn thành sửa chữa.", now);
        slaService.onCaseTransition(assignment.caseId(), assignment.caseStatus(), "DA_SUA_XONG", now);
    }
}
