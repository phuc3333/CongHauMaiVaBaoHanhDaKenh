package haumai.core.controller;

import haumai.core.dto.PhanCongForm;
import haumai.core.dto.XacMinhForm;
import haumai.core.repository.HoSoRepository;
import haumai.core.service.HoSoService;
import haumai.core.service.HoSoQueryService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.ModelAttribute;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;
import org.springframework.web.server.ResponseStatusException;

import static org.springframework.http.HttpStatus.NOT_FOUND;
import static org.springframework.http.HttpStatus.FORBIDDEN;

import java.time.format.DateTimeFormatter;
import java.time.ZoneId;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

@Controller
public class HoSoController {
    private static final Logger log = LoggerFactory.getLogger(HoSoController.class);

    private final HoSoRepository hoSoRepository;
    private final HoSoService hoSoService;
    private final HoSoQueryService queryService;

    public HoSoController(
        HoSoRepository hoSoRepository,
        HoSoService hoSoService,
        HoSoQueryService queryService
    ) {
        this.hoSoRepository = hoSoRepository;
        this.hoSoService = hoSoService;
        this.queryService = queryService;
    }


    private Map<Long, List<Map<String, Object>>> laySlaTheoHoSo() {
        return queryService.slas().stream().collect(Collectors.groupingBy(
            row -> ((Number) row.get("ho_so_id")).longValue()
        ));
    }


    @GetMapping("/nhan-vien/ho-so")
    public String danhSach(
        Authentication authentication,
        Model model,
        @RequestParam(required = false) Long caseId,
        @RequestParam(required = false) Long conversationId
    ) {
        model.addAttribute("username", authentication.getName());
        boolean laDieuPhoiVien = authentication.getAuthorities().stream()
            .anyMatch(role -> role.getAuthority().equals("ROLE_DIEU_PHOI_VIEN"));
        boolean laCskh = authentication.getAuthorities().stream()
            .anyMatch(role -> role.getAuthority().equals("ROLE_CSKH"));
        model.addAttribute("laDieuPhoiVien", laDieuPhoiVien);
        model.addAttribute("laCskh", laCskh);
        model.addAttribute("coQuyenSla", laDieuPhoiVien);
        var hoSos = hoSoRepository.findAllByOrderByNgayTiepNhanDesc();
        model.addAttribute("hoSos", hoSos);
        DateTimeFormatter dinhDangNgayGio = DateTimeFormatter
            .ofPattern("dd/MM/yyyy HH:mm")
            .withZone(ZoneId.of("Asia/Ho_Chi_Minh"));
        model.addAttribute(
            "thoiGianTiepNhanTheoHoSo",
            hoSos.stream().collect(Collectors.toMap(
                hoSo -> hoSo.getId(),
                hoSo -> dinhDangNgayGio.format(hoSo.getNgayTiepNhan())
            ))
        );
        model.addAttribute(
            "kyThuatVienTheoHoSo",
            queryService.techniciansByCase().stream().collect(Collectors.toMap(
                row -> ((Number) row.get("ho_so_id")).longValue(),
                row -> row.get("ky_thuat_vien").toString()
            ))
        );
        model.addAttribute(
            "thongTinKhachHangTheoHoSo",
            queryService.customerByCase().stream().collect(Collectors.toMap(
                row -> ((Number) row.get("ho_so_id")).longValue(),
                row -> row
            ))
        );
        model.addAttribute("slaTheoHoSo", laySlaTheoHoSo());
        model.addAttribute("cuocTroChuyen", laCskh
            ? queryService.openConversations()
            : List.of());
        Set<Long> hoSoZalo = queryService.zaloCaseIds().stream().collect(Collectors.toSet());
        model.addAttribute("hoSoZalo", hoSoZalo);
        Set<Long> hoSoFacebook = queryService.facebookCaseIds().stream().collect(Collectors.toSet());
        model.addAttribute("hoSoFacebook", hoSoFacebook);
        var hoSoDangChon = conversationId != null ? null : hoSos.stream()
            .filter(hoSo -> caseId != null && hoSo.getId().equals(caseId))
            .findFirst()
            .orElse(hoSos.isEmpty() ? null : hoSos.getFirst());
        model.addAttribute("hoSoDangChon", hoSoDangChon);
        Map<String, Object> cuocTroChuyenDangChon = null;
        if (laCskh && conversationId != null) {
            var selected = queryService.conversation(conversationId);
            if (!selected.isEmpty()) cuocTroChuyenDangChon = selected.getFirst();
        }
        model.addAttribute("cuocTroChuyenDangChon", cuocTroChuyenDangChon);
        return "ho-so/danh-sach";
    }

