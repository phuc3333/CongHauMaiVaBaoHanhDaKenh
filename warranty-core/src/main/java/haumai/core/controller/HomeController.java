package haumai.core.controller;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;

@Controller
public class HomeController {

    @GetMapping("/")
    public String home(Authentication authentication, Model model) {
        String role = authentication == null ? "ROLE_GUEST" : authentication.getAuthorities().stream()
            .map(authority -> authority.getAuthority())
            .filter(authority -> !authority.equals("ROLE_ANONYMOUS"))
            .findFirst()
            .orElse("ROLE_GUEST");

        if ("ROLE_CSKH".equals(role)) {
            return "redirect:/nhan-vien/ho-so";
        }
        if ("ROLE_DIEU_PHOI_VIEN".equals(role)) {
            return "redirect:/nhan-vien/ho-so";
        }
        if ("ROLE_KY_THUAT_VIEN".equals(role)) {
            return "redirect:/nhan-vien/ky-thuat-vien/ho-so";
        }

        if (role.equals("ROLE_GUEST")) {
            model.addAttribute("username", "Khách");
            model.addAttribute("role", role);
            return "home";
        }

        model.addAttribute("username", authentication.getName());
        model.addAttribute("role", role);
        return "home";
    }
}
