CREATE FUNCTION public.fn_tra_cuu_ho_so(
    p_ma_ho_so VARCHAR(30),
    p_so_dien_thoai VARCHAR(30)
)
RETURNS TABLE (
    ma_ho_so VARCHAR(30),
    trang_thai VARCHAR(40),
    mo_ta_loi TEXT,
    serial VARCHAR(100),
    ngay_tiep_nhan TIMESTAMPTZ,
    ket_qua_xac_minh TEXT,
    ket_luan_xu_ly TEXT,
    ngay_dong TIMESTAMPTZ
)
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT
        hs.ma_ho_so,
        hs.trang_thai,
        hs.mo_ta_loi,
        COALESCE(hs.serial, hs.serial_khach_khai_bao),
        hs.ngay_tiep_nhan,
        hs.ket_qua_xac_minh,
        hs.ket_luan_xu_ly,
        hs.ngay_dong
    FROM public.ho_so hs
    JOIN public.khach_hang kh ON kh.id = hs.khach_hang_id
    WHERE UPPER(hs.ma_ho_so) = UPPER(BTRIM(p_ma_ho_so))
      AND BTRIM(kh.so_dien_thoai) = BTRIM(p_so_dien_thoai)
    LIMIT 1;
$$;


ALTER FUNCTION public.fn_tra_cuu_ho_so(
    CHARACTER VARYING, CHARACTER VARYING
)
OWNER TO hau_mai_owner;

REVOKE EXECUTE ON FUNCTION public.fn_tra_cuu_ho_so(
    CHARACTER VARYING, CHARACTER VARYING
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_tra_cuu_ho_so(
    CHARACTER VARYING, CHARACTER VARYING
) TO hau_mai_app;