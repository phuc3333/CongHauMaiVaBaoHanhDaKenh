package haumai.core.controller;

import haumai.core.service.PortalQueryService;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

import java.util.List;
import java.util.Map;
import java.util.Set;

@Controller
public class SlaController {
    private final PortalQueryService portalQueryService;

    public SlaController(PortalQueryService portalQueryService) {
        this.portalQueryService = portalQueryService;
    }
    @GetMapping("/nhan-vien/sla")
    public String giamSatSla(Authentication authentication, Model model) {
        var rows = portalQueryService.slaDashboard().stream().filter(row ->
            !"CHUA_BAT_DAU".equals(row.get("nhan_trang_thai"))
                || "CHO_PHAN_CONG".equals(row.get("trang_thai_ho_so"))
        ).toList();
        var viPham = rows.stream().filter(row ->
            Set.of("QUA_HAN", "KHONG_DAT_SLA").contains(row.get("nhan_trang_thai"))
        ).toList();
        var sapDenHan = rows.stream().filter(row ->
            "SAP_DEN_HAN".equals(row.get("nhan_trang_thai"))
        ).toList();
        var dangTheoDoi = rows.stream().filter(row ->
            Set.of("DANG_CON_HAN", "TAM_DUNG", "CHUA_BAT_DAU").contains(row.get("nhan_trang_thai"))
        ).toList();

        model.addAttribute("username", authentication.getName());
        model.addAttribute("coQuyenSla", true);
        model.addAttribute("laCskh", authentication.getAuthorities().stream()
            .anyMatch(role -> role.getAuthority().equals("ROLE_CSKH")));
        model.addAttribute("slaViPham", viPham);
        model.addAttribute("slaSapDenHan", sapDenHan);
        model.addAttribute("slaDangTheoDoi", dangTheoDoi);
        model.addAttribute("soHoSoQuaHan", demHoSoSla(viPham));
        model.addAttribute("soHoSoSapDenHan", demHoSoSla(sapDenHan));
        model.addAttribute("soHoSoDangTheoDoi", demHoSoSla(dangTheoDoi));
        return "sla/danh-sach";
    }

    private long demHoSoSla(List<Map<String, Object>> rows) {
        return rows.stream()
            .map(row -> ((Number) row.get("ho_so_id")).longValue())
            .distinct()
            .count();
    }
}
