-- Cho role chủ sở hữu quản lý các object trong schema public.
GRANT CREATE ON SCHEMA public TO hau_mai_owner;
ALTER SCHEMA public OWNER TO hau_mai_owner;

-- Đổi tên các procedure đang có thành entry point nội bộ.
ALTER PROCEDURE public.sp_tao_ho_so_website(
    character varying, character varying, character varying, text, timestamp with time zone
) RENAME TO sp_tao_ho_so_website_impl;

ALTER PROCEDURE public.sp_chuyen_trang_thai(
    bigint, character varying, character varying, bigint, text, timestamp with time zone
) RENAME TO sp_chuyen_trang_thai_impl;

ALTER PROCEDURE public.sp_quet_sla(
    timestamp with time zone
) RENAME TO sp_quet_sla_impl;

-- Chuyển bảng, view, sequence và routine trong public sang role không đăng nhập.
DO $$
DECLARE
    obj RECORD;
BEGIN
    FOR obj IN
        SELECT c.relname, c.relkind
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname <> 'flyway_schema_history'
          AND c.relkind IN ('r', 'p', 'v', 'm', 'S')
          AND (
              c.relkind <> 'S'
              OR NOT EXISTS (
                  SELECT 1
                  FROM pg_depend d
                  WHERE d.classid = 'pg_class'::regclass
                    AND d.objid = c.oid
                    AND d.refclassid = 'pg_class'::regclass
                    AND d.deptype IN ('a', 'i')
              )
          )
    LOOP
        IF obj.relkind = 'S' THEN
            EXECUTE format(
                'ALTER SEQUENCE public.%I OWNER TO hau_mai_owner',
                obj.relname
            );
        ELSIF obj.relkind = 'v' THEN
            EXECUTE format(
                'ALTER VIEW public.%I OWNER TO hau_mai_owner',
                obj.relname
            );
        ELSIF obj.relkind = 'm' THEN
            EXECUTE format(
                'ALTER MATERIALIZED VIEW public.%I OWNER TO hau_mai_owner',
                obj.relname
            );
        ELSE
            EXECUTE format(
                'ALTER TABLE public.%I OWNER TO hau_mai_owner',
                obj.relname
            );
        END IF;
    END LOOP;

    FOR obj IN
        SELECT p.proname,
               pg_get_function_identity_arguments(p.oid) AS args
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'public'
          AND NOT EXISTS (
              SELECT 1
              FROM pg_depend d
              WHERE d.classid = 'pg_proc'::regclass
                AND d.objid = p.oid
                AND d.deptype = 'e'
          )
    LOOP
        EXECUTE format(
            'ALTER ROUTINE public.%I(%s) OWNER TO hau_mai_owner',
            obj.proname,
            obj.args
        );
    END LOOP;
END;
$$;

-- Procedure công khai chạy với quyền của owner, có search_path cố định.
CREATE PROCEDURE public.sp_tao_ho_so_website(
    IN p_ho_ten character varying,
    IN p_so_dien_thoai character varying,
    IN p_serial character varying,
    IN p_mo_ta_loi text,
    IN p_now timestamp with time zone,
    OUT p_ho_so_id bigint,
    OUT p_ma_ho_so character varying
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    CALL public.sp_tao_ho_so_website_impl(
        p_ho_ten,
        p_so_dien_thoai,
        p_serial,
        p_mo_ta_loi,
        p_now,
        p_ho_so_id,
        p_ma_ho_so
    );
END;
$$;

CREATE PROCEDURE public.sp_chuyen_trang_thai(
    IN p_ho_so_id bigint,
    IN p_trang_thai_moi character varying,
    IN p_loai_tac_nhan character varying,
    IN p_nhan_vien_id bigint,
    IN p_ghi_chu text,
    IN p_now timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    CALL public.sp_chuyen_trang_thai_impl(
        p_ho_so_id,
        p_trang_thai_moi,
        p_loai_tac_nhan,
        p_nhan_vien_id,
        p_ghi_chu,
        p_now
    );
END;
$$;

CREATE PROCEDURE public.sp_quet_sla(
    IN p_now timestamp with time zone DEFAULT now()
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    CALL public.sp_quet_sla_impl(p_now);
END;
$$;

ALTER PROCEDURE public.sp_tao_ho_so_website(
    character varying, character varying, character varying, text, timestamp with time zone
) OWNER TO hau_mai_owner;

ALTER PROCEDURE public.sp_chuyen_trang_thai(
    bigint, character varying, character varying, bigint, text, timestamp with time zone
) OWNER TO hau_mai_owner;

ALTER PROCEDURE public.sp_quet_sla(
    timestamp with time zone
) OWNER TO hau_mai_owner;

-- App không được gọi routine nội bộ hay sửa trực tiếp bảng.
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM hau_mai_app;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM hau_mai_app;

GRANT CONNECT ON DATABASE hau_mai TO hau_mai_app;
GRANT USAGE ON SCHEMA public TO hau_mai_app;

-- Các quyền đọc hiện cần cho đăng nhập, tìm nhân viên và danh sách hồ sơ.
GRANT SELECT ON TABLE public.ho_so TO hau_mai_app;
GRANT SELECT (id, ten_dang_nhap, mat_khau_bam, vai_tro, dang_hoat_dong)
    ON TABLE public.tai_khoan TO hau_mai_app;
GRANT SELECT (id, tai_khoan_id)
    ON TABLE public.nhan_vien TO hau_mai_app;

GRANT EXECUTE ON PROCEDURE public.sp_tao_ho_so_website(
    character varying, character varying, character varying, text, timestamp with time zone
) TO hau_mai_app;

GRANT EXECUTE ON PROCEDURE public.sp_chuyen_trang_thai(
    bigint, character varying, character varying, bigint, text, timestamp with time zone
) TO hau_mai_app;

GRANT EXECUTE ON PROCEDURE public.sp_quet_sla(
    timestamp with time zone
) TO hau_mai_app;