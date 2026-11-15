-- Email/Gmail intake has been retired; preserve existing channel and case history.
UPDATE public.kenh_goc
SET dang_bat = FALSE
WHERE ma_kenh = 'EMAIL';
