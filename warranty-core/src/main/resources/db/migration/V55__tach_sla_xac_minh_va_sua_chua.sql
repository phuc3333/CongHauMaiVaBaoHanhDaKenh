-- The processing SLA now waits until the dispatcher assigns a technician.
-- Add an explicit not-started state while retaining the same two SLA types.
ALTER TABLE public.sla DROP CONSTRAINT IF EXISTS sla_trang_thai_check;
ALTER TABLE public.sla ADD CONSTRAINT ck_sla_trang_thai CHECK (trang_thai IN (
    'CHUA_BAT_DAU', 'DANG_DEM', 'TAM_DUNG', 'DA_QUA_HAN', 'DAT_SLA', 'KHONG_DAT_SLA'
));

-- Recalculate existing SLA rows to match the new definitions.
WITH pause_intervals AS (
    SELECT start_event.ho_so_id, start_event.tao_luc AS paused_at,
           (SELECT MIN(end_event.tao_luc)
            FROM public.lich_su_xu_ly end_event
            WHERE end_event.ho_so_id = start_event.ho_so_id
              AND end_event.trang_thai_tu = 'CHO_KHACH_BO_SUNG'
              AND end_event.tao_luc > start_event.tao_luc) AS resumed_at
    FROM public.lich_su_xu_ly start_event
    WHERE start_event.trang_thai_sang = 'CHO_KHACH_BO_SUNG'
), paused_totals AS (
    SELECT ho_so_id,
           COALESCE(SUM(CEIL(GREATEST(EXTRACT(EPOCH FROM (resumed_at - paused_at)), 0) / 60.0))
               FILTER (WHERE resumed_at IS NOT NULL), 0)::BIGINT AS paused_minutes
    FROM pause_intervals GROUP BY ho_so_id
), final_decisions AS (
    SELECT ho_so_id, MIN(tao_luc) AS decided_at
    FROM public.lich_su_xu_ly
    WHERE trang_thai_tu = 'DANG_XAC_MINH'
      AND trang_thai_sang IN ('CHO_PHAN_CONG', 'TU_CHOI')
    GROUP BY ho_so_id
), intake_facts AS (
    SELECT h.id AS ho_so_id, h.trang_thai AS case_status, h.ngay_tiep_nhan,
           h.bat_dau_cho_khach_luc, h.ngay_dong,
           COALESCE(p.paused_minutes, 0) AS paused_minutes,
           d.decided_at,
           COALESCE(d.decided_at, h.ngay_dong) AS ended_at
    FROM public.ho_so h
    LEFT JOIN paused_totals p ON p.ho_so_id = h.id
    LEFT JOIN final_decisions d ON d.ho_so_id = h.id
)
UPDATE public.sla s
SET thoi_diem_bat_dau = f.ngay_tiep_nhan,
    thoi_diem_ket_thuc = CASE
        WHEN f.case_status IN ('MOI', 'DANG_XAC_MINH', 'CHO_KHACH_BO_SUNG') THEN NULL
        ELSE COALESCE(f.ended_at, s.thoi_diem_ket_thuc)
    END,
    thoi_gian_tam_dung_phut = f.paused_minutes,
    thoi_diem_tam_dung = CASE WHEN f.case_status = 'CHO_KHACH_BO_SUNG' THEN f.bat_dau_cho_khach_luc ELSE NULL END,
    trang_thai = CASE
        WHEN f.case_status IN ('MOI', 'DANG_XAC_MINH') THEN 'DANG_DEM'
        WHEN f.case_status = 'CHO_KHACH_BO_SUNG' THEN 'TAM_DUNG'
        WHEN f.ended_at IS NOT NULL AND f.ended_at <= f.ngay_tiep_nhan
            + ((s.thoi_han_phut::BIGINT + f.paused_minutes) * INTERVAL '1 minute') THEN 'DAT_SLA'
        WHEN f.ended_at IS NOT NULL THEN 'KHONG_DAT_SLA'
        ELSE s.trang_thai
    END
FROM intake_facts f
WHERE s.ho_so_id = f.ho_so_id AND s.loai_sla = 'TIEP_NHAN';

