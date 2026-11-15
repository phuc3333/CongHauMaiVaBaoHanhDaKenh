CREATE OR REPLACE VIEW public.v_ho_so_zalo AS
SELECT DISTINCT hs.id AS ho_so_id
FROM public.ho_so hs
JOIN public.kenh_goc kg ON kg.id = hs.kenh_goc_id AND kg.ma_kenh = 'ZALO'
JOIN public.dinh_danh_kenh dk
  ON dk.khach_hang_id = hs.khach_hang_id AND dk.kenh_id = kg.id;

ALTER VIEW public.v_ho_so_zalo OWNER TO hau_mai_owner;
REVOKE ALL ON TABLE public.v_ho_so_zalo FROM PUBLIC;
GRANT SELECT ON TABLE public.v_ho_so_zalo TO hau_mai_app;

CREATE OR REPLACE VIEW public.v_tin_nhan_zalo AS
SELECT tn.ho_so_id, tn.huong_tin, tn.noi_dung, tn.trang_thai_gui, tn.tao_luc, tn.gui_luc
FROM public.tin_nhan tn
JOIN public.kenh_goc kg ON kg.id = tn.kenh_id
WHERE kg.ma_kenh = 'ZALO';

ALTER VIEW public.v_tin_nhan_zalo OWNER TO hau_mai_owner;
REVOKE ALL ON TABLE public.v_tin_nhan_zalo FROM PUBLIC;
GRANT SELECT ON TABLE public.v_tin_nhan_zalo TO hau_mai_app;

CREATE OR REPLACE PROCEDURE public.sp_tao_phan_hoi_zalo(
    IN p_ho_so_id BIGINT,
    IN p_nhan_vien_id BIGINT,
    IN p_noi_dung TEXT,
    IN p_now TIMESTAMPTZ,
    OUT p_tin_nhan_id BIGINT,
    OUT p_recipient_id VARCHAR
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_kenh_id BIGINT;
BEGIN
    IF NULLIF(BTRIM(p_noi_dung), '') IS NULL OR LENGTH(p_noi_dung) > 2000 THEN
        RAISE EXCEPTION 'Nội dung phản hồi phải từ 1 đến 2000 ký tự';
    END IF;

    PERFORM 1
    FROM public.nhan_vien nv
    JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
    WHERE nv.id = p_nhan_vien_id
      AND tk.vai_tro = 'CSKH'
      AND tk.dang_hoat_dong = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Nhân viên không có quyền CSKH đang hoạt động';
    END IF;

    SELECT kg.id, dk.ma_nguoi_dung_kenh
    INTO v_kenh_id, p_recipient_id
    FROM public.ho_so hs
    JOIN public.kenh_goc kg ON kg.id = hs.kenh_goc_id AND kg.ma_kenh = 'ZALO'
    JOIN public.dinh_danh_kenh dk
      ON dk.khach_hang_id = hs.khach_hang_id AND dk.kenh_id = kg.id
    WHERE hs.id = p_ho_so_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy định danh Zalo cho hồ sơ %', p_ho_so_id;
    END IF;

    INSERT INTO public.tin_nhan (
        ho_so_id, kenh_id, huong_tin, noi_dung, nhan_vien_id, trang_thai_gui, tao_luc
    ) VALUES (
        p_ho_so_id, v_kenh_id, 'DI', BTRIM(p_noi_dung), p_nhan_vien_id,
        'CHO_GUI', COALESCE(p_now, now())
    ) RETURNING id INTO p_tin_nhan_id;
END;
$$;

ALTER PROCEDURE public.sp_tao_phan_hoi_zalo(BIGINT, BIGINT, TEXT, TIMESTAMPTZ)
    OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_tao_phan_hoi_zalo(BIGINT, BIGINT, TEXT, TIMESTAMPTZ)
    FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_tao_phan_hoi_zalo(BIGINT, BIGINT, TEXT, TIMESTAMPTZ)
    TO hau_mai_app;

CREATE OR REPLACE PROCEDURE public.sp_cap_nhat_ket_qua_gui_zalo(
    IN p_tin_nhan_id BIGINT,
    IN p_trang_thai VARCHAR(20),
    IN p_ma_tin_nha_cung_cap VARCHAR(255),
    IN p_now TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_ma_tin_goc VARCHAR(255);
    v_rows INTEGER;
BEGIN
    IF p_trang_thai NOT IN ('DA_GUI', 'THAT_BAI') THEN
        RAISE EXCEPTION 'Trạng thái gửi không hợp lệ';
    END IF;
    v_ma_tin_goc := NULLIF(BTRIM(p_ma_tin_nha_cung_cap), '');

    UPDATE public.tin_nhan
    SET trang_thai_gui = p_trang_thai,
        ma_tin_goc = v_ma_tin_goc,
        gui_luc = CASE WHEN p_trang_thai = 'DA_GUI' THEN COALESCE(p_now, now()) ELSE gui_luc END
    WHERE id = p_tin_nhan_id
      AND huong_tin = 'DI'
      AND trang_thai_gui = 'CHO_GUI';
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 AND NOT EXISTS (
        SELECT 1 FROM public.tin_nhan
        WHERE id = p_tin_nhan_id
          AND huong_tin = 'DI'
          AND trang_thai_gui = p_trang_thai
          AND ma_tin_goc IS NOT DISTINCT FROM v_ma_tin_goc
    ) THEN
        RAISE EXCEPTION 'Không tìm thấy tin nhắn gửi chờ xử lý id=%', p_tin_nhan_id;
    END IF;
END;
$$;

ALTER PROCEDURE public.sp_cap_nhat_ket_qua_gui_zalo(BIGINT, VARCHAR, VARCHAR, TIMESTAMPTZ)
    OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_cap_nhat_ket_qua_gui_zalo(BIGINT, VARCHAR, VARCHAR, TIMESTAMPTZ)
    FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_cap_nhat_ket_qua_gui_zalo(BIGINT, VARCHAR, VARCHAR, TIMESTAMPTZ)
    TO hau_mai_app;
