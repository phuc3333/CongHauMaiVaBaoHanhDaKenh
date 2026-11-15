-- Remove legacy business procedures replaced by service-layer decisions.
-- V49 already revoked the application's EXECUTE privileges; current Java
-- repositories use the validated write procedures instead.
DROP PROCEDURE IF EXISTS public.sp_phan_cong(BIGINT, BIGINT, BIGINT, TEXT, TIMESTAMPTZ);
DROP PROCEDURE IF EXISTS public.sp_dong_ho_so(BIGINT, BIGINT, TEXT, TIMESTAMPTZ);
DROP PROCEDURE IF EXISTS public.sp_xac_minh(BIGINT, VARCHAR, TEXT, BIGINT, TIMESTAMPTZ);
DROP PROCEDURE IF EXISTS public.sp_ktv_tiep_nhan_phan_cong(BIGINT, BIGINT, TIMESTAMPTZ);
DROP PROCEDURE IF EXISTS public.sp_hoan_tat_sua_chua(BIGINT, BIGINT, VARCHAR, TEXT, TIMESTAMPTZ);

-- Pending follow-up messages remain stored and processed by the current
-- conversation flow; this legacy standalone view has no application caller.
DROP VIEW IF EXISTS public.v_tin_nhan_cho_bo_sung;
