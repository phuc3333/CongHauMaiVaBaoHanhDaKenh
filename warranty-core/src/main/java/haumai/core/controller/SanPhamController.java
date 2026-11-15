package haumai.core.controller;

import haumai.core.service.PortalQueryService;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class SanPhamController {
    private final PortalQueryService portalQueryService;

    public SanPhamController(PortalQueryService portalQueryService) {
        this.portalQueryService = portalQueryService;
    }

    @GetMapping("/nhan-vien/san-pham")
    public String danhMucSanPham(Authentication authentication, Model model) {
        model.addAttribute("username", authentication.getName());
        model.addAttribute("coQuyenSla", authentication.getAuthorities().stream()
            .anyMatch(role -> role.getAuthority().equals("ROLE_DIEU_PHOI_VIEN")));
        model.addAttribute("coQuyenKiemTraBaoHanh", authentication.getAuthorities().stream()
            .anyMatch(role -> role.getAuthority().equals("ROLE_CSKH")
                || role.getAuthority().equals("ROLE_DIEU_PHOI_VIEN")));
        model.addAttribute("sanPhams", portalQueryService.products());
        return "san-pham/danh-sach";
    }
}
