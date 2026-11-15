package haumai.core.controller;

import haumai.core.service.KyThuatVienService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataAccessException;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

@Controller
public class KyThuatVienController {
    private static final Logger log = LoggerFactory.getLogger(KyThuatVienController.class);
    private final KyThuatVienService service;

    public KyThuatVienController(KyThuatVienService service) {
        this.service = service;
    }

    @GetMapping("/nhan-vien/ky-thuat-vien/ho-so")
    public String danhSachHoSoKyThuatVien(Authentication authentication, Model model) {
        model.addAttribute("username", authentication.getName());
        model.addAttribute("coQuyenSla", false);
        model.addAttribute("slaTheoHoSo", service.slaByCase());
        model.addAttribute("hoSos", service.workFor(authentication.getName()));
        return "ho-so/ky-thuat-vien";
    }

    @PostMapping("/nhan-vien/ky-thuat-vien/phan-cong/{phanCongId}/tiep-nhan")
    public String tiepNhanHoSoKyThuatVien(@PathVariable Long phanCongId,
                                          Authentication authentication,
                                          RedirectAttributes redirectAttributes) {
        try {
            service.accept(phanCongId, authentication.getName());
            redirectAttributes.addFlashAttribute("thongBaoThanhCong",
                "Đã tiếp nhận hồ sơ. Trạng thái chuyển sang Đang sửa chữa.");
        } catch (DataAccessException | IllegalStateException ex) {
            log.error("Không tiếp nhận được phân công id={}", phanCongId, ex);
            redirectAttributes.addFlashAttribute("loiThaoTac",
                "Không tiếp nhận được hồ sơ. Hồ sơ có thể đã được tiếp nhận hoặc không còn thuộc bạn.");
        }
        return "redirect:/nhan-vien/ky-thuat-vien/ho-so#phan-cong-" + phanCongId;
    }

    @PostMapping("/nhan-vien/ky-thuat-vien/phan-cong/{phanCongId}/hoan-tat")
    public String hoanTatSuaChua(@PathVariable Long phanCongId,
                                 Authentication authentication,
                                 RedirectAttributes redirectAttributes) {
        try {
            service.complete(phanCongId, authentication.getName());
            redirectAttributes.addFlashAttribute("thongBaoThanhCong",
                "Đã hoàn thành sửa chữa và cập nhật trạng thái hồ sơ.");
        } catch (DataAccessException | IllegalStateException ex) {
            log.error("Không chốt được kết quả sửa chữa phân công id={}", phanCongId, ex);
            redirectAttributes.addFlashAttribute("loiThaoTac",
                "Không hoàn thành được hồ sơ. Hãy tiếp nhận hồ sơ trước hoặc kiểm tra quyền được phân công.");
        }
        return "redirect:/nhan-vien/ky-thuat-vien/ho-so#phan-cong-" + phanCongId;
    }
}
