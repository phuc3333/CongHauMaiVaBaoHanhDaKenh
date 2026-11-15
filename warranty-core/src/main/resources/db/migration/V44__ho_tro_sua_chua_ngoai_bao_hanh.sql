ALTER TABLE public.ho_so
    ADD COLUMN ngoai_bao_hanh BOOLEAN NOT NULL DEFAULT FALSE;

CREATE OR REPLACE PROCEDURE public.sp_xac_minh(
    IN p_ho_so_id BIGINT,
    IN p_quyet_dinh VARCHAR(40),
    IN p_ly_do_tu_choi TEXT,
    IN p_nhan_vien_id BIGINT,
    IN p_now TIMESTAMPTZ DEFAULT now()
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_trang_thai_hien_tai VARCHAR(40);
    v_serial VARCHAR(100);
    v_ten_san_pham VARCHAR(200);
    v_ngay_het_han DATE;
    v_ngay_tiep_nhan DATE;
    v_now TIMESTAMPTZ;
    v_con_bao_hanh BOOLEAN;
    v_trang_thai_moi VARCHAR(40);
    v_ket_qua TEXT;
    v_ly_do TEXT;
    v_ghi_chu TEXT;
    v_ngoai_bao_hanh BOOLEAN := FALSE;
BEGIN
    v_now := COALESCE(p_now, now());

    SELECT h.trang_thai,
           COALESCE(h.serial, h.serial_khach_khai_bao),
           sp.ten_san_pham,
           COALESCE(
               sp.ngay_het_han_bao_hanh,
               (sp.ngay_mua + make_interval(months => sp.thoi_han_bao_hanh_thang))::date
           ),
           (h.ngay_tiep_nhan AT TIME ZONE 'Asia/Ho_Chi_Minh')::date
    INTO v_trang_thai_hien_tai, v_serial, v_ten_san_pham, v_ngay_het_han, v_ngay_tiep_nhan
    FROM public.ho_so h
    LEFT JOIN public.san_pham sp ON sp.serial = COALESCE(h.serial, h.serial_khach_khai_bao)
    WHERE h.id = p_ho_so_id
    FOR UPDATE OF h;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy hồ sơ id=%', p_ho_so_id;
    END IF;
    IF v_trang_thai_hien_tai <> 'DANG_XAC_MINH' THEN
        RAISE EXCEPTION 'Chỉ xác minh được hồ sơ đang ở trạng thái DANG_XAC_MINH';
    END IF;

    v_con_bao_hanh := public.fn_con_bao_hanh(v_serial, v_ngay_tiep_nhan);

    IF v_con_bao_hanh IS NULL THEN
        v_trang_thai_moi := 'CHO_KHACH_BO_SUNG';
        v_ly_do := NULL;
        IF v_serial IS NULL THEN
            v_ket_qua := 'Khách chưa cung cấp serial sản phẩm.';
        ELSIF v_ten_san_pham IS NULL THEN
            v_ket_qua := FORMAT('Không tìm thấy sản phẩm có serial %s.', v_serial);
        ELSE
            v_ket_qua := 'Thiếu dữ liệu ngày mua hoặc thời hạn bảo hành.';
        END IF;

    ELSIF v_con_bao_hanh = FALSE THEN
        IF p_quyet_dinh = 'SUA_CHUA_CO_PHI' THEN
            v_trang_thai_moi := 'CHO_PHAN_CONG';
            v_ngoai_bao_hanh := TRUE;
            v_ly_do := NULL;
            v_ket_qua := FORMAT(
                'Sản phẩm hết hạn bảo hành ngày %s. Khách đã đồng ý sửa chữa ngoài bảo hành có tính phí.',
                TO_CHAR(v_ngay_het_han, 'DD/MM/YYYY')
            );
        ELSIF p_quyet_dinh = 'TU_CHOI' THEN
            v_trang_thai_moi := 'TU_CHOI';
            v_ly_do := COALESCE(
                NULLIF(BTRIM(p_ly_do_tu_choi), ''),
                'Khách không đồng ý sửa chữa ngoài bảo hành có tính phí.'
            );
            v_ket_qua := FORMAT(
                'Sản phẩm đã hết hạn bảo hành ngày %s; khách không đồng ý sửa chữa có tính phí.',
                TO_CHAR(v_ngay_het_han, 'DD/MM/YYYY')
            );
        ELSE
            RAISE EXCEPTION 'Cần ghi nhận khách đồng ý sửa có phí hoặc từ chối sửa';
        END IF;

    ELSE
        IF p_quyet_dinh IS NULL OR p_quyet_dinh NOT IN ('DU_DIEU_KIEN', 'TU_CHOI') THEN
            RAISE EXCEPTION 'Sản phẩm còn hạn: quyết định phải là DU_DIEU_KIEN hoặc TU_CHOI';
        END IF;
        v_ket_qua := FORMAT('Sản phẩm còn bảo hành đến ngày %s.', TO_CHAR(v_ngay_het_han, 'DD/MM/YYYY'));
        IF p_quyet_dinh = 'DU_DIEU_KIEN' THEN
            v_trang_thai_moi := 'CHO_PHAN_CONG';
            v_ly_do := NULL;
        ELSE
            v_trang_thai_moi := 'TU_CHOI';
            v_ly_do := NULLIF(BTRIM(p_ly_do_tu_choi), '');
            IF v_ly_do IS NULL THEN
                RAISE EXCEPTION 'Từ chối hồ sơ cần có lý do';
            END IF;
        END IF;
    END IF;

    UPDATE public.ho_so
    SET ket_qua_xac_minh = v_ket_qua,
        ly_do_tu_choi = v_ly_do,
        ngoai_bao_hanh = v_ngoai_bao_hanh
    WHERE id = p_ho_so_id;

    v_ghi_chu := v_ket_qua;
    IF v_ly_do IS NOT NULL THEN
        v_ghi_chu := v_ghi_chu || ' Lý do: ' || v_ly_do;
    END IF;

    CALL public.sp_chuyen_trang_thai(
        p_ho_so_id, v_trang_thai_moi, 'NHAN_VIEN', p_nhan_vien_id, v_ghi_chu, v_now
    );
END;
$$;

ALTER PROCEDURE public.sp_xac_minh(BIGINT, CHARACTER VARYING, TEXT, BIGINT, TIMESTAMPTZ)
    OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_xac_minh(BIGINT, CHARACTER VARYING, TEXT, BIGINT, TIMESTAMPTZ)
    FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_xac_minh(BIGINT, CHARACTER VARYING, TEXT, BIGINT, TIMESTAMPTZ)
    TO hau_mai_app;

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
    td.tao_luc AS cap_nhat_tien_do_luc,
    hs.ngoai_bao_hanh
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
