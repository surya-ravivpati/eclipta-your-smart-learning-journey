-- Learner model: structured calibration output that drives Luna's tutoring.
-- learner_profile holds the latest LearningProfile (see src/lib/luna-calibration.ts);
-- calibration_runs keeps the history of diagnostic runs for audit / re-tuning.

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS learner_profile jsonb;

CREATE TABLE IF NOT EXISTS public.calibration_runs (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  profile     jsonb       NOT NULL,
  responses   jsonb       NOT NULL DEFAULT '[]'::jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.calibration_runs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own calibration runs" ON public.calibration_runs;
CREATE POLICY "Users manage own calibration runs" ON public.calibration_runs
  FOR ALL TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_calibration_runs_user
  ON public.calibration_runs(user_id, created_at DESC);
