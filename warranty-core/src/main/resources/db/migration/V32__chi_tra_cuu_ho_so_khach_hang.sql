-- Customer lookup is read-only and exposes only customer-facing case information.
DROP FUNCTION public.fn_tra_cuu_ho_so(VARCHAR, VARCHAR);

CREATE FUNCTION public.fn_tra_cuu_ho_so(
    p_ma_ho_so VARCHAR(30),
    p_so_dien_thoai VARCHAR(30)
)
RETURNS TABLE (
    ma_ho_so VARCHAR(30),
    trang_thai VARCHAR(40),
    trang_thai_hien_thi VARCHAR(80),
    ten_san_pham VARCHAR(200),
    serial VARCHAR(100),
    ngay_tiep_nhan TIMESTAMPTZ,
    kenh_tiep_nhan VARCHAR(100),
    tien_do TEXT,
    ket_luan_xu_ly TEXT
)
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT
        hs.ma_ho_so,
        hs.trang_thai,
        CASE hs.trang_thai
            WHEN 'MOI' THEN 'Mới tiếp nhận'
            WHEN 'DANG_XAC_MINH' THEN 'Đang xác minh'
            WHEN 'CHO_KHACH_BO_SUNG' THEN 'Chờ bổ sung thông tin'
            WHEN 'CHO_PHAN_CONG' THEN 'Chờ phân công'
            WHEN 'DANG_SUA_CHUA' THEN 'Đang sửa chữa'
            WHEN 'CHO_CSKH_XU_LY' THEN 'Đang hoàn tất hồ sơ'
            WHEN 'DA_SUA_XONG' THEN 'Đã sửa xong'
            WHEN 'TU_CHOI' THEN 'Không đủ điều kiện bảo hành'
            WHEN 'DA_DONG' THEN 'Đã hoàn tất'
            ELSE 'Đang cập nhật'
        END,
        sp.ten_san_pham,
        COALESCE(hs.serial, hs.serial_khach_khai_bao),
        hs.ngay_tiep_nhan,
        CASE kg.ma_kenh
            WHEN 'FACEBOOK' THEN 'Facebook Messenger'
            ELSE kg.ten_hien_thi
        END,
        CASE hs.trang_thai
            WHEN 'MOI' THEN 'Đã tiếp nhận yêu cầu'
            WHEN 'DANG_XAC_MINH' THEN 'CSKH đang xác minh hồ sơ'
            WHEN 'CHO_KHACH_BO_SUNG' THEN 'Đang chờ bổ sung thông tin'
            WHEN 'CHO_PHAN_CONG' THEN 'Đã xác minh, đang chờ phân công kỹ thuật viên'
            WHEN 'DANG_SUA_CHUA' THEN 'Kỹ thuật viên đang sửa chữa'
            WHEN 'CHO_CSKH_XU_LY' THEN 'Đang hoàn tất hồ sơ sau sửa chữa'
            WHEN 'DA_SUA_XONG' THEN 'Đã sửa xong'
            WHEN 'TU_CHOI' THEN 'Đã có kết luận không đủ điều kiện bảo hành'
            WHEN 'DA_DONG' THEN 'Hồ sơ đã hoàn tất'
            ELSE 'Đang cập nhật'
        END,
        hs.ket_luan_xu_ly
    FROM public.ho_so hs
    JOIN public.khach_hang kh ON kh.id = hs.khach_hang_id
    JOIN public.kenh_goc kg ON kg.id = hs.kenh_goc_id
    LEFT JOIN public.san_pham sp
        ON sp.serial = COALESCE(hs.serial, hs.serial_khach_khai_bao)
    WHERE UPPER(hs.ma_ho_so) = UPPER(BTRIM(p_ma_ho_so))
      AND BTRIM(kh.so_dien_thoai) = BTRIM(p_so_dien_thoai)
    LIMIT 1;
$$;

ALTER FUNCTION public.fn_tra_cuu_ho_so(VARCHAR, VARCHAR)
    OWNER TO hau_mai_owner;
REVOKE EXECUTE ON FUNCTION public.fn_tra_cuu_ho_so(VARCHAR, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_tra_cuu_ho_so(VARCHAR, VARCHAR) TO hau_mai_app;
