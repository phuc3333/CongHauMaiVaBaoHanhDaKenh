CREATE EXTENSION IF NOT EXISTS pg_cron;

GRANT USAGE ON SCHEMA cron TO hau_mai_app;
GRANT EXECUTE ON FUNCTION cron.schedule(text, text, text)
    TO hau_mai_app;

-- Xóa job cũ nếu migration được áp dụng lại ở một môi trường mới.
DO $$
DECLARE
    v_job_id BIGINT;
BEGIN
    FOR v_job_id IN
        SELECT jobid
        FROM cron.job
        WHERE jobname = 'quet-sla'
    LOOP
        PERFORM cron.unschedule(v_job_id);
    END LOOP;
END;
$$;

-- Job được tạo dưới danh nghĩa role ứng dụng bị giới hạn quyền.
SET ROLE hau_mai_app;

SELECT cron.schedule(
    'quet-sla',
    '30 seconds',
    'CALL public.sp_quet_sla();'
);

RESET ROLE;