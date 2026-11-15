-- Trả về TRUE nếu còn hạn, FALSE nếu hết hạn,
-- NULL nếu không tìm thấy sản phẩm hoặc thiếu dữ liệu để tính.
CREATE FUNCTION public.fn_con_bao_hanh(
    p_serial character varying,
    p_ngay date
)
RETURNS boolean
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
    SELECT CASE
        WHEN COALESCE(
            sp.ngay_het_han_bao_hanh,
            (sp.ngay_mua
                + make_interval(months => sp.thoi_han_bao_hanh_thang)
            )::date
        ) IS NULL THEN NULL
        ELSE p_ngay <= COALESCE(
            sp.ngay_het_han_bao_hanh,
            (sp.ngay_mua
                + make_interval(months => sp.thoi_han_bao_hanh_thang)
            )::date
        )
    END
    FROM san_pham sp
    WHERE sp.serial = p_serial;
$$;

ALTER FUNCTION public.fn_con_bao_hanh(character varying, date)
    OWNER TO hau_mai_owner;

REVOKE EXECUTE
    ON FUNCTION public.fn_con_bao_hanh(character varying, date)
    FROM PUBLIC;

GRANT EXECUTE
    ON FUNCTION public.fn_con_bao_hanh(character varying, date)
    TO hau_mai_app;


-- CSKH xác minh sản phẩm và chuyển hồ sơ theo kết quả.
CREATE PROCEDURE public.sp_xac_minh(
    IN p_ho_so_id bigint,
    IN p_quyet_dinh character varying,
    IN p_ly_do_tu_choi text,
    IN p_nhan_vien_id bigint,
    IN p_now timestamp with time zone DEFAULT now()
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_trang_thai_hien_tai character varying(40);
    v_serial character varying(100);
    v_ten_san_pham character varying(200);
    v_ngay_het_han date;
    v_ngay_tiep_nhan date;
    v_now timestamp with time zone;
    v_con_bao_hanh boolean;
    v_trang_thai_moi character varying(40);
    v_ket_qua text;
    v_ly_do text;
    v_ghi_chu text;
BEGIN
    v_now := COALESCE(p_now, now());

    SELECT
        h.trang_thai,
        COALESCE(h.serial, h.serial_khach_khai_bao),
        sp.ten_san_pham,
        COALESCE(
            sp.ngay_het_han_bao_hanh,
            (sp.ngay_mua
                + make_interval(months => sp.thoi_han_bao_hanh_thang)
            )::date
        ),
        (h.ngay_tiep_nhan AT TIME ZONE 'Asia/Ho_Chi_Minh')::date
    INTO
        v_trang_thai_hien_tai,
        v_serial,
        v_ten_san_pham,
        v_ngay_het_han,
        v_ngay_tiep_nhan
    FROM ho_so h
    LEFT JOIN san_pham sp
        ON sp.serial = COALESCE(h.serial, h.serial_khach_khai_bao)
    WHERE h.id = p_ho_so_id
    FOR UPDATE OF h;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy hồ sơ id=%', p_ho_so_id;
    END IF;

    IF v_trang_thai_hien_tai <> 'DANG_XAC_MINH' THEN
        RAISE EXCEPTION
            'Chỉ xác minh được hồ sơ đang ở trạng thái DANG_XAC_MINH';
    END IF;

    v_con_bao_hanh := public.fn_con_bao_hanh(v_serial, v_ngay_tiep_nhan);

    IF v_con_bao_hanh IS NULL THEN
        v_trang_thai_moi := 'CHO_KHACH_BO_SUNG';
        v_ly_do := NULL;

        IF v_serial IS NULL THEN
            v_ket_qua := 'Khách chưa cung cấp serial sản phẩm.';
        ELSIF v_ten_san_pham IS NULL THEN
            v_ket_qua := FORMAT(
                'Không tìm thấy sản phẩm có serial %s.',
                v_serial
            );
        ELSE
            v_ket_qua := 'Thiếu dữ liệu ngày mua hoặc thời hạn bảo hành.';
        END IF;

    ELSIF v_con_bao_hanh = FALSE THEN
        v_trang_thai_moi := 'TU_CHOI';
        v_ket_qua := FORMAT(
            'Sản phẩm đã hết hạn bảo hành ngày %s.',
            TO_CHAR(v_ngay_het_han, 'DD/MM/YYYY')
        );
        v_ly_do := COALESCE(
            NULLIF(BTRIM(p_ly_do_tu_choi), ''),
            FORMAT(
                'Sản phẩm đã hết hạn bảo hành ngày %s.',
                TO_CHAR(v_ngay_het_han, 'DD/MM/YYYY')
            )
        );

    ELSE
        IF p_quyet_dinh IS NULL
           OR p_quyet_dinh NOT IN ('DU_DIEU_KIEN', 'TU_CHOI') THEN
            RAISE EXCEPTION
                'Sản phẩm còn hạn: quyết định phải là DU_DIEU_KIEN hoặc TU_CHOI';
        END IF;

        v_ket_qua := FORMAT(
            'Sản phẩm còn bảo hành đến ngày %s.',
            TO_CHAR(v_ngay_het_han, 'DD/MM/YYYY')
        );

        IF p_quyet_dinh = 'DU_DIEU_KIEN' THEN
            v_trang_thai_moi := 'CHO_PHAN_CONG';
            v_ly_do := NULL;
        ELSE
            v_trang_thai_moi := 'TU_CHOI';
            v_ly_do := NULLIF(BTRIM(p_ly_do_tu_choi), '');

            IF v_ly_do IS NULL THEN
                RAISE EXCEPTION
                    'Từ chối hồ sơ cần có lý do';
            END IF;
        END IF;
    END IF;

    UPDATE ho_so
    SET ket_qua_xac_minh = v_ket_qua,
        ly_do_tu_choi = v_ly_do
    WHERE id = p_ho_so_id;

    v_ghi_chu := v_ket_qua;

    IF v_ly_do IS NOT NULL THEN
        v_ghi_chu := v_ghi_chu || ' Lý do: ' || v_ly_do;
    END IF;

    CALL public.sp_chuyen_trang_thai(
        p_ho_so_id,
        v_trang_thai_moi,
        'NHAN_VIEN',
        p_nhan_vien_id,
        v_ghi_chu,
        v_now
    );
END;
$$;

ALTER PROCEDURE public.sp_xac_minh(
    bigint, character varying, text, bigint, timestamp with time zone
) OWNER TO hau_mai_owner;

REVOKE EXECUTE
    ON PROCEDURE public.sp_xac_minh(
        bigint, character varying, text, bigint, timestamp with time zone
    )
    FROM PUBLIC;

GRANT EXECUTE
    ON PROCEDURE public.sp_xac_minh(
        bigint, character varying, text, bigint, timestamp with time zone
    )
    TO hau_mai_app;