    @GetMapping("/nhan-vien/ho-so/{id}/sua")
    public String moTrangSuaHoSo(
        @PathVariable Long id,
        Authentication authentication,
        Model model
    ) {
        if (!laCskh(authentication)) throw new ResponseStatusException(FORBIDDEN);
        try {
            var hoSo = queryService.editForm(id);
            model.addAttribute("hoSo", hoSo);
            model.addAttribute("dangChoKhachBoSung", "CHO_KHACH_BO_SUNG".equals(hoSo.get("trang_thai")));
            model.addAttribute("username", authentication.getName());
            model.addAttribute("coQuyenSla", false);
            return "ho-so/chinh-sua";
        } catch (DataAccessException ex) {
            log.error("Không tải được hồ sơ để chỉnh sửa id={}", id, ex);
            throw new ResponseStatusException(NOT_FOUND, "Chỉ sửa được hồ sơ đang xác minh hoặc chờ khách bổ sung");
        }
    }

    @PostMapping("/nhan-vien/ho-so/{id}/sua")
    public String suaHoSo(
        @PathVariable Long id,
        @RequestParam String hoTen,
        @RequestParam String soDienThoai,
        @RequestParam(required = false) String serial,
        @RequestParam String moTa,
        Authentication authentication,
        RedirectAttributes redirectAttributes
    ) {
        if (!laCskh(authentication)) throw new ResponseStatusException(FORBIDDEN);
        try {
            boolean resumed = hoSoService.updateDetails(id, hoTen, soDienThoai, serial, moTa,
                authentication.getName());
            redirectAttributes.addFlashAttribute("thongBaoThanhCong",
                "Đã cập nhật thông tin hồ sơ." + (resumed
                    ? " Hồ sơ đã quay lại trạng thái đang xác minh." : ""));
            return "redirect:/nhan-vien/ho-so?caseId=" + id;
        } catch (Exception ex) {
            log.error("Không cập nhật được hồ sơ id={}", id, ex);
            redirectAttributes.addFlashAttribute("loiThaoTac",
                "Chưa cập nhật được hồ sơ. Hãy kiểm tra thông tin và trạng thái hiện tại.");
            return "redirect:/nhan-vien/ho-so/" + id + "/sua";
        }
    }

    private static boolean laCskh(Authentication authentication) {
        return authentication != null && authentication.getAuthorities().stream()
            .anyMatch(role -> role.getAuthority().equals("ROLE_CSKH"));
    }


    @GetMapping("/nhan-vien/ho-so/{id}/phan-cong")
    public String moTrangPhanCong(
        @PathVariable Long id,
        Authentication authentication,
        Model model
    ) {
        try {
            var hoSo = queryService.assignmentForm(id);
            model.addAttribute("hoSo", hoSo);
            model.addAttribute("username", authentication.getName());
            model.addAttribute("coQuyenSla", true);
            model.addAttribute(
                "kyThuatViens",
                queryService.technicians()
            );
            model.addAttribute("form", new PhanCongForm());
            return "ho-so/phan-cong";
        } catch (DataAccessException ex) {
            log.error("Không tải được trang phân công hồ sơ id={}", id, ex);
            throw new ResponseStatusException(NOT_FOUND, "Không tìm thấy hồ sơ cần phân công");
        }
    }

