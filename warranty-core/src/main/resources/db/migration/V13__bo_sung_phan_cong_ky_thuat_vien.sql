CREATE OR REPLACE VIEW public.v_tai_ky_thuat_vien AS
SELECT
    nv.id AS ky_thuat_vien_id,
    nv.ho_ten,
    tk.ten_dang_nhap,
    COUNT(pc.id) FILTER (WHERE hs.trang_thai = 'DANG_SUA_CHUA')::INTEGER
        AS so_ho_so_dang_xu_ly,
    COALESCE(
        (
            SELECT gia_tri::INTEGER
            FROM public.cau_hinh
            WHERE ma_cau_hinh = 'toi_da_ho_so_ky_thuat_vien'
        ),
        5
    ) AS gioi_han_ho_so
FROM public.nhan_vien nv
JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
LEFT JOIN public.phan_cong pc
    ON pc.ky_thuat_vien_id = nv.id
   AND pc.dang_hieu_luc = TRUE
LEFT JOIN public.ho_so hs ON hs.id = pc.ho_so_id
WHERE tk.vai_tro = 'KY_THUAT_VIEN'
  AND tk.dang_hoat_dong = TRUE
GROUP BY nv.id, nv.ho_ten, tk.ten_dang_nhap;


CREATE PROCEDURE public.sp_phan_cong(
    IN p_ho_so_id BIGINT,
    IN p_ky_thuat_vien_id BIGINT,
    IN p_dieu_phoi_vien_id BIGINT,
    IN p_ly_do_thay_doi TEXT,
    IN p_now TIMESTAMPTZ DEFAULT now()
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_now TIMESTAMPTZ;
    v_trang_thai VARCHAR(40);
    v_ho_so_ma VARCHAR(30);
    v_gioi_han INTEGER;
    v_so_ho_so_dang_xu_ly INTEGER;
    v_phan_cong_cu_id BIGINT;
    v_ky_thuat_vien_cu_id BIGINT;
    v_phan_cong_moi_id BIGINT;
    v_ly_do TEXT;
BEGIN
    v_now := COALESCE(p_now, now());

    -- Khóa hồ sơ để không thể phân công đồng thời cùng một hồ sơ.
    SELECT trang_thai, ma_ho_so
    INTO v_trang_thai, v_ho_so_ma
    FROM public.ho_so
    WHERE id = p_ho_so_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy hồ sơ id=%', p_ho_so_id;
    END IF;

    IF v_trang_thai NOT IN ('CHO_PHAN_CONG', 'DANG_SUA_CHUA') THEN
        RAISE EXCEPTION
            'Chỉ phân công được hồ sơ CHO_PHAN_CONG hoặc đổi kỹ thuật viên của hồ sơ DANG_SUA_CHUA';
    END IF;

    -- Chỉ tài khoản điều phối đang hoạt động mới được giao việc.
    PERFORM 1
    FROM public.nhan_vien nv
    JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
    WHERE nv.id = p_dieu_phoi_vien_id
      AND tk.vai_tro = 'DIEU_PHOI_VIEN'
      AND tk.dang_hoat_dong = TRUE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Điều phối viên không hợp lệ hoặc đã bị khóa';
    END IF;

    -- Khóa dòng kỹ thuật viên để các lần phân công đồng thời được tuần tự hóa.
    PERFORM nv.id
    FROM public.nhan_vien nv
    JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
    WHERE nv.id = p_ky_thuat_vien_id
      AND tk.vai_tro = 'KY_THUAT_VIEN'
      AND tk.dang_hoat_dong = TRUE
    FOR UPDATE OF nv;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kỹ thuật viên không hợp lệ hoặc đã bị khóa';
    END IF;

    SELECT pc.id, pc.ky_thuat_vien_id
    INTO v_phan_cong_cu_id, v_ky_thuat_vien_cu_id
    FROM public.phan_cong pc
    WHERE pc.ho_so_id = p_ho_so_id
      AND pc.dang_hieu_luc = TRUE
    FOR UPDATE;

    IF v_trang_thai = 'CHO_PHAN_CONG'
       AND v_phan_cong_cu_id IS NOT NULL THEN
        RAISE EXCEPTION 'Hồ sơ chờ phân công nhưng đã có phân công hiệu lực';
    END IF;

    IF v_trang_thai = 'DANG_SUA_CHUA'
       AND v_phan_cong_cu_id IS NULL THEN
        RAISE EXCEPTION 'Không tìm thấy phân công hiện tại để đổi kỹ thuật viên';
    END IF;

    IF v_ky_thuat_vien_cu_id = p_ky_thuat_vien_id THEN
        RAISE EXCEPTION 'Hồ sơ đã được giao cho kỹ thuật viên này';
    END IF;

    SELECT COALESCE(
        (
            SELECT gia_tri::INTEGER
            FROM public.cau_hinh
            WHERE ma_cau_hinh = 'toi_da_ho_so_ky_thuat_vien'
        ),
        5
    )
    INTO v_gioi_han;

    IF v_gioi_han <= 0 THEN
        RAISE EXCEPTION 'Giới hạn hồ sơ trên mỗi kỹ thuật viên phải lớn hơn 0';
    END IF;

    SELECT COUNT(*)::INTEGER
    INTO v_so_ho_so_dang_xu_ly
    FROM public.phan_cong pc
    JOIN public.ho_so hs ON hs.id = pc.ho_so_id
    WHERE pc.ky_thuat_vien_id = p_ky_thuat_vien_id
      AND pc.dang_hieu_luc = TRUE
      AND hs.trang_thai = 'DANG_SUA_CHUA'
      AND pc.ho_so_id <> p_ho_so_id;

    IF v_so_ho_so_dang_xu_ly >= v_gioi_han THEN
        RAISE EXCEPTION
            'Kỹ thuật viên đã đủ tải: %/% hồ sơ',
            v_so_ho_so_dang_xu_ly,
            v_gioi_han;
    END IF;

    v_ly_do := COALESCE(
        NULLIF(BTRIM(p_ly_do_thay_doi), ''),
        CASE
            WHEN v_trang_thai = 'CHO_PHAN_CONG' THEN 'Phân công lần đầu'
            ELSE 'Đổi kỹ thuật viên'
        END
    );

    IF v_phan_cong_cu_id IS NOT NULL THEN
        UPDATE public.phan_cong
        SET dang_hieu_luc = FALSE,
            ngay_ket_thuc = v_now,
            ly_do_thay_doi = v_ly_do
        WHERE id = v_phan_cong_cu_id;
    END IF;

    INSERT INTO public.phan_cong (
        ho_so_id,
        ky_thuat_vien_id,
        dieu_phoi_vien_id,
        ngay_phan_cong,
        ly_do_thay_doi,
        dang_hieu_luc
    )
    VALUES (
        p_ho_so_id,
        p_ky_thuat_vien_id,
        p_dieu_phoi_vien_id,
        v_now,
        v_ly_do,
        TRUE
    )
    RETURNING id INTO v_phan_cong_moi_id;

    -- Mỗi lần phân công bắt đầu một tiến độ sửa chữa mới.
    INSERT INTO public.tien_do_sua_chua (
        phan_cong_id,
        trang_thai,
        ghi_chu,
        tao_luc
    )
    VALUES (
        v_phan_cong_moi_id,
        'DA_NHAN_THIET_BI',
        'Khởi tạo tiến độ cho lần phân công mới',
        v_now
    );

    -- Lần đầu phân công thì hồ sơ chuyển sang DANG_SUA_CHUA.
    -- Đổi kỹ thuật viên thì giữ nguyên trạng thái đó.
    IF v_trang_thai = 'CHO_PHAN_CONG' THEN
        CALL public.sp_chuyen_trang_thai(
            p_ho_so_id,
            'DANG_SUA_CHUA',
            'NHAN_VIEN',
            p_dieu_phoi_vien_id,
            v_ly_do,
            v_now
        );
    END IF;

    INSERT INTO public.thong_bao (
        ho_so_id,
        nhan_vien_nhan_id,
        khoa_chong_trung,
        tieu_de,
        noi_dung,
        loai_thong_bao,
        tao_luc
    )
    VALUES (
        p_ho_so_id,
        p_ky_thuat_vien_id,
        'phan-cong:' || v_phan_cong_moi_id,
        'Hồ sơ mới được phân công',
        'Bạn được giao xử lý hồ sơ ' || v_ho_so_ma || '.',
        'PHAN_CONG',
        v_now
    )
    ON CONFLICT (khoa_chong_trung) DO NOTHING;
END;
$$;


ALTER VIEW public.v_tai_ky_thuat_vien
    OWNER TO hau_mai_owner;

ALTER PROCEDURE public.sp_phan_cong(
    BIGINT, BIGINT, BIGINT, TEXT, TIMESTAMPTZ
)
OWNER TO hau_mai_owner;

REVOKE ALL ON TABLE public.v_tai_ky_thuat_vien FROM PUBLIC;
GRANT SELECT ON TABLE public.v_tai_ky_thuat_vien TO hau_mai_app;

REVOKE EXECUTE ON PROCEDURE public.sp_phan_cong(
    BIGINT, BIGINT, BIGINT, TEXT, TIMESTAMPTZ
) FROM PUBLIC;

GRANT EXECUTE ON PROCEDURE public.sp_phan_cong(
    BIGINT, BIGINT, BIGINT, TEXT, TIMESTAMPTZ
) TO hau_mai_app;