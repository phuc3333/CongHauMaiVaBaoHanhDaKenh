-- Read and lock only the assignment facts needed by the technician workflow.
-- The application role cannot read or lock the underlying HR/workflow tables.
CREATE FUNCTION public.fn_ktv_phan_cong_facts(p_phan_cong_id BIGINT)
RETURNS TABLE (
    ho_so_id BIGINT,
    ky_thuat_vien_id BIGINT,
    dang_hieu_luc BOOLEAN,
    case_status TEXT,
    progress_status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
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

ALTER FUNCTION public.fn_ktv_phan_cong_facts(BIGINT) OWNER TO hau_mai_owner;
REVOKE ALL ON FUNCTION public.fn_ktv_phan_cong_facts(BIGINT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fn_ktv_phan_cong_facts(BIGINT) TO hau_mai_app;
