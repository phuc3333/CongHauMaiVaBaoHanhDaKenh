CREATE PROCEDURE public.sp_khach_bo_sung_thong_tin(
    IN p_ma_ho_so VARCHAR(30),
    IN p_so_dien_thoai VARCHAR(30),
    IN p_noi_dung TEXT,
    IN p_now TIMESTAMPTZ DEFAULT now()
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_now TIMESTAMPTZ;
    v_ho_so_id BIGINT;
    v_trang_thai VARCHAR(40);
    v_kenh_website_id BIGINT;
    v_noi_dung TEXT;
BEGIN
    v_now := COALESCE(p_now, now());
    v_noi_dung := NULLIF(BTRIM(p_noi_dung), '');

    IF NULLIF(BTRIM(p_ma_ho_so), '') IS NULL
       OR NULLIF(BTRIM(p_so_dien_thoai), '') IS NULL THEN
        RAISE EXCEPTION 'Cần nhập mã hồ sơ và số điện thoại';
    END IF;

    IF v_noi_dung IS NULL THEN
        RAISE EXCEPTION 'Nội dung bổ sung không được để trống';
    END IF;

    SELECT hs.id, hs.trang_thai
    INTO v_ho_so_id, v_trang_thai
    FROM public.ho_so hs
    JOIN public.khach_hang kh ON kh.id = hs.khach_hang_id
    WHERE UPPER(hs.ma_ho_so) = UPPER(BTRIM(p_ma_ho_so))
      AND BTRIM(kh.so_dien_thoai) = BTRIM(p_so_dien_thoai)
    FOR UPDATE OF hs;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy hồ sơ khớp với thông tin đã nhập';
    END IF;

    IF v_trang_thai <> 'CHO_KHACH_BO_SUNG' THEN
        RAISE EXCEPTION 'Hồ sơ hiện không chờ khách bổ sung thông tin';
    END IF;

    SELECT id
    INTO v_kenh_website_id
    FROM public.kenh_goc
    WHERE ma_kenh = 'WEBSITE'
      AND dang_bat = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kênh WEBSITE chưa được cấu hình hoặc đang tắt';
    END IF;

    INSERT INTO public.tin_nhan (
        ho_so_id,
        kenh_id,
        huong_tin,
        noi_dung,
        nhan_vien_id,
        trang_thai_gui,
        tao_luc
    )
    VALUES (
        v_ho_so_id,
        v_kenh_website_id,
        'DEN',
        v_noi_dung,
        NULL,
        'KHONG_AP_DUNG',
        v_now
    );

    CALL public.sp_chuyen_trang_thai(
        v_ho_so_id,
        'DANG_XAC_MINH',
        'KHACH_HANG',
        NULL,
        'Khách hàng đã bổ sung thông tin qua Website.',
        v_now
    );
END;
$$;


ALTER PROCEDURE public.sp_khach_bo_sung_thong_tin(
    CHARACTER VARYING, CHARACTER VARYING, TEXT, TIMESTAMPTZ
)
OWNER TO hau_mai_owner;

REVOKE EXECUTE ON PROCEDURE public.sp_khach_bo_sung_thong_tin(
    CHARACTER VARYING, CHARACTER VARYING, TEXT, TIMESTAMPTZ
) FROM PUBLIC;

GRANT EXECUTE ON PROCEDURE public.sp_khach_bo_sung_thong_tin(
    CHARACTER VARYING, CHARACTER VARYING, TEXT, TIMESTAMPTZ
) TO hau_mai_app;