-- Keep the serial entered by the customer even when it is not registered yet.
ALTER TABLE ho_so
    ADD COLUMN serial_khach_khai_bao VARCHAR(100);

-- Record the initial state of every newly created case.
CREATE FUNCTION fn_ho_so_ghi_lich_su_tao()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO lich_su_xu_ly (
        ho_so_id,
        trang_thai_tu,
        trang_thai_sang,
        loai_tac_nhan,
        ghi_chu,
        tao_luc
    )
    VALUES (
        NEW.id,
        NULL,
        NEW.trang_thai,
        'KHACH_HANG',
        'Khách hàng gửi yêu cầu',
        NEW.ngay_tiep_nhan
    );

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ho_so_ghi_lich_su_tao
AFTER INSERT ON ho_so
FOR EACH ROW
EXECUTE FUNCTION fn_ho_so_ghi_lich_su_tao();

-- Create a website case, its first message, and both SLA records atomically.
CREATE PROCEDURE sp_tao_ho_so_website(
    IN p_ho_ten VARCHAR(200),
    IN p_so_dien_thoai VARCHAR(30),
    IN p_serial VARCHAR(100),
    IN p_mo_ta_loi TEXT,
    IN p_now TIMESTAMPTZ,
    OUT p_ho_so_id BIGINT,
    OUT p_ma_ho_so VARCHAR(30)
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_khach_hang_id BIGINT;
    v_kenh_id BIGINT;
    v_serial_khai_bao VARCHAR(100);
    v_serial_da_dang_ky VARCHAR(100);
    v_ma_so BIGINT;
    v_now TIMESTAMPTZ;
    v_sla_tiep_nhan INTEGER;
    v_sla_xu_ly INTEGER;
BEGIN
    v_now := COALESCE(p_now, now());

    IF NULLIF(BTRIM(p_ho_ten), '') IS NULL THEN
        RAISE EXCEPTION 'Họ tên không được để trống';
    END IF;

    IF NULLIF(BTRIM(p_so_dien_thoai), '') IS NULL THEN
        RAISE EXCEPTION 'Số điện thoại không được để trống';
    END IF;

    IF NULLIF(BTRIM(p_mo_ta_loi), '') IS NULL THEN
        RAISE EXCEPTION 'Mô tả vấn đề không được để trống';
    END IF;

    SELECT id
    INTO v_kenh_id
    FROM kenh_goc
    WHERE ma_kenh = 'WEBSITE'
      AND dang_bat = TRUE;

    IF v_kenh_id IS NULL THEN
        RAISE EXCEPTION 'Kênh WEBSITE chưa được cấu hình hoặc đang tắt';
    END IF;

    INSERT INTO khach_hang (ho_ten, so_dien_thoai)
    VALUES (BTRIM(p_ho_ten), BTRIM(p_so_dien_thoai))
    ON CONFLICT (so_dien_thoai)
    DO UPDATE SET ho_ten = EXCLUDED.ho_ten
    RETURNING id INTO v_khach_hang_id;

    v_serial_khai_bao := NULLIF(BTRIM(p_serial), '');

    IF v_serial_khai_bao IS NOT NULL THEN
        SELECT serial
        INTO v_serial_da_dang_ky
        FROM san_pham
        WHERE serial = v_serial_khai_bao;
    END IF;

    SELECT
        COALESCE(
            (SELECT gia_tri::INTEGER
             FROM cau_hinh
             WHERE ma_cau_hinh = 'sla_tiep_nhan_phut'),
            30
        ),
        COALESCE(
            (SELECT gia_tri::INTEGER
             FROM cau_hinh
             WHERE ma_cau_hinh = 'sla_xu_ly_phut'),
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

    INSERT INTO ho_so (
        ma_ho_so,
        khach_hang_id,
        serial,
        serial_khach_khai_bao,
        kenh_goc_id,
        mo_ta_loi,
        ngay_tiep_nhan,
        trang_thai,
        tao_luc
    )
    VALUES (
        p_ma_ho_so,
        v_khach_hang_id,
        v_serial_da_dang_ky,
        v_serial_khai_bao,
        v_kenh_id,
        BTRIM(p_mo_ta_loi),
        v_now,
        'MOI',
        v_now
    )
    RETURNING id INTO p_ho_so_id;

    INSERT INTO tin_nhan (
        ho_so_id,
        kenh_id,
        huong_tin,
        noi_dung,
        tao_luc
    )
    VALUES (
        p_ho_so_id,
        v_kenh_id,
        'DEN',
        BTRIM(p_mo_ta_loi),
        v_now
    );

    INSERT INTO sla (
        ho_so_id,
        loai_sla,
        thoi_han_phut,
        thoi_diem_bat_dau,
        trang_thai
    )
    VALUES
        (p_ho_so_id, 'TIEP_NHAN', v_sla_tiep_nhan, v_now, 'DANG_DEM'),
        (p_ho_so_id, 'XU_LY', v_sla_xu_ly, v_now, 'DANG_DEM');
END;
$$;