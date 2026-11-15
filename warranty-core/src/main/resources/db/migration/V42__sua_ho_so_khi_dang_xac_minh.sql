CREATE PROCEDURE public.sp_sua_ho_so_dang_xac_minh(
    IN p_ho_so_id BIGINT,
    IN p_ho_ten VARCHAR(200),
    IN p_so_dien_thoai VARCHAR(30),
    IN p_serial VARCHAR(100),
    IN p_mo_ta_loi TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_khach_hang_id BIGINT;
    v_serial_khai_bao VARCHAR(100);
    v_serial_da_dang_ky VARCHAR(100);
BEGIN
    IF NULLIF(BTRIM(p_ho_ten), '') IS NULL
       OR NULLIF(BTRIM(p_so_dien_thoai), '') IS NULL
       OR NULLIF(BTRIM(p_mo_ta_loi), '') IS NULL THEN
        RAISE EXCEPTION 'Họ tên, số điện thoại và mô tả lỗi không được để trống';
    END IF;

    SELECT h.khach_hang_id INTO v_khach_hang_id
    FROM public.ho_so h
    WHERE h.id = p_ho_so_id AND h.trang_thai = 'DANG_XAC_MINH'
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Chỉ được chỉnh sửa hồ sơ đang xác minh';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.khach_hang kh
        WHERE kh.so_dien_thoai = BTRIM(p_so_dien_thoai)
          AND kh.id <> v_khach_hang_id
    ) THEN
        RAISE EXCEPTION 'Số điện thoại này đã thuộc về một khách hàng khác';
    END IF;

    v_serial_khai_bao := NULLIF(BTRIM(p_serial), '');
    IF v_serial_khai_bao IS NOT NULL THEN
        SELECT sp.serial INTO v_serial_da_dang_ky
        FROM public.san_pham sp WHERE UPPER(sp.serial) = UPPER(v_serial_khai_bao);
    END IF;

    UPDATE public.khach_hang
    SET ho_ten = BTRIM(p_ho_ten), so_dien_thoai = BTRIM(p_so_dien_thoai)
    WHERE id = v_khach_hang_id;

    UPDATE public.dinh_danh_kenh
    SET ten_hien_thi = BTRIM(p_ho_ten)
    WHERE khach_hang_id = v_khach_hang_id;

    UPDATE public.ho_so
    SET serial = v_serial_da_dang_ky,
        serial_khach_khai_bao = CASE WHEN v_serial_da_dang_ky IS NULL THEN v_serial_khai_bao ELSE NULL END,
        mo_ta_loi = BTRIM(p_mo_ta_loi)
    WHERE id = p_ho_so_id;
END;
$$;

ALTER PROCEDURE public.sp_sua_ho_so_dang_xac_minh(
    BIGINT, CHARACTER VARYING, CHARACTER VARYING, CHARACTER VARYING, TEXT
) OWNER TO hau_mai_owner;

REVOKE EXECUTE ON PROCEDURE public.sp_sua_ho_so_dang_xac_minh(
    BIGINT, CHARACTER VARYING, CHARACTER VARYING, CHARACTER VARYING, TEXT
) FROM PUBLIC;

GRANT EXECUTE ON PROCEDURE public.sp_sua_ho_so_dang_xac_minh(
    BIGINT, CHARACTER VARYING, CHARACTER VARYING, CHARACTER VARYING, TEXT
) TO hau_mai_app;
