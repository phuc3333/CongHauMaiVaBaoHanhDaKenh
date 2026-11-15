-- Unified intake entry point for messages normalized by channel-gateway.
-- The gateway must publish to Redis; warranty-core consumes the stream and calls this procedure.
CREATE PROCEDURE public.sp_tao_ho_so_da_kenh(
    IN p_ma_kenh VARCHAR(30),
    IN p_ma_tin_goc VARCHAR(255),
    IN p_ma_nguoi_dung_kenh VARCHAR(255),
    IN p_ho_ten VARCHAR(200),
    IN p_so_dien_thoai VARCHAR(30),
    IN p_email VARCHAR(255),
    IN p_serial VARCHAR(100),
    IN p_noi_dung TEXT,
    IN p_now TIMESTAMPTZ,
    OUT p_ho_so_id BIGINT,
    OUT p_ma_ho_so VARCHAR(30)
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_ma_kenh VARCHAR(30);
    v_kenh_id BIGINT;
    v_khach_hang_id BIGINT;
    v_khach_hang_theo_dinh_danh BIGINT;
    v_serial_khai_bao VARCHAR(100);
    v_serial_da_dang_ky VARCHAR(100);
    v_ma_so BIGINT;
    v_now TIMESTAMPTZ;
    v_sla_tiep_nhan INTEGER;
    v_sla_xu_ly INTEGER;
BEGIN
    v_now := COALESCE(p_now, now());
    v_ma_kenh := UPPER(NULLIF(BTRIM(p_ma_kenh), ''));
    p_ma_tin_goc := NULLIF(BTRIM(p_ma_tin_goc), '');
    p_ma_nguoi_dung_kenh := NULLIF(BTRIM(p_ma_nguoi_dung_kenh), '');
    v_serial_khai_bao := NULLIF(BTRIM(p_serial), '');

    IF v_ma_kenh IS NULL THEN
        RAISE EXCEPTION 'Mã kênh không được để trống';
    END IF;
    IF NULLIF(BTRIM(p_ho_ten), '') IS NULL THEN
        RAISE EXCEPTION 'Họ tên khách hàng không được để trống';
    END IF;
    -- Current customer schema requires a phone number. Channel adapters must collect it before publishing.
    IF NULLIF(BTRIM(p_so_dien_thoai), '') IS NULL THEN
        RAISE EXCEPTION 'Số điện thoại khách hàng không được để trống';
    END IF;
    IF NULLIF(BTRIM(p_noi_dung), '') IS NULL THEN
        RAISE EXCEPTION 'Nội dung yêu cầu không được để trống';
    END IF;
    IF v_ma_kenh <> 'WEBSITE' AND p_ma_tin_goc IS NULL THEN
        RAISE EXCEPTION 'Kênh ngoài Website phải có mã tin nhắn gốc để chống tạo trùng';
    END IF;

    SELECT kg.id
    INTO v_kenh_id
    FROM public.kenh_goc kg
    WHERE kg.ma_kenh = v_ma_kenh
      AND kg.dang_bat = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kênh % chưa được cấu hình hoặc đang tắt', v_ma_kenh;
    END IF;

    -- Idempotency: a redelivered source message returns the case already created for it.
    IF p_ma_tin_goc IS NOT NULL THEN
        SELECT hs.id, hs.ma_ho_so
        INTO p_ho_so_id, p_ma_ho_so
        FROM public.tin_nhan tn
        JOIN public.ho_so hs ON hs.id = tn.ho_so_id
        WHERE tn.kenh_id = v_kenh_id
          AND tn.ma_tin_goc = p_ma_tin_goc;
        IF FOUND THEN
            RETURN;
        END IF;
    END IF;

    INSERT INTO public.khach_hang (ho_ten, so_dien_thoai, email)
    VALUES (
        BTRIM(p_ho_ten),
        BTRIM(p_so_dien_thoai),
        NULLIF(BTRIM(p_email), '')
    )
    ON CONFLICT (so_dien_thoai)
    DO UPDATE SET
        ho_ten = EXCLUDED.ho_ten,
        email = COALESCE(EXCLUDED.email, public.khach_hang.email)
    RETURNING id INTO v_khach_hang_id;

    -- Link a platform identity to the customer without silently reassigning an existing identity.
    IF p_ma_nguoi_dung_kenh IS NOT NULL THEN
        INSERT INTO public.dinh_danh_kenh (
            khach_hang_id, kenh_id, ma_nguoi_dung_kenh, ten_hien_thi, tao_luc
        )
        VALUES (
            v_khach_hang_id, v_kenh_id, p_ma_nguoi_dung_kenh,
            NULLIF(BTRIM(p_ho_ten), ''), v_now
        )
        ON CONFLICT (kenh_id, ma_nguoi_dung_kenh) DO NOTHING;

        SELECT dk.khach_hang_id
        INTO v_khach_hang_theo_dinh_danh
        FROM public.dinh_danh_kenh dk
        WHERE dk.kenh_id = v_kenh_id
          AND dk.ma_nguoi_dung_kenh = p_ma_nguoi_dung_kenh;

        IF v_khach_hang_theo_dinh_danh IS DISTINCT FROM v_khach_hang_id THEN
            RAISE EXCEPTION 'Định danh kênh đã liên kết với khách hàng khác';
        END IF;
    END IF;

    IF v_serial_khai_bao IS NOT NULL THEN
        SELECT sp.serial
        INTO v_serial_da_dang_ky
        FROM public.san_pham sp
        WHERE sp.serial = v_serial_khai_bao;
    END IF;

    SELECT
        COALESCE(
            (SELECT c.gia_tri::INTEGER FROM public.cau_hinh c
             WHERE c.ma_cau_hinh = 'sla_tiep_nhan_phut'),
            30
        ),
        COALESCE(
            (SELECT c.gia_tri::INTEGER FROM public.cau_hinh c
             WHERE c.ma_cau_hinh = 'sla_xu_ly_phut'),
            4320
        )
    INTO v_sla_tiep_nhan, v_sla_xu_ly;

    IF v_sla_tiep_nhan <= 0 OR v_sla_xu_ly <= 0 THEN
        RAISE EXCEPTION 'Thời hạn SLA phải lớn hơn 0';
    END IF;

    v_ma_so := nextval('public.ho_so_code_seq');
    p_ma_ho_so :=
        'HS-' ||
        TO_CHAR(v_now AT TIME ZONE 'Asia/Ho_Chi_Minh', 'YYYY') ||
        '-' ||
        LPAD(v_ma_so::TEXT, 6, '0');

    INSERT INTO public.ho_so (
        ma_ho_so, khach_hang_id, serial, serial_khach_khai_bao,
        kenh_goc_id, mo_ta_loi, ngay_tiep_nhan, trang_thai, tao_luc
    )
    VALUES (
        p_ma_ho_so, v_khach_hang_id, v_serial_da_dang_ky, v_serial_khai_bao,
        v_kenh_id, BTRIM(p_noi_dung), v_now, 'MOI', v_now
    )
    RETURNING id INTO p_ho_so_id;

    INSERT INTO public.tin_nhan (
        ho_so_id, kenh_id, ma_tin_goc, huong_tin, noi_dung,
        nhan_vien_id, trang_thai_gui, tao_luc
    )
    VALUES (
        p_ho_so_id, v_kenh_id, p_ma_tin_goc, 'DEN', BTRIM(p_noi_dung),
        NULL, 'KHONG_AP_DUNG', v_now
    );

    INSERT INTO public.sla (
        ho_so_id, loai_sla, thoi_han_phut, thoi_diem_bat_dau, trang_thai
    )
    VALUES
        (p_ho_so_id, 'TIEP_NHAN', v_sla_tiep_nhan, v_now, 'DANG_DEM'),
        (p_ho_so_id, 'XU_LY', v_sla_xu_ly, v_now, 'DANG_DEM');
END;
$$;

ALTER PROCEDURE public.sp_tao_ho_so_da_kenh(
    CHARACTER VARYING, CHARACTER VARYING, CHARACTER VARYING,
    CHARACTER VARYING, CHARACTER VARYING, CHARACTER VARYING,
    CHARACTER VARYING, TEXT, TIMESTAMPTZ
) OWNER TO hau_mai_owner;

REVOKE EXECUTE ON PROCEDURE public.sp_tao_ho_so_da_kenh(
    CHARACTER VARYING, CHARACTER VARYING, CHARACTER VARYING,
    CHARACTER VARYING, CHARACTER VARYING, CHARACTER VARYING,
    CHARACTER VARYING, TEXT, TIMESTAMPTZ
) FROM PUBLIC;

GRANT EXECUTE ON PROCEDURE public.sp_tao_ho_so_da_kenh(
    CHARACTER VARYING, CHARACTER VARYING, CHARACTER VARYING,
    CHARACTER VARYING, CHARACTER VARYING, CHARACTER VARYING,
    CHARACTER VARYING, TEXT, TIMESTAMPTZ
) TO hau_mai_app;