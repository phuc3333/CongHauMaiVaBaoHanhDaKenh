-- Expose only the employee id needed by the authenticated workflow.
CREATE FUNCTION public.fn_nhan_vien_id_theo_dang_nhap(
    p_ten_dang_nhap VARCHAR,
    p_vai_tro VARCHAR
)
RETURNS BIGINT
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT nv.id
    FROM public.nhan_vien nv
    JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
    WHERE tk.ten_dang_nhap = p_ten_dang_nhap
      AND tk.vai_tro = p_vai_tro
      AND tk.dang_hoat_dong = TRUE
$$;

-- Serialize assignments for the same technician without granting the app
-- direct UPDATE/row-lock privileges on employee or account tables.
CREATE FUNCTION public.fn_ktv_dang_hoat_dong_khoa(p_ky_thuat_vien_id BIGINT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    PERFORM nv.id
    FROM public.nhan_vien nv
    JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
    WHERE nv.id = p_ky_thuat_vien_id
      AND tk.vai_tro = 'KY_THUAT_VIEN'
      AND tk.dang_hoat_dong = TRUE
    FOR UPDATE OF nv;
    RETURN FOUND;
END;
$$;

-- Read case closure facts and lock that case within the service transaction.
CREATE FUNCTION public.fn_ho_so_thong_tin_khoa(p_ho_so_id BIGINT)
RETURNS TABLE (
    case_status VARCHAR,
    waiting_since TIMESTAMPTZ,
    waiting_days INTEGER
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    RETURN QUERY
    SELECT h.trang_thai,
           h.bat_dau_cho_khach_luc,
           COALESCE((
               SELECT c.gia_tri::INTEGER
               FROM public.cau_hinh c
               WHERE c.ma_cau_hinh = 'so_ngay_cho_khach'
           ), 7)
    FROM public.ho_so h
    WHERE h.id = p_ho_so_id
    FOR UPDATE OF h;
END;
$$;

ALTER FUNCTION public.fn_nhan_vien_id_theo_dang_nhap(VARCHAR, VARCHAR) OWNER TO hau_mai_owner;
ALTER FUNCTION public.fn_ktv_dang_hoat_dong_khoa(BIGINT) OWNER TO hau_mai_owner;
ALTER FUNCTION public.fn_ho_so_thong_tin_khoa(BIGINT) OWNER TO hau_mai_owner;

REVOKE ALL ON FUNCTION public.fn_nhan_vien_id_theo_dang_nhap(VARCHAR, VARCHAR) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_ktv_dang_hoat_dong_khoa(BIGINT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_ho_so_thong_tin_khoa(BIGINT) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fn_nhan_vien_id_theo_dang_nhap(VARCHAR, VARCHAR) TO hau_mai_app;
GRANT EXECUTE ON FUNCTION public.fn_ktv_dang_hoat_dong_khoa(BIGINT) TO hau_mai_app;
GRANT EXECUTE ON FUNCTION public.fn_ho_so_thong_tin_khoa(BIGINT) TO hau_mai_app;
