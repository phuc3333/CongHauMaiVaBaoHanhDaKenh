-- Hồ sơ đã ở DANG_SUA_CHUA nhưng tiến độ cũ có thể vẫn là DA_NHAN_THIET_BI.
-- Cho phép KTV hoàn thành dựa trên trạng thái hồ sơ, không bắt buộc có bản ghi tiến độ trung gian.
CREATE OR REPLACE PROCEDURE public.sp_hoan_tat_sua_chua(
    IN p_phan_cong_id BIGINT,
    IN p_ky_thuat_vien_id BIGINT,
    IN p_ket_qua VARCHAR(30),
    IN p_ket_luan TEXT,
    IN p_now TIMESTAMPTZ DEFAULT now()
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_now TIMESTAMPTZ := COALESCE(p_now, now());
    v_ho_so_id BIGINT;
    v_trang_thai_ho_so VARCHAR(40);
    v_trang_thai_tien_do VARCHAR(30);
    v_trang_thai_ho_so_moi VARCHAR(40);
    v_ket_luan TEXT := NULLIF(BTRIM(p_ket_luan), '');
BEGIN
    IF v_ket_luan IS NULL THEN
        RAISE EXCEPTION 'Cần nhập kết luận sửa chữa';
    END IF;

    IF p_ket_qua NOT IN ('DA_SUA_XONG', 'KHONG_THE_SUA') THEN
        RAISE EXCEPTION 'Kết quả sửa chữa không hợp lệ';
    END IF;

    SELECT ho_so_id INTO v_ho_so_id
    FROM public.phan_cong
    WHERE id = p_phan_cong_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy phân công id=%', p_phan_cong_id;
    END IF;

    SELECT trang_thai INTO v_trang_thai_ho_so
    FROM public.ho_so
    WHERE id = v_ho_so_id
    FOR UPDATE;
    IF NOT FOUND OR v_trang_thai_ho_so <> 'DANG_SUA_CHUA' THEN
        RAISE EXCEPTION 'Hồ sơ không tồn tại hoặc không ở trạng thái DANG_SUA_CHUA';
    END IF;

    PERFORM 1
    FROM public.phan_cong
    WHERE id = p_phan_cong_id
      AND ky_thuat_vien_id = p_ky_thuat_vien_id
      AND dang_hieu_luc = TRUE
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Phân công không còn hiệu lực hoặc không thuộc kỹ thuật viên này';
    END IF;

    PERFORM 1
    FROM public.nhan_vien nv
    JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
    WHERE nv.id = p_ky_thuat_vien_id
      AND tk.vai_tro = 'KY_THUAT_VIEN'
      AND tk.dang_hoat_dong = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tài khoản kỹ thuật viên không hợp lệ hoặc đã bị khóa';
    END IF;

    SELECT trang_thai INTO v_trang_thai_tien_do
    FROM public.tien_do_sua_chua
    WHERE phan_cong_id = p_phan_cong_id
    ORDER BY tao_luc DESC, id DESC
    LIMIT 1;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Phân công chưa có tiến độ sửa chữa';
    END IF;

    IF p_ket_qua = 'DA_SUA_XONG' THEN
        -- Trạng thái hồ sơ đã được khóa và xác nhận DANG_SUA_CHUA ở trên.
        -- DA_NHAN_THIET_BI được chấp nhận để hỗ trợ hồ sơ có thiếu bản ghi
        -- tiến độ tiếp nhận trong dữ liệu cũ.
        IF v_trang_thai_tien_do NOT IN ('DA_NHAN_THIET_BI', 'DANG_SUA_CHUA') THEN
            RAISE EXCEPTION 'Chỉ hoàn thành khi hồ sơ đang sửa chữa';
        END IF;
        v_trang_thai_ho_so_moi := 'DA_SUA_XONG';
    ELSE
        IF v_trang_thai_tien_do NOT IN (
            'DANG_KIEM_TRA', 'DANG_SUA_CHUA', 'CHO_LINH_KIEN', 'DANG_KIEM_TRA_LAI'
        ) THEN
            RAISE EXCEPTION 'Cần bắt đầu kiểm tra trước khi chốt không thể sửa';
        END IF;
        v_trang_thai_ho_so_moi := 'CHO_CSKH_XU_LY';
    END IF;

    INSERT INTO public.tien_do_sua_chua(phan_cong_id, trang_thai, ghi_chu, tao_luc)
    VALUES (p_phan_cong_id, p_ket_qua, v_ket_luan, v_now);

    UPDATE public.ho_so
    SET ket_luan_xu_ly = v_ket_luan
    WHERE id = v_ho_so_id;

    CALL public.sp_chuyen_trang_thai(
        v_ho_so_id,
        v_trang_thai_ho_so_moi,
        'NHAN_VIEN',
        p_ky_thuat_vien_id,
        v_ket_luan,
        v_now
    );
END;
$$;

ALTER PROCEDURE public.sp_hoan_tat_sua_chua(BIGINT, BIGINT, VARCHAR, TEXT, TIMESTAMPTZ)
    OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_hoan_tat_sua_chua(BIGINT, BIGINT, VARCHAR, TEXT, TIMESTAMPTZ)
    FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_hoan_tat_sua_chua(BIGINT, BIGINT, VARCHAR, TEXT, TIMESTAMPTZ)
    TO hau_mai_app;
