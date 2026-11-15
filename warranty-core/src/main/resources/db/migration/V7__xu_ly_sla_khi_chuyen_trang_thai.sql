-- Apply SLA effects caused by a case status transition.
CREATE FUNCTION fn_ho_so_cap_nhat_sla(
    p_ho_so_id BIGINT,
    p_trang_thai_tu VARCHAR(40),
    p_trang_thai_sang VARCHAR(40),
    p_now TIMESTAMPTZ
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_sla RECORD;
    v_phut_tam_dung BIGINT;
    v_trang_thai_cuoi VARCHAR(20);
BEGIN
    -- Finish the intake SLA when verification begins.
    IF p_trang_thai_sang = 'DANG_XAC_MINH' THEN
        UPDATE sla s
        SET thoi_diem_ket_thuc = p_now,
            trang_thai = CASE
                WHEN p_now <= s.thoi_diem_bat_dau
                    + ((s.thoi_han_phut::BIGINT
                        + s.thoi_gian_tam_dung_phut) * INTERVAL '1 minute')
                    THEN 'DAT_SLA'
                ELSE 'KHONG_DAT_SLA'
            END
        WHERE s.ho_so_id = p_ho_so_id
          AND s.loai_sla = 'TIEP_NHAN'
          AND s.trang_thai = 'DANG_DEM';
    END IF;

    -- Pause the processing SLA while waiting for the customer.
    IF p_trang_thai_sang = 'CHO_KHACH_BO_SUNG' THEN
        UPDATE sla
        SET trang_thai = 'TAM_DUNG',
            thoi_diem_tam_dung = p_now
        WHERE ho_so_id = p_ho_so_id
          AND loai_sla = 'XU_LY'
          AND trang_thai = 'DANG_DEM';
    END IF;

    -- Resume the processing SLA when the customer responds.
    IF p_trang_thai_tu = 'CHO_KHACH_BO_SUNG'
       AND p_trang_thai_sang <> 'DA_DONG' THEN
        UPDATE sla s
        SET thoi_gian_tam_dung_phut =
                s.thoi_gian_tam_dung_phut
                + CEIL(
                    GREATEST(
                        EXTRACT(
                            EPOCH FROM (p_now - s.thoi_diem_tam_dung)
                        ),
                        0
                    ) / 60.0
                )::BIGINT,
            trang_thai = 'DANG_DEM',
            thoi_diem_tam_dung = NULL
        WHERE s.ho_so_id = p_ho_so_id
          AND s.loai_sla = 'XU_LY'
          AND s.trang_thai = 'TAM_DUNG'
          AND s.thoi_diem_tam_dung IS NOT NULL;
    END IF;

    -- Stop and finalize every active or overdue SLA when the case closes.
    IF p_trang_thai_sang = 'DA_DONG' THEN
        FOR v_sla IN
            SELECT *
            FROM sla
            WHERE ho_so_id = p_ho_so_id
              AND trang_thai IN ('DANG_DEM', 'TAM_DUNG', 'DA_QUA_HAN')
            FOR UPDATE
        LOOP
            v_phut_tam_dung := v_sla.thoi_gian_tam_dung_phut;

            IF v_sla.trang_thai = 'TAM_DUNG'
               AND v_sla.thoi_diem_tam_dung IS NOT NULL THEN
                v_phut_tam_dung := v_phut_tam_dung
                    + CEIL(
                        GREATEST(
                            EXTRACT(
                                EPOCH FROM (p_now - v_sla.thoi_diem_tam_dung)
                            ),
                            0
                        ) / 60.0
                    )::BIGINT;
            END IF;

            IF v_sla.trang_thai = 'DA_QUA_HAN'
               OR p_now > v_sla.thoi_diem_bat_dau
                    + ((v_sla.thoi_han_phut::BIGINT + v_phut_tam_dung)
                       * INTERVAL '1 minute') THEN
                v_trang_thai_cuoi := 'KHONG_DAT_SLA';
            ELSE
                v_trang_thai_cuoi := 'DAT_SLA';
            END IF;

            UPDATE sla
            SET thoi_diem_ket_thuc = p_now,
                thoi_gian_tam_dung_phut = v_phut_tam_dung,
                thoi_diem_tam_dung = NULL,
                trang_thai = v_trang_thai_cuoi
            WHERE id = v_sla.id;
        END LOOP;
    END IF;
END;
$$;

-- Keep the V6 history trigger and run SLA updates before clearing audit context.
CREATE OR REPLACE FUNCTION fn_ho_so_ghi_lich_su_chuyen_trang_thai()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_loai_tac_nhan VARCHAR(20);
    v_nhan_vien_id BIGINT;
    v_nhan_vien_text TEXT;
    v_ghi_chu TEXT;
    v_now TIMESTAMPTZ;
BEGIN
    IF NEW.trang_thai IS DISTINCT FROM OLD.trang_thai THEN
        v_loai_tac_nhan :=
            NULLIF(current_setting('app.audit_actor_type', TRUE), '');

        IF v_loai_tac_nhan NOT IN ('NHAN_VIEN', 'KHACH_HANG', 'HE_THONG')
            OR v_loai_tac_nhan IS NULL THEN
            v_loai_tac_nhan := 'HE_THONG';
        END IF;

        v_nhan_vien_text :=
            NULLIF(current_setting('app.audit_employee_id', TRUE), '');

        IF v_loai_tac_nhan = 'NHAN_VIEN' AND v_nhan_vien_text IS NOT NULL THEN
            v_nhan_vien_id := v_nhan_vien_text::BIGINT;
        ELSE
            v_nhan_vien_id := NULL;
        END IF;

        v_ghi_chu := NULLIF(
            current_setting('app.audit_note', TRUE),
            ''
        );

        v_now := COALESCE(
            NULLIF(current_setting('app.audit_now', TRUE), '')::TIMESTAMPTZ,
            now()
        );

        INSERT INTO lich_su_xu_ly (
            ho_so_id,
            trang_thai_tu,
            trang_thai_sang,
            loai_tac_nhan,
            nhan_vien_id,
            ghi_chu,
            tao_luc
        )
        VALUES (
            NEW.id,
            OLD.trang_thai,
            NEW.trang_thai,
            v_loai_tac_nhan,
            v_nhan_vien_id,
            v_ghi_chu,
            v_now
        );

        PERFORM fn_ho_so_cap_nhat_sla(
            NEW.id,
            OLD.trang_thai,
            NEW.trang_thai,
            v_now
        );

        PERFORM set_config('app.audit_actor_type', '', TRUE);
        PERFORM set_config('app.audit_employee_id', '', TRUE);
        PERFORM set_config('app.audit_note', '', TRUE);
        PERFORM set_config('app.audit_now', '', TRUE);
    END IF;

    RETURN NEW;
END;
$$;
-- Reconcile intake SLAs for cases that entered verification before V7.
WITH lan_xac_minh_dau AS (
    SELECT
        ho_so_id,
        MIN(tao_luc) AS thoi_diem_xac_minh
    FROM lich_su_xu_ly
    WHERE trang_thai_sang = 'DANG_XAC_MINH'
    GROUP BY ho_so_id
)
UPDATE sla s
SET thoi_diem_ket_thuc = x.thoi_diem_xac_minh,
    trang_thai = CASE
        WHEN x.thoi_diem_xac_minh <= s.thoi_diem_bat_dau
            + ((s.thoi_han_phut::BIGINT
                + s.thoi_gian_tam_dung_phut) * INTERVAL '1 minute')
            THEN 'DAT_SLA'
        ELSE 'KHONG_DAT_SLA'
    END
FROM lan_xac_minh_dau x
WHERE s.ho_so_id = x.ho_so_id
  AND s.loai_sla = 'TIEP_NHAN'
  AND s.trang_thai = 'DANG_DEM';