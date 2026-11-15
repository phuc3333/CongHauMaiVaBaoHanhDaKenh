-- Let CSKH correct stale contact details for a channel identity when creating a case.
CREATE PROCEDURE public.sp_cap_nhat_khach_hang_tu_dinh_danh(
    IN p_ma_kenh VARCHAR(30),
    IN p_ma_nguoi_dung_kenh VARCHAR(255),
    IN p_ho_ten VARCHAR(200),
    IN p_so_dien_thoai VARCHAR(30)
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_khach_hang_id BIGINT;
    v_kenh_id BIGINT;
    v_so_dien_thoai VARCHAR(30);
BEGIN
    v_so_dien_thoai := NULLIF(BTRIM(p_so_dien_thoai), '');
    IF NULLIF(BTRIM(p_ho_ten), '') IS NULL OR v_so_dien_thoai IS NULL THEN
        RAISE EXCEPTION 'Họ tên và số điện thoại không được để trống';
    END IF;

    SELECT kg.id INTO v_kenh_id
    FROM public.kenh_goc kg
    WHERE kg.ma_kenh = UPPER(BTRIM(p_ma_kenh));

    SELECT dk.khach_hang_id INTO v_khach_hang_id
    FROM public.dinh_danh_kenh dk
    WHERE dk.kenh_id = v_kenh_id
      AND dk.ma_nguoi_dung_kenh = NULLIF(BTRIM(p_ma_nguoi_dung_kenh), '')
    FOR UPDATE;

    -- A new sender has no existing customer row to correct. The case procedure creates it.
    IF v_khach_hang_id IS NULL THEN
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.khach_hang kh
        WHERE kh.so_dien_thoai = v_so_dien_thoai
          AND kh.id <> v_khach_hang_id
    ) THEN
        RAISE EXCEPTION 'Số điện thoại này đã thuộc về một khách hàng khác';
    END IF;

    UPDATE public.khach_hang
    SET ho_ten = BTRIM(p_ho_ten), so_dien_thoai = v_so_dien_thoai
    WHERE id = v_khach_hang_id;

    UPDATE public.dinh_danh_kenh
    SET ten_hien_thi = BTRIM(p_ho_ten)
    WHERE kenh_id = v_kenh_id
      AND ma_nguoi_dung_kenh = NULLIF(BTRIM(p_ma_nguoi_dung_kenh), '');
END;
$$;

ALTER PROCEDURE public.sp_cap_nhat_khach_hang_tu_dinh_danh(
    CHARACTER VARYING, CHARACTER VARYING, CHARACTER VARYING, CHARACTER VARYING
) OWNER TO hau_mai_owner;

REVOKE EXECUTE ON PROCEDURE public.sp_cap_nhat_khach_hang_tu_dinh_danh(
    CHARACTER VARYING, CHARACTER VARYING, CHARACTER VARYING, CHARACTER VARYING
) FROM PUBLIC;

GRANT EXECUTE ON PROCEDURE public.sp_cap_nhat_khach_hang_tu_dinh_danh(
    CHARACTER VARYING, CHARACTER VARYING, CHARACTER VARYING, CHARACTER VARYING
) TO hau_mai_app;