WITH first_assignment AS (
    SELECT ho_so_id, MIN(ngay_phan_cong) AS started_at
    FROM public.phan_cong GROUP BY ho_so_id
), repair_completion AS (
    SELECT pc.ho_so_id, MIN(td.tao_luc) AS completed_at
    FROM public.phan_cong pc
    JOIN public.tien_do_sua_chua td ON td.phan_cong_id = pc.id
    WHERE td.trang_thai = 'DA_SUA_XONG'
    GROUP BY pc.ho_so_id
)
UPDATE public.sla s
SET thoi_diem_bat_dau = COALESCE(a.started_at, h.ngay_tiep_nhan),
    thoi_diem_ket_thuc = c.completed_at,
    thoi_gian_tam_dung_phut = 0,
    thoi_diem_tam_dung = NULL,
    trang_thai = CASE
        WHEN a.started_at IS NULL THEN 'CHUA_BAT_DAU'
        WHEN c.completed_at IS NULL THEN 'DANG_DEM'
        WHEN c.completed_at <= a.started_at + (s.thoi_han_phut::BIGINT * INTERVAL '1 minute') THEN 'DAT_SLA'
        ELSE 'KHONG_DAT_SLA'
    END
FROM public.ho_so h
LEFT JOIN first_assignment a ON a.ho_so_id = h.id
LEFT JOIN repair_completion c ON c.ho_so_id = h.id
WHERE s.ho_so_id = h.id AND s.loai_sla = 'XU_LY';

-- The SLA view displays an unstarted repair clock without inventing a deadline.
CREATE OR REPLACE VIEW public.v_sla_ho_so AS
WITH han AS (
    SELECT s.id AS sla_id, s.ho_so_id, s.loai_sla, s.thoi_han_phut, s.trang_thai,
           CASE WHEN s.trang_thai = 'CHUA_BAT_DAU' THEN NULL ELSE
             s.thoi_diem_bat_dau + (s.thoi_han_phut::BIGINT + s.thoi_gian_tam_dung_phut
               + CASE WHEN s.trang_thai = 'TAM_DUNG' AND s.thoi_diem_tam_dung IS NOT NULL
                      THEN GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - s.thoi_diem_tam_dung)) / 60)::BIGINT)
                      ELSE 0 END) * INTERVAL '1 minute'
           END AS thoi_diem_den_han
    FROM public.sla s
), con_lai AS (
    SELECT h.*, CEIL(EXTRACT(EPOCH FROM (h.thoi_diem_den_han - now())) / 60)::BIGINT AS phut_con_lai,
           COALESCE((SELECT gia_tri::NUMERIC FROM public.cau_hinh WHERE ma_cau_hinh='canh_bao_phan_tram'),20) AS nguong_canh_bao
    FROM han h
)
SELECT sla_id, ho_so_id, loai_sla, trang_thai, phut_con_lai,
       TO_CHAR(thoi_diem_den_han AT TIME ZONE 'Asia/Ho_Chi_Minh','DD/MM/YYYY HH24:MI') AS den_han_luc,
       CASE WHEN trang_thai='CHUA_BAT_DAU' THEN 'CHUA_BAT_DAU'
            WHEN trang_thai='TAM_DUNG' THEN 'TAM_DUNG'
            WHEN trang_thai='DAT_SLA' THEN 'DAT_SLA'
            WHEN trang_thai='KHONG_DAT_SLA' THEN 'KHONG_DAT_SLA'
            WHEN trang_thai='DA_QUA_HAN' OR phut_con_lai <= 0 THEN 'QUA_HAN'
            WHEN phut_con_lai <= CEIL(thoi_han_phut * nguong_canh_bao / 100) THEN 'SAP_DEN_HAN'
            ELSE 'DANG_CON_HAN' END AS nhan_trang_thai,
       CASE WHEN trang_thai='CHUA_BAT_DAU' THEN 'Chưa bắt đầu'
            WHEN trang_thai='TAM_DUNG' THEN 'Đang tạm dừng'
            WHEN trang_thai='DAT_SLA' THEN 'Hoàn tất đúng hạn'
            WHEN trang_thai='KHONG_DAT_SLA' THEN 'Hoàn tất trễ hạn'
            WHEN trang_thai='DA_QUA_HAN' OR phut_con_lai <= 0
                THEN 'Quá hạn ' || CEIL(ABS(phut_con_lai) / 60.0)::INTEGER || ' giờ'
            WHEN phut_con_lai >= 1440 THEN 'Còn ' || FLOOR(phut_con_lai / 1440.0)::INTEGER || ' ngày'
            WHEN phut_con_lai >= 60 THEN 'Còn ' || FLOOR(phut_con_lai / 60.0)::INTEGER || ' giờ'
            ELSE 'Còn ' || phut_con_lai::INTEGER || ' phút' END AS thoi_gian_hien_thi
FROM con_lai;
ALTER VIEW public.v_sla_ho_so OWNER TO hau_mai_owner;
REVOKE ALL ON TABLE public.v_sla_ho_so FROM PUBLIC;
GRANT SELECT ON TABLE public.v_sla_ho_so TO hau_mai_app;

