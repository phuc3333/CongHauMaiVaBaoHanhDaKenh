package haumai.core.controller;

import haumai.core.service.ConversationService;
import org.springframework.dao.DataAccessException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.Authentication;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.servlet.mvc.support.RedirectAttributes;

import java.util.Map;

@Controller
public class ConversationController {
    private final ConversationService service;

    public ConversationController(ConversationService service) {
        this.service = service;
    }

    @GetMapping("/nhan-vien/ho-so/cuoc-tro-chuyen")
    @ResponseBody
    public Object conversations() {
        return service.unlinkedConversations();
    }

    @GetMapping("/nhan-vien/ho-so/cuoc-tro-chuyen/{id}/tin-nhan")
    @ResponseBody
    public Object conversationMessages(@PathVariable Long id) {
        return service.conversationMessages(id);
    }

    @GetMapping("/nhan-vien/ho-so/{id}/tin-nhan")
    @ResponseBody
    public Object caseMessages(@PathVariable Long id) {
        return service.caseMessages(id);
    }

    @PostMapping("/nhan-vien/ho-so/cuoc-tro-chuyen/{id}/phan-hoi")
    @ResponseBody
    public ResponseEntity<?> replyToConversation(@PathVariable Long id,
            @RequestParam String noiDung, Authentication authentication) {
        try {
            String channel = service.replyToConversation(id, noiDung, authentication.getName());
            return ResponseEntity.ok(Map.of("success", true, "channel", channel));
        } catch (IllegalArgumentException ex) {
            return ResponseEntity.badRequest().body(Map.of("success", false, "message", ex.getMessage()));
        } catch (DataAccessException | IllegalStateException ex) {
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY)
                .body(Map.of("success", false, "message", "Chưa gửi được tin nhắn."));
        }
    }

    @PostMapping("/nhan-vien/ho-so/cuoc-tro-chuyen/{id}/tao-ho-so")
    public String createCase(@PathVariable Long id, @RequestParam String hoTen,
            @RequestParam String soDienThoai, @RequestParam String moTa,
            @RequestParam(required = false) String serial, RedirectAttributes flash) {
        try {
            ConversationService.CreatedCase created = service.createCase(id, hoTen, soDienThoai, moTa, serial);
            flash.addFlashAttribute("thongBaoThanhCong", "Đã tạo hồ sơ " + created.caseNumber() + " từ hội thoại.");
            return "redirect:/nhan-vien/ho-so?caseId=" + created.caseId();
        } catch (DataAccessException | IllegalArgumentException ex) {
            flash.addFlashAttribute("loiThaoTac", "Chưa tạo được hồ sơ. Hãy kiểm tra thông tin hội thoại.");
            return "redirect:/nhan-vien/ho-so?conversationId=" + id;
        }
    }

    @PostMapping("/nhan-vien/ho-so/{id}/phan-hoi-zalo")
    public Object replyZalo(@PathVariable Long id, @RequestParam String noiDung,
            Authentication authentication, RedirectAttributes flash,
            @RequestHeader(value = "X-Requested-With", required = false) String requestedWith) {
        return replyToCase(id, "ZALO", noiDung, authentication, flash, requestedWith);
    }

    @PostMapping("/nhan-vien/ho-so/{id}/phan-hoi-facebook")
    public Object replyFacebook(@PathVariable Long id, @RequestParam String noiDung,
            Authentication authentication, RedirectAttributes flash,
            @RequestHeader(value = "X-Requested-With", required = false) String requestedWith) {
        return replyToCase(id, "FACEBOOK", noiDung, authentication, flash, requestedWith);
    }

    private Object replyToCase(Long id, String channel, String content,
            Authentication authentication, RedirectAttributes flash, String requestedWith) {
        boolean ajax = "XMLHttpRequest".equalsIgnoreCase(requestedWith);
        String redirect = "redirect:/nhan-vien/ho-so?caseId=" + id;
        try {
            service.replyToCase(id, channel, content, authentication.getName());
            String message = "Đã đưa tin nhắn vào hàng đợi gửi.";
            if (ajax) return ResponseEntity.ok(Map.of("success", true, "message", message));
            flash.addFlashAttribute("thongBaoThanhCong", message);
        } catch (DataAccessException | IllegalArgumentException | IllegalStateException ex) {
            String message = "Chưa gửi được tin nhắn.";
            if (ajax) {
                return ResponseEntity.status(HttpStatus.BAD_GATEWAY)
                    .body(Map.of("success", false, "message", message));
            }
            flash.addFlashAttribute("loiThaoTac", message);
        }
        return redirect;
    }
}
