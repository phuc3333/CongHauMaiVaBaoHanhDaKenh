package haumai.core.repository;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

import java.util.List;
import java.util.Map;

@Repository
public class PortalReadRepository {
    private final JdbcTemplate jdbc;

    public PortalReadRepository(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    public List<Map<String, Object>> findWarrantyBySerial(String serial) {
        return jdbc.queryForList(
            """
            SELECT serial, ten_san_pham, ngay_het_han_bao_hanh,
                   trang_thai_bao_hanh, so_ngay_con_lai
            FROM public.v_san_pham WHERE UPPER(serial) = UPPER(?) LIMIT 1
            """, serial);
    }

    public List<Map<String, Object>> findCustomerCase(String caseCode, String phone) {
        return jdbc.queryForList("SELECT * FROM public.fn_tra_cuu_ho_so(?, ?)", caseCode, phone);
    }

    public List<Map<String, Object>> findProducts() {
        return jdbc.queryForList(
            """
            SELECT serial, ten_san_pham, ngay_mua, thoi_han_bao_hanh_thang,
                   ngay_het_han_bao_hanh, trang_thai_bao_hanh, so_ngay_con_lai
            FROM public.v_san_pham ORDER BY ten_san_pham, serial
            """);
    }

    public List<Map<String, Object>> findSlaDashboard() {
        return jdbc.queryForList(
            """
            SELECT ho_so_id, ma_ho_so, trang_thai_ho_so, mo_ta_loi,
                   ten_khach_hang, loai_sla, nhan_trang_thai,
                   thoi_gian_hien_thi, den_han_luc, phut_con_lai, ky_thuat_vien
            FROM public.v_sla_dashboard
            WHERE trang_thai_ho_so NOT IN ('DA_DONG', 'TU_CHOI')
              AND nhan_trang_thai <> 'DAT_SLA'
              AND (nhan_trang_thai <> 'CHUA_BAT_DAU' OR trang_thai_ho_so = 'CHO_PHAN_CONG')
            ORDER BY CASE nhan_trang_thai
                         WHEN 'QUA_HAN' THEN 0 WHEN 'KHONG_DAT_SLA' THEN 0
                         WHEN 'SAP_DEN_HAN' THEN 1 WHEN 'DANG_CON_HAN' THEN 2 ELSE 3
                     END, phut_con_lai ASC NULLS LAST, ho_so_id
            """);
    }
}
