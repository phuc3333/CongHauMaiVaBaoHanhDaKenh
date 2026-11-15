-- Scan running SLAs, record each overdue SLA once,
-- and create deduplicated notifications for the manager.
CREATE PROCEDURE sp_quet_sla(
    IN p_now TIMESTAMPTZ DEFAULT now()
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_now TIMESTAMPTZ;
    v_nguong_canh_bao NUMERIC;
    v_nguoi_quan_ly_id BIGINT;
    v_sla RECORD;
BEGIN
    v_now := COALESCE(p_now, now());

    SELECT COALESCE(
        (
            SELECT gia_tri::NUMERIC
            FROM cau_hinh
            WHERE ma_cau_hinh = 'canh_bao_phan_tram'
        ),
        20
    )
    INTO v_nguong_canh_bao;

    IF v_nguong_canh_bao < 0 OR v_nguong_canh_bao > 100 THEN
        RAISE EXCEPTION 'Ngưỡng cảnh báo SLA phải nằm trong khoảng 0 đến 100';
    END IF;

    SELECT nv.id
    INTO v_nguoi_quan_ly_id
    FROM nhan_vien nv
    JOIN tai_khoan tk ON tk.id = nv.tai_khoan_id
    WHERE tk.vai_tro = 'DIEU_PHOI_VIEN'
      AND tk.dang_hoat_dong = TRUE
    ORDER BY nv.id
    LIMIT 1;

    FOR v_sla IN
        SELECT
            s.id,
            s.ho_so_id,
            s.loai_sla,
            s.thoi_han_phut,
            s.thoi_diem_bat_dau,
            s.thoi_gian_tam_dung_phut,
            h.ma_ho_so,
            s.thoi_diem_bat_dau
                + ((s.thoi_han_phut::BIGINT
                    + s.thoi_gian_tam_dung_phut) * INTERVAL '1 minute')
                AS han_sla
        FROM sla s
        JOIN ho_so h ON h.id = s.ho_so_id
        WHERE s.trang_thai = 'DANG_DEM'
        ORDER BY s.id
        FOR UPDATE OF s
    LOOP
        IF v_now > v_sla.han_sla THEN
            UPDATE sla
            SET trang_thai = 'DA_QUA_HAN',
                thoi_diem_ket_thuc = v_sla.han_sla
            WHERE id = v_sla.id
              AND trang_thai = 'DANG_DEM';

            INSERT INTO vi_pham_sla (
                sla_id,
                thoi_diem_phat_hien,
                muc_do,
                noi_dung
            )
            VALUES (
                v_sla.id,
                v_now,
                'QUA_HAN',
                FORMAT(
                    'SLA %s của hồ sơ %s đã quá hạn.',
                    v_sla.loai_sla,
                    v_sla.ma_ho_so
                )
            )
            ON CONFLICT (sla_id) DO NOTHING;

            IF v_nguoi_quan_ly_id IS NOT NULL THEN
                INSERT INTO thong_bao (
                    ho_so_id,
                    nhan_vien_nhan_id,
                    khoa_chong_trung,
                    tieu_de,
                    noi_dung,
                    loai_thong_bao
                )
                VALUES (
                    v_sla.ho_so_id,
                    v_nguoi_quan_ly_id,
                    'sla_qua_han:' || v_sla.id,
                    'Hồ sơ quá hạn SLA',
                    FORMAT(
                        'SLA %s của hồ sơ %s đã quá hạn.',
                        v_sla.loai_sla,
                        v_sla.ma_ho_so
                    ),
                    'SLA_QUA_HAN'
                )
                ON CONFLICT (khoa_chong_trung) DO NOTHING;
            END IF;

        ELSIF v_nguong_canh_bao > 0
          AND v_nguoi_quan_ly_id IS NOT NULL
          AND v_now >= v_sla.han_sla
                - (
                    INTERVAL '1 minute'
                    * (
                        v_sla.thoi_han_phut::DOUBLE PRECISION
                        * v_nguong_canh_bao::DOUBLE PRECISION
                        / 100.0
                    )
                ) THEN
            INSERT INTO thong_bao (
                ho_so_id,
                nhan_vien_nhan_id,
                khoa_chong_trung,
                tieu_de,
                noi_dung,
                loai_thong_bao
            )
            VALUES (
                v_sla.ho_so_id,
                v_nguoi_quan_ly_id,
                'sla_sap_qua_han:' || v_sla.id,
                'SLA sắp quá hạn',
                FORMAT(
                    'SLA %s của hồ sơ %s sắp quá hạn.',
                    v_sla.loai_sla,
                    v_sla.ma_ho_so
                ),
                'SLA_SAP_QUA_HAN'
            )
            ON CONFLICT (khoa_chong_trung) DO NOTHING;
        END IF;
    END LOOP;
END;
$$;