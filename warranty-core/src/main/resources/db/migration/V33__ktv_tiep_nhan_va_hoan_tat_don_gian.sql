-- KTV workflow: assigned -> accept -> complete. Keep detailed legacy progress endpoint available.
CREATE OR REPLACE VIEW public.v_tai_ky_thuat_vien AS
SELECT
    nv.id AS ky_thuat_vien_id,
    nv.ho_ten,
    tk.ten_dang_nhap,
    COUNT(pc.id) FILTER (WHERE hs.trang_thai IN ('CHO_PHAN_CONG', 'DANG_SUA_CHUA'))::INTEGER
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


CREATE OR REPLACE PROCEDURE public.sp_phan_cong(
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
      AND hs.trang_thai IN ('CHO_PHAN_CONG', 'DANG_SUA_CHUA')
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

    -- Giữ hồ sơ ở CHO_PHAN_CONG đến khi kỹ thuật viên bấm Tiếp nhận.

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
CREATE OR REPLACE VIEW public.v_ho_so_ky_thuat_vien AS
SELECT
    pc.id AS phan_cong_id,
    pc.ho_so_id,
    pc.ky_thuat_vien_id,
    hs.ma_ho_so,
    hs.mo_ta_loi,
    hs.serial,
    hs.serial_khach_khai_bao,
    hs.trang_thai AS trang_thai_ho_so,
    kh.ho_ten AS ten_khach_hang,
    kh.so_dien_thoai,
    td.trang_thai AS trang_thai_tien_do,
    td.ghi_chu AS ghi_chu_tien_do,
    td.de_xuat_linh_kien,
    td.tao_luc AS cap_nhat_tien_do_luc
FROM public.phan_cong pc
JOIN public.ho_so hs ON hs.id = pc.ho_so_id
JOIN public.khach_hang kh ON kh.id = hs.khach_hang_id
LEFT JOIN LATERAL (
    SELECT t.trang_thai, t.ghi_chu, t.de_xuat_linh_kien, t.tao_luc
    FROM public.tien_do_sua_chua t
    WHERE t.phan_cong_id = pc.id
    ORDER BY t.tao_luc DESC, t.id DESC
    LIMIT 1
) td ON TRUE
WHERE pc.dang_hieu_luc = TRUE
  AND hs.trang_thai IN ('CHO_PHAN_CONG', 'DANG_SUA_CHUA', 'DA_SUA_XONG');

ALTER VIEW public.v_ho_so_ky_thuat_vien OWNER TO hau_mai_owner;
REVOKE ALL ON TABLE public.v_ho_so_ky_thuat_vien FROM PUBLIC;
GRANT SELECT ON TABLE public.v_ho_so_ky_thuat_vien TO hau_mai_app;
CREATE PROCEDURE public.sp_ktv_tiep_nhan_phan_cong(
    IN p_phan_cong_id BIGINT,
    IN p_ky_thuat_vien_id BIGINT,
    IN p_now TIMESTAMPTZ DEFAULT now()
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_now TIMESTAMPTZ := COALESCE(p_now, now());
    v_ho_so_id BIGINT;
    v_trang_thai VARCHAR(40);
    v_tien_do VARCHAR(30);
BEGIN
    SELECT ho_so_id INTO v_ho_so_id
    FROM public.phan_cong WHERE id = p_phan_cong_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy phân công'; END IF;

    SELECT trang_thai INTO v_trang_thai
    FROM public.ho_so WHERE id = v_ho_so_id FOR UPDATE;
    IF v_trang_thai <> 'CHO_PHAN_CONG' THEN
        RAISE EXCEPTION 'Hồ sơ không còn ở trạng thái chờ tiếp nhận';
    END IF;

    PERFORM 1 FROM public.phan_cong
    WHERE id = p_phan_cong_id AND ky_thuat_vien_id = p_ky_thuat_vien_id AND dang_hieu_luc = TRUE
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Phân công không còn hiệu lực hoặc không thuộc kỹ thuật viên này'; END IF;

    PERFORM 1 FROM public.nhan_vien nv
    JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
    WHERE nv.id = p_ky_thuat_vien_id AND tk.vai_tro = 'KY_THUAT_VIEN' AND tk.dang_hoat_dong = TRUE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Tài khoản kỹ thuật viên không hợp lệ hoặc đã bị khóa'; END IF;

    SELECT trang_thai INTO v_tien_do FROM public.tien_do_sua_chua
    WHERE phan_cong_id = p_phan_cong_id ORDER BY tao_luc DESC, id DESC LIMIT 1;
    IF v_tien_do <> 'DA_NHAN_THIET_BI' THEN RAISE EXCEPTION 'Hồ sơ đã được tiếp nhận'; END IF;

    INSERT INTO public.tien_do_sua_chua(phan_cong_id, trang_thai, ghi_chu, tao_luc)
    VALUES (p_phan_cong_id, 'DANG_SUA_CHUA', 'Kỹ thuật viên đã tiếp nhận hồ sơ', v_now);
    CALL public.sp_chuyen_trang_thai(v_ho_so_id, 'DANG_SUA_CHUA', 'NHAN_VIEN', p_ky_thuat_vien_id, 'Kỹ thuật viên tiếp nhận sửa chữa', v_now);
END;
$$;

ALTER PROCEDURE public.sp_ktv_tiep_nhan_phan_cong(BIGINT, BIGINT, TIMESTAMPTZ) OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_ktv_tiep_nhan_phan_cong(BIGINT, BIGINT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_ktv_tiep_nhan_phan_cong(BIGINT, BIGINT, TIMESTAMPTZ) TO hau_mai_app;
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
    v_now TIMESTAMPTZ;
    v_ho_so_id BIGINT;
    v_trang_thai_ho_so VARCHAR(40);
    v_trang_thai_tien_do VARCHAR(30);
    v_trang_thai_ho_so_moi VARCHAR(40);
    v_ket_luan TEXT;
BEGIN
    v_now := COALESCE(p_now, now());
    v_ket_luan := NULLIF(BTRIM(p_ket_luan), '');

    IF v_ket_luan IS NULL THEN
        RAISE EXCEPTION 'Cần nhập kết luận sửa chữa';
    END IF;

    IF p_ket_qua NOT IN ('DA_SUA_XONG', 'KHONG_THE_SUA') THEN
        RAISE EXCEPTION 'Kết quả sửa chữa không hợp lệ';
    END IF;

    SELECT ho_so_id
    INTO v_ho_so_id
    FROM public.phan_cong
    WHERE id = p_phan_cong_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy phân công id=%', p_phan_cong_id;
    END IF;

    -- Khóa hồ sơ trước để đồng bộ thứ tự khóa với các procedure khác.
    SELECT trang_thai
    INTO v_trang_thai_ho_so
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

    SELECT trang_thai
    INTO v_trang_thai_tien_do
    FROM public.tien_do_sua_chua
    WHERE phan_cong_id = p_phan_cong_id
    ORDER BY tao_luc DESC, id DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Phân công chưa có tiến độ sửa chữa';
    END IF;

    IF p_ket_qua = 'DA_SUA_XONG' THEN
        IF v_trang_thai_tien_do <> 'DANG_SUA_CHUA' THEN
            RAISE EXCEPTION 'Chỉ hoàn thành khi hồ sơ đang sửa chữa';
        END IF;

        v_trang_thai_ho_so_moi := 'DA_SUA_XONG';

    ELSE
        IF v_trang_thai_tien_do NOT IN (
            'DANG_KIEM_TRA',
            'DANG_SUA_CHUA',
            'CHO_LINH_KIEN',
            'DANG_KIEM_TRA_LAI'
        ) THEN
            RAISE EXCEPTION 'Cần bắt đầu kiểm tra trước khi chốt không thể sửa';
        END IF;

        v_trang_thai_ho_so_moi := 'CHO_CSKH_XU_LY';
    END IF;

    INSERT INTO public.tien_do_sua_chua (
        phan_cong_id,
        trang_thai,
        ghi_chu,
        tao_luc
    )
    VALUES (
        p_phan_cong_id,
        p_ket_qua,
        v_ket_luan,
        v_now
    );

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


ALTER PROCEDURE public.sp_hoan_tat_sua_chua(
    BIGINT, BIGINT, VARCHAR, TEXT, TIMESTAMPTZ
)
OWNER TO hau_mai_owner;

REVOKE EXECUTE ON PROCEDURE public.sp_hoan_tat_sua_chua(
    BIGINT, BIGINT, VARCHAR, TEXT, TIMESTAMPTZ
) FROM PUBLIC;

GRANT EXECUTE ON PROCEDURE public.sp_hoan_tat_sua_chua(
    BIGINT, BIGINT, VARCHAR, TEXT, TIMESTAMPTZ
) TO hau_mai_app;
