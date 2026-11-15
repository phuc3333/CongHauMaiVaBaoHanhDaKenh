package haumai.core.repository;

import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.sql.CallableStatement;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;

@Repository
public class KyThuatVienRepository {
    private final JdbcTemplate jdbc;

    public KyThuatVienRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public Long findTechnicianId(String username) {
        return jdbc.queryForObject(
            """
            SELECT nv.id FROM public.nhan_vien nv
            JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
            WHERE tk.ten_dang_nhap = ? AND tk.vai_tro = 'KY_THUAT_VIEN' AND tk.dang_hoat_dong = TRUE
            """, Long.class, username);
    }

    public List<Map<String, Object>> findWork(Long technicianId) {
        return jdbc.queryForList(
            """
            SELECT * FROM public.v_ho_so_ky_thuat_vien
            WHERE ky_thuat_vien_id = ?
            ORDER BY cap_nhat_tien_do_luc DESC NULLS LAST, ma_ho_so
            """, technicianId);
    }

    public List<Map<String, Object>> findSla() {
        return jdbc.queryForList(
            """
            SELECT ho_so_id, loai_sla, nhan_trang_thai, thoi_gian_hien_thi, den_han_luc
            FROM public.v_sla_ho_so
            ORDER BY ho_so_id, CASE loai_sla WHEN 'TIEP_NHAN' THEN 1 ELSE 2 END
            """);
    }

    public AssignmentFacts assignmentFacts(Long assignmentId) {
        return jdbc.queryForObject("""
            SELECT ho_so_id, ky_thuat_vien_id, dang_hieu_luc, case_status, progress_status
            FROM public.fn_ktv_phan_cong_facts(?)
            """, (rs, rowNum) -> new AssignmentFacts(rs.getLong("ho_so_id"), rs.getLong("ky_thuat_vien_id"),
                rs.getBoolean("dang_hieu_luc"), rs.getString("case_status"), rs.getString("progress_status")),
            assignmentId);
    }

    public void accept(Long assignmentId, OffsetDateTime now) {
        jdbc.execute((ConnectionCallback<Void>) connection -> {
            try (CallableStatement call = connection.prepareCall(
                "{call public.sp_luu_ktv_tiep_nhan(?, ?)}")) {
                call.setLong(1, assignmentId); call.setObject(2, now);
                call.execute();
            }
            return null;
        });
    }

    public void complete(Long caseId, Long assignmentId, OffsetDateTime now) {
        jdbc.execute((ConnectionCallback<Void>) connection -> {
            try (CallableStatement call = connection.prepareCall(
                "{call public.sp_luu_ktv_hoan_tat(?, ?, ?, ?)}")) {
                call.setLong(1, caseId); call.setLong(2, assignmentId);
                call.setString(3, "Đã hoàn thành sửa chữa."); call.setObject(4, now);
                call.execute();
            }
            return null;
        });
    }

    public void transition(Long caseId, String nextStatus, Long employeeId, String note, OffsetDateTime now) {
        jdbc.execute((ConnectionCallback<Void>) connection -> {
            try (CallableStatement call = connection.prepareCall(
                "{call public.sp_chuyen_trang_thai(?, ?, ?, ?, ?, ?)}")) {
                call.setLong(1, caseId); call.setString(2, nextStatus); call.setString(3, "NHAN_VIEN");
                call.setLong(4, employeeId); call.setString(5, note); call.setObject(6, now);
                call.execute();
            }
            return null;
        });
    }

    public record AssignmentFacts(Long caseId, Long technicianId, boolean active,
                                  String caseStatus, String progressStatus) {}
}