    @PostMapping("/nhan-vien/ho-so/{id}/phan-cong")
    public String phanCong(
        @PathVariable Long id,
        @ModelAttribute("form") PhanCongForm form,
        Authentication authentication,
        RedirectAttributes redirectAttributes
    ) {
        if (form.getKyThuatVienId() == null) {
            redirectAttributes.addFlashAttribute("loiThaoTac", "Hãy chọn kỹ thuật viên trước khi xác nhận.");
            return "redirect:/nhan-vien/ho-so#ho-so-" + id;
        }
        try {
            hoSoService.assign(id, form.getKyThuatVienId(), form.getLyDoThayDoi(), authentication.getName());

            redirectAttributes.addFlashAttribute(
                "thongBaoThanhCong",
                "Đã phân công hồ sơ cho kỹ thuật viên."
            );
        } catch (DataAccessException | IllegalArgumentException | IllegalStateException ex) {
            log.error("Không phân công được hồ sơ id={}", id, ex);
            redirectAttributes.addFlashAttribute(
                "loiThaoTac",
                "Không phân công được. Kiểm tra kỹ thuật viên, giới hạn tải và trạng thái hồ sơ."
            );
        }
        return "redirect:/nhan-vien/ho-so#ho-so-" + id;
    }
    @PostMapping("/nhan-vien/ho-so/{id}/dong")
    public String dongHoSo(
        @PathVariable Long id,
        @RequestParam(required = false) String ghiChu,
        Authentication authentication,
        RedirectAttributes redirectAttributes
    ) {
        try {
            hoSoService.close(id, ghiChu, authentication.getName());

            redirectAttributes.addFlashAttribute(
                "thongBaoThanhCong",
                "Đã đóng hồ sơ."
            );
        } catch (DataAccessException | IllegalStateException ex) {
            log.error("Không đóng được hồ sơ id={}", id, ex);
            redirectAttributes.addFlashAttribute(
                "loiThaoTac",
                "Không thể đóng hồ sơ. Có thể hồ sơ chưa đủ điều kiện hoặc thời gian chờ khách chưa hết."
            );
        }
        return "redirect:/nhan-vien/ho-so#ho-so-" + id;
    }
    @GetMapping("/nhan-vien/ho-so/{id}/xac-minh")
    public String moTrangXacMinh(
        @PathVariable Long id,
        Authentication authentication,
        Model model
    ) {
        try {
            var hoSo = hoSoService.verificationForm(id);

            model.addAttribute("hoSo", hoSo);
            model.addAttribute("username", authentication.getName());
            model.addAttribute("coQuyenSla", false);
            model.addAttribute("form", new XacMinhForm());
            return "ho-so/xac-minh";
        } catch (DataAccessException | IllegalArgumentException | IllegalStateException ex) {
            log.error("Không tải được hồ sơ xác minh id={}", id, ex);
            throw new ResponseStatusException(NOT_FOUND, "Không tìm thấy hồ sơ đang xác minh");
        }
    }
    @PostMapping("/nhan-vien/ho-so/{id}/xac-minh")
    public String xacMinh(
        @PathVariable Long id,
        @ModelAttribute("form") XacMinhForm form,
        Authentication authentication,
        RedirectAttributes redirectAttributes
    ) {
        try {
            hoSoService.verify(id, form.getQuyetDinh(), form.getLyDoTuChoi(), authentication.getName());

            redirectAttributes.addFlashAttribute(
                "thongBaoThanhCong",
                "Đã gửi kết quả xác minh. Trạng thái hồ sơ đã được cập nhật."
            );
        } catch (DataAccessException | IllegalArgumentException | IllegalStateException ex) {
            log.error("Không xác minh được hồ sơ id={}", id, ex);
            redirectAttributes.addFlashAttribute(
                "loiThaoTac",
                "Không thể xác minh hồ sơ. Kiểm tra quyết định, lý do và trạng thái hiện tại."
            );
        }

        return "redirect:/nhan-vien/ho-so#ho-so-" + id;
    }
}
