package haumai.core.service;

import haumai.core.repository.HoSoWorkflowRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.OffsetDateTime;
import java.time.ZoneId;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.Map;

/** Application/business layer for staff case workflows. */
@Service
public class HoSoService {
    private static final ZoneId BUSINESS_ZONE = ZoneId.of("Asia/Ho_Chi_Minh");
    private final HoSoWorkflowRepository workflowRepository;
    private final HoSoQueryService queryService;
    private final CaseStatusPolicy statusPolicy;
    private final SlaService slaService;

    public HoSoService(HoSoWorkflowRepository workflowRepository, HoSoQueryService queryService,
                       CaseStatusPolicy statusPolicy, SlaService slaService) {
        this.workflowRepository = workflowRepository;
        this.queryService = queryService;
        this.statusPolicy = statusPolicy;
        this.slaService = slaService;
    }

    public Map<String, Object> verificationForm(Long caseId) {
        Map<String, Object> facts = queryService.verificationForm(caseId);
        String serial = (String) facts.get("serial");
        if (serial == null || serial.isBlank()) serial = (String) facts.get("serial_khach_khai_bao");
        facts.put("serial", serial);
        LocalDate expiry = asLocalDate(facts.get("ngay_het_han_bao_hanh"));
        LocalDate purchase = asLocalDate(facts.get("ngay_mua"));
        Object termValue = facts.get("thoi_han_bao_hanh_thang");
        if (expiry == null && purchase != null && termValue instanceof Number months && months.intValue() >= 0) {
            expiry = purchase.plusMonths(months.longValue());
            facts.put("ngay_het_han_bao_hanh", expiry);
        }
        LocalDate received = asLocalDate(facts.get("ngay_xac_minh"));
        Boolean inWarranty = serial == null || serial.isBlank() || facts.get("ten_san_pham") == null
            || expiry == null || received == null ? null : !received.isAfter(expiry);
        facts.put("con_bao_hanh", inWarranty);
        return facts;
    }

    @Transactional
    public boolean updateDetails(Long caseId, String fullName, String phone, String serial,
                                 String description, String username) {
        String currentStatus = workflowRepository.findCaseStatus(caseId);
        if (!"DANG_XAC_MINH".equals(currentStatus) && !"CHO_KHACH_BO_SUNG".equals(currentStatus)) {
            throw new IllegalStateException("Chỉ sửa được hồ sơ đang xác minh hoặc chờ khách bổ sung");
        }
        Long employeeId = workflowRepository.findActiveEmployeeId(username, "CSKH");
        boolean resumeVerification = "CHO_KHACH_BO_SUNG".equals(currentStatus);
        if (resumeVerification) statusPolicy.requireAllowed(currentStatus, "DANG_XAC_MINH");
        OffsetDateTime now = OffsetDateTime.now(BUSINESS_ZONE);
        workflowRepository.updateCaseDetails(caseId, required(fullName, "Họ tên"),
            required(phone, "Số điện thoại"), blankToNull(serial),
            required(description, "Mô tả lỗi"), employeeId, resumeVerification,
            now);
        if (resumeVerification) slaService.onCaseTransition(caseId, currentStatus, "DANG_XAC_MINH", now);
        return resumeVerification;
    }

    @Transactional
    public void assign(Long caseId, Long technicianId, String reason, String username) {
        if (technicianId == null) throw new IllegalArgumentException("Cần chọn kỹ thuật viên");
        Long dispatcherId = workflowRepository.findActiveEmployeeId(username, "DIEU_PHOI_VIEN");
        String status = workflowRepository.findCaseStatus(caseId);
        if (!"CHO_PHAN_CONG".equals(status) && !"DANG_SUA_CHUA".equals(status))
            throw new IllegalStateException("Chỉ phân công hồ sơ đang chờ phân công hoặc đang sửa chữa");
        if (!workflowRepository.isActiveTechnician(technicianId))
            throw new IllegalArgumentException("Kỹ thuật viên không hợp lệ hoặc đã bị khóa");
        Long currentTechnicianId = workflowRepository.currentTechnicianForCase(caseId);
        if ("DANG_SUA_CHUA".equals(status) && currentTechnicianId == null)
            throw new IllegalStateException("Không tìm thấy phân công hiện tại để đổi kỹ thuật viên");
        if (technicianId.equals(currentTechnicianId))
            throw new IllegalArgumentException("Hồ sơ đã được giao cho kỹ thuật viên này");
        int capacity = workflowRepository.technicianCapacity();
        if (capacity <= 0) throw new IllegalStateException("Giới hạn hồ sơ trên mỗi kỹ thuật viên phải lớn hơn 0");
        int workload = workflowRepository.activeCaseCount(technicianId, caseId);
        if (workload >= capacity)
            throw new IllegalStateException("Kỹ thuật viên đã đủ tải: " + workload + "/" + capacity + " hồ sơ");
        // The procedure keeps row locks and atomic writes; these service checks provide the application rules.
        String assignmentReason = blankToNull(reason);
        if (assignmentReason == null)
            assignmentReason = "CHO_PHAN_CONG".equals(status) ? "Phân công lần đầu" : "Đổi kỹ thuật viên";
        OffsetDateTime now = OffsetDateTime.now(BUSINESS_ZONE);
        workflowRepository.assign(caseId, technicianId, dispatcherId, assignmentReason, now);
        slaService.startRepairSla(caseId, now);
    }