-- Extend the persistence routine with a start timestamp so the Service can start XU_LY at assignment.
DROP PROCEDURE public.sp_luu_sla_tu_service(BIGINT, VARCHAR, VARCHAR, TIMESTAMPTZ, BIGINT, TIMESTAMPTZ,
    TIMESTAMPTZ, TEXT, BIGINT, VARCHAR, VARCHAR, TEXT, VARCHAR, TIMESTAMPTZ);
CREATE PROCEDURE public.sp_luu_sla_tu_service(
    IN p_sla_id BIGINT, IN p_expected_status VARCHAR, IN p_status VARCHAR,
    IN p_started_at TIMESTAMPTZ, IN p_end_at TIMESTAMPTZ,
    IN p_paused_minutes BIGINT, IN p_paused_at TIMESTAMPTZ,
    IN p_detected_at TIMESTAMPTZ, IN p_violation_note TEXT,
    IN p_receiver_id BIGINT, IN p_notification_key VARCHAR,
    IN p_title VARCHAR, IN p_body TEXT, IN p_notification_type VARCHAR,
    IN p_notification_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp
AS $$
DECLARE v_updated INTEGER;
BEGIN
    UPDATE public.sla SET trang_thai=p_status, thoi_diem_bat_dau=p_started_at,
        thoi_diem_ket_thuc=p_end_at, thoi_gian_tam_dung_phut=p_paused_minutes,
        thoi_diem_tam_dung=p_paused_at
    WHERE id=p_sla_id AND trang_thai=p_expected_status;
    GET DIAGNOSTICS v_updated = ROW_COUNT;
    IF v_updated = 0 THEN RETURN; END IF;
    IF p_detected_at IS NOT NULL THEN
        INSERT INTO public.vi_pham_sla(sla_id, thoi_diem_phat_hien, muc_do, noi_dung)
        VALUES(p_sla_id, p_detected_at, 'QUA_HAN', p_violation_note)
        ON CONFLICT(sla_id) DO NOTHING;
    END IF;
    IF p_receiver_id IS NOT NULL AND p_notification_key IS NOT NULL THEN
        INSERT INTO public.thong_bao(ho_so_id, nhan_vien_nhan_id, khoa_chong_trung,
            tieu_de, noi_dung, loai_thong_bao, tao_luc)
        VALUES((SELECT ho_so_id FROM public.sla WHERE id=p_sla_id), p_receiver_id,
            p_notification_key, p_title, p_body, p_notification_type, COALESCE(p_notification_at, now()))
        ON CONFLICT(khoa_chong_trung) DO NOTHING;
    END IF;
END;
$$;
ALTER PROCEDURE public.sp_luu_sla_tu_service(BIGINT, VARCHAR, VARCHAR, TIMESTAMPTZ, TIMESTAMPTZ,
    BIGINT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, BIGINT, VARCHAR, VARCHAR, TEXT, VARCHAR, TIMESTAMPTZ) OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_luu_sla_tu_service(BIGINT, VARCHAR, VARCHAR, TIMESTAMPTZ, TIMESTAMPTZ,
    BIGINT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, BIGINT, VARCHAR, VARCHAR, TEXT, VARCHAR, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_luu_sla_tu_service(BIGINT, VARCHAR, VARCHAR, TIMESTAMPTZ, TIMESTAMPTZ,
    BIGINT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, BIGINT, VARCHAR, VARCHAR, TEXT, VARCHAR, TIMESTAMPTZ) TO hau_mai_app;

CREATE PROCEDURE public.sp_bat_dau_sla_sua_chua(
    IN p_sla_id BIGINT, IN p_expected_status VARCHAR, IN p_started_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp
AS $$
BEGIN
    UPDATE public.sla SET trang_thai='DANG_DEM', thoi_diem_bat_dau=p_started_at,
        thoi_diem_ket_thuc=NULL, thoi_gian_tam_dung_phut=0, thoi_diem_tam_dung=NULL
    WHERE id=p_sla_id AND loai_sla='XU_LY' AND trang_thai=p_expected_status;
    IF NOT FOUND THEN RAISE EXCEPTION 'Không thể bắt đầu SLA sửa chữa'; END IF;
END;
$$;
ALTER PROCEDURE public.sp_bat_dau_sla_sua_chua(BIGINT, VARCHAR, TIMESTAMPTZ) OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_bat_dau_sla_sua_chua(BIGINT, VARCHAR, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_bat_dau_sla_sua_chua(BIGINT, VARCHAR, TIMESTAMPTZ) TO hau_mai_app;
