-- Keep linked conversations in the case inbox and copy their history into
-- the case message stream used by CSKH and customer replies.
CREATE OR REPLACE PROCEDURE public.sp_gan_cuoc_tro_chuyen_vao_ho_so(
    IN p_ma_kenh VARCHAR(30),
    IN p_ma_nguoi_dung VARCHAR(255),
    IN p_ho_so_id BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_kenh_id BIGINT;
    v_khach_hang_id BIGINT;
    v_cuoc_tro_chuyen_id BIGINT;
BEGIN
    SELECT hs.kenh_goc_id, hs.khach_hang_id
    INTO v_kenh_id, v_khach_hang_id
    FROM public.ho_so hs
    JOIN public.kenh_goc kg ON kg.id = hs.kenh_goc_id
    JOIN public.dinh_danh_kenh dk
      ON dk.kenh_id = kg.id AND dk.khach_hang_id = hs.khach_hang_id
    WHERE hs.id = p_ho_so_id
      AND kg.ma_kenh = UPPER(BTRIM(p_ma_kenh))
      AND dk.ma_nguoi_dung_kenh = p_ma_nguoi_dung;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    INSERT INTO public.cuoc_tro_chuyen(kenh_id, ma_nguoi_dung_kenh, khach_hang_id, ho_so_id)
    VALUES (v_kenh_id, p_ma_nguoi_dung, v_khach_hang_id, p_ho_so_id)
    ON CONFLICT (kenh_id, ma_nguoi_dung_kenh) DO UPDATE SET
        khach_hang_id = EXCLUDED.khach_hang_id,
        ho_so_id = EXCLUDED.ho_so_id,
        cap_nhat_luc = now()
    RETURNING id INTO v_cuoc_tro_chuyen_id;

    UPDATE public.tin_nhan_cuoc_tro_chuyen
    SET ho_so_id = p_ho_so_id
    WHERE cuoc_tro_chuyen_id = v_cuoc_tro_chuyen_id;

    INSERT INTO public.tin_nhan(
        ho_so_id, kenh_id, ma_tin_goc, huong_tin, noi_dung,
        nhan_vien_id, trang_thai_gui, gui_luc, tao_luc
    )
    SELECT p_ho_so_id, v_kenh_id, m.ma_tin_goc, m.huong_tin, m.noi_dung,
           m.nhan_vien_id, m.trang_thai_gui, m.gui_luc, m.tao_luc
    FROM public.tin_nhan_cuoc_tro_chuyen m
    WHERE m.cuoc_tro_chuyen_id = v_cuoc_tro_chuyen_id
    ORDER BY m.tao_luc, m.id
    ON CONFLICT (kenh_id, ma_tin_goc) WHERE ma_tin_goc IS NOT NULL DO NOTHING;
END;
$$;

ALTER PROCEDURE public.sp_gan_cuoc_tro_chuyen_vao_ho_so(VARCHAR, VARCHAR, BIGINT)
    OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_gan_cuoc_tro_chuyen_vao_ho_so(VARCHAR, VARCHAR, BIGINT)
    FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_gan_cuoc_tro_chuyen_vao_ho_so(VARCHAR, VARCHAR, BIGINT)
    TO hau_mai_app;

-- Preserve history for conversations that were already linked before this change.
INSERT INTO public.tin_nhan(
    ho_so_id, kenh_id, ma_tin_goc, huong_tin, noi_dung,
    nhan_vien_id, trang_thai_gui, gui_luc, tao_luc
)
SELECT c.ho_so_id, c.kenh_id, m.ma_tin_goc, m.huong_tin, m.noi_dung,
       m.nhan_vien_id, m.trang_thai_gui, m.gui_luc, m.tao_luc
FROM public.cuoc_tro_chuyen c
JOIN public.tin_nhan_cuoc_tro_chuyen m ON m.cuoc_tro_chuyen_id = c.id
WHERE c.ho_so_id IS NOT NULL
ON CONFLICT (kenh_id, ma_tin_goc) WHERE ma_tin_goc IS NOT NULL DO NOTHING;
