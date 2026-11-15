-- Remove database objects for retired web/technician flows that have no callers
-- in the current application. Keep all case and conversation history intact.

-- This table has no application upload flow. Refuse to drop it if data appears
-- between the audit and migration, so an attachment can never be deleted silently.
DO $$
BEGIN
    IF to_regclass('public.tep_dinh_kem') IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.tep_dinh_kem) THEN
        RAISE EXCEPTION
            'Không thể xóa tep_dinh_kem: bảng đã có dữ liệu; cần lưu trữ/chuyển dữ liệu trước';
    END IF;
END;
$$;

DROP TABLE IF EXISTS public.tep_dinh_kem;

-- The customer portal is read-only; new cases currently enter through
-- Facebook/Zalo conversations and are created by CSKH or the inbound consumer.
DROP PROCEDURE IF EXISTS public.sp_tao_ho_so_website(
    VARCHAR, VARCHAR, VARCHAR, TEXT, TIMESTAMPTZ
);
DROP PROCEDURE IF EXISTS public.sp_tao_ho_so_website_impl(
    VARCHAR, VARCHAR, VARCHAR, TEXT, TIMESTAMPTZ
);

-- Customers currently look up cases but do not submit supplementary details
-- through the portal. Inbound channel replies remain stored in their own flow.
DROP PROCEDURE IF EXISTS public.sp_khach_bo_sung_thong_tin(
    VARCHAR, VARCHAR, TEXT, TIMESTAMPTZ
);
DROP PROCEDURE IF EXISTS public.sp_khach_bo_sung_thong_tin(
    VARCHAR, VARCHAR, VARCHAR, TEXT, TIMESTAMPTZ
);

-- The current technician UI supports accept and finish; it has no intermediate
-- progress-update form/endpoint. Historical progress rows and table are kept.
DROP PROCEDURE IF EXISTS public.sp_cap_nhat_tien_do(
    BIGINT, BIGINT, VARCHAR, TEXT, TEXT, TIMESTAMPTZ
);
