--
-- PostgreSQL database dump
--

\restrict 9O4bIEJQ5bV9cw0qyH7WcUHR96ucih3CYIDqeaapegscbXHsTYhflJNcVL0E1ep

-- Dumped from database version 16.15 (Debian 16.15-1.pgdg12+2)
-- Dumped by pg_dump version 16.15 (Debian 16.15-1.pgdg12+2)

-- Reference snapshot exported from the current database on 2026-11-04.
-- This file contains schema definitions only; it does not contain application data.
-- It is a readable snapshot, not a Flyway migration. Keep db/migration as the
-- authoritative upgrade history for existing databases.

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pg_cron; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;


--
-- Name: EXTENSION pg_cron; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pg_cron IS 'Job scheduler for PostgreSQL';


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

-- *not* creating schema, since initdb creates it


--
-- Name: fn_ho_so_ghi_lich_su_chuyen_trang_thai(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_ho_so_ghi_lich_su_chuyen_trang_thai() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


--
-- Name: fn_ho_so_ghi_lich_su_tao(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_ho_so_ghi_lich_su_tao() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO lich_su_xu_ly (
        ho_so_id,
        trang_thai_tu,
        trang_thai_sang,
        loai_tac_nhan,
        ghi_chu,
        tao_luc
    )
    VALUES (
        NEW.id,
        NULL,
        NEW.trang_thai,
        'KHACH_HANG',
        'Khách hàng gửi yêu cầu',
        NEW.ngay_tiep_nhan
    );

    RETURN NEW;
END;
$$;


--
-- Name: fn_ho_so_thong_tin_khoa(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_ho_so_thong_tin_khoa(p_ho_so_id bigint) RETURNS TABLE(case_status character varying, waiting_since timestamp with time zone, waiting_days integer)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    RETURN QUERY
    SELECT h.trang_thai,
           h.bat_dau_cho_khach_luc,
           COALESCE((
               SELECT c.gia_tri::INTEGER
               FROM public.cau_hinh c
               WHERE c.ma_cau_hinh = 'so_ngay_cho_khach'
           ), 7)
    FROM public.ho_so h
    WHERE h.id = p_ho_so_id
    FOR UPDATE OF h;
END;
$$;


--
-- Name: fn_ktv_dang_hoat_dong_khoa(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_ktv_dang_hoat_dong_khoa(p_ky_thuat_vien_id bigint) RETURNS boolean
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    PERFORM nv.id
    FROM public.nhan_vien nv
    JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
    WHERE nv.id = p_ky_thuat_vien_id
      AND tk.vai_tro = 'KY_THUAT_VIEN'
      AND tk.dang_hoat_dong = TRUE
    FOR UPDATE OF nv;
    RETURN FOUND;
END;
$$;


--
-- Name: fn_ktv_phan_cong_facts(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_ktv_phan_cong_facts(p_phan_cong_id bigint) RETURNS TABLE(ho_so_id bigint, ky_thuat_vien_id bigint, dang_hieu_luc boolean, case_status text, progress_status text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    RETURN QUERY
    SELECT pc.ho_so_id,
           pc.ky_thuat_vien_id,
           pc.dang_hieu_luc,
           hs.trang_thai::TEXT,
           (SELECT ts.trang_thai::TEXT
            FROM public.tien_do_sua_chua ts
            WHERE ts.phan_cong_id = pc.id
            ORDER BY ts.tao_luc DESC, ts.id DESC
            LIMIT 1)
    FROM public.phan_cong pc
    JOIN public.ho_so hs ON hs.id = pc.ho_so_id
    WHERE pc.id = p_phan_cong_id
    FOR UPDATE OF pc, hs;
END;
$$;


--
-- Name: fn_nhan_vien_id_theo_dang_nhap(character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_nhan_vien_id_theo_dang_nhap(p_ten_dang_nhap character varying, p_vai_tro character varying) RETURNS bigint
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT nv.id
    FROM public.nhan_vien nv
    JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
    WHERE tk.ten_dang_nhap = p_ten_dang_nhap
      AND tk.vai_tro = p_vai_tro
      AND tk.dang_hoat_dong = TRUE
$$;


--
-- Name: fn_tra_cuu_ho_so(character varying, character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.fn_tra_cuu_ho_so(p_ma_ho_so character varying, p_so_dien_thoai character varying) RETURNS TABLE(ma_ho_so character varying, trang_thai character varying, trang_thai_hien_thi character varying, ten_san_pham character varying, serial character varying, ngay_tiep_nhan timestamp with time zone, kenh_tiep_nhan character varying, tien_do text, ket_luan_xu_ly text)
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
    SELECT
        hs.ma_ho_so,
        hs.trang_thai,
        CASE hs.trang_thai
            WHEN 'MOI' THEN 'Mới tiếp nhận'
            WHEN 'DANG_XAC_MINH' THEN 'Đang xác minh'
            WHEN 'CHO_KHACH_BO_SUNG' THEN 'Chờ bổ sung thông tin'
            WHEN 'CHO_PHAN_CONG' THEN 'Chờ phân công'
            WHEN 'DANG_SUA_CHUA' THEN 'Đang sửa chữa'
            WHEN 'CHO_CSKH_XU_LY' THEN 'Đang hoàn tất hồ sơ'
            WHEN 'DA_SUA_XONG' THEN 'Đã sửa xong'
            WHEN 'TU_CHOI' THEN 'Không đủ điều kiện bảo hành'
            WHEN 'DA_DONG' THEN 'Đã hoàn tất'
            ELSE 'Đang cập nhật'
        END,
        sp.ten_san_pham,
        COALESCE(hs.serial, hs.serial_khach_khai_bao),
        hs.ngay_tiep_nhan,
        CASE kg.ma_kenh
            WHEN 'FACEBOOK' THEN 'Facebook Messenger'
            ELSE kg.ten_hien_thi
        END,
        CASE hs.trang_thai
            WHEN 'MOI' THEN 'Đã tiếp nhận yêu cầu'
            WHEN 'DANG_XAC_MINH' THEN 'CSKH đang xác minh hồ sơ'
            WHEN 'CHO_KHACH_BO_SUNG' THEN 'Đang chờ bổ sung thông tin'
            WHEN 'CHO_PHAN_CONG' THEN 'Đã xác minh, đang chờ phân công kỹ thuật viên'
            WHEN 'DANG_SUA_CHUA' THEN 'Kỹ thuật viên đang sửa chữa'
            WHEN 'CHO_CSKH_XU_LY' THEN 'Đang hoàn tất hồ sơ sau sửa chữa'
            WHEN 'DA_SUA_XONG' THEN 'Đã sửa xong'
            WHEN 'TU_CHOI' THEN 'Đã có kết luận không đủ điều kiện bảo hành'
            WHEN 'DA_DONG' THEN 'Hồ sơ đã hoàn tất'
            ELSE 'Đang cập nhật'
        END,
        hs.ket_luan_xu_ly
    FROM public.ho_so hs
    JOIN public.khach_hang kh ON kh.id = hs.khach_hang_id
    JOIN public.kenh_goc kg ON kg.id = hs.kenh_goc_id
    LEFT JOIN public.san_pham sp
        ON sp.serial = COALESCE(hs.serial, hs.serial_khach_khai_bao)
    WHERE UPPER(hs.ma_ho_so) = UPPER(BTRIM(p_ma_ho_so))
      AND BTRIM(kh.so_dien_thoai) = BTRIM(p_so_dien_thoai)
    LIMIT 1;
$$;


--
-- Name: sp_bat_dau_sla_sua_chua(bigint, character varying, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_bat_dau_sla_sua_chua(IN p_sla_id bigint, IN p_expected_status character varying, IN p_started_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    UPDATE public.sla SET trang_thai='DANG_DEM', thoi_diem_bat_dau=p_started_at,
        thoi_diem_ket_thuc=NULL, thoi_gian_tam_dung_phut=0, thoi_diem_tam_dung=NULL
    WHERE id=p_sla_id AND loai_sla='XU_LY' AND trang_thai=p_expected_status;
    IF NOT FOUND THEN RAISE EXCEPTION 'Không thể bắt đầu SLA sửa chữa'; END IF;
END;
$$;


--
-- Name: sp_cap_nhat_gui_cuoc_tro_chuyen(bigint, character varying, character varying, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_cap_nhat_gui_cuoc_tro_chuyen(IN p_tin_nhan_id bigint, IN p_trang_thai character varying, IN p_ma_tin_goc character varying, IN p_now timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    IF p_trang_thai NOT IN ('DA_GUI', 'THAT_BAI') THEN RAISE EXCEPTION 'Trạng thái gửi không hợp lệ'; END IF;
    UPDATE public.tin_nhan_cuoc_tro_chuyen SET trang_thai_gui=p_trang_thai,
        ma_tin_goc=COALESCE(NULLIF(BTRIM(p_ma_tin_goc), ''), ma_tin_goc),
        gui_luc=CASE WHEN p_trang_thai='DA_GUI' THEN COALESCE(p_now, now()) ELSE gui_luc END
    WHERE id=p_tin_nhan_id AND huong_tin='DI';
    IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy tin nhắn chờ gửi'; END IF;
END; $$;


--
-- Name: sp_cap_nhat_ket_qua_gui_facebook(bigint, character varying, character varying, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_cap_nhat_ket_qua_gui_facebook(IN p_tin_nhan_id bigint, IN p_trang_thai character varying, IN p_ma_tin_nha_cung_cap character varying, IN p_now timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_ma_tin_goc VARCHAR(255);
    v_rows INTEGER;
BEGIN
    IF p_trang_thai NOT IN ('DA_GUI', 'THAT_BAI') THEN
        RAISE EXCEPTION 'Trạng thái gửi không hợp lệ';
    END IF;
    v_ma_tin_goc := NULLIF(BTRIM(p_ma_tin_nha_cung_cap), '');

    UPDATE public.tin_nhan tn
    SET trang_thai_gui = p_trang_thai,
        ma_tin_goc = v_ma_tin_goc,
        gui_luc = CASE WHEN p_trang_thai = 'DA_GUI' THEN COALESCE(p_now, now()) ELSE gui_luc END
    FROM public.kenh_goc kg
    WHERE tn.id = p_tin_nhan_id
      AND tn.kenh_id = kg.id
      AND kg.ma_kenh = 'FACEBOOK'
      AND tn.huong_tin = 'DI'
      AND tn.trang_thai_gui = 'CHO_GUI';
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 AND NOT EXISTS (
        SELECT 1
        FROM public.tin_nhan tn
        JOIN public.kenh_goc kg ON kg.id = tn.kenh_id AND kg.ma_kenh = 'FACEBOOK'
        WHERE tn.id = p_tin_nhan_id
          AND tn.huong_tin = 'DI'
          AND tn.trang_thai_gui = p_trang_thai
          AND tn.ma_tin_goc IS NOT DISTINCT FROM v_ma_tin_goc
    ) THEN
        RAISE EXCEPTION 'Không tìm thấy tin nhắn Facebook chờ xử lý id=%', p_tin_nhan_id;
    END IF;
END;
$$;


--
-- Name: sp_cap_nhat_ket_qua_gui_zalo(bigint, character varying, character varying, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_cap_nhat_ket_qua_gui_zalo(IN p_tin_nhan_id bigint, IN p_trang_thai character varying, IN p_ma_tin_nha_cung_cap character varying, IN p_now timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_ma_tin_goc VARCHAR(255);
    v_rows INTEGER;
BEGIN
    IF p_trang_thai NOT IN ('DA_GUI', 'THAT_BAI') THEN
        RAISE EXCEPTION 'Trạng thái gửi không hợp lệ';
    END IF;
    v_ma_tin_goc := NULLIF(BTRIM(p_ma_tin_nha_cung_cap), '');

    UPDATE public.tin_nhan
    SET trang_thai_gui = p_trang_thai,
        ma_tin_goc = v_ma_tin_goc,
        gui_luc = CASE WHEN p_trang_thai = 'DA_GUI' THEN COALESCE(p_now, now()) ELSE gui_luc END
    WHERE id = p_tin_nhan_id
      AND huong_tin = 'DI'
      AND trang_thai_gui = 'CHO_GUI';
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 AND NOT EXISTS (
        SELECT 1 FROM public.tin_nhan
        WHERE id = p_tin_nhan_id
          AND huong_tin = 'DI'
          AND trang_thai_gui = p_trang_thai
          AND ma_tin_goc IS NOT DISTINCT FROM v_ma_tin_goc
    ) THEN
        RAISE EXCEPTION 'Không tìm thấy tin nhắn gửi chờ xử lý id=%', p_tin_nhan_id;
    END IF;
END;
$$;


--
-- Name: sp_cap_nhat_khach_hang_tu_dinh_danh(character varying, character varying, character varying, character varying); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_cap_nhat_khach_hang_tu_dinh_danh(IN p_ma_kenh character varying, IN p_ma_nguoi_dung_kenh character varying, IN p_ho_ten character varying, IN p_so_dien_thoai character varying)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_khach_hang_id BIGINT;
    v_kenh_id BIGINT;
    v_so_dien_thoai VARCHAR(30);
BEGIN
    v_so_dien_thoai := NULLIF(BTRIM(p_so_dien_thoai), '');
    IF NULLIF(BTRIM(p_ho_ten), '') IS NULL OR v_so_dien_thoai IS NULL THEN
        RAISE EXCEPTION 'Họ tên và số điện thoại không được để trống';
    END IF;

    SELECT kg.id INTO v_kenh_id
    FROM public.kenh_goc kg
    WHERE kg.ma_kenh = UPPER(BTRIM(p_ma_kenh));

    SELECT dk.khach_hang_id INTO v_khach_hang_id
    FROM public.dinh_danh_kenh dk
    WHERE dk.kenh_id = v_kenh_id
      AND dk.ma_nguoi_dung_kenh = NULLIF(BTRIM(p_ma_nguoi_dung_kenh), '')
    FOR UPDATE;

    -- A new sender has no existing customer row to correct. The case procedure creates it.
    IF v_khach_hang_id IS NULL THEN
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.khach_hang kh
        WHERE kh.so_dien_thoai = v_so_dien_thoai
          AND kh.id <> v_khach_hang_id
    ) THEN
        RAISE EXCEPTION 'Số điện thoại này đã thuộc về một khách hàng khác';
    END IF;

    UPDATE public.khach_hang
    SET ho_ten = BTRIM(p_ho_ten), so_dien_thoai = v_so_dien_thoai
    WHERE id = v_khach_hang_id;

    UPDATE public.dinh_danh_kenh
    SET ten_hien_thi = BTRIM(p_ho_ten)
    WHERE kenh_id = v_kenh_id
      AND ma_nguoi_dung_kenh = NULLIF(BTRIM(p_ma_nguoi_dung_kenh), '');
END;
$$;


--
-- Name: sp_chuyen_trang_thai(bigint, character varying, character varying, bigint, text, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_chuyen_trang_thai(IN p_ho_so_id bigint, IN p_trang_thai_moi character varying, IN p_loai_tac_nhan character varying, IN p_nhan_vien_id bigint, IN p_ghi_chu text, IN p_now timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sp_gan_cuoc_tro_chuyen_vao_ho_so(character varying, character varying, bigint); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_gan_cuoc_tro_chuyen_vao_ho_so(IN p_ma_kenh character varying, IN p_ma_nguoi_dung character varying, IN p_ho_so_id bigint)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_kenh_id BIGINT;
    v_khach_hang_id BIGINT;
    v_cuoc_tro_chuyen_id BIGINT;
BEGIN
    SELECT hs.kenh_goc_id, hs.khach_hang_id
    INTO v_kenh_id, v_khach_hang_id
    FROM public.ho_so hs
    JOIN public.kenh_goc kg ON kg.id = hs.kenh_goc_id
    JOIN public.dinh_danh_kenh dk
      ON dk.kenh_id = kg.id AND dk.khach_hang_id = hs.khach_hang_id
    WHERE hs.id = p_ho_so_id
      AND kg.ma_kenh = UPPER(BTRIM(p_ma_kenh))
      AND dk.ma_nguoi_dung_kenh = p_ma_nguoi_dung;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    INSERT INTO public.cuoc_tro_chuyen(kenh_id, ma_nguoi_dung_kenh, khach_hang_id, ho_so_id)
    VALUES (v_kenh_id, p_ma_nguoi_dung, v_khach_hang_id, p_ho_so_id)
    ON CONFLICT (kenh_id, ma_nguoi_dung_kenh) DO UPDATE SET
        khach_hang_id = EXCLUDED.khach_hang_id,
        ho_so_id = EXCLUDED.ho_so_id,
        cap_nhat_luc = now()
    RETURNING id INTO v_cuoc_tro_chuyen_id;

    UPDATE public.tin_nhan_cuoc_tro_chuyen
    SET ho_so_id = p_ho_so_id
    WHERE cuoc_tro_chuyen_id = v_cuoc_tro_chuyen_id;

    INSERT INTO public.tin_nhan(
        ho_so_id, kenh_id, ma_tin_goc, huong_tin, noi_dung,
        nhan_vien_id, trang_thai_gui, gui_luc, tao_luc
    )
    SELECT p_ho_so_id, v_kenh_id, m.ma_tin_goc, m.huong_tin, m.noi_dung,
           m.nhan_vien_id, m.trang_thai_gui, m.gui_luc, m.tao_luc
    FROM public.tin_nhan_cuoc_tro_chuyen m
    WHERE m.cuoc_tro_chuyen_id = v_cuoc_tro_chuyen_id
    ORDER BY m.tao_luc, m.id
    ON CONFLICT (kenh_id, ma_tin_goc) WHERE ma_tin_goc IS NOT NULL DO NOTHING;
END;
$$;


--
-- Name: sp_gan_tin_cho_bo_sung_vao_ho_so(character varying, character varying, bigint); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_gan_tin_cho_bo_sung_vao_ho_so(IN p_ma_kenh character varying, IN p_ma_nguoi_dung_kenh character varying, IN p_ho_so_id bigint)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_kenh_id BIGINT;
BEGIN
    SELECT kg.id INTO v_kenh_id
    FROM public.kenh_goc kg
    JOIN public.dinh_danh_kenh dk ON dk.kenh_id = kg.id
    JOIN public.ho_so hs ON hs.khach_hang_id = dk.khach_hang_id AND hs.kenh_goc_id = kg.id
    WHERE kg.ma_kenh = UPPER(BTRIM(p_ma_kenh))
      AND dk.ma_nguoi_dung_kenh = p_ma_nguoi_dung_kenh
      AND hs.id = p_ho_so_id;
    IF NOT FOUND THEN
        RETURN;
    END IF;

    INSERT INTO public.tin_nhan (
        ho_so_id, kenh_id, ma_tin_goc, huong_tin, noi_dung,
        nhan_vien_id, trang_thai_gui, tao_luc
    )
    SELECT p_ho_so_id, t.kenh_id, t.ma_tin_goc, 'DEN', t.noi_dung,
           NULL, 'KHONG_AP_DUNG', t.nhan_luc
    FROM public.tin_nhan_cho_bo_sung t
    WHERE t.kenh_id = v_kenh_id
      AND t.ma_nguoi_dung_kenh = p_ma_nguoi_dung_kenh
      AND t.trang_thai = 'CHO_BO_SUNG'
    ON CONFLICT (kenh_id, ma_tin_goc) WHERE ma_tin_goc IS NOT NULL DO NOTHING;

    UPDATE public.tin_nhan_cho_bo_sung
    SET trang_thai = 'DA_GAN_HO_SO', ho_so_id = p_ho_so_id
    WHERE kenh_id = v_kenh_id
      AND ma_nguoi_dung_kenh = p_ma_nguoi_dung_kenh
      AND trang_thai = 'CHO_BO_SUNG';
END;
$$;


--
-- Name: sp_ghi_nhan_tin_tiep_theo_facebook(character varying, character varying, text, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_ghi_nhan_tin_tiep_theo_facebook(IN p_ma_tin_goc character varying, IN p_ma_nguoi_dung_kenh character varying, IN p_noi_dung text, IN p_nhan_luc timestamp with time zone, OUT p_ho_so_id bigint, OUT p_ma_ho_so character varying, OUT p_ket_qua character varying)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_kenh_id BIGINT;
    v_khach_hang_id BIGINT;
    v_so_ho_so INTEGER;
    v_rows INTEGER;
BEGIN
    p_ho_so_id := NULL;
    p_ma_ho_so := NULL;
    p_ket_qua := 'KHONG_TIM_THAY';

    IF NULLIF(BTRIM(p_ma_tin_goc), '') IS NULL
       OR NULLIF(BTRIM(p_ma_nguoi_dung_kenh), '') IS NULL
       OR NULLIF(BTRIM(p_noi_dung), '') IS NULL THEN
        RAISE EXCEPTION 'Thiếu mã tin, định danh Facebook hoặc nội dung';
    END IF;

    SELECT kg.id, dk.khach_hang_id
    INTO v_kenh_id, v_khach_hang_id
    FROM public.kenh_goc kg
    JOIN public.dinh_danh_kenh dk ON dk.kenh_id = kg.id
    WHERE kg.ma_kenh = 'FACEBOOK'
      AND dk.ma_nguoi_dung_kenh = p_ma_nguoi_dung_kenh;
    IF NOT FOUND THEN
        p_ket_qua := 'CHUA_CO_DINH_DANH';
        RETURN;
    END IF;

    -- Webhooks can be redelivered. Return the existing case without inserting twice.
    SELECT tn.ho_so_id, hs.ma_ho_so
    INTO p_ho_so_id, p_ma_ho_so
    FROM public.tin_nhan tn
    JOIN public.ho_so hs ON hs.id = tn.ho_so_id
    WHERE tn.kenh_id = v_kenh_id
      AND tn.ma_tin_goc = p_ma_tin_goc;
    IF FOUND THEN
        p_ket_qua := 'DA_TON_TAI';
        RETURN;
    END IF;

    -- A sender may have more than one active case. Do not guess which one a reply belongs to.
    SELECT COUNT(*)::INTEGER, MIN(hs.id)
    INTO v_so_ho_so, p_ho_so_id
    FROM public.ho_so hs
    WHERE hs.khach_hang_id = v_khach_hang_id
      AND hs.kenh_goc_id = v_kenh_id
      AND hs.trang_thai NOT IN ('DA_DONG', 'TU_CHOI');

    IF v_so_ho_so = 0 THEN
        p_ho_so_id := NULL;
        p_ket_qua := 'KHONG_CO_HO_SO_MO';
        RETURN;
    ELSIF v_so_ho_so > 1 THEN
        p_ho_so_id := NULL;
        p_ket_qua := 'NHIEU_HO_SO_MO';
        RETURN;
    END IF;

    SELECT hs.ma_ho_so INTO p_ma_ho_so
    FROM public.ho_so hs WHERE hs.id = p_ho_so_id;

    INSERT INTO public.tin_nhan (
        ho_so_id, kenh_id, ma_tin_goc, huong_tin, noi_dung,
        nhan_vien_id, trang_thai_gui, tao_luc
    ) VALUES (
        p_ho_so_id, v_kenh_id, p_ma_tin_goc, 'DEN', BTRIM(p_noi_dung),
        NULL, 'KHONG_AP_DUNG', COALESCE(p_nhan_luc, now())
    ) ON CONFLICT (kenh_id, ma_tin_goc) WHERE ma_tin_goc IS NOT NULL DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 THEN
        SELECT tn.ho_so_id, hs.ma_ho_so
        INTO p_ho_so_id, p_ma_ho_so
        FROM public.tin_nhan tn
        JOIN public.ho_so hs ON hs.id = tn.ho_so_id
        WHERE tn.kenh_id = v_kenh_id
          AND tn.ma_tin_goc = p_ma_tin_goc;
        p_ket_qua := 'DA_TON_TAI';
    ELSE
        p_ket_qua := 'DA_GHI_NHAN';
    END IF;
END;
$$;


--
-- Name: sp_ghi_nhan_tin_tiep_theo_kenh(character varying, character varying, character varying, text, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_ghi_nhan_tin_tiep_theo_kenh(IN p_ma_kenh character varying, IN p_ma_tin_goc character varying, IN p_ma_nguoi_dung_kenh character varying, IN p_noi_dung text, IN p_nhan_luc timestamp with time zone, OUT p_ho_so_id bigint, OUT p_ma_ho_so character varying, OUT p_ket_qua character varying)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_ma_kenh VARCHAR(30);
    v_kenh_id BIGINT;
    v_khach_hang_id BIGINT;
    v_so_ho_so INTEGER;
    v_rows INTEGER;
BEGIN
    v_ma_kenh := UPPER(NULLIF(BTRIM(p_ma_kenh), ''));
    p_ho_so_id := NULL;
    p_ma_ho_so := NULL;
    p_ket_qua := 'KHONG_TIM_THAY';

    IF v_ma_kenh NOT IN ('FACEBOOK', 'ZALO')
       OR NULLIF(BTRIM(p_ma_tin_goc), '') IS NULL
       OR NULLIF(BTRIM(p_ma_nguoi_dung_kenh), '') IS NULL
       OR NULLIF(BTRIM(p_noi_dung), '') IS NULL THEN
        RAISE EXCEPTION 'Thiếu kênh, mã tin, định danh hoặc nội dung';
    END IF;

    SELECT kg.id INTO v_kenh_id
    FROM public.kenh_goc kg
    WHERE kg.ma_kenh = v_ma_kenh AND kg.dang_bat;
    IF NOT FOUND THEN RAISE EXCEPTION 'Kênh chưa được cấu hình hoặc đang tắt'; END IF;

    SELECT dk.khach_hang_id INTO v_khach_hang_id
    FROM public.dinh_danh_kenh dk
    WHERE dk.kenh_id = v_kenh_id
      AND dk.ma_nguoi_dung_kenh = p_ma_nguoi_dung_kenh;
    IF NOT FOUND THEN
        p_ket_qua := 'CHUA_CO_DINH_DANH';
        RETURN;
    END IF;

    SELECT tn.ho_so_id, hs.ma_ho_so INTO p_ho_so_id, p_ma_ho_so
    FROM public.tin_nhan tn
    LEFT JOIN public.ho_so hs ON hs.id = tn.ho_so_id
    WHERE tn.kenh_id = v_kenh_id AND tn.ma_tin_goc = p_ma_tin_goc;
    IF FOUND THEN
        p_ket_qua := 'DA_TON_TAI';
        RETURN;
    END IF;

    SELECT COUNT(*)::INTEGER, MIN(hs.id)
    INTO v_so_ho_so, p_ho_so_id
    FROM public.ho_so hs
    WHERE hs.khach_hang_id = v_khach_hang_id
      AND hs.kenh_goc_id = v_kenh_id
      AND hs.trang_thai NOT IN ('DA_DONG', 'TU_CHOI');

    IF v_so_ho_so = 0 THEN
        p_ho_so_id := NULL;
        p_ket_qua := 'KHONG_CO_HO_SO_MO';
        RETURN;
    ELSIF v_so_ho_so > 1 THEN
        p_ho_so_id := NULL;
        p_ket_qua := 'NHIEU_HO_SO_MO';
        RETURN;
    END IF;

    SELECT hs.ma_ho_so INTO p_ma_ho_so
    FROM public.ho_so hs WHERE hs.id = p_ho_so_id;

    INSERT INTO public.tin_nhan (
        ho_so_id, kenh_id, ma_tin_goc, huong_tin, noi_dung,
        nhan_vien_id, trang_thai_gui, tao_luc
    ) VALUES (
        p_ho_so_id, v_kenh_id, p_ma_tin_goc, 'DEN', BTRIM(p_noi_dung),
        NULL, 'KHONG_AP_DUNG', COALESCE(p_nhan_luc, now())
    ) ON CONFLICT (kenh_id, ma_tin_goc) WHERE ma_tin_goc IS NOT NULL DO NOTHING;
    GET DIAGNOSTICS v_rows = ROW_COUNT;

    IF v_rows = 0 THEN
        SELECT tn.ho_so_id, hs.ma_ho_so INTO p_ho_so_id, p_ma_ho_so
        FROM public.tin_nhan tn
        LEFT JOIN public.ho_so hs ON hs.id = tn.ho_so_id
        WHERE tn.kenh_id = v_kenh_id AND tn.ma_tin_goc = p_ma_tin_goc;
        p_ket_qua := 'DA_TON_TAI';
    ELSE
        p_ket_qua := 'DA_GHI_NHAN';
    END IF;
END;
$$;


--
-- Name: sp_luu_ket_qua_xac_minh(bigint, text, text, boolean); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_luu_ket_qua_xac_minh(IN p_ho_so_id bigint, IN p_ket_qua text, IN p_ly_do_tu_choi text, IN p_ngoai_bao_hanh boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    UPDATE public.ho_so
    SET ket_qua_xac_minh = p_ket_qua, ly_do_tu_choi = p_ly_do_tu_choi,
        ngoai_bao_hanh = p_ngoai_bao_hanh
    WHERE id = p_ho_so_id AND trang_thai = 'DANG_XAC_MINH';
    IF NOT FOUND THEN RAISE EXCEPTION 'Hồ sơ không còn ở trạng thái đang xác minh'; END IF;
END;
$$;


--
-- Name: sp_luu_ktv_hoan_tat(bigint, bigint, text, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_luu_ktv_hoan_tat(IN p_ho_so_id bigint, IN p_phan_cong_id bigint, IN p_ket_luan text, IN p_now timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    INSERT INTO public.tien_do_sua_chua(phan_cong_id, trang_thai, ghi_chu, tao_luc)
    VALUES(p_phan_cong_id, 'DA_SUA_XONG', p_ket_luan, p_now);
    UPDATE public.ho_so SET ket_luan_xu_ly = p_ket_luan WHERE id = p_ho_so_id;
END;
$$;


--
-- Name: sp_luu_ktv_tiep_nhan(bigint, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_luu_ktv_tiep_nhan(IN p_phan_cong_id bigint, IN p_now timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
BEGIN
    INSERT INTO public.tien_do_sua_chua(phan_cong_id, trang_thai, ghi_chu, tao_luc)
    VALUES(p_phan_cong_id, 'DANG_SUA_CHUA', 'Kỹ thuật viên đã tiếp nhận hồ sơ', p_now);
END;
$$;


--
-- Name: sp_luu_phan_cong_da_kiem_tra(bigint, bigint, bigint, text, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_luu_phan_cong_da_kiem_tra(IN p_ho_so_id bigint, IN p_ky_thuat_vien_id bigint, IN p_dieu_phoi_vien_id bigint, IN p_ly_do text, IN p_now timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE v_ho_so_ma VARCHAR(30); v_phan_cong_id BIGINT;
BEGIN
    SELECT ma_ho_so INTO v_ho_so_ma FROM public.ho_so WHERE id = p_ho_so_id;
    UPDATE public.phan_cong
    SET dang_hieu_luc = FALSE, ngay_ket_thuc = p_now, ly_do_thay_doi = p_ly_do
    WHERE ho_so_id = p_ho_so_id AND dang_hieu_luc = TRUE;
    INSERT INTO public.phan_cong(ho_so_id, ky_thuat_vien_id, dieu_phoi_vien_id,
        ngay_phan_cong, ly_do_thay_doi, dang_hieu_luc)
    VALUES(p_ho_so_id, p_ky_thuat_vien_id, p_dieu_phoi_vien_id, p_now, p_ly_do, TRUE)
    RETURNING id INTO v_phan_cong_id;
    INSERT INTO public.tien_do_sua_chua(phan_cong_id, trang_thai, ghi_chu, tao_luc)
    VALUES(v_phan_cong_id, 'DA_NHAN_THIET_BI', 'Khởi tạo tiến độ cho lần phân công mới', p_now);
    INSERT INTO public.thong_bao(ho_so_id, nhan_vien_nhan_id, khoa_chong_trung,
        tieu_de, noi_dung, loai_thong_bao, tao_luc)
    VALUES(p_ho_so_id, p_ky_thuat_vien_id, 'phan-cong:' || v_phan_cong_id,
        'Hồ sơ mới được phân công', 'Bạn được giao xử lý hồ sơ ' || v_ho_so_ma || '.', 'PHAN_CONG', p_now)
    ON CONFLICT(khoa_chong_trung) DO NOTHING;
END;
$$;


--
-- Name: sp_luu_sla_tu_service(bigint, character varying, character varying, timestamp with time zone, timestamp with time zone, bigint, timestamp with time zone, timestamp with time zone, text, bigint, character varying, character varying, text, character varying, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_luu_sla_tu_service(IN p_sla_id bigint, IN p_expected_status character varying, IN p_status character varying, IN p_started_at timestamp with time zone, IN p_end_at timestamp with time zone, IN p_paused_minutes bigint, IN p_paused_at timestamp with time zone, IN p_detected_at timestamp with time zone, IN p_violation_note text, IN p_receiver_id bigint, IN p_notification_key character varying, IN p_title character varying, IN p_body text, IN p_notification_type character varying, IN p_notification_at timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
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


--
-- Name: sp_luu_tin_cho_bo_sung(character varying, character varying, character varying, text, character varying, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_luu_tin_cho_bo_sung(IN p_ma_kenh character varying, IN p_ma_tin_goc character varying, IN p_ma_nguoi_dung_kenh character varying, IN p_noi_dung text, IN p_ly_do character varying, IN p_nhan_luc timestamp with time zone)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_kenh_id BIGINT;
BEGIN
    SELECT id INTO v_kenh_id
    FROM public.kenh_goc
    WHERE ma_kenh = UPPER(BTRIM(p_ma_kenh)) AND dang_bat = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kênh % chưa được cấu hình hoặc đang tắt', p_ma_kenh;
    END IF;
    IF NULLIF(BTRIM(p_ma_tin_goc), '') IS NULL
       OR NULLIF(BTRIM(p_ma_nguoi_dung_kenh), '') IS NULL
       OR NULLIF(BTRIM(p_noi_dung), '') IS NULL THEN
        RAISE EXCEPTION 'Thiếu mã tin, mã người gửi hoặc nội dung';
    END IF;

    INSERT INTO public.tin_nhan_cho_bo_sung (
        kenh_id, ma_tin_goc, ma_nguoi_dung_kenh, noi_dung, ly_do, nhan_luc
    ) VALUES (
        v_kenh_id, BTRIM(p_ma_tin_goc), BTRIM(p_ma_nguoi_dung_kenh),
        BTRIM(p_noi_dung), COALESCE(NULLIF(BTRIM(p_ly_do), ''), 'CAN_FORM'),
        COALESCE(p_nhan_luc, now())
    ) ON CONFLICT (kenh_id, ma_tin_goc) DO NOTHING;
END;
$$;


--
-- Name: sp_luu_tin_cuoc_tro_chuyen(character varying, character varying, character varying, text, character varying, bigint, bigint, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_luu_tin_cuoc_tro_chuyen(IN p_ma_kenh character varying, IN p_ma_nguoi_dung character varying, IN p_ma_tin_goc character varying, IN p_noi_dung text, IN p_huong_tin character varying, IN p_ho_so_id bigint, IN p_nhan_vien_id bigint, IN p_nhan_luc timestamp with time zone, OUT p_cuoc_tro_chuyen_id bigint, OUT p_tin_nhan_id bigint)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE v_kenh_id BIGINT; v_khach_hang_id BIGINT;
BEGIN
    SELECT id INTO v_kenh_id FROM public.kenh_goc
    WHERE ma_kenh = UPPER(BTRIM(p_ma_kenh)) AND dang_bat;
    IF NOT FOUND THEN RAISE EXCEPTION 'Kênh chưa được cấu hình'; END IF;
    IF NULLIF(BTRIM(p_ma_nguoi_dung), '') IS NULL OR NULLIF(BTRIM(p_noi_dung), '') IS NULL
       OR p_huong_tin NOT IN ('DEN', 'DI') THEN RAISE EXCEPTION 'Dữ liệu hội thoại không hợp lệ'; END IF;
    IF p_ho_so_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.ho_so hs
        JOIN public.dinh_danh_kenh dk
          ON dk.khach_hang_id=hs.khach_hang_id AND dk.kenh_id=v_kenh_id
        WHERE hs.id=p_ho_so_id AND hs.kenh_goc_id=v_kenh_id
          AND dk.ma_nguoi_dung_kenh=p_ma_nguoi_dung
    ) THEN
        RAISE EXCEPTION 'Hồ sơ không thuộc người gửi trên kênh này';
    END IF;

    SELECT dk.khach_hang_id INTO v_khach_hang_id FROM public.dinh_danh_kenh dk
    WHERE dk.kenh_id = v_kenh_id AND dk.ma_nguoi_dung_kenh = p_ma_nguoi_dung;
    INSERT INTO public.cuoc_tro_chuyen(kenh_id, ma_nguoi_dung_kenh, khach_hang_id, ho_so_id, cap_nhat_luc)
    VALUES (v_kenh_id, p_ma_nguoi_dung, v_khach_hang_id, p_ho_so_id, COALESCE(p_nhan_luc, now()))
    ON CONFLICT (kenh_id, ma_nguoi_dung_kenh) DO UPDATE SET
        khach_hang_id = COALESCE(public.cuoc_tro_chuyen.khach_hang_id, EXCLUDED.khach_hang_id),
        ho_so_id = EXCLUDED.ho_so_id,
        cap_nhat_luc = GREATEST(public.cuoc_tro_chuyen.cap_nhat_luc, EXCLUDED.cap_nhat_luc)
    RETURNING id INTO p_cuoc_tro_chuyen_id;

    INSERT INTO public.tin_nhan_cuoc_tro_chuyen(
        cuoc_tro_chuyen_id, ho_so_id, ma_tin_goc, huong_tin, noi_dung,
        trang_thai_gui, nhan_vien_id, tao_luc
    ) VALUES (
        p_cuoc_tro_chuyen_id, p_ho_so_id, NULLIF(BTRIM(p_ma_tin_goc), ''), p_huong_tin,
        BTRIM(p_noi_dung), CASE WHEN p_huong_tin = 'DI' THEN 'CHO_GUI' ELSE 'KHONG_AP_DUNG' END,
        p_nhan_vien_id, COALESCE(p_nhan_luc, now())
    ) ON CONFLICT (cuoc_tro_chuyen_id, ma_tin_goc) WHERE ma_tin_goc IS NOT NULL DO NOTHING
    RETURNING id INTO p_tin_nhan_id;
    IF p_tin_nhan_id IS NULL AND p_ma_tin_goc IS NOT NULL THEN
        SELECT id INTO p_tin_nhan_id FROM public.tin_nhan_cuoc_tro_chuyen
        WHERE cuoc_tro_chuyen_id = p_cuoc_tro_chuyen_id AND ma_tin_goc = p_ma_tin_goc;
    END IF;
END; $$;


--
-- Name: sp_luu_tin_nhan_da_phan_loai(character varying, character varying, bigint, text, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_luu_tin_nhan_da_phan_loai(IN p_ma_kenh character varying, IN p_ma_tin_goc character varying, IN p_ho_so_id bigint, IN p_noi_dung text, IN p_nhan_luc timestamp with time zone, OUT p_da_ghi_nhan boolean)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE v_kenh_id BIGINT;
BEGIN
    SELECT id INTO v_kenh_id FROM public.kenh_goc WHERE ma_kenh = p_ma_kenh;
    INSERT INTO public.tin_nhan(ho_so_id, kenh_id, ma_tin_goc, huong_tin, noi_dung,
        nhan_vien_id, trang_thai_gui, tao_luc)
    VALUES(p_ho_so_id, v_kenh_id, p_ma_tin_goc, 'DEN', p_noi_dung,
        NULL, 'KHONG_AP_DUNG', p_nhan_luc)
    ON CONFLICT (kenh_id, ma_tin_goc) WHERE ma_tin_goc IS NOT NULL DO NOTHING;
    p_da_ghi_nhan := FOUND;
END;
$$;


--
-- Name: sp_sua_ho_so_dang_xac_minh(bigint, character varying, character varying, character varying, text); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_sua_ho_so_dang_xac_minh(IN p_ho_so_id bigint, IN p_ho_ten character varying, IN p_so_dien_thoai character varying, IN p_serial character varying, IN p_mo_ta_loi text)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_khach_hang_id BIGINT;
    v_serial_khai_bao VARCHAR(100);
    v_serial_da_dang_ky VARCHAR(100);
BEGIN
    IF NULLIF(BTRIM(p_ho_ten), '') IS NULL
       OR NULLIF(BTRIM(p_so_dien_thoai), '') IS NULL
       OR NULLIF(BTRIM(p_mo_ta_loi), '') IS NULL THEN
        RAISE EXCEPTION 'Họ tên, số điện thoại và mô tả lỗi không được để trống';
    END IF;

    SELECT h.khach_hang_id INTO v_khach_hang_id
    FROM public.ho_so h
    WHERE h.id = p_ho_so_id
      AND h.trang_thai IN ('DANG_XAC_MINH', 'CHO_KHACH_BO_SUNG')
    FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Chỉ được sửa hồ sơ đang xác minh hoặc chờ khách bổ sung';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.khach_hang kh
        WHERE kh.so_dien_thoai = BTRIM(p_so_dien_thoai)
          AND kh.id <> v_khach_hang_id
    ) THEN
        RAISE EXCEPTION 'Số điện thoại này đã thuộc về một khách hàng khác';
    END IF;

    v_serial_khai_bao := NULLIF(BTRIM(p_serial), '');
    IF v_serial_khai_bao IS NOT NULL THEN
        SELECT sp.serial INTO v_serial_da_dang_ky
        FROM public.san_pham sp WHERE UPPER(sp.serial) = UPPER(v_serial_khai_bao);
    END IF;

    UPDATE public.khach_hang
    SET ho_ten = BTRIM(p_ho_ten), so_dien_thoai = BTRIM(p_so_dien_thoai)
    WHERE id = v_khach_hang_id;

    UPDATE public.dinh_danh_kenh
    SET ten_hien_thi = BTRIM(p_ho_ten)
    WHERE khach_hang_id = v_khach_hang_id;

    UPDATE public.ho_so
    SET serial = v_serial_da_dang_ky,
        serial_khach_khai_bao = CASE WHEN v_serial_da_dang_ky IS NULL THEN v_serial_khai_bao ELSE NULL END,
        mo_ta_loi = BTRIM(p_mo_ta_loi)
    WHERE id = p_ho_so_id;
END;
$$;


--
-- Name: sp_tao_ho_so_da_kenh(character varying, character varying, character varying, character varying, character varying, character varying, character varying, text, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_tao_ho_so_da_kenh(IN p_ma_kenh character varying, IN p_ma_tin_goc character varying, IN p_ma_nguoi_dung_kenh character varying, IN p_ho_ten character varying, IN p_so_dien_thoai character varying, IN p_email character varying, IN p_serial character varying, IN p_noi_dung text, IN p_now timestamp with time zone, OUT p_ho_so_id bigint, OUT p_ma_ho_so character varying)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_ma_kenh VARCHAR(30);
    v_kenh_id BIGINT;
    v_khach_hang_id BIGINT;
    v_khach_hang_theo_dinh_danh BIGINT;
    v_serial_khai_bao VARCHAR(100);
    v_serial_da_dang_ky VARCHAR(100);
    v_ma_so BIGINT;
    v_now TIMESTAMPTZ;
    v_sla_tiep_nhan INTEGER;
    v_sla_xu_ly INTEGER;
BEGIN
    v_now := COALESCE(p_now, now());
    v_ma_kenh := UPPER(NULLIF(BTRIM(p_ma_kenh), ''));
    p_ma_tin_goc := NULLIF(BTRIM(p_ma_tin_goc), '');
    p_ma_nguoi_dung_kenh := NULLIF(BTRIM(p_ma_nguoi_dung_kenh), '');
    v_serial_khai_bao := NULLIF(BTRIM(p_serial), '');

    IF v_ma_kenh IS NULL THEN
        RAISE EXCEPTION 'Mã kênh không được để trống';
    END IF;
    IF NULLIF(BTRIM(p_ho_ten), '') IS NULL THEN
        RAISE EXCEPTION 'Họ tên khách hàng không được để trống';
    END IF;
    -- Current customer schema requires a phone number. Channel adapters must collect it before publishing.
    IF NULLIF(BTRIM(p_so_dien_thoai), '') IS NULL THEN
        RAISE EXCEPTION 'Số điện thoại khách hàng không được để trống';
    END IF;
    IF NULLIF(BTRIM(p_noi_dung), '') IS NULL THEN
        RAISE EXCEPTION 'Nội dung yêu cầu không được để trống';
    END IF;
    IF v_ma_kenh <> 'WEBSITE' AND p_ma_tin_goc IS NULL THEN
        RAISE EXCEPTION 'Kênh ngoài Website phải có mã tin nhắn gốc để chống tạo trùng';
    END IF;

    SELECT kg.id
    INTO v_kenh_id
    FROM public.kenh_goc kg
    WHERE kg.ma_kenh = v_ma_kenh
      AND kg.dang_bat = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Kênh % chưa được cấu hình hoặc đang tắt', v_ma_kenh;
    END IF;

    -- Idempotency: a redelivered source message returns the case already created for it.
    IF p_ma_tin_goc IS NOT NULL THEN
        SELECT hs.id, hs.ma_ho_so
        INTO p_ho_so_id, p_ma_ho_so
        FROM public.tin_nhan tn
        JOIN public.ho_so hs ON hs.id = tn.ho_so_id
        WHERE tn.kenh_id = v_kenh_id
          AND tn.ma_tin_goc = p_ma_tin_goc;
        IF FOUND THEN
            RETURN;
        END IF;
    END IF;

    INSERT INTO public.khach_hang (ho_ten, so_dien_thoai, email)
    VALUES (
        BTRIM(p_ho_ten),
        BTRIM(p_so_dien_thoai),
        NULLIF(BTRIM(p_email), '')
    )
    ON CONFLICT (so_dien_thoai)
    DO UPDATE SET
        ho_ten = EXCLUDED.ho_ten,
        email = COALESCE(EXCLUDED.email, public.khach_hang.email)
    RETURNING id INTO v_khach_hang_id;

    -- Link a platform identity to the customer without silently reassigning an existing identity.
    IF p_ma_nguoi_dung_kenh IS NOT NULL THEN
        INSERT INTO public.dinh_danh_kenh (
            khach_hang_id, kenh_id, ma_nguoi_dung_kenh, ten_hien_thi, tao_luc
        )
        VALUES (
            v_khach_hang_id, v_kenh_id, p_ma_nguoi_dung_kenh,
            NULLIF(BTRIM(p_ho_ten), ''), v_now
        )
        ON CONFLICT (kenh_id, ma_nguoi_dung_kenh) DO NOTHING;

        SELECT dk.khach_hang_id
        INTO v_khach_hang_theo_dinh_danh
        FROM public.dinh_danh_kenh dk
        WHERE dk.kenh_id = v_kenh_id
          AND dk.ma_nguoi_dung_kenh = p_ma_nguoi_dung_kenh;

        IF v_khach_hang_theo_dinh_danh IS DISTINCT FROM v_khach_hang_id THEN
            RAISE EXCEPTION 'Định danh kênh đã liên kết với khách hàng khác';
        END IF;
    END IF;

    IF v_serial_khai_bao IS NOT NULL THEN
        SELECT sp.serial
        INTO v_serial_da_dang_ky
        FROM public.san_pham sp
        WHERE sp.serial = v_serial_khai_bao;
    END IF;

    SELECT
        COALESCE(
            (SELECT c.gia_tri::INTEGER FROM public.cau_hinh c
             WHERE c.ma_cau_hinh = 'sla_tiep_nhan_phut'),
            30
        ),
        COALESCE(
            (SELECT c.gia_tri::INTEGER FROM public.cau_hinh c
             WHERE c.ma_cau_hinh = 'sla_xu_ly_phut'),
            4320
        )
    INTO v_sla_tiep_nhan, v_sla_xu_ly;

    IF v_sla_tiep_nhan <= 0 OR v_sla_xu_ly <= 0 THEN
        RAISE EXCEPTION 'Thời hạn SLA phải lớn hơn 0';
    END IF;

    v_ma_so := nextval('public.ho_so_code_seq');
    p_ma_ho_so :=
        'HS-' ||
        TO_CHAR(v_now AT TIME ZONE 'Asia/Ho_Chi_Minh', 'YYYY') ||
        '-' ||
        LPAD(v_ma_so::TEXT, 6, '0');

    INSERT INTO public.ho_so (
        ma_ho_so, khach_hang_id, serial, serial_khach_khai_bao,
        kenh_goc_id, mo_ta_loi, ngay_tiep_nhan, trang_thai, tao_luc
    )
    VALUES (
        p_ma_ho_so, v_khach_hang_id, v_serial_da_dang_ky, v_serial_khai_bao,
        v_kenh_id, BTRIM(p_noi_dung), v_now, 'MOI', v_now
    )
    RETURNING id INTO p_ho_so_id;

    INSERT INTO public.tin_nhan (
        ho_so_id, kenh_id, ma_tin_goc, huong_tin, noi_dung,
        nhan_vien_id, trang_thai_gui, tao_luc
    )
    VALUES (
        p_ho_so_id, v_kenh_id, p_ma_tin_goc, 'DEN', BTRIM(p_noi_dung),
        NULL, 'KHONG_AP_DUNG', v_now
    );

    INSERT INTO public.sla (
        ho_so_id, loai_sla, thoi_han_phut, thoi_diem_bat_dau, trang_thai
    )
    VALUES
        (p_ho_so_id, 'TIEP_NHAN', v_sla_tiep_nhan, v_now, 'DANG_DEM'),
        (p_ho_so_id, 'XU_LY', v_sla_xu_ly, v_now, 'DANG_DEM');
END;
$$;


--
-- Name: sp_tao_phan_hoi_cuoc_tro_chuyen(bigint, bigint, text, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_tao_phan_hoi_cuoc_tro_chuyen(IN p_cuoc_tro_chuyen_id bigint, IN p_nhan_vien_id bigint, IN p_noi_dung text, IN p_now timestamp with time zone, OUT p_tin_nhan_id bigint, OUT p_ma_kenh character varying, OUT p_recipient character varying)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_kenh_id BIGINT;
BEGIN
    IF NULLIF(BTRIM(p_noi_dung), '') IS NULL OR LENGTH(p_noi_dung) > 2000 THEN
        RAISE EXCEPTION 'Nội dung phải từ 1 đến 2000 ký tự';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.nhan_vien nv
        JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
        WHERE nv.id = p_nhan_vien_id AND tk.vai_tro = 'CSKH' AND tk.dang_hoat_dong
    ) THEN
        RAISE EXCEPTION 'Nhân viên CSKH không hoạt động';
    END IF;

    SELECT c.kenh_id, kg.ma_kenh, c.ma_nguoi_dung_kenh
    INTO v_kenh_id, p_ma_kenh, p_recipient
    FROM public.cuoc_tro_chuyen c
    JOIN public.kenh_goc kg ON kg.id = c.kenh_id
    WHERE c.id = p_cuoc_tro_chuyen_id AND kg.ma_kenh IN ('FACEBOOK', 'ZALO');
    IF NOT FOUND THEN RAISE EXCEPTION 'Không tìm thấy cuộc trò chuyện hỗ trợ'; END IF;

    INSERT INTO public.tin_nhan_cuoc_tro_chuyen(
        cuoc_tro_chuyen_id, ho_so_id, huong_tin, noi_dung, trang_thai_gui,
        nhan_vien_id, tao_luc
    ) VALUES (
        p_cuoc_tro_chuyen_id, NULL, 'DI', BTRIM(p_noi_dung), 'CHO_GUI',
        p_nhan_vien_id, COALESCE(p_now, now())
    ) RETURNING id INTO p_tin_nhan_id;

    UPDATE public.cuoc_tro_chuyen SET cap_nhat_luc = COALESCE(p_now, now())
    WHERE id = p_cuoc_tro_chuyen_id;
END;
$$;


--
-- Name: sp_tao_phan_hoi_facebook(bigint, bigint, text, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_tao_phan_hoi_facebook(IN p_ho_so_id bigint, IN p_nhan_vien_id bigint, IN p_noi_dung text, IN p_now timestamp with time zone, OUT p_tin_nhan_id bigint, OUT p_recipient_id character varying)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_kenh_id BIGINT;
BEGIN
    IF NULLIF(BTRIM(p_noi_dung), '') IS NULL OR LENGTH(p_noi_dung) > 2000 THEN
        RAISE EXCEPTION 'Nội dung phản hồi phải từ 1 đến 2000 ký tự';
    END IF;

    PERFORM 1
    FROM public.nhan_vien nv
    JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
    WHERE nv.id = p_nhan_vien_id
      AND tk.vai_tro = 'CSKH'
      AND tk.dang_hoat_dong = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Nhân viên không có quyền CSKH đang hoạt động';
    END IF;

    SELECT kg.id, dk.ma_nguoi_dung_kenh
    INTO v_kenh_id, p_recipient_id
    FROM public.ho_so hs
    JOIN public.kenh_goc kg ON kg.id = hs.kenh_goc_id AND kg.ma_kenh = 'FACEBOOK'
    JOIN public.dinh_danh_kenh dk
      ON dk.khach_hang_id = hs.khach_hang_id AND dk.kenh_id = kg.id
    WHERE hs.id = p_ho_so_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy định danh Facebook cho hồ sơ %', p_ho_so_id;
    END IF;

    INSERT INTO public.tin_nhan (
        ho_so_id, kenh_id, huong_tin, noi_dung, nhan_vien_id, trang_thai_gui, tao_luc
    ) VALUES (
        p_ho_so_id, v_kenh_id, 'DI', BTRIM(p_noi_dung), p_nhan_vien_id,
        'CHO_GUI', COALESCE(p_now, now())
    ) RETURNING id INTO p_tin_nhan_id;
END;
$$;


--
-- Name: sp_tao_phan_hoi_zalo(bigint, bigint, text, timestamp with time zone); Type: PROCEDURE; Schema: public; Owner: -
--

CREATE PROCEDURE public.sp_tao_phan_hoi_zalo(IN p_ho_so_id bigint, IN p_nhan_vien_id bigint, IN p_noi_dung text, IN p_now timestamp with time zone, OUT p_tin_nhan_id bigint, OUT p_recipient_id character varying)
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO 'public', 'pg_temp'
    AS $$
DECLARE
    v_kenh_id BIGINT;
BEGIN
    IF NULLIF(BTRIM(p_noi_dung), '') IS NULL OR LENGTH(p_noi_dung) > 2000 THEN
        RAISE EXCEPTION 'Nội dung phản hồi phải từ 1 đến 2000 ký tự';
    END IF;

    PERFORM 1
    FROM public.nhan_vien nv
    JOIN public.tai_khoan tk ON tk.id = nv.tai_khoan_id
    WHERE nv.id = p_nhan_vien_id
      AND tk.vai_tro = 'CSKH'
      AND tk.dang_hoat_dong = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Nhân viên không có quyền CSKH đang hoạt động';
    END IF;

    SELECT kg.id, dk.ma_nguoi_dung_kenh
    INTO v_kenh_id, p_recipient_id
    FROM public.ho_so hs
    JOIN public.kenh_goc kg ON kg.id = hs.kenh_goc_id AND kg.ma_kenh = 'ZALO'
    JOIN public.dinh_danh_kenh dk
      ON dk.khach_hang_id = hs.khach_hang_id AND dk.kenh_id = kg.id
    WHERE hs.id = p_ho_so_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy định danh Zalo cho hồ sơ %', p_ho_so_id;
    END IF;

    INSERT INTO public.tin_nhan (
        ho_so_id, kenh_id, huong_tin, noi_dung, nhan_vien_id, trang_thai_gui, tao_luc
    ) VALUES (
        p_ho_so_id, v_kenh_id, 'DI', BTRIM(p_noi_dung), p_nhan_vien_id,
        'CHO_GUI', COALESCE(p_now, now())
    ) RETURNING id INTO p_tin_nhan_id;
END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: cau_hinh; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cau_hinh (
    ma_cau_hinh character varying(100) NOT NULL,
    gia_tri character varying(500) NOT NULL,
    mo_ta text,
    cap_nhat_luc timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: cuoc_tro_chuyen; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.cuoc_tro_chuyen (
    id bigint NOT NULL,
    kenh_id bigint NOT NULL,
    ma_nguoi_dung_kenh character varying(255) NOT NULL,
    khach_hang_id bigint,
    ho_so_id bigint,
    tao_luc timestamp with time zone DEFAULT now() NOT NULL,
    cap_nhat_luc timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: cuoc_tro_chuyen_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.cuoc_tro_chuyen ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.cuoc_tro_chuyen_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: dinh_danh_kenh; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dinh_danh_kenh (
    id bigint NOT NULL,
    khach_hang_id bigint NOT NULL,
    kenh_id bigint NOT NULL,
    ma_nguoi_dung_kenh character varying(255) NOT NULL,
    ten_hien_thi character varying(200),
    tao_luc timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: dinh_danh_kenh_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.dinh_danh_kenh ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.dinh_danh_kenh_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: flyway_schema_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flyway_schema_history (
    installed_rank integer NOT NULL,
    version character varying(50),
    description character varying(200) NOT NULL,
    type character varying(20) NOT NULL,
    script character varying(1000) NOT NULL,
    checksum integer,
    installed_by character varying(100) NOT NULL,
    installed_on timestamp without time zone DEFAULT now() NOT NULL,
    execution_time integer NOT NULL,
    success boolean NOT NULL
);


--
-- Name: ho_so; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ho_so (
    id bigint NOT NULL,
    ma_ho_so character varying(30) NOT NULL,
    khach_hang_id bigint NOT NULL,
    serial character varying(100),
    kenh_goc_id bigint NOT NULL,
    mo_ta_loi text NOT NULL,
    ngay_tiep_nhan timestamp with time zone DEFAULT now() NOT NULL,
    trang_thai character varying(40) NOT NULL,
    ket_qua_xac_minh text,
    ly_do_tu_choi text,
    ket_luan_xu_ly text,
    bat_dau_cho_khach_luc timestamp with time zone,
    ngay_dong timestamp with time zone,
    version bigint DEFAULT 0 NOT NULL,
    tao_luc timestamp with time zone DEFAULT now() NOT NULL,
    serial_khach_khai_bao character varying(100),
    ngoai_bao_hanh boolean DEFAULT false NOT NULL,
    CONSTRAINT ho_so_check CHECK (((((trang_thai)::text = 'CHO_KHACH_BO_SUNG'::text) AND (bat_dau_cho_khach_luc IS NOT NULL)) OR ((trang_thai)::text <> 'CHO_KHACH_BO_SUNG'::text))),
    CONSTRAINT ho_so_trang_thai_check CHECK (((trang_thai)::text = ANY (ARRAY[('MOI'::character varying)::text, ('DANG_XAC_MINH'::character varying)::text, ('CHO_KHACH_BO_SUNG'::character varying)::text, ('CHO_PHAN_CONG'::character varying)::text, ('DANG_SUA_CHUA'::character varying)::text, ('DA_SUA_XONG'::character varying)::text, ('TU_CHOI'::character varying)::text, ('DA_DONG'::character varying)::text, ('CHO_CSKH_XU_LY'::character varying)::text])))
);


--
-- Name: ho_so_code_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ho_so_code_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ho_so_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.ho_so ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.ho_so_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: kenh_goc; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.kenh_goc (
    id bigint NOT NULL,
    ma_kenh character varying(30) NOT NULL,
    ten_hien_thi character varying(100) NOT NULL,
    dang_bat boolean DEFAULT true NOT NULL,
    CONSTRAINT kenh_goc_ma_kenh_check CHECK (((ma_kenh)::text = ANY (ARRAY[('WEBSITE'::character varying)::text, ('EMAIL'::character varying)::text, ('FACEBOOK'::character varying)::text, ('ZALO'::character varying)::text])))
);


--
-- Name: kenh_goc_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.kenh_goc ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.kenh_goc_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: khach_hang; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.khach_hang (
    id bigint NOT NULL,
    ho_ten character varying(200),
    so_dien_thoai character varying(30) NOT NULL,
    email character varying(255),
    tao_luc timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: khach_hang_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.khach_hang ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.khach_hang_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: lich_su_xu_ly; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lich_su_xu_ly (
    id bigint NOT NULL,
    ho_so_id bigint NOT NULL,
    trang_thai_tu character varying(40),
    trang_thai_sang character varying(40) NOT NULL,
    loai_tac_nhan character varying(20) NOT NULL,
    nhan_vien_id bigint,
    ghi_chu text,
    tao_luc timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT lich_su_xu_ly_loai_tac_nhan_check CHECK (((loai_tac_nhan)::text = ANY (ARRAY[('NHAN_VIEN'::character varying)::text, ('KHACH_HANG'::character varying)::text, ('HE_THONG'::character varying)::text])))
);


--
-- Name: lich_su_xu_ly_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.lich_su_xu_ly ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.lich_su_xu_ly_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: nhan_vien; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.nhan_vien (
    id bigint NOT NULL,
    tai_khoan_id bigint NOT NULL,
    ho_ten character varying(200) NOT NULL,
    so_dien_thoai character varying(30),
    email character varying(255)
);


--
-- Name: nhan_vien_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.nhan_vien ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.nhan_vien_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: phan_cong; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.phan_cong (
    id bigint NOT NULL,
    ho_so_id bigint NOT NULL,
    ky_thuat_vien_id bigint NOT NULL,
    dieu_phoi_vien_id bigint NOT NULL,
    ngay_phan_cong timestamp with time zone DEFAULT now() NOT NULL,
    ngay_ket_thuc timestamp with time zone,
    ly_do_thay_doi text,
    dang_hieu_luc boolean DEFAULT true NOT NULL
);


--
-- Name: phan_cong_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.phan_cong ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.phan_cong_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: san_pham; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.san_pham (
    serial character varying(100) NOT NULL,
    ten_san_pham character varying(200) NOT NULL,
    ngay_mua date,
    thoi_han_bao_hanh_thang integer,
    ngay_het_han_bao_hanh date,
    CONSTRAINT san_pham_thoi_han_bao_hanh_thang_check CHECK (((thoi_han_bao_hanh_thang IS NULL) OR (thoi_han_bao_hanh_thang >= 0)))
);


--
-- Name: sla; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sla (
    id bigint NOT NULL,
    ho_so_id bigint NOT NULL,
    loai_sla character varying(20) NOT NULL,
    thoi_han_phut integer NOT NULL,
    thoi_diem_bat_dau timestamp with time zone DEFAULT now() NOT NULL,
    thoi_diem_ket_thuc timestamp with time zone,
    thoi_gian_tam_dung_phut bigint DEFAULT 0 NOT NULL,
    thoi_diem_tam_dung timestamp with time zone,
    trang_thai character varying(20) NOT NULL,
    CONSTRAINT ck_sla_trang_thai CHECK (((trang_thai)::text = ANY ((ARRAY['CHUA_BAT_DAU'::character varying, 'DANG_DEM'::character varying, 'TAM_DUNG'::character varying, 'DA_QUA_HAN'::character varying, 'DAT_SLA'::character varying, 'KHONG_DAT_SLA'::character varying])::text[]))),
    CONSTRAINT sla_loai_sla_check CHECK (((loai_sla)::text = ANY (ARRAY[('TIEP_NHAN'::character varying)::text, ('XU_LY'::character varying)::text]))),
    CONSTRAINT sla_thoi_gian_tam_dung_phut_check CHECK ((thoi_gian_tam_dung_phut >= 0)),
    CONSTRAINT sla_thoi_han_phut_check CHECK ((thoi_han_phut > 0))
);


--
-- Name: sla_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.sla ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.sla_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tai_khoan; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tai_khoan (
    id bigint NOT NULL,
    ten_dang_nhap character varying(100) NOT NULL,
    mat_khau_bam character varying(255) NOT NULL,
    vai_tro character varying(30) NOT NULL,
    dang_hoat_dong boolean DEFAULT true NOT NULL,
    tao_luc timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tai_khoan_vai_tro_check CHECK (((vai_tro)::text = ANY (ARRAY[('CSKH'::character varying)::text, ('DIEU_PHOI_VIEN'::character varying)::text, ('KY_THUAT_VIEN'::character varying)::text])))
);


--
-- Name: tai_khoan_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.tai_khoan ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tai_khoan_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: thong_bao; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.thong_bao (
    id bigint NOT NULL,
    ho_so_id bigint,
    nhan_vien_nhan_id bigint NOT NULL,
    khoa_chong_trung character varying(255) NOT NULL,
    tieu_de character varying(255) NOT NULL,
    noi_dung text NOT NULL,
    loai_thong_bao character varying(40) NOT NULL,
    da_doc boolean DEFAULT false NOT NULL,
    tao_luc timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: thong_bao_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.thong_bao ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.thong_bao_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tien_do_sua_chua; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tien_do_sua_chua (
    id bigint NOT NULL,
    phan_cong_id bigint NOT NULL,
    trang_thai character varying(30) NOT NULL,
    ghi_chu text,
    de_xuat_linh_kien text,
    tao_luc timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tien_do_sua_chua_trang_thai_check CHECK (((trang_thai)::text = ANY (ARRAY[('DA_NHAN_THIET_BI'::character varying)::text, ('DANG_KIEM_TRA'::character varying)::text, ('DANG_SUA_CHUA'::character varying)::text, ('CHO_LINH_KIEN'::character varying)::text, ('DANG_KIEM_TRA_LAI'::character varying)::text, ('DA_SUA_XONG'::character varying)::text, ('KHONG_THE_SUA'::character varying)::text])))
);


--
-- Name: tien_do_sua_chua_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.tien_do_sua_chua ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tien_do_sua_chua_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tin_nhan; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tin_nhan (
    id bigint NOT NULL,
    ho_so_id bigint NOT NULL,
    kenh_id bigint NOT NULL,
    ma_tin_goc character varying(255),
    huong_tin character varying(10) NOT NULL,
    noi_dung text NOT NULL,
    nhan_vien_id bigint,
    trang_thai_gui character varying(20) DEFAULT 'KHONG_AP_DUNG'::character varying NOT NULL,
    gui_luc timestamp with time zone,
    tao_luc timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tin_nhan_huong_tin_check CHECK (((huong_tin)::text = ANY (ARRAY[('DEN'::character varying)::text, ('DI'::character varying)::text]))),
    CONSTRAINT tin_nhan_trang_thai_gui_check CHECK (((trang_thai_gui)::text = ANY (ARRAY[('KHONG_AP_DUNG'::character varying)::text, ('CHO_GUI'::character varying)::text, ('DA_GUI'::character varying)::text, ('THAT_BAI'::character varying)::text])))
);


--
-- Name: tin_nhan_cho_bo_sung; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tin_nhan_cho_bo_sung (
    id bigint NOT NULL,
    kenh_id bigint NOT NULL,
    ma_tin_goc character varying(255) NOT NULL,
    ma_nguoi_dung_kenh character varying(255) NOT NULL,
    noi_dung text NOT NULL,
    ho_so_id bigint,
    ly_do character varying(40) NOT NULL,
    trang_thai character varying(30) DEFAULT 'CHO_BO_SUNG'::character varying NOT NULL,
    nhan_luc timestamp with time zone DEFAULT now() NOT NULL,
    tao_luc timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tin_nhan_cho_bo_sung_trang_thai_check CHECK (((trang_thai)::text = ANY ((ARRAY['CHO_BO_SUNG'::character varying, 'DA_GAN_HO_SO'::character varying, 'DA_DONG'::character varying])::text[])))
);


--
-- Name: tin_nhan_cho_bo_sung_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.tin_nhan_cho_bo_sung ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tin_nhan_cho_bo_sung_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tin_nhan_cuoc_tro_chuyen; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tin_nhan_cuoc_tro_chuyen (
    id bigint NOT NULL,
    cuoc_tro_chuyen_id bigint NOT NULL,
    ho_so_id bigint,
    ma_tin_goc character varying(255),
    huong_tin character varying(10) NOT NULL,
    noi_dung text NOT NULL,
    trang_thai_gui character varying(20) DEFAULT 'KHONG_AP_DUNG'::character varying NOT NULL,
    nhan_vien_id bigint,
    tao_luc timestamp with time zone DEFAULT now() NOT NULL,
    gui_luc timestamp with time zone,
    CONSTRAINT tin_nhan_cuoc_tro_chuyen_huong_tin_check CHECK (((huong_tin)::text = ANY ((ARRAY['DEN'::character varying, 'DI'::character varying])::text[]))),
    CONSTRAINT tin_nhan_cuoc_tro_chuyen_trang_thai_gui_check CHECK (((trang_thai_gui)::text = ANY ((ARRAY['KHONG_AP_DUNG'::character varying, 'CHO_GUI'::character varying, 'DA_GUI'::character varying, 'THAT_BAI'::character varying])::text[])))
);


--
-- Name: tin_nhan_cuoc_tro_chuyen_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.tin_nhan_cuoc_tro_chuyen ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tin_nhan_cuoc_tro_chuyen_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: tin_nhan_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.tin_nhan ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.tin_nhan_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: v_cuoc_tro_chuyen; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_cuoc_tro_chuyen AS
 SELECT c.id,
    kg.ma_kenh,
    c.ma_nguoi_dung_kenh,
    c.khach_hang_id,
    c.ho_so_id,
    c.cap_nhat_luc,
    ( SELECT m.noi_dung
           FROM public.tin_nhan_cuoc_tro_chuyen m
          WHERE (m.cuoc_tro_chuyen_id = c.id)
          ORDER BY m.tao_luc DESC, m.id DESC
         LIMIT 1) AS tin_moi_nhat,
    kh.ho_ten AS ten_khach_hang,
    kh.so_dien_thoai
   FROM ((public.cuoc_tro_chuyen c
     JOIN public.kenh_goc kg ON ((kg.id = c.kenh_id)))
     LEFT JOIN public.khach_hang kh ON ((kh.id = c.khach_hang_id)));


--
-- Name: v_ho_so_facebook; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_ho_so_facebook AS
 SELECT DISTINCT hs.id AS ho_so_id
   FROM ((public.ho_so hs
     JOIN public.kenh_goc kg ON (((kg.id = hs.kenh_goc_id) AND ((kg.ma_kenh)::text = 'FACEBOOK'::text))))
     JOIN public.dinh_danh_kenh dk ON (((dk.khach_hang_id = hs.khach_hang_id) AND (dk.kenh_id = kg.id))));


--
-- Name: v_ho_so_khach_hang; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_ho_so_khach_hang AS
 SELECT hs.id AS ho_so_id,
    kh.ho_ten AS ten_khach_hang,
    kh.so_dien_thoai
   FROM (public.ho_so hs
     JOIN public.khach_hang kh ON ((kh.id = hs.khach_hang_id)));


--
-- Name: v_ho_so_ky_thuat_vien; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_ho_so_ky_thuat_vien AS
 SELECT pc.id AS phan_cong_id,
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
   FROM (((public.phan_cong pc
     JOIN public.ho_so hs ON ((hs.id = pc.ho_so_id)))
     JOIN public.khach_hang kh ON ((kh.id = hs.khach_hang_id)))
     LEFT JOIN LATERAL ( SELECT t.trang_thai,
            t.ghi_chu,
            t.de_xuat_linh_kien,
            t.tao_luc
           FROM public.tien_do_sua_chua t
          WHERE (t.phan_cong_id = pc.id)
          ORDER BY t.tao_luc DESC, t.id DESC
         LIMIT 1) td ON (true))
  WHERE ((pc.dang_hieu_luc = true) AND ((hs.trang_thai)::text = ANY ((ARRAY['CHO_PHAN_CONG'::character varying, 'DANG_SUA_CHUA'::character varying, 'DA_SUA_XONG'::character varying])::text[])));


--
-- Name: v_ho_so_mo_theo_dinh_danh_kenh; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_ho_so_mo_theo_dinh_danh_kenh AS
SELECT
    NULL::character varying(30) AS ma_kenh,
    NULL::boolean AS dang_bat,
    NULL::character varying(255) AS ma_nguoi_dung_kenh,
    NULL::integer AS so_ho_so_mo,
    NULL::bigint AS ho_so_id,
    NULL::text AS ma_ho_so;


--
-- Name: v_ho_so_zalo; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_ho_so_zalo AS
 SELECT DISTINCT hs.id AS ho_so_id
   FROM ((public.ho_so hs
     JOIN public.kenh_goc kg ON (((kg.id = hs.kenh_goc_id) AND ((kg.ma_kenh)::text = 'ZALO'::text))))
     JOIN public.dinh_danh_kenh dk ON (((dk.khach_hang_id = hs.khach_hang_id) AND (dk.kenh_id = kg.id))));


--
-- Name: v_kenh_tich_hop; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_kenh_tich_hop AS
 SELECT ma_kenh,
    dang_bat
   FROM public.kenh_goc;


--
-- Name: v_san_pham; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_san_pham AS
 SELECT serial,
    ten_san_pham,
    ngay_mua,
    thoi_han_bao_hanh_thang,
    ngay_het_han_bao_hanh,
        CASE
            WHEN (ngay_het_han_bao_hanh IS NULL) THEN 'CHUA_XAC_DINH'::text
            WHEN (ngay_het_han_bao_hanh >= CURRENT_DATE) THEN 'CON_HAN'::text
            ELSE 'HET_HAN'::text
        END AS trang_thai_bao_hanh,
        CASE
            WHEN (ngay_het_han_bao_hanh >= CURRENT_DATE) THEN (ngay_het_han_bao_hanh - CURRENT_DATE)
            ELSE 0
        END AS so_ngay_con_lai
   FROM public.san_pham sp;


--
-- Name: v_sla_ho_so; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_sla_ho_so AS
 WITH han AS (
         SELECT s.id AS sla_id,
            s.ho_so_id,
            s.loai_sla,
            s.thoi_han_phut,
            s.trang_thai,
                CASE
                    WHEN ((s.trang_thai)::text = 'CHUA_BAT_DAU'::text) THEN NULL::timestamp with time zone
                    ELSE (s.thoi_diem_bat_dau + (((((s.thoi_han_phut)::bigint + s.thoi_gian_tam_dung_phut) +
                    CASE
                        WHEN (((s.trang_thai)::text = 'TAM_DUNG'::text) AND (s.thoi_diem_tam_dung IS NOT NULL)) THEN GREATEST((0)::bigint, (floor((EXTRACT(epoch FROM (now() - s.thoi_diem_tam_dung)) / (60)::numeric)))::bigint)
                        ELSE (0)::bigint
                    END))::double precision * '00:01:00'::interval))
                END AS thoi_diem_den_han
           FROM public.sla s
        ), con_lai AS (
         SELECT h.sla_id,
            h.ho_so_id,
            h.loai_sla,
            h.thoi_han_phut,
            h.trang_thai,
            h.thoi_diem_den_han,
            (ceil((EXTRACT(epoch FROM (h.thoi_diem_den_han - now())) / (60)::numeric)))::bigint AS phut_con_lai,
            COALESCE(( SELECT (cau_hinh.gia_tri)::numeric AS gia_tri
                   FROM public.cau_hinh
                  WHERE ((cau_hinh.ma_cau_hinh)::text = 'canh_bao_phan_tram'::text)), (20)::numeric) AS nguong_canh_bao
           FROM han h
        )
 SELECT sla_id,
    ho_so_id,
    loai_sla,
    trang_thai,
    phut_con_lai,
    to_char((thoi_diem_den_han AT TIME ZONE 'Asia/Ho_Chi_Minh'::text), 'DD/MM/YYYY HH24:MI'::text) AS den_han_luc,
        CASE
            WHEN ((trang_thai)::text = 'CHUA_BAT_DAU'::text) THEN 'CHUA_BAT_DAU'::text
            WHEN ((trang_thai)::text = 'TAM_DUNG'::text) THEN 'TAM_DUNG'::text
            WHEN ((trang_thai)::text = 'DAT_SLA'::text) THEN 'DAT_SLA'::text
            WHEN ((trang_thai)::text = 'KHONG_DAT_SLA'::text) THEN 'KHONG_DAT_SLA'::text
            WHEN (((trang_thai)::text = 'DA_QUA_HAN'::text) OR (phut_con_lai <= 0)) THEN 'QUA_HAN'::text
            WHEN ((phut_con_lai)::numeric <= ceil((((thoi_han_phut)::numeric * nguong_canh_bao) / (100)::numeric))) THEN 'SAP_DEN_HAN'::text
            ELSE 'DANG_CON_HAN'::text
        END AS nhan_trang_thai,
        CASE
            WHEN ((trang_thai)::text = 'CHUA_BAT_DAU'::text) THEN 'Chưa bắt đầu'::text
            WHEN ((trang_thai)::text = 'TAM_DUNG'::text) THEN 'Đang tạm dừng'::text
            WHEN ((trang_thai)::text = 'DAT_SLA'::text) THEN 'Hoàn tất đúng hạn'::text
            WHEN ((trang_thai)::text = 'KHONG_DAT_SLA'::text) THEN 'Hoàn tất trễ hạn'::text
            WHEN (((trang_thai)::text = 'DA_QUA_HAN'::text) OR (phut_con_lai <= 0)) THEN (('Quá hạn '::text || (ceil(((abs(phut_con_lai))::numeric / 60.0)))::integer) || ' giờ'::text)
            WHEN (phut_con_lai >= 1440) THEN (('Còn '::text || (floor(((phut_con_lai)::numeric / 1440.0)))::integer) || ' ngày'::text)
            WHEN (phut_con_lai >= 60) THEN (('Còn '::text || (floor(((phut_con_lai)::numeric / 60.0)))::integer) || ' giờ'::text)
            ELSE (('Còn '::text || (phut_con_lai)::integer) || ' phút'::text)
        END AS thoi_gian_hien_thi
   FROM con_lai;


--
-- Name: v_sla_dashboard; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_sla_dashboard AS
 SELECT s.ho_so_id,
    hs.ma_ho_so,
    hs.trang_thai AS trang_thai_ho_so,
    hs.mo_ta_loi,
    kh.ho_ten AS ten_khach_hang,
    s.loai_sla,
    s.nhan_trang_thai,
    s.thoi_gian_hien_thi,
    s.den_han_luc,
    s.phut_con_lai,
    ktv.ho_ten AS ky_thuat_vien
   FROM (((public.v_sla_ho_so s
     JOIN public.ho_so hs ON ((hs.id = s.ho_so_id)))
     JOIN public.khach_hang kh ON ((kh.id = hs.khach_hang_id)))
     LEFT JOIN LATERAL ( SELECT nv.ho_ten
           FROM (public.phan_cong pc
             JOIN public.nhan_vien nv ON ((nv.id = pc.ky_thuat_vien_id)))
          WHERE ((pc.ho_so_id = hs.id) AND (pc.dang_hieu_luc = true))
          ORDER BY pc.ngay_phan_cong DESC, pc.id DESC
         LIMIT 1) ktv ON (true));


--
-- Name: v_sla_service; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_sla_service AS
 SELECT s.id AS sla_id,
    s.ho_so_id,
    h.ma_ho_so,
    s.loai_sla,
    s.thoi_han_phut,
    s.thoi_diem_bat_dau,
    s.thoi_diem_ket_thuc,
    s.thoi_gian_tam_dung_phut,
    s.thoi_diem_tam_dung,
    s.trang_thai,
    COALESCE(( SELECT (c.gia_tri)::numeric AS gia_tri
           FROM public.cau_hinh c
          WHERE ((c.ma_cau_hinh)::text = 'canh_bao_phan_tram'::text)), (20)::numeric) AS nguong_canh_bao,
    q.nhan_vien_id AS nguoi_quan_ly_id
   FROM ((public.sla s
     JOIN public.ho_so h ON ((h.id = s.ho_so_id)))
     LEFT JOIN LATERAL ( SELECT nv.id AS nhan_vien_id
           FROM (public.nhan_vien nv
             JOIN public.tai_khoan tk ON ((tk.id = nv.tai_khoan_id)))
          WHERE (((tk.vai_tro)::text = 'DIEU_PHOI_VIEN'::text) AND (tk.dang_hoat_dong = true))
          ORDER BY nv.id
         LIMIT 1) q ON (true));


--
-- Name: v_tai_ky_thuat_vien; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_tai_ky_thuat_vien AS
 SELECT nv.id AS ky_thuat_vien_id,
    nv.ho_ten,
    tk.ten_dang_nhap,
    (count(pc.id) FILTER (WHERE ((hs.trang_thai)::text = ANY ((ARRAY['CHO_PHAN_CONG'::character varying, 'DANG_SUA_CHUA'::character varying])::text[]))))::integer AS so_ho_so_dang_xu_ly,
    COALESCE(( SELECT (cau_hinh.gia_tri)::integer AS gia_tri
           FROM public.cau_hinh
          WHERE ((cau_hinh.ma_cau_hinh)::text = 'toi_da_ho_so_ky_thuat_vien'::text)), 5) AS gioi_han_ho_so
   FROM (((public.nhan_vien nv
     JOIN public.tai_khoan tk ON ((tk.id = nv.tai_khoan_id)))
     LEFT JOIN public.phan_cong pc ON (((pc.ky_thuat_vien_id = nv.id) AND (pc.dang_hieu_luc = true))))
     LEFT JOIN public.ho_so hs ON ((hs.id = pc.ho_so_id)))
  WHERE (((tk.vai_tro)::text = 'KY_THUAT_VIEN'::text) AND (tk.dang_hoat_dong = true))
  GROUP BY nv.id, nv.ho_ten, tk.ten_dang_nhap;


--
-- Name: v_tin_nhan_cuoc_tro_chuyen; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_tin_nhan_cuoc_tro_chuyen AS
 SELECT m.id,
    m.cuoc_tro_chuyen_id,
    m.ho_so_id,
    m.ma_tin_goc,
    m.huong_tin,
    m.noi_dung,
    m.trang_thai_gui,
    m.tao_luc,
    m.gui_luc,
    kg.ma_kenh
   FROM ((public.tin_nhan_cuoc_tro_chuyen m
     JOIN public.cuoc_tro_chuyen c ON ((c.id = m.cuoc_tro_chuyen_id)))
     JOIN public.kenh_goc kg ON ((kg.id = c.kenh_id)));


--
-- Name: v_tin_nhan_facebook; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_tin_nhan_facebook AS
 SELECT tn.ho_so_id,
    tn.huong_tin,
    tn.noi_dung,
    tn.trang_thai_gui,
    tn.tao_luc,
    tn.gui_luc
   FROM (public.tin_nhan tn
     JOIN public.kenh_goc kg ON ((kg.id = tn.kenh_id)))
  WHERE ((kg.ma_kenh)::text = 'FACEBOOK'::text);


--
-- Name: v_tin_nhan_kenh_goc; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_tin_nhan_kenh_goc AS
 SELECT kg.ma_kenh,
    tn.ma_tin_goc,
    tn.ho_so_id,
    hs.ma_ho_so
   FROM ((public.tin_nhan tn
     JOIN public.kenh_goc kg ON ((kg.id = tn.kenh_id)))
     JOIN public.ho_so hs ON ((hs.id = tn.ho_so_id)));


--
-- Name: v_tin_nhan_zalo; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_tin_nhan_zalo AS
 SELECT tn.ho_so_id,
    tn.huong_tin,
    tn.noi_dung,
    tn.trang_thai_gui,
    tn.tao_luc,
    tn.gui_luc
   FROM (public.tin_nhan tn
     JOIN public.kenh_goc kg ON ((kg.id = tn.kenh_id)))
  WHERE ((kg.ma_kenh)::text = 'ZALO'::text);


--
-- Name: vi_pham_sla; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vi_pham_sla (
    id bigint NOT NULL,
    sla_id bigint NOT NULL,
    thoi_diem_phat_hien timestamp with time zone DEFAULT now() NOT NULL,
    muc_do character varying(30) NOT NULL,
    noi_dung text,
    da_xu_ly boolean DEFAULT false NOT NULL,
    nhan_vien_xu_ly_id bigint
);


--
-- Name: vi_pham_sla_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

ALTER TABLE public.vi_pham_sla ALTER COLUMN id ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME public.vi_pham_sla_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: cau_hinh cau_hinh_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cau_hinh
    ADD CONSTRAINT cau_hinh_pkey PRIMARY KEY (ma_cau_hinh);


--
-- Name: cuoc_tro_chuyen cuoc_tro_chuyen_kenh_id_ma_nguoi_dung_kenh_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cuoc_tro_chuyen
    ADD CONSTRAINT cuoc_tro_chuyen_kenh_id_ma_nguoi_dung_kenh_key UNIQUE (kenh_id, ma_nguoi_dung_kenh);


--
-- Name: cuoc_tro_chuyen cuoc_tro_chuyen_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cuoc_tro_chuyen
    ADD CONSTRAINT cuoc_tro_chuyen_pkey PRIMARY KEY (id);


--
-- Name: dinh_danh_kenh dinh_danh_kenh_kenh_id_ma_nguoi_dung_kenh_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dinh_danh_kenh
    ADD CONSTRAINT dinh_danh_kenh_kenh_id_ma_nguoi_dung_kenh_key UNIQUE (kenh_id, ma_nguoi_dung_kenh);


--
-- Name: dinh_danh_kenh dinh_danh_kenh_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dinh_danh_kenh
    ADD CONSTRAINT dinh_danh_kenh_pkey PRIMARY KEY (id);


--
-- Name: flyway_schema_history flyway_schema_history_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.flyway_schema_history
    ADD CONSTRAINT flyway_schema_history_pk PRIMARY KEY (installed_rank);


--
-- Name: ho_so ho_so_ma_ho_so_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ho_so
    ADD CONSTRAINT ho_so_ma_ho_so_key UNIQUE (ma_ho_so);


--
-- Name: ho_so ho_so_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ho_so
    ADD CONSTRAINT ho_so_pkey PRIMARY KEY (id);


--
-- Name: kenh_goc kenh_goc_ma_kenh_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kenh_goc
    ADD CONSTRAINT kenh_goc_ma_kenh_key UNIQUE (ma_kenh);


--
-- Name: kenh_goc kenh_goc_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.kenh_goc
    ADD CONSTRAINT kenh_goc_pkey PRIMARY KEY (id);


--
-- Name: khach_hang khach_hang_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.khach_hang
    ADD CONSTRAINT khach_hang_pkey PRIMARY KEY (id);


--
-- Name: khach_hang khach_hang_so_dien_thoai_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.khach_hang
    ADD CONSTRAINT khach_hang_so_dien_thoai_key UNIQUE (so_dien_thoai);


--
-- Name: lich_su_xu_ly lich_su_xu_ly_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lich_su_xu_ly
    ADD CONSTRAINT lich_su_xu_ly_pkey PRIMARY KEY (id);


--
-- Name: nhan_vien nhan_vien_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nhan_vien
    ADD CONSTRAINT nhan_vien_pkey PRIMARY KEY (id);


--
-- Name: nhan_vien nhan_vien_tai_khoan_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nhan_vien
    ADD CONSTRAINT nhan_vien_tai_khoan_id_key UNIQUE (tai_khoan_id);


--
-- Name: phan_cong phan_cong_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phan_cong
    ADD CONSTRAINT phan_cong_pkey PRIMARY KEY (id);


--
-- Name: san_pham san_pham_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.san_pham
    ADD CONSTRAINT san_pham_pkey PRIMARY KEY (serial);


--
-- Name: sla sla_ho_so_id_loai_sla_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla
    ADD CONSTRAINT sla_ho_so_id_loai_sla_key UNIQUE (ho_so_id, loai_sla);


--
-- Name: sla sla_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla
    ADD CONSTRAINT sla_pkey PRIMARY KEY (id);


--
-- Name: tai_khoan tai_khoan_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tai_khoan
    ADD CONSTRAINT tai_khoan_pkey PRIMARY KEY (id);


--
-- Name: tai_khoan tai_khoan_ten_dang_nhap_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tai_khoan
    ADD CONSTRAINT tai_khoan_ten_dang_nhap_key UNIQUE (ten_dang_nhap);


--
-- Name: thong_bao thong_bao_khoa_chong_trung_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.thong_bao
    ADD CONSTRAINT thong_bao_khoa_chong_trung_key UNIQUE (khoa_chong_trung);


--
-- Name: thong_bao thong_bao_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.thong_bao
    ADD CONSTRAINT thong_bao_pkey PRIMARY KEY (id);


--
-- Name: tien_do_sua_chua tien_do_sua_chua_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tien_do_sua_chua
    ADD CONSTRAINT tien_do_sua_chua_pkey PRIMARY KEY (id);


--
-- Name: tin_nhan_cho_bo_sung tin_nhan_cho_bo_sung_kenh_id_ma_tin_goc_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tin_nhan_cho_bo_sung
    ADD CONSTRAINT tin_nhan_cho_bo_sung_kenh_id_ma_tin_goc_key UNIQUE (kenh_id, ma_tin_goc);


--
-- Name: tin_nhan_cho_bo_sung tin_nhan_cho_bo_sung_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tin_nhan_cho_bo_sung
    ADD CONSTRAINT tin_nhan_cho_bo_sung_pkey PRIMARY KEY (id);


--
-- Name: tin_nhan_cuoc_tro_chuyen tin_nhan_cuoc_tro_chuyen_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tin_nhan_cuoc_tro_chuyen
    ADD CONSTRAINT tin_nhan_cuoc_tro_chuyen_pkey PRIMARY KEY (id);


--
-- Name: tin_nhan tin_nhan_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tin_nhan
    ADD CONSTRAINT tin_nhan_pkey PRIMARY KEY (id);


--
-- Name: vi_pham_sla vi_pham_sla_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vi_pham_sla
    ADD CONSTRAINT vi_pham_sla_pkey PRIMARY KEY (id);


--
-- Name: vi_pham_sla vi_pham_sla_sla_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vi_pham_sla
    ADD CONSTRAINT vi_pham_sla_sla_id_key UNIQUE (sla_id);


--
-- Name: flyway_schema_history_s_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flyway_schema_history_s_idx ON public.flyway_schema_history USING btree (success);


--
-- Name: idx_ho_so_khach_kenh_trang_thai; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_ho_so_khach_kenh_trang_thai ON public.ho_so USING btree (khach_hang_id, kenh_goc_id, trang_thai, ngay_tiep_nhan DESC);


--
-- Name: idx_phan_cong_ky_thuat_vien_hieu_luc; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_phan_cong_ky_thuat_vien_hieu_luc ON public.phan_cong USING btree (ky_thuat_vien_id, dang_hieu_luc);


--
-- Name: idx_tin_nhan_cho_bo_sung_moi_nhat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tin_nhan_cho_bo_sung_moi_nhat ON public.tin_nhan_cho_bo_sung USING btree (trang_thai, nhan_luc DESC);


--
-- Name: idx_tin_nhan_cuoc_tro_chuyen_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tin_nhan_cuoc_tro_chuyen_time ON public.tin_nhan_cuoc_tro_chuyen USING btree (cuoc_tro_chuyen_id, tao_luc);


--
-- Name: idx_tin_nhan_ho_so_thoi_gian; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tin_nhan_ho_so_thoi_gian ON public.tin_nhan USING btree (ho_so_id, tao_luc);


--
-- Name: uq_phan_cong_dang_hieu_luc_ho_so; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_phan_cong_dang_hieu_luc_ho_so ON public.phan_cong USING btree (ho_so_id) WHERE (dang_hieu_luc = true);


--
-- Name: uq_tin_nhan_cuoc_tro_chuyen_external; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_tin_nhan_cuoc_tro_chuyen_external ON public.tin_nhan_cuoc_tro_chuyen USING btree (cuoc_tro_chuyen_id, ma_tin_goc) WHERE (ma_tin_goc IS NOT NULL);


--
-- Name: uq_tin_nhan_kenh_ma_goc; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_tin_nhan_kenh_ma_goc ON public.tin_nhan USING btree (kenh_id, ma_tin_goc) WHERE (ma_tin_goc IS NOT NULL);


--
-- Name: v_ho_so_mo_theo_dinh_danh_kenh _RETURN; Type: RULE; Schema: public; Owner: -
--

CREATE OR REPLACE VIEW public.v_ho_so_mo_theo_dinh_danh_kenh AS
 SELECT kg.ma_kenh,
    kg.dang_bat,
    dk.ma_nguoi_dung_kenh,
    (count(hs.id) FILTER (WHERE ((hs.trang_thai)::text <> ALL ((ARRAY['DA_DONG'::character varying, 'TU_CHOI'::character varying])::text[]))))::integer AS so_ho_so_mo,
    min(hs.id) FILTER (WHERE ((hs.trang_thai)::text <> ALL ((ARRAY['DA_DONG'::character varying, 'TU_CHOI'::character varying])::text[]))) AS ho_so_id,
    min((hs.ma_ho_so)::text) FILTER (WHERE ((hs.trang_thai)::text <> ALL ((ARRAY['DA_DONG'::character varying, 'TU_CHOI'::character varying])::text[]))) AS ma_ho_so
   FROM ((public.kenh_goc kg
     LEFT JOIN public.dinh_danh_kenh dk ON ((dk.kenh_id = kg.id)))
     LEFT JOIN public.ho_so hs ON (((hs.khach_hang_id = dk.khach_hang_id) AND (hs.kenh_goc_id = kg.id))))
  GROUP BY kg.id, dk.id;


--
-- Name: ho_so trg_ho_so_ghi_lich_su_chuyen_trang_thai; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ho_so_ghi_lich_su_chuyen_trang_thai AFTER UPDATE OF trang_thai ON public.ho_so FOR EACH ROW EXECUTE FUNCTION public.fn_ho_so_ghi_lich_su_chuyen_trang_thai();


--
-- Name: ho_so trg_ho_so_ghi_lich_su_tao; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_ho_so_ghi_lich_su_tao AFTER INSERT ON public.ho_so FOR EACH ROW EXECUTE FUNCTION public.fn_ho_so_ghi_lich_su_tao();


--
-- Name: cuoc_tro_chuyen cuoc_tro_chuyen_ho_so_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cuoc_tro_chuyen
    ADD CONSTRAINT cuoc_tro_chuyen_ho_so_id_fkey FOREIGN KEY (ho_so_id) REFERENCES public.ho_so(id);


--
-- Name: cuoc_tro_chuyen cuoc_tro_chuyen_kenh_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cuoc_tro_chuyen
    ADD CONSTRAINT cuoc_tro_chuyen_kenh_id_fkey FOREIGN KEY (kenh_id) REFERENCES public.kenh_goc(id);


--
-- Name: cuoc_tro_chuyen cuoc_tro_chuyen_khach_hang_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.cuoc_tro_chuyen
    ADD CONSTRAINT cuoc_tro_chuyen_khach_hang_id_fkey FOREIGN KEY (khach_hang_id) REFERENCES public.khach_hang(id);


--
-- Name: dinh_danh_kenh dinh_danh_kenh_kenh_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dinh_danh_kenh
    ADD CONSTRAINT dinh_danh_kenh_kenh_id_fkey FOREIGN KEY (kenh_id) REFERENCES public.kenh_goc(id);


--
-- Name: dinh_danh_kenh dinh_danh_kenh_khach_hang_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dinh_danh_kenh
    ADD CONSTRAINT dinh_danh_kenh_khach_hang_id_fkey FOREIGN KEY (khach_hang_id) REFERENCES public.khach_hang(id);


--
-- Name: ho_so ho_so_kenh_goc_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ho_so
    ADD CONSTRAINT ho_so_kenh_goc_id_fkey FOREIGN KEY (kenh_goc_id) REFERENCES public.kenh_goc(id);


--
-- Name: ho_so ho_so_khach_hang_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ho_so
    ADD CONSTRAINT ho_so_khach_hang_id_fkey FOREIGN KEY (khach_hang_id) REFERENCES public.khach_hang(id);


--
-- Name: ho_so ho_so_serial_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ho_so
    ADD CONSTRAINT ho_so_serial_fkey FOREIGN KEY (serial) REFERENCES public.san_pham(serial);


--
-- Name: lich_su_xu_ly lich_su_xu_ly_ho_so_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lich_su_xu_ly
    ADD CONSTRAINT lich_su_xu_ly_ho_so_id_fkey FOREIGN KEY (ho_so_id) REFERENCES public.ho_so(id);


--
-- Name: lich_su_xu_ly lich_su_xu_ly_nhan_vien_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lich_su_xu_ly
    ADD CONSTRAINT lich_su_xu_ly_nhan_vien_id_fkey FOREIGN KEY (nhan_vien_id) REFERENCES public.nhan_vien(id);


--
-- Name: nhan_vien nhan_vien_tai_khoan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.nhan_vien
    ADD CONSTRAINT nhan_vien_tai_khoan_id_fkey FOREIGN KEY (tai_khoan_id) REFERENCES public.tai_khoan(id);


--
-- Name: phan_cong phan_cong_dieu_phoi_vien_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phan_cong
    ADD CONSTRAINT phan_cong_dieu_phoi_vien_id_fkey FOREIGN KEY (dieu_phoi_vien_id) REFERENCES public.nhan_vien(id);


--
-- Name: phan_cong phan_cong_ho_so_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phan_cong
    ADD CONSTRAINT phan_cong_ho_so_id_fkey FOREIGN KEY (ho_so_id) REFERENCES public.ho_so(id);


--
-- Name: phan_cong phan_cong_ky_thuat_vien_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.phan_cong
    ADD CONSTRAINT phan_cong_ky_thuat_vien_id_fkey FOREIGN KEY (ky_thuat_vien_id) REFERENCES public.nhan_vien(id);


--
-- Name: sla sla_ho_so_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sla
    ADD CONSTRAINT sla_ho_so_id_fkey FOREIGN KEY (ho_so_id) REFERENCES public.ho_so(id);


--
-- Name: thong_bao thong_bao_ho_so_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.thong_bao
    ADD CONSTRAINT thong_bao_ho_so_id_fkey FOREIGN KEY (ho_so_id) REFERENCES public.ho_so(id);


--
-- Name: thong_bao thong_bao_nhan_vien_nhan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.thong_bao
    ADD CONSTRAINT thong_bao_nhan_vien_nhan_id_fkey FOREIGN KEY (nhan_vien_nhan_id) REFERENCES public.nhan_vien(id);


--
-- Name: tien_do_sua_chua tien_do_sua_chua_phan_cong_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tien_do_sua_chua
    ADD CONSTRAINT tien_do_sua_chua_phan_cong_id_fkey FOREIGN KEY (phan_cong_id) REFERENCES public.phan_cong(id);


--
-- Name: tin_nhan_cho_bo_sung tin_nhan_cho_bo_sung_ho_so_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tin_nhan_cho_bo_sung
    ADD CONSTRAINT tin_nhan_cho_bo_sung_ho_so_id_fkey FOREIGN KEY (ho_so_id) REFERENCES public.ho_so(id);


--
-- Name: tin_nhan_cho_bo_sung tin_nhan_cho_bo_sung_kenh_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tin_nhan_cho_bo_sung
    ADD CONSTRAINT tin_nhan_cho_bo_sung_kenh_id_fkey FOREIGN KEY (kenh_id) REFERENCES public.kenh_goc(id);


--
-- Name: tin_nhan_cuoc_tro_chuyen tin_nhan_cuoc_tro_chuyen_cuoc_tro_chuyen_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tin_nhan_cuoc_tro_chuyen
    ADD CONSTRAINT tin_nhan_cuoc_tro_chuyen_cuoc_tro_chuyen_id_fkey FOREIGN KEY (cuoc_tro_chuyen_id) REFERENCES public.cuoc_tro_chuyen(id);


--
-- Name: tin_nhan_cuoc_tro_chuyen tin_nhan_cuoc_tro_chuyen_ho_so_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tin_nhan_cuoc_tro_chuyen
    ADD CONSTRAINT tin_nhan_cuoc_tro_chuyen_ho_so_id_fkey FOREIGN KEY (ho_so_id) REFERENCES public.ho_so(id);


--
-- Name: tin_nhan_cuoc_tro_chuyen tin_nhan_cuoc_tro_chuyen_nhan_vien_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tin_nhan_cuoc_tro_chuyen
    ADD CONSTRAINT tin_nhan_cuoc_tro_chuyen_nhan_vien_id_fkey FOREIGN KEY (nhan_vien_id) REFERENCES public.nhan_vien(id);


--
-- Name: tin_nhan tin_nhan_ho_so_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tin_nhan
    ADD CONSTRAINT tin_nhan_ho_so_id_fkey FOREIGN KEY (ho_so_id) REFERENCES public.ho_so(id);


--
-- Name: tin_nhan tin_nhan_kenh_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tin_nhan
    ADD CONSTRAINT tin_nhan_kenh_id_fkey FOREIGN KEY (kenh_id) REFERENCES public.kenh_goc(id);


--
-- Name: tin_nhan tin_nhan_nhan_vien_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tin_nhan
    ADD CONSTRAINT tin_nhan_nhan_vien_id_fkey FOREIGN KEY (nhan_vien_id) REFERENCES public.nhan_vien(id);


--
-- Name: vi_pham_sla vi_pham_sla_nhan_vien_xu_ly_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vi_pham_sla
    ADD CONSTRAINT vi_pham_sla_nhan_vien_xu_ly_id_fkey FOREIGN KEY (nhan_vien_xu_ly_id) REFERENCES public.nhan_vien(id);


--
-- Name: vi_pham_sla vi_pham_sla_sla_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vi_pham_sla
    ADD CONSTRAINT vi_pham_sla_sla_id_fkey FOREIGN KEY (sla_id) REFERENCES public.sla(id);


--
-- PostgreSQL database dump complete
--

\unrestrict 9O4bIEJQ5bV9cw0qyH7WcUHR96ucih3CYIDqeaapegscbXHsTYhflJNcVL0E1ep

