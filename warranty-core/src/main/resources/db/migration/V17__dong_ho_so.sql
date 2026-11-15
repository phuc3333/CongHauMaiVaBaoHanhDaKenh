CREATE PROCEDURE public.sp_dong_ho_so(
    IN p_ho_so_id BIGINT,
    IN p_nhan_vien_id BIGINT,
    IN p_ghi_chu TEXT,
    IN p_now TIMESTAMPTZ DEFAULT now()
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_now TIMESTAMPTZ;
    v_trang_thai VARCHAR(40);
    v_bat_dau_cho_khach TIMESTAMPTZ;
    v_so_ngay_cho_khach INTEGER;
    v_ghi_chu TEXT;
BEGIN
    v_now := COALESCE(p_now, now());

    -- Chỉ CSKH đang hoạt động được đóng hồ sơ.
    PERFORM 1
    FROM public.nhan_vien nv
    JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
    WHERE nv.id = p_nhan_vien_id
      AND tk.vai_tro = 'CSKH'
      AND tk.dang_hoat_dong = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tài khoản CSKH không hợp lệ hoặc đã bị khóa';
    END IF;

    SELECT trang_thai, bat_dau_cho_khach_luc
    INTO v_trang_thai, v_bat_dau_cho_khach
    FROM public.ho_so
    WHERE id = p_ho_so_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy hồ sơ id=%', p_ho_so_id;
    END IF;

    IF v_trang_thai = 'CHO_KHACH_BO_SUNG' THEN
        SELECT COALESCE(
            (
                SELECT gia_tri::INTEGER
                FROM public.cau_hinh
                WHERE ma_cau_hinh = 'so_ngay_cho_khach'
            ),
            7
        )
        INTO v_so_ngay_cho_khach;

        IF v_so_ngay_cho_khach <= 0 THEN
            RAISE EXCEPTION 'Số ngày chờ khách phải lớn hơn 0';
        END IF;

        IF v_bat_dau_cho_khach IS NULL THEN
            RAISE EXCEPTION 'Hồ sơ thiếu thời điểm bắt đầu chờ khách';
        END IF;

        IF v_now < v_bat_dau_cho_khach
            + make_interval(days => v_so_ngay_cho_khach) THEN
            RAISE EXCEPTION
                'Chưa hết thời hạn % ngày chờ khách',
                v_so_ngay_cho_khach;
        END IF;

    ELSIF v_trang_thai NOT IN (
        'DA_SUA_XONG',
        'TU_CHOI',
        'CHO_CSKH_XU_LY'
    ) THEN
        RAISE EXCEPTION
            'Không thể đóng hồ sơ đang ở trạng thái %',
            v_trang_thai;
    END IF;

    v_ghi_chu := COALESCE(
        NULLIF(BTRIM(p_ghi_chu), ''),
        'CSKH đóng hồ sơ sau khi xử lý với khách hàng'
    );

    CALL public.sp_chuyen_trang_thai(
        p_ho_so_id,
        'DA_DONG',
        'NHAN_VIEN',
        p_nhan_vien_id,
        v_ghi_chu,
        v_now
    );
END;
$$;


ALTER PROCEDURE public.sp_dong_ho_so(
    BIGINT, BIGINT, TEXT, TIMESTAMPTZ
)
OWNER TO hau_mai_owner;

REVOKE EXECUTE ON PROCEDURE public.sp_dong_ho_so(
    BIGINT, BIGINT, TEXT, TIMESTAMPTZ
) FROM PUBLIC;

GRANT EXECUTE ON PROCEDURE public.sp_dong_ho_so(
    BIGINT, BIGINT, TEXT, TIMESTAMPTZ
) TO hau_mai_app;