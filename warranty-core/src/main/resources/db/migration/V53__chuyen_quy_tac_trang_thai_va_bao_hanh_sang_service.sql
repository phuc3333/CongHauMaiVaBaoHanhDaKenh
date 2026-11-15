-- Move warranty and case-status decisions to the Java service layer.
-- The database retains atomic writes, audit history, and integrity constraints.

DROP TRIGGER IF EXISTS trg_ho_so_kiem_tra_chuyen_trang_thai ON public.ho_so;
DROP FUNCTION IF EXISTS public.fn_ho_so_kiem_tra_chuyen_trang_thai();
DROP FUNCTION IF EXISTS public.fn_cho_phep_chuyen(VARCHAR, VARCHAR);
DROP TRIGGER IF EXISTS trg_ho_so_bat_dau_xac_minh ON public.ho_so;
DROP FUNCTION IF EXISTS public.fn_ho_so_bat_dau_xac_minh();

CREATE OR REPLACE PROCEDURE public.sp_chuyen_trang_thai(
    IN p_ho_so_id BIGINT,
    IN p_trang_thai_moi VARCHAR,
    IN p_loai_tac_nhan VARCHAR,
    IN p_nhan_vien_id BIGINT,
    IN p_ghi_chu TEXT,
    IN p_now TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_now TIMESTAMPTZ := COALESCE(p_now, now());
BEGIN
    IF p_loai_tac_nhan NOT IN ('NHAN_VIEN', 'KHACH_HANG', 'HE_THONG') OR p_loai_tac_nhan IS NULL THEN
        RAISE EXCEPTION 'Loại tác nhân không hợp lệ';
    END IF;
    IF p_loai_tac_nhan = 'NHAN_VIEN' THEN
        IF p_nhan_vien_id IS NULL OR NOT EXISTS (SELECT 1 FROM public.nhan_vien WHERE id = p_nhan_vien_id) THEN
            RAISE EXCEPTION 'Tác nhân nhân viên không hợp lệ';
        END IF;
    ELSIF p_nhan_vien_id IS NOT NULL THEN
        RAISE EXCEPTION 'Chỉ tác nhân NHAN_VIEN mới được truyền nhan_vien_id';
    END IF;

    PERFORM 1 FROM public.ho_so WHERE id = p_ho_so_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy hồ sơ id=%', p_ho_so_id; END IF;

    PERFORM set_config('app.audit_actor_type', p_loai_tac_nhan, TRUE);
    PERFORM set_config('app.audit_employee_id', COALESCE(p_nhan_vien_id::TEXT, ''), TRUE);
    PERFORM set_config('app.audit_note', COALESCE(p_ghi_chu, ''), TRUE);
    PERFORM set_config('app.audit_now', v_now::TEXT, TRUE);

    UPDATE public.ho_so
    SET trang_thai = p_trang_thai_moi,
        bat_dau_cho_khach_luc = CASE
            WHEN p_trang_thai_moi = 'CHO_KHACH_BO_SUNG' THEN v_now
            ELSE NULL
        END,
        ngay_dong = CASE WHEN p_trang_thai_moi = 'DA_DONG' THEN v_now ELSE ngay_dong END,
        version = version + CASE WHEN trang_thai IS DISTINCT FROM p_trang_thai_moi THEN 1 ELSE 0 END
    WHERE id = p_ho_so_id;
END;
$$;

ALTER PROCEDURE public.sp_chuyen_trang_thai(BIGINT, VARCHAR, VARCHAR, BIGINT, TEXT, TIMESTAMPTZ) OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_chuyen_trang_thai(BIGINT, VARCHAR, VARCHAR, BIGINT, TEXT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_chuyen_trang_thai(BIGINT, VARCHAR, VARCHAR, BIGINT, TEXT, TIMESTAMPTZ) TO hau_mai_app;

-- The history trigger only writes audit data; SLA decisions now run in SlaService.
CREATE OR REPLACE FUNCTION public.fn_ho_so_ghi_lich_su_chuyen_trang_thai()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_actor VARCHAR(20);
    v_employee_id BIGINT;
    v_employee_text TEXT;
    v_now TIMESTAMPTZ;
BEGIN
    IF NEW.trang_thai IS DISTINCT FROM OLD.trang_thai THEN
        v_actor := NULLIF(current_setting('app.audit_actor_type', TRUE), '');
        IF v_actor NOT IN ('NHAN_VIEN', 'KHACH_HANG', 'HE_THONG') OR v_actor IS NULL THEN v_actor := 'HE_THONG'; END IF;
        v_employee_text := NULLIF(current_setting('app.audit_employee_id', TRUE), '');
        IF v_actor = 'NHAN_VIEN' AND v_employee_text IS NOT NULL THEN v_employee_id := v_employee_text::BIGINT; END IF;
        v_now := COALESCE(NULLIF(current_setting('app.audit_now', TRUE), '')::TIMESTAMPTZ, now());
        INSERT INTO public.lich_su_xu_ly(ho_so_id, trang_thai_tu, trang_thai_sang, loai_tac_nhan, nhan_vien_id, ghi_chu, tao_luc)
        VALUES (NEW.id, OLD.trang_thai, NEW.trang_thai, v_actor, v_employee_id,
            NULLIF(current_setting('app.audit_note', TRUE), ''), v_now);
        PERFORM set_config('app.audit_actor_type', '', TRUE);
        PERFORM set_config('app.audit_employee_id', '', TRUE);
        PERFORM set_config('app.audit_note', '', TRUE);
        PERFORM set_config('app.audit_now', '', TRUE);
    END IF;
    RETURN NEW;
END;
$$;

-- Result and progress procedures persist facts; Java services choose the next state.
DROP PROCEDURE public.sp_luu_ket_qua_xac_minh(BIGINT, TEXT, TEXT, BOOLEAN, VARCHAR, BIGINT, TEXT, TIMESTAMPTZ);
CREATE PROCEDURE public.sp_luu_ket_qua_xac_minh(
    IN p_ho_so_id BIGINT, IN p_ket_qua TEXT, IN p_ly_do_tu_choi TEXT,
    IN p_ngoai_bao_hanh BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    UPDATE public.ho_so
    SET ket_qua_xac_minh = p_ket_qua, ly_do_tu_choi = p_ly_do_tu_choi,
        ngoai_bao_hanh = p_ngoai_bao_hanh
    WHERE id = p_ho_so_id AND trang_thai = 'DANG_XAC_MINH';
    IF NOT FOUND THEN RAISE EXCEPTION 'Hồ sơ không còn ở trạng thái đang xác minh'; END IF;
END;
$$;
ALTER PROCEDURE public.sp_luu_ket_qua_xac_minh(BIGINT, TEXT, TEXT, BOOLEAN) OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_luu_ket_qua_xac_minh(BIGINT, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_luu_ket_qua_xac_minh(BIGINT, TEXT, TEXT, BOOLEAN) TO hau_mai_app;

DROP PROCEDURE public.sp_luu_ktv_tiep_nhan(BIGINT, BIGINT, BIGINT, TIMESTAMPTZ);
DROP PROCEDURE public.sp_luu_ktv_hoan_tat(BIGINT, BIGINT, BIGINT, TEXT, TIMESTAMPTZ);

CREATE PROCEDURE public.sp_luu_ktv_tiep_nhan(
    IN p_phan_cong_id BIGINT, IN p_now TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO public.tien_do_sua_chua(phan_cong_id, trang_thai, ghi_chu, tao_luc)
    VALUES(p_phan_cong_id, 'DANG_SUA_CHUA', 'Kỹ thuật viên đã tiếp nhận hồ sơ', p_now);
END;
$$;

CREATE PROCEDURE public.sp_luu_ktv_hoan_tat(
    IN p_ho_so_id BIGINT, IN p_phan_cong_id BIGINT, IN p_ket_luan TEXT, IN p_now TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
    INSERT INTO public.tien_do_sua_chua(phan_cong_id, trang_thai, ghi_chu, tao_luc)
    VALUES(p_phan_cong_id, 'DA_SUA_XONG', p_ket_luan, p_now);
    UPDATE public.ho_so SET ket_luan_xu_ly = p_ket_luan WHERE id = p_ho_so_id;
END;
$$;
ALTER PROCEDURE public.sp_luu_ktv_tiep_nhan(BIGINT, TIMESTAMPTZ) OWNER TO hau_mai_owner;
ALTER PROCEDURE public.sp_luu_ktv_hoan_tat(BIGINT, BIGINT, TEXT, TIMESTAMPTZ) OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_luu_ktv_tiep_nhan(BIGINT, TIMESTAMPTZ) FROM PUBLIC;
REVOKE EXECUTE ON PROCEDURE public.sp_luu_ktv_hoan_tat(BIGINT, BIGINT, TEXT, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_luu_ktv_tiep_nhan(BIGINT, TIMESTAMPTZ) TO hau_mai_app;
GRANT EXECUTE ON PROCEDURE public.sp_luu_ktv_hoan_tat(BIGINT, BIGINT, TEXT, TIMESTAMPTZ) TO hau_mai_app;

-- Remove the old database-driven SLA worker. A Java scheduled service now evaluates it.
DO $$
DECLARE v_job_id BIGINT;
BEGIN
    FOR v_job_id IN SELECT jobid FROM cron.job WHERE jobname='quet-sla' LOOP
        PERFORM cron.unschedule(v_job_id);
    END LOOP;
END $$;
DROP PROCEDURE IF EXISTS public.sp_quet_sla(TIMESTAMPTZ);
DROP PROCEDURE IF EXISTS public.sp_quet_sla_impl(TIMESTAMPTZ);
DROP PROCEDURE IF EXISTS public.sp_chuyen_trang_thai_impl(BIGINT, VARCHAR, VARCHAR, BIGINT, TEXT, TIMESTAMPTZ);
DROP FUNCTION IF EXISTS public.fn_ho_so_cap_nhat_sla(BIGINT, VARCHAR, VARCHAR, TIMESTAMPTZ);
DROP FUNCTION IF EXISTS public.fn_con_bao_hanh(VARCHAR, DATE);

-- Java reads SLA inputs and sends computed outcomes to this persistence-only routine.
CREATE OR REPLACE VIEW public.v_sla_service AS
SELECT s.id AS sla_id, s.ho_so_id, h.ma_ho_so, s.loai_sla, s.thoi_han_phut,
       s.thoi_diem_bat_dau, s.thoi_diem_ket_thuc, s.thoi_gian_tam_dung_phut,
       s.thoi_diem_tam_dung, s.trang_thai,
       COALESCE((SELECT c.gia_tri::NUMERIC FROM public.cau_hinh c WHERE c.ma_cau_hinh='canh_bao_phan_tram'), 20) AS nguong_canh_bao,
       q.nhan_vien_id AS nguoi_quan_ly_id
FROM public.sla s JOIN public.ho_so h ON h.id=s.ho_so_id
LEFT JOIN LATERAL (
    SELECT nv.id AS nhan_vien_id FROM public.nhan_vien nv
    JOIN public.tai_khoan tk ON tk.id=nv.tai_khoan_id
    WHERE tk.vai_tro='DIEU_PHOI_VIEN' AND tk.dang_hoat_dong=TRUE
    ORDER BY nv.id LIMIT 1
) q ON TRUE;
ALTER VIEW public.v_sla_service OWNER TO hau_mai_owner;
REVOKE ALL ON TABLE public.v_sla_service FROM PUBLIC;
GRANT SELECT ON TABLE public.v_sla_service TO hau_mai_app;

CREATE OR REPLACE PROCEDURE public.sp_luu_sla_tu_service(
    IN p_sla_id BIGINT, IN p_expected_status VARCHAR, IN p_status VARCHAR, IN p_end_at TIMESTAMPTZ,
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
    UPDATE public.sla SET trang_thai=p_status, thoi_diem_ket_thuc=p_end_at,
        thoi_gian_tam_dung_phut=p_paused_minutes, thoi_diem_tam_dung=p_paused_at
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
ALTER PROCEDURE public.sp_luu_sla_tu_service(BIGINT, VARCHAR, VARCHAR, TIMESTAMPTZ, BIGINT, TIMESTAMPTZ,
    TIMESTAMPTZ, TEXT, BIGINT, VARCHAR, VARCHAR, TEXT, VARCHAR, TIMESTAMPTZ) OWNER TO hau_mai_owner;
REVOKE EXECUTE ON PROCEDURE public.sp_luu_sla_tu_service(BIGINT, VARCHAR, VARCHAR, TIMESTAMPTZ, BIGINT, TIMESTAMPTZ,
    TIMESTAMPTZ, TEXT, BIGINT, VARCHAR, VARCHAR, TEXT, VARCHAR, TIMESTAMPTZ) FROM PUBLIC;
GRANT EXECUTE ON PROCEDURE public.sp_luu_sla_tu_service(BIGINT, VARCHAR, VARCHAR, TIMESTAMPTZ, BIGINT, TIMESTAMPTZ,
    TIMESTAMPTZ, TEXT, BIGINT, VARCHAR, VARCHAR, TEXT, VARCHAR, TIMESTAMPTZ) TO hau_mai_app;
