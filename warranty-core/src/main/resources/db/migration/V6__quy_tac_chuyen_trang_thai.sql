-- Return true only for transitions allowed by the approved workflow.
CREATE FUNCTION fn_cho_phep_chuyen(
    p_tu VARCHAR(40),
    p_den VARCHAR(40)
)
RETURNS BOOLEAN
LANGUAGE SQL
IMMUTABLE
AS $$
    SELECT
        (p_tu = 'MOI' AND p_den = 'DANG_XAC_MINH')
        OR
        (p_tu = 'DANG_XAC_MINH'
            AND p_den IN ('CHO_PHAN_CONG', 'TU_CHOI', 'CHO_KHACH_BO_SUNG'))
        OR
        (p_tu = 'CHO_KHACH_BO_SUNG'
            AND p_den IN ('DANG_XAC_MINH', 'DA_DONG'))
        OR
        (p_tu = 'CHO_PHAN_CONG' AND p_den = 'DANG_SUA_CHUA')
        OR
        (p_tu = 'DANG_SUA_CHUA'
            AND p_den IN ('DA_SUA_XONG', 'CHO_CSKH_XU_LY'))
        OR
        (p_tu IN ('DA_SUA_XONG', 'TU_CHOI', 'CHO_CSKH_XU_LY')
            AND p_den = 'DA_DONG');
$$;

-- Validate transitions and maintain the case's waiting/closed timestamps.
CREATE FUNCTION fn_ho_so_kiem_tra_chuyen_trang_thai()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_now TIMESTAMPTZ;
BEGIN
    IF NEW.trang_thai IS DISTINCT FROM OLD.trang_thai THEN
        IF fn_cho_phep_chuyen(OLD.trang_thai, NEW.trang_thai)
            IS DISTINCT FROM TRUE THEN
            RAISE EXCEPTION
                'Không thể chuyển hồ sơ từ % sang %',
                OLD.trang_thai,
                NEW.trang_thai
                USING ERRCODE = 'HM001';
        END IF;

        v_now := COALESCE(
            NULLIF(current_setting('app.audit_now', TRUE), '')::TIMESTAMPTZ,
            now()
        );

        IF NEW.trang_thai = 'CHO_KHACH_BO_SUNG' THEN
            NEW.bat_dau_cho_khach_luc := v_now;
        ELSIF OLD.trang_thai = 'CHO_KHACH_BO_SUNG' THEN
            NEW.bat_dau_cho_khach_luc := NULL;
        END IF;

        IF NEW.trang_thai = 'DA_DONG' THEN
            NEW.ngay_dong := v_now;
        END IF;

        NEW.version := OLD.version + 1;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ho_so_kiem_tra_chuyen_trang_thai
BEFORE UPDATE OF trang_thai ON ho_so
FOR EACH ROW
EXECUTE FUNCTION fn_ho_so_kiem_tra_chuyen_trang_thai();

-- Record each successful state transition in the case history.
CREATE FUNCTION fn_ho_so_ghi_lich_su_chuyen_trang_thai()
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

        -- Prevent this audit context from leaking to another update
        -- in the same database transaction.
        PERFORM set_config('app.audit_actor_type', '', TRUE);
        PERFORM set_config('app.audit_employee_id', '', TRUE);
        PERFORM set_config('app.audit_note', '', TRUE);
        PERFORM set_config('app.audit_now', '', TRUE);
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_ho_so_ghi_lich_su_chuyen_trang_thai
AFTER UPDATE OF trang_thai ON ho_so
FOR EACH ROW
EXECUTE FUNCTION fn_ho_so_ghi_lich_su_chuyen_trang_thai();

-- This is the application entry point for changing a case state.
CREATE PROCEDURE sp_chuyen_trang_thai(
    IN p_ho_so_id BIGINT,
    IN p_trang_thai_moi VARCHAR(40),
    IN p_loai_tac_nhan VARCHAR(20),
    IN p_nhan_vien_id BIGINT,
    IN p_ghi_chu TEXT,
    IN p_now TIMESTAMPTZ
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_now TIMESTAMPTZ;
BEGIN
    v_now := COALESCE(p_now, now());

    IF p_loai_tac_nhan NOT IN ('NHAN_VIEN', 'KHACH_HANG', 'HE_THONG')
        OR p_loai_tac_nhan IS NULL THEN
        RAISE EXCEPTION 'Loại tác nhân không hợp lệ';
    END IF;

    IF p_loai_tac_nhan = 'NHAN_VIEN' THEN
        IF p_nhan_vien_id IS NULL THEN
            RAISE EXCEPTION 'Thao tác của nhân viên cần có nhan_vien_id';
        END IF;

        PERFORM 1
        FROM nhan_vien
        WHERE id = p_nhan_vien_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Không tìm thấy nhân viên id=%', p_nhan_vien_id;
        END IF;
    ELSIF p_nhan_vien_id IS NOT NULL THEN
        RAISE EXCEPTION
            'Chỉ tác nhân NHAN_VIEN mới được truyền nhan_vien_id';
    END IF;

    PERFORM set_config(
        'app.audit_actor_type',
        p_loai_tac_nhan,
        TRUE
    );

    PERFORM set_config(
        'app.audit_employee_id',
        COALESCE(p_nhan_vien_id::TEXT, ''),
        TRUE
    );

    PERFORM set_config(
        'app.audit_note',
        COALESCE(p_ghi_chu, ''),
        TRUE
    );

    PERFORM set_config(
        'app.audit_now',
        v_now::TEXT,
        TRUE
    );

    UPDATE ho_so
    SET trang_thai = p_trang_thai_moi
    WHERE id = p_ho_so_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Không tìm thấy hồ sơ id=%', p_ho_so_id;
    END IF;
END;
$$;