-- Quyết định xác minh được thực hiện trong HoSoService.
-- Procedure chỉ lưu kết quả và áp dụng chuyển trạng thái nguyên tử.
CREATE OR REPLACE PROCEDURE public.sp_luu_ket_qua_xac_minh(
    IN p_ho_so_id BIGINT,
    IN p_ket_qua TEXT,
    IN p_ly_do_tu_choi TEXT,
    IN p_ngoai_bao_hanh BOOLEAN,
    IN p_trang_thai_moi VARCHAR(40),
    IN p_nhan_vien_id BIGINT,
    IN p_ghi_chu TEXT,
    IN p_now TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_trang_thai_hien_tai VARCHAR(40);
BEGIN
    -- Khóa hàng để phần lưu kết quả và chuyển trạng thái cùng áp dụng trên một hồ sơ.
    SELECT trang_thai INTO v_trang_thai_hien_tai
    FROM public.ho_so WHERE id = p_ho_so_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy hồ sơ id=%', p_ho_so_id;
    END IF;
    IF v_trang_thai_hien_tai <> 'DANG_XAC_MINH' THEN
        RAISE EXCEPTION 'Hồ sơ không còn ở trạng thái đang xác minh';
    END IF;

    UPDATE public.ho_so
    SET ket_qua_xac_minh = p_ket_qua,
        ly_do_tu_choi = p_ly_do_tu_choi,
        ngoai_bao_hanh = p_ngoai_bao_hanh
    WHERE id = p_ho_so_id;

    CALL public.sp_chuyen_trang_thai(
        p_ho_so_id, p_trang_thai_moi, 'NHAN_VIEN', p_nhan_vien_id, p_ghi_chu, p_now
    );
END;
$$;

ALTER PROCEDURE public.sp_luu_ket_qua_xac_minh(
    BIGINT, TEXT, TEXT, BOOLEAN, VARCHAR, BIGINT, TEXT, TIMESTAMPTZ
) OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_luu_ket_qua_xac_minh(
    BIGINT, TEXT, TEXT, BOOLEAN, VARCHAR, BIGINT, TEXT, TIMESTAMPTZ
) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_luu_ket_qua_xac_minh(
    BIGINT, TEXT, TEXT, BOOLEAN, VARCHAR, BIGINT, TEXT, TIMESTAMPTZ
) TO hau_mai_app;
