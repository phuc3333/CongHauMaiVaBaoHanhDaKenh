package haumai.core.repository;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Map;

@Repository
public class HoSoReadRepository {
    private final JdbcTemplate jdbc;
    public HoSoReadRepository(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    public List<Map<String, Object>> slas() {
        return jdbc.queryForList("SELECT ho_so_id, loai_sla, nhan_trang_thai, thoi_gian_hien_thi, den_han_luc FROM public.v_sla_ho_so ORDER BY ho_so_id, CASE loai_sla WHEN 'TIEP_NHAN' THEN 1 ELSE 2 END");
    }
    public List<Map<String, Object>> techniciansByCase() {
        return jdbc.queryForList("SELECT DISTINCT ON (ho_so_id) ho_so_id, ky_thuat_vien FROM public.v_sla_dashboard WHERE ky_thuat_vien IS NOT NULL ORDER BY ho_so_id");
    }
    public List<Map<String, Object>> customerByCase() {
        return jdbc.queryForList("SELECT ho_so_id, ten_khach_hang, so_dien_thoai FROM public.v_ho_so_khach_hang");
    }
    public List<Map<String, Object>> openConversations() {
        return jdbc.queryForList("SELECT * FROM public.v_cuoc_tro_chuyen WHERE ma_kenh IN ('FACEBOOK', 'ZALO') AND ho_so_id IS NULL ORDER BY cap_nhat_luc DESC");
    }
    public List<Long> caseIdsForChannel(String view) {
        if (!"public.v_ho_so_zalo".equals(view) && !"public.v_ho_so_facebook".equals(view)) throw new IllegalArgumentException("Unsupported channel view");
        return jdbc.queryForList("SELECT ho_so_id FROM " + view, Long.class);
    }
    public List<Map<String, Object>> conversation(Long id) {
        return jdbc.queryForList("SELECT * FROM public.v_cuoc_tro_chuyen WHERE id = ? AND ma_kenh IN ('FACEBOOK', 'ZALO')", id);
    }
    public Map<String, Object> editForm(Long id) {
        return jdbc.queryForMap("SELECT h.id, h.ma_ho_so, h.trang_thai, h.mo_ta_loi, COALESCE(h.serial, h.serial_khach_khai_bao) AS serial, hk.ten_khach_hang AS ho_ten, hk.so_dien_thoai FROM public.ho_so h JOIN public.v_ho_so_khach_hang hk ON hk.ho_so_id = h.id WHERE h.id = ? AND h.trang_thai IN ('DANG_XAC_MINH', 'CHO_KHACH_BO_SUNG')", id);
    }
    public Map<String, Object> assignmentForm(Long id) {
        return jdbc.queryForMap("SELECT hs.id, hs.ma_ho_so, hs.trang_thai, hs.mo_ta_loi, kh.ten_khach_hang, kh.so_dien_thoai FROM public.ho_so hs JOIN public.v_ho_so_khach_hang kh ON kh.ho_so_id = hs.id WHERE hs.id = ? AND hs.trang_thai IN ('CHO_PHAN_CONG', 'DANG_SUA_CHUA')", id);
    }
    public List<Map<String, Object>> technicians() { return jdbc.queryForList("SELECT * FROM v_tai_ky_thuat_vien ORDER BY ho_ten"); }
    public Map<String, Object> verificationForm(Long id) {
        return jdbc.queryForMap("""
            SELECT h.id, h.ma_ho_so, h.serial, h.serial_khach_khai_bao, h.trang_thai,
                   sp.serial AS serial_da_dang_ky, sp.ten_san_pham, sp.ngay_mua,
                   sp.ngay_het_han_bao_hanh,
                   sp.thoi_han_bao_hanh_thang,
                   (h.ngay_tiep_nhan AT TIME ZONE 'Asia/Ho_Chi_Minh')::date AS ngay_xac_minh
            FROM ho_so h LEFT JOIN public.v_san_pham sp ON sp.serial = COALESCE(h.serial, h.serial_khach_khai_bao)
            WHERE h.id = ? AND h.trang_thai = 'DANG_XAC_MINH'
            """, id);
    }
}
