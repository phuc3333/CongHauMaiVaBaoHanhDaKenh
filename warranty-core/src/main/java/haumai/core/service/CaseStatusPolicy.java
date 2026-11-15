package haumai.core.service;

import org.springframework.stereotype.Component;
import java.util.Map;
import java.util.Set;

/** Business rules for allowed case status changes. */
@Component
public class CaseStatusPolicy {
    private static final Map<String, Set<String>> ALLOWED = Map.of(
        "MOI", Set.of("DANG_XAC_MINH"),
        "DANG_XAC_MINH", Set.of("CHO_PHAN_CONG", "TU_CHOI", "CHO_KHACH_BO_SUNG"),
        "CHO_KHACH_BO_SUNG", Set.of("DANG_XAC_MINH", "DA_DONG"),
        "CHO_PHAN_CONG", Set.of("DANG_SUA_CHUA"),
        "DANG_SUA_CHUA", Set.of("DA_SUA_XONG", "CHO_CSKH_XU_LY"),
        "DA_SUA_XONG", Set.of("DA_DONG"), "TU_CHOI", Set.of("DA_DONG"),
        "CHO_CSKH_XU_LY", Set.of("DA_DONG")
    );
    public void requireAllowed(String current, String next) {
        if (current == null || !ALLOWED.getOrDefault(current, Set.of()).contains(next))
            throw new IllegalStateException("Không thể chuyển hồ sơ từ " + current + " sang " + next);
    }
}
