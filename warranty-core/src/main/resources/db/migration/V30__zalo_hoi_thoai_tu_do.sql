CREATE OR REPLACE PROCEDURE public.sp_ghi_nhan_tin_tiep_theo_kenh(
    IN p_ma_kenh VARCHAR(30),
    IN p_ma_tin_goc VARCHAR(255),
    IN p_ma_nguoi_dung_kenh VARCHAR(255),
    IN p_noi_dung TEXT,
    IN p_nhan_luc TIMESTAMPTZ,
    OUT p_ho_so_id BIGINT,
    OUT p_ma_ho_so VARCHAR(30),
    OUT p_ket_qua VARCHAR(30)
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_ma_kenh VARCHAR(30);
    v_kenh_id BIGINT;
    v_khach_hang_id BIGINT;
    v_so_ho_so INTEGER;
    v_rows INTEGER;
BEGIN
    v_ma_kenh := UPPER(NULLIF(BTRIM(p_ma_kenh), ''));
    p_ho_so_id := NULL;
    p_ma_ho_so := NULL;
    p_ket_qua := 'KHONG_TIM_THAY';

    IF v_ma_kenh NOT IN ('FACEBOOK', 'ZALO')
       OR NULLIF(BTRIM(p_ma_tin_goc), '') IS NULL
       OR NULLIF(BTRIM(p_ma_nguoi_dung_kenh), '') IS NULL
       OR NULLIF(BTRIM(p_noi_dung), '') IS NULL THEN
        RAISE EXCEPTION 'Thiếu kênh, mã tin, định danh hoặc nội dung';
    END IF;

    SELECT kg.id INTO v_kenh_id
    FROM public.kenh_goc kg
    WHERE kg.ma_kenh = v_ma_kenh AND kg.dang_bat;
    IF NOT FOUND THEN RAISE EXCEPTION 'Kênh chưa được cấu hình hoặc đang tắt'; END IF;

    SELECT dk.khach_hang_id INTO v_khach_hang_id
    FROM public.dinh_danh_kenh dk
    WHERE dk.kenh_id = v_kenh_id
      AND dk.ma_nguoi_dung_kenh = p_ma_nguoi_dung_kenh;
    IF NOT FOUND THEN
        p_ket_qua := 'CHUA_CO_DINH_DANH';
        RETURN;
    END IF;

    SELECT tn.ho_so_id, hs.ma_ho_so INTO p_ho_so_id, p_ma_ho_so
    FROM public.tin_nhan tn
    LEFT JOIN public.ho_so hs ON hs.id = tn.ho_so_id
    WHERE tn.kenh_id = v_kenh_id AND tn.ma_tin_goc = p_ma_tin_goc;
    IF FOUND THEN
        p_ket_qua := 'DA_TON_TAI';
        RETURN;
    END IF;

    SELECT COUNT(*)::INTEGER, MIN(hs.id)
    INTO v_so_ho_so, p_ho_so_id
    FROM public.ho_so hs
    WHERE hs.khach_hang_id = v_khach_hang_id
      AND hs.kenh_goc_id = v_kenh_id
      AND hs.trang_thai NOT IN ('DA_DONG', 'TU_CHOI');

    IF v_so_ho_so = 0 THEN
        p_ho_so_id := NULL;
        p_ket_qua := 'KHONG_CO_HO_SO_MO';
        RETURN;
    ELSIF v_so_ho_so > 1 THEN
        p_ho_so_id := NULL;
        p_ket_qua := 'NHIEU_HO_SO_MO';
        RETURN;
    END IF;

    SELECT hs.ma_ho_so INTO p_ma_ho_so
    FROM public.ho_so hs WHERE hs.id = p_ho_so_id;

    INSERT INTO public.tin_nhan (
        ho_so_id, kenh_id, ma_tin_goc, huong_tin, noi_dung,
        nhan_vien_id, trang_thai_gui, tao_luc
    ) VALUES (
        p_ho_so_id, v_kenh_id, p_ma_tin_goc, 'DEN', BTRIM(p_noi_dung),
        NULL, 'KHONG_AP_DUNG', COALESCE(p_nhan_luc, now())
    ) ON CONFLICT (kenh_id, ma_tin_goc) WHERE ma_tin_goc IS NOT NULL DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 THEN
        SELECT tn.ho_so_id, hs.ma_ho_so INTO p_ho_so_id, p_ma_ho_so
        FROM public.tin_nhan tn
        LEFT JOIN public.ho_so hs ON hs.id = tn.ho_so_id
        WHERE tn.kenh_id = v_kenh_id AND tn.ma_tin_goc = p_ma_tin_goc;
        p_ket_qua := 'DA_TON_TAI';
    ELSE
        p_ket_qua := 'DA_GHI_NHAN';
    END IF;
END;
$$;

ALTER PROCEDURE public.sp_ghi_nhan_tin_tiep_theo_kenh(
    VARCHAR, VARCHAR, VARCHAR, TEXT, TIMESTAMPTZ
) OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_ghi_nhan_tin_tiep_theo_kenh(
    VARCHAR, VARCHAR, VARCHAR, TEXT, TIMESTAMPTZ
) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_ghi_nhan_tin_tiep_theo_kenh(
    VARCHAR, VARCHAR, VARCHAR, TEXT, TIMESTAMPTZ
) TO hau_mai_app;

CREATE OR REPLACE PROCEDURE public.sp_tao_phan_hoi_cuoc_tro_chuyen(
    IN p_cuoc_tro_chuyen_id BIGINT,
    IN p_nhan_vien_id BIGINT,
    IN p_noi_dung TEXT,
    IN p_now TIMESTAMPTZ,
    OUT p_tin_nhan_id BIGINT,
    OUT p_ma_kenh VARCHAR,
    OUT p_recipient VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_kenh_id BIGINT;
BEGIN
    IF NULLIF(BTRIM(p_noi_dung), '') IS NULL OR LENGTH(p_noi_dung) > 2000 THEN
        RAISE EXCEPTION 'Nội dung phải từ 1 đến 2000 ký tự';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.nhan_vien nv
        JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
        WHERE nv.id = p_nhan_vien_id AND tk.vai_tro = 'CSKH' AND tk.dang_hoat_dong
    ) THEN
        RAISE EXCEPTION 'Nhân viên CSKH không hoạt động';
    END IF;

    SELECT c.kenh_id, kg.ma_kenh, c.ma_nguoi_dung_kenh
    INTO v_kenh_id, p_ma_kenh, p_recipient
    FROM public.cuoc_tro_chuyen c
    JOIN public.kenh_goc kg ON kg.id = c.kenh_id
    WHERE c.id = p_cuoc_tro_chuyen_id AND kg.ma_kenh IN ('FACEBOOK', 'ZALO');
    IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy cuộc trò chuyện hỗ trợ'; END IF;

    INSERT INTO public.tin_nhan_cuoc_tro_chuyen(
        cuoc_tro_chuyen_id, ho_so_id, huong_tin, noi_dung, trang_thai_gui,
        nhan_vien_id, tao_luc
    ) VALUES (
        p_cuoc_tro_chuyen_id, NULL, 'DI', BTRIM(p_noi_dung), 'CHO_GUI',
        p_nhan_vien_id, COALESCE(p_now, now())
    ) RETURNING id INTO p_tin_nhan_id;

    UPDATE public.cuoc_tro_chuyen SET cap_nhat_luc = COALESCE(p_now, now())
    WHERE id = p_cuoc_tro_chuyen_id;
END;
$$;

ALTER PROCEDURE public.sp_tao_phan_hoi_cuoc_tro_chuyen(BIGINT, BIGINT, TEXT, TIMESTAMPTZ)
    OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_tao_phan_hoi_cuoc_tro_chuyen(BIGINT, BIGINT, TEXT, TIMESTAMPTZ)
    FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_tao_phan_hoi_cuoc_tro_chuyen(BIGINT, BIGINT, TEXT, TIMESTAMPTZ)
    TO hau_mai_app;
