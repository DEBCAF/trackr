-- Daily allowance: idempotent catch-up + pause/resume.
-- Run this once in the Supabase SQL Editor (after transactions_rls.sql).
-- "Days" are calendar days in Europe/London.

-- 1. Each allowance row records which day it is for, and a user can only
--    have one allowance row per day (stops double-adds from retries).
ALTER TABLE public.transactions
  ADD COLUMN IF NOT EXISTS allowance_date date;

-- Tag existing allowance rows with their day. If an old cron run added two
-- rows on the same day, only the first is tagged so the unique index below
-- can be created (the extra row stays in the balance; see the query at the
-- bottom to find any).
WITH ranked AS (
  SELECT id,
         (created_at AT TIME ZONE 'Europe/London')::date AS d,
         row_number() OVER (
           PARTITION BY user_id, (created_at AT TIME ZONE 'Europe/London')::date
           ORDER BY created_at
         ) AS rn
  FROM public.transactions
  WHERE type = 'allowance' AND allowance_date IS NULL
)
UPDATE public.transactions t
SET allowance_date = ranked.d
FROM ranked
WHERE t.id = ranked.id AND ranked.rn = 1;

CREATE UNIQUE INDEX IF NOT EXISTS transactions_one_allowance_per_day
  ON public.transactions (user_id, allowance_date)
  WHERE type = 'allowance';

-- 2. Per-user allowance settings.
CREATE TABLE IF NOT EXISTS public.allowance_settings (
  user_id      uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE DEFAULT auth.uid(),
  daily_amount numeric(12, 2) NOT NULL DEFAULT 40,
  paused       boolean NOT NULL DEFAULT false,
  -- First day the allowance may be added for. Set when the settings row is
  -- created and on every resume, so paused days are never back-filled.
  resume_from  date NOT NULL DEFAULT (now() AT TIME ZONE 'Europe/London')::date,
  updated_at   timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.allowance_settings ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.allowance_settings FROM anon, PUBLIC;
GRANT SELECT, INSERT, UPDATE ON TABLE public.allowance_settings TO authenticated;

DROP POLICY IF EXISTS "Users manage own allowance settings" ON public.allowance_settings;
CREATE POLICY "Users manage own allowance settings"
  ON public.allowance_settings
  FOR ALL
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- 3. Add every missing (non-paused) day's allowance up to and including today.
--    Safe to call any number of times. Called by the dashboard on load and by
--    the Vercel cron (which passes the owner's id via the service role).
--    SECURITY INVOKER: a signed-in user can only insert their own rows (RLS).
CREATE OR REPLACE FUNCTION public.ensure_allowance(p_user_id uuid DEFAULT auth.uid())
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_today    date := (now() AT TIME ZONE 'Europe/London')::date;
  v_settings public.allowance_settings%ROWTYPE;
  v_last     date;
  v_start    date;
  v_added    integer;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'ensure_allowance: no user';
  END IF;

  INSERT INTO public.allowance_settings (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO v_settings FROM public.allowance_settings WHERE user_id = p_user_id;
  IF v_settings.paused THEN
    RETURN 0;
  END IF;

  SELECT max(allowance_date) INTO v_last
  FROM public.transactions
  WHERE user_id = p_user_id AND type = 'allowance';

  -- greatest() ignores NULL, so with no previous allowance we start at resume_from.
  v_start := greatest(v_last + 1, v_settings.resume_from);

  INSERT INTO public.transactions (title, amount, category, type, user_id, allowance_date, created_at)
  SELECT 'Daily Allowance',
         v_settings.daily_amount,
         'Allowance',
         'allowance',
         p_user_id,
         d::date,
         CASE WHEN d::date = v_today THEN now()
              ELSE (d::date::timestamp AT TIME ZONE 'Europe/London') END
  FROM generate_series(v_start::timestamp, v_today::timestamp, interval '1 day') AS d
  ON CONFLICT (user_id, allowance_date) WHERE type = 'allowance' DO NOTHING;

  GET DIAGNOSTICS v_added = ROW_COUNT;
  RETURN v_added;
END;
$$;

-- 4. Pause / resume. Pausing stops future days (today's allowance, if already
--    added, stays). Resuming starts again from today without back-filling the
--    paused days.
CREATE OR REPLACE FUNCTION public.set_allowance_paused(p_paused boolean)
RETURNS public.allowance_settings
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_row public.allowance_settings;
BEGIN
  INSERT INTO public.allowance_settings AS s (user_id, paused)
  VALUES (auth.uid(), p_paused)
  ON CONFLICT (user_id) DO UPDATE
    SET paused      = excluded.paused,
        resume_from = CASE
                        WHEN s.paused AND NOT excluded.paused
                          THEN (now() AT TIME ZONE 'Europe/London')::date
                        ELSE s.resume_from
                      END,
        updated_at  = now()
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_allowance(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_allowance_paused(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ensure_allowance(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.set_allowance_paused(boolean) TO authenticated;

-- Optional: find days where the old cron added the allowance more than once.
-- SELECT user_id, (created_at AT TIME ZONE 'Europe/London')::date AS day, count(*)
-- FROM public.transactions
-- WHERE type = 'allowance'
-- GROUP BY 1, 2
-- HAVING count(*) > 1;
