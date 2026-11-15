CREATE OR REPLACE PROCEDURE public.sp_ghi_nhan_tin_tiep_theo_facebook(
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
    v_kenh_id BIGINT;
    v_khach_hang_id BIGINT;
    v_so_ho_so INTEGER;
    v_rows INTEGER;
BEGIN
    p_ho_so_id := NULL;
    p_ma_ho_so := NULL;
    p_ket_qua := 'KHONG_TIM_THAY';

    IF NULLIF(BTRIM(p_ma_tin_goc), '') IS NULL
       OR NULLIF(BTRIM(p_ma_nguoi_dung_kenh), '') IS NULL
       OR NULLIF(BTRIM(p_noi_dung), '') IS NULL THEN
        RAISE EXCEPTION 'Thiếu mã tin, định danh Facebook hoặc nội dung';
    END IF;

    SELECT kg.id, dk.khach_hang_id
    INTO v_kenh_id, v_khach_hang_id
    FROM public.kenh_goc kg
    JOIN public.dinh_danh_kenh dk ON dk.kenh_id = kg.id
    WHERE kg.ma_kenh = 'FACEBOOK'
      AND dk.ma_nguoi_dung_kenh = p_ma_nguoi_dung_kenh;
    IF NOT FOUND THEN
        p_ket_qua := 'CHUA_CO_DINH_DANH';
        RETURN;
    END IF;

    -- Webhooks can be redelivered. Return the existing case without inserting twice.
    SELECT tn.ho_so_id, hs.ma_ho_so
    INTO p_ho_so_id, p_ma_ho_so
    FROM public.tin_nhan tn
    JOIN public.ho_so hs ON hs.id = tn.ho_so_id
    WHERE tn.kenh_id = v_kenh_id
      AND tn.ma_tin_goc = p_ma_tin_goc;
    IF FOUND THEN
        p_ket_qua := 'DA_TON_TAI';
        RETURN;
    END IF;

    -- A sender may have more than one active case. Do not guess which one a reply belongs to.
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
        SELECT tn.ho_so_id, hs.ma_ho_so
        INTO p_ho_so_id, p_ma_ho_so
        FROM public.tin_nhan tn
        JOIN public.ho_so hs ON hs.id = tn.ho_so_id
        WHERE tn.kenh_id = v_kenh_id
          AND tn.ma_tin_goc = p_ma_tin_goc;
        p_ket_qua := 'DA_TON_TAI';
    ELSE
        p_ket_qua := 'DA_GHI_NHAN';
    END IF;
END;
$$;

ALTER PROCEDURE public.sp_ghi_nhan_tin_tiep_theo_facebook(
    CHARACTER VARYING, CHARACTER VARYING, TEXT, TIMESTAMPTZ
) OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_ghi_nhan_tin_tiep_theo_facebook(
    CHARACTER VARYING, CHARACTER VARYING, TEXT, TIMESTAMPTZ
) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_ghi_nhan_tin_tiep_theo_facebook(
    CHARACTER VARYING, CHARACTER VARYING, TEXT, TIMESTAMPTZ
) TO hau_mai_app;
