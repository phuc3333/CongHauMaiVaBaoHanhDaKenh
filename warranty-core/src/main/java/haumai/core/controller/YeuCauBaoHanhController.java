package haumai.core.controller;

import haumai.core.service.PortalQueryService;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;

@Controller
public class YeuCauBaoHanhController {
    private final PortalQueryService portalQueryService;

    public YeuCauBaoHanhController(PortalQueryService portalQueryService) {
        this.portalQueryService = portalQueryService;
    }

    @GetMapping("/khach/tra-cuu")
    public String hienThiTraCuu(Model model) {
        if (!model.containsAttribute("maHoSoNhap")) {
            model.addAttribute("maHoSoNhap", "");
        }
        if (!model.containsAttribute("soDienThoaiNhap")) {
            model.addAttribute("soDienThoaiNhap", "");
        }
        return "khach/tra-cuu";
    }

    @GetMapping("/khach/kiem-tra-bao-hanh")
    public String hienThiKiemTraBaoHanh(Model model) {
        if (!model.containsAttribute("serialNhap")) {
            model.addAttribute("serialNhap", "");
        }
        return "khach/kiem-tra-bao-hanh";
    }

    @PostMapping("/khach/kiem-tra-bao-hanh")
    public String kiemTraBaoHanh(@RequestParam String serial, Model model) {
        String serialDaNhap = serial == null ? "" : serial.trim();
        model.addAttribute("serialNhap", serialDaNhap);

        if (serialDaNhap.isBlank()) {
            model.addAttribute("loiKiemTraBaoHanh", "Vui lòng nhập serial sản phẩm.");
            return "khach/kiem-tra-bao-hanh";
        }

        var ketQua = portalQueryService.warrantyBySerial(serialDaNhap);

        if (ketQua.isEmpty()) {
            model.addAttribute(
                "loiKiemTraBaoHanh",
                "Chưa tìm thấy sản phẩm có serial này. Bạn hãy kiểm tra lại serial trên sản phẩm."
            );
        } else {
            model.addAttribute("ketQuaBaoHanh", ketQua.getFirst());
        }
        return "khach/kiem-tra-bao-hanh";
    }

    @PostMapping("/khach/tra-cuu")
    public String traCuuHoSo(
        @RequestParam String maHoSo,
        @RequestParam String soDienThoai,
        Model model
    ) {
        String maDaNhap = maHoSo == null ? "" : maHoSo.trim();
        String dienThoaiDaNhap = soDienThoai == null ? "" : soDienThoai.trim();
        model.addAttribute("maHoSoNhap", maDaNhap);
        model.addAttribute("soDienThoaiNhap", dienThoaiDaNhap);

        if (maDaNhap.isBlank() || dienThoaiDaNhap.isBlank()) {
            model.addAttribute("loiTraCuu", "Vui lòng nhập cả mã hồ sơ và số điện thoại.");
            return "khach/tra-cuu";
        }

        var ketQua = portalQueryService.customerCase(maDaNhap, dienThoaiDaNhap);

        if (ketQua.isEmpty()) {
            model.addAttribute(
                "loiTraCuu",
                "Không tìm thấy hồ sơ khớp với mã hồ sơ và số điện thoại đã nhập."
            );
        } else {
            model.addAttribute("ketQuaTraCuu", ketQua.get(0));
        }
        return "khach/tra-cuu";
    }
}