    @Transactional
    public void close(Long caseId, String note, String username) {
        Long employeeId = workflowRepository.findActiveEmployeeId(username, "CSKH");
        var facts = workflowRepository.findClosureFacts(caseId);
        OffsetDateTime now = OffsetDateTime.now(BUSINESS_ZONE);
        if ("CHO_KHACH_BO_SUNG".equals(facts.status())) {
            if (facts.waitingDays() <= 0) throw new IllegalStateException("Số ngày chờ khách phải lớn hơn 0");
            if (facts.waitingSince() == null) throw new IllegalStateException("Hồ sơ thiếu thời điểm bắt đầu chờ khách");
            if (now.isBefore(facts.waitingSince().plusDays(facts.waitingDays()))) {
                throw new IllegalStateException("Chưa hết thời hạn " + facts.waitingDays() + " ngày chờ khách");
            }
        } else if (!java.util.Set.of("DA_SUA_XONG", "TU_CHOI", "CHO_CSKH_XU_LY").contains(facts.status())) {
            throw new IllegalStateException("Không thể đóng hồ sơ đang ở trạng thái " + facts.status());
        }
        String closeNote = blankToNull(note);
        statusPolicy.requireAllowed(facts.status(), "DA_DONG");
        workflowRepository.transition(caseId, "DA_DONG", employeeId,
            closeNote == null ? "CSKH đóng hồ sơ sau khi xử lý với khách hàng" : closeNote, now);
        slaService.onCaseTransition(caseId, facts.status(), "DA_DONG", now);
    }

    @Transactional
    public void verify(Long caseId, String decision, String rejectionReason, String username) {
        Long employeeId = workflowRepository.findActiveEmployeeId(username, "CSKH");
        Map<String, Object> facts = verificationForm(caseId);
        Boolean inWarranty = (Boolean) facts.get("con_bao_hanh");
        String serial = (String) facts.get("serial");
        String productName = (String) facts.get("ten_san_pham");
        String nextStatus;
        String result;
        String reason = blankToNull(rejectionReason);
        boolean outsideWarranty = false;
        String normalizedDecision = blankToNull(decision);

        if (inWarranty == null) {
            nextStatus = "CHO_KHACH_BO_SUNG";
            reason = null;
            if (serial == null || serial.isBlank()) result = "Khách chưa cung cấp serial sản phẩm.";
            else if (productName == null) result = "Không tìm thấy sản phẩm có serial " + serial + ".";
            else result = "Thiếu dữ liệu ngày mua hoặc thời hạn bảo hành.";
        } else if (!inWarranty) {
            LocalDate expiry = asLocalDate(facts.get("ngay_het_han_bao_hanh"));
            if ("SUA_CHUA_CO_PHI".equals(normalizedDecision)) {
                nextStatus = "CHO_PHAN_CONG";
                outsideWarranty = true;
                reason = null;
                result = "Sản phẩm hết hạn bảo hành ngày " + formatDate(expiry)
                    + ". Khách đã đồng ý sửa chữa ngoài bảo hành có tính phí.";
            } else if ("TU_CHOI".equals(normalizedDecision)) {
                nextStatus = "TU_CHOI";
                if (reason == null) reason = "Khách không đồng ý sửa chữa ngoài bảo hành có tính phí.";
                result = "Sản phẩm đã hết hạn bảo hành ngày " + formatDate(expiry)
                    + "; khách không đồng ý sửa chữa có tính phí.";
            } else throw new IllegalArgumentException("Cần ghi nhận khách đồng ý sửa có phí hoặc từ chối sửa");
        } else {
            if (!"DU_DIEU_KIEN".equals(normalizedDecision) && !"TU_CHOI".equals(normalizedDecision))
                throw new IllegalArgumentException("Sản phẩm còn hạn: quyết định phải là DU_DIEU_KIEN hoặc TU_CHOI");
            result = "Sản phẩm còn bảo hành đến ngày " + formatDate(asLocalDate(facts.get("ngay_het_han_bao_hanh"))) + ".";
            if ("DU_DIEU_KIEN".equals(normalizedDecision)) {
                nextStatus = "CHO_PHAN_CONG";
                reason = null;
            } else {
                nextStatus = "TU_CHOI";
                if (reason == null) throw new IllegalArgumentException("Từ chối hồ sơ cần có lý do");
            }
        }

        String note = reason == null ? result : result + " Lý do: " + reason;
        statusPolicy.requireAllowed((String) facts.get("trang_thai"), nextStatus);
        OffsetDateTime now = OffsetDateTime.now(BUSINESS_ZONE);
        String currentStatus = (String) facts.get("trang_thai");
        workflowRepository.saveVerificationOutcome(caseId, result, reason, outsideWarranty);
        workflowRepository.transition(caseId, nextStatus, employeeId, note, now);
        slaService.onCaseTransition(caseId, currentStatus, nextStatus, now);
    }

    private static String required(String value, String label) {
        if (value == null || value.isBlank()) throw new IllegalArgumentException(label + " không được để trống");
        return value.trim();
    }

    private static String blankToNull(String value) {
        return value == null || value.isBlank() ? null : value.trim();
    }

    private static LocalDate asLocalDate(Object value) {
        if (value instanceof LocalDate date) return date;
        if (value instanceof java.sql.Date date) return date.toLocalDate();
        if (value instanceof java.time.OffsetDateTime timestamp) return timestamp.toLocalDate();
        if (value instanceof java.time.LocalDateTime timestamp) return timestamp.toLocalDate();
        if (value instanceof String text) return LocalDate.parse(text);
        return null;
    }

    private static String formatDate(LocalDate date) {
        return date == null ? "chưa xác định" : date.format(DateTimeFormatter.ofPattern("dd/MM/yyyy"));
    }
}
