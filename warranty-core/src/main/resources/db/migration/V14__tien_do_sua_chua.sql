CREATE PROCEDURE public.sp_cap_nhat_tien_do(
    IN p_phan_cong_id BIGINT,
    IN p_ky_thuat_vien_id BIGINT,
    IN p_trang_thai_moi VARCHAR(30),
    IN p_ghi_chu TEXT,
    IN p_de_xuat_linh_kien TEXT,
    IN p_now TIMESTAMPTZ DEFAULT now()
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_now TIMESTAMPTZ;
    v_ho_so_id BIGINT;
    v_trang_thai_ho_so VARCHAR(40);
    v_trang_thai_hien_tai VARCHAR(30);
BEGIN
    v_now := COALESCE(p_now, now());

    -- Tìm hồ sơ thuộc phân công.
    SELECT ho_so_id
    INTO v_ho_so_id
    FROM public.phan_cong
    WHERE id = p_phan_cong_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy phân công id=%', p_phan_cong_id;
    END IF;

    -- Khóa hồ sơ trước để đồng bộ thứ tự khóa với thao tác phân công lại.
    SELECT trang_thai
    INTO v_trang_thai_ho_so
    FROM public.ho_so
    WHERE id = v_ho_so_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy hồ sơ id=%', v_ho_so_id;
    END IF;

    IF v_trang_thai_ho_so <> 'DANG_SUA_CHUA' THEN
        RAISE EXCEPTION 'Hồ sơ hiện không ở trạng thái DANG_SUA_CHUA';
    END IF;

    -- Khóa phân công và xác nhận đây là phân công hiện tại của kỹ thuật viên.
    PERFORM 1
    FROM public.phan_cong
    WHERE id = p_phan_cong_id
      AND ky_thuat_vien_id = p_ky_thuat_vien_id
      AND dang_hieu_luc = TRUE
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Phân công không còn hiệu lực hoặc không thuộc kỹ thuật viên này';
    END IF;

    -- Tài khoản phải đang hoạt động và có vai trò kỹ thuật viên.
    PERFORM 1
    FROM public.nhan_vien nv
    JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
    WHERE nv.id = p_ky_thuat_vien_id
      AND tk.vai_tro = 'KY_THUAT_VIEN'
      AND tk.dang_hoat_dong = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tài khoản kỹ thuật viên không hợp lệ hoặc đã bị khóa';
    END IF;

    SELECT trang_thai
    INTO v_trang_thai_hien_tai
    FROM public.tien_do_sua_chua
    WHERE phan_cong_id = p_phan_cong_id
    ORDER BY tao_luc DESC, id DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Phân công chưa có tiến độ khởi tạo';
    END IF;

    IF NOT (
        (v_trang_thai_hien_tai = 'DA_NHAN_THIET_BI'
            AND p_trang_thai_moi = 'DANG_KIEM_TRA')
        OR
        (v_trang_thai_hien_tai = 'DANG_KIEM_TRA'
            AND p_trang_thai_moi IN ('DANG_SUA_CHUA', 'CHO_LINH_KIEN'))
        OR
        (v_trang_thai_hien_tai = 'DANG_SUA_CHUA'
            AND p_trang_thai_moi IN ('CHO_LINH_KIEN', 'DANG_KIEM_TRA_LAI'))
        OR
        (v_trang_thai_hien_tai = 'CHO_LINH_KIEN'
            AND p_trang_thai_moi = 'DANG_SUA_CHUA')
        OR
        (v_trang_thai_hien_tai = 'DANG_KIEM_TRA_LAI'
            AND p_trang_thai_moi = 'DANG_SUA_CHUA')
    ) THEN
        RAISE EXCEPTION
            'Không thể chuyển tiến độ từ % sang %',
            v_trang_thai_hien_tai,
            p_trang_thai_moi;
    END IF;

    IF p_trang_thai_moi = 'CHO_LINH_KIEN'
       AND NULLIF(BTRIM(p_de_xuat_linh_kien), '') IS NULL THEN
        RAISE EXCEPTION 'Chuyển sang CHO_LINH_KIEN cần ghi đề xuất linh kiện';
    END IF;

    INSERT INTO public.tien_do_sua_chua (
        phan_cong_id,
        trang_thai,
        ghi_chu,
        de_xuat_linh_kien,
        tao_luc
    )
    VALUES (
        p_phan_cong_id,
        p_trang_thai_moi,
        NULLIF(BTRIM(p_ghi_chu), ''),
        CASE
            WHEN p_trang_thai_moi = 'CHO_LINH_KIEN'
                THEN NULLIF(BTRIM(p_de_xuat_linh_kien), '')
            ELSE NULL
        END,
        v_now
    );
END;
$$;


ALTER PROCEDURE public.sp_cap_nhat_tien_do(
    BIGINT, BIGINT, VARCHAR, TEXT, TEXT, TIMESTAMPTZ
)
OWNER TO hau_mai_owner;

REVOKE EXECUTE ON PROCEDURE public.sp_cap_nhat_tien_do(
    BIGINT, BIGINT, VARCHAR, TEXT, TEXT, TIMESTAMPTZ
) FROM PUBLIC;

GRANT EXECUTE ON PROCEDURE public.sp_cap_nhat_tien_do(
    BIGINT, BIGINT, VARCHAR, TEXT, TEXT, TIMESTAMPTZ
) TO hau_mai_app;