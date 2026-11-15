package haumai.core.repository;

import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.CallableStatement;
import java.sql.Types;
import java.time.OffsetDateTime;

/** Persistence adapter for case workflow commands. Business decisions belong in HoSoService. */
@Repository
public class HoSoWorkflowRepository {
    private final JdbcTemplate jdbc;

    public HoSoWorkflowRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Long findActiveEmployeeId(String username, String role) {
        return jdbc.queryForObject(
            "SELECT public.fn_nhan_vien_id_theo_dang_nhap(?, ?)", Long.class, username, role
        );
    }

    public String findCaseStatus(Long caseId) {
        return jdbc.queryForObject(
            "SELECT case_status FROM public.fn_ho_so_thong_tin_khoa(?)",
            String.class, caseId
        );
    }

    public boolean isActiveTechnician(Long technicianId) {
        Boolean active = jdbc.queryForObject(
            "SELECT public.fn_ktv_dang_hoat_dong_khoa(?)", Boolean.class, technicianId);
        return Boolean.TRUE.equals(active);
    }

    public Long currentTechnicianForCase(Long caseId) {
        return jdbc.query("""
            SELECT ky_thuat_vien_id FROM public.v_ho_so_ky_thuat_vien
            WHERE ho_so_id = ? AND trang_thai_ho_so IN ('CHO_PHAN_CONG', 'DANG_SUA_CHUA')
            ORDER BY phan_cong_id DESC LIMIT 1
            """,
            rs -> rs.next() ? rs.getLong(1) : null, caseId);
    }

    public int activeCaseCount(Long technicianId, Long excludedCaseId) {
        Integer count = jdbc.queryForObject("""
            SELECT COUNT(*) FROM public.v_ho_so_ky_thuat_vien
            WHERE ky_thuat_vien_id = ? AND ho_so_id <> ?
              AND trang_thai_ho_so IN ('CHO_PHAN_CONG', 'DANG_SUA_CHUA')
            """, Integer.class, technicianId, excludedCaseId);
        return count == null ? 0 : count;
    }

    public int technicianCapacity() {
        Integer value = jdbc.queryForObject("""
            SELECT gioi_han_ho_so FROM public.v_tai_ky_thuat_vien ORDER BY ky_thuat_vien_id LIMIT 1
            """, Integer.class);
        return value == null ? 5 : value;
    }

    public ClosureFacts findClosureFacts(Long caseId) {
        return jdbc.queryForObject("""
            SELECT case_status, waiting_since, waiting_days
            FROM public.fn_ho_so_thong_tin_khoa(?)
            """, (rs, rowNum) -> new ClosureFacts(rs.getString("case_status"),
                rs.getObject("waiting_since", OffsetDateTime.class), rs.getInt("waiting_days")), caseId);
    }

    public void transition(Long caseId, String nextStatus, Long employeeId, String note, OffsetDateTime now) {
        callVoid("{call public.sp_chuyen_trang_thai(?, ?, ?, ?, ?, ?)}", call -> {
            call.setLong(1, caseId); call.setString(2, nextStatus); call.setString(3, "NHAN_VIEN");
            call.setLong(4, employeeId); call.setString(5, note); call.setObject(6, now);
        });
    }

    public void transitionSystem(Long caseId, String nextStatus, String note, OffsetDateTime now) {
        callVoid("{call public.sp_chuyen_trang_thai(?, ?, ?, ?, ?, ?)}", call -> {
            call.setLong(1, caseId); call.setString(2, nextStatus); call.setString(3, "HE_THONG");
            call.setNull(4, java.sql.Types.BIGINT); call.setString(5, note); call.setObject(6, now);
        });
    }

    public void updateCaseDetails(Long caseId, String name, String phone, String serial,
                                  String description, Long employeeId, boolean resumeVerification,
                                  OffsetDateTime now) {
        jdbc.execute((ConnectionCallback<Void>) connection -> {
            try (CallableStatement edit = connection.prepareCall(
                "{call public.sp_sua_ho_so_dang_xac_minh(?, ?, ?, ?, ?)}")) {
                edit.setLong(1, caseId);
                edit.setString(2, name);
                edit.setString(3, phone);
                edit.setString(4, serial);
                edit.setString(5, description);
                edit.execute();
            }
            if (resumeVerification) {
                try (CallableStatement transition = connection.prepareCall(
                    "{call public.sp_chuyen_trang_thai(?, ?, ?, ?, ?, ?)}")) {
                    transition.setLong(1, caseId);
                    transition.setString(2, "DANG_XAC_MINH");
                    transition.setString(3, "NHAN_VIEN");
                    transition.setLong(4, employeeId);
                    transition.setString(5, "CSKH đã cập nhật thông tin khách bổ sung; tiếp tục xác minh.");
                    transition.setObject(6, now);
                    transition.execute();
                }
            }
            return null;
        });
    }

    public void assign(Long caseId, Long technicianId, Long dispatcherId, String reason,
                       OffsetDateTime now) {
        jdbc.execute((ConnectionCallback<Void>) connection -> {
            try (CallableStatement call = connection.prepareCall(
                "{call public.sp_luu_phan_cong_da_kiem_tra(?, ?, ?, ?, ?)}")) {
                call.setLong(1, caseId); call.setLong(2, technicianId); call.setLong(3, dispatcherId);
                call.setString(4, reason); call.setObject(5, now);
                call.execute();
            }
            return null;
        });
    }

    public void saveVerificationOutcome(Long caseId, String result, String rejectionReason,
                                        boolean outsideWarranty) {
        callVoid("{call public.sp_luu_ket_qua_xac_minh(?, ?, ?, ?)}", call -> {
            call.setLong(1, caseId); call.setString(2, result); call.setString(3, rejectionReason);
            call.setBoolean(4, outsideWarranty);
        });
    }

    private void callVoid(String sql, SqlCall action) {
        jdbc.execute((ConnectionCallback<Void>) connection -> {
            try (CallableStatement call = connection.prepareCall(sql)) {
                action.bind(call);
                call.execute();
            }
            return null;
        });
    }

    @FunctionalInterface
    private interface SqlCall {
        void bind(CallableStatement statement) throws java.sql.SQLException;
    }

    public record ClosureFacts(String status, OffsetDateTime waitingSince, int waitingDays) {}
}
