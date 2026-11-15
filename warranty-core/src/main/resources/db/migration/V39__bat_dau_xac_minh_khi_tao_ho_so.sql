-- Start every newly created case in verification immediately.
CREATE OR REPLACE FUNCTION public.fn_ho_so_bat_dau_xac_minh()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NEW.trang_thai = 'MOI' THEN
        NEW.trang_thai := 'DANG_XAC_MINH';
    END IF;
    RETURN NEW;
END;
$$;

ALTER FUNCTION public.fn_ho_so_bat_dau_xac_minh() OWNER TO hau_mai_owner;
REVOKE ALL ON FUNCTION public.fn_ho_so_bat_dau_xac_minh() FROM PUBLIC;

CREATE TRIGGER trg_ho_so_bat_dau_xac_minh
BEFORE INSERT ON public.ho_so
FOR EACH ROW
EXECUTE FUNCTION public.fn_ho_so_bat_dau_xac_minh();

-- Move already received cases into the same step so they do not require the removed button.
UPDATE public.ho_so
SET trang_thai = 'DANG_XAC_MINH'
WHERE trang_thai = 'MOI';
