-- Course progress — the substrate the unified Courses hub needs.
--
-- Until now, `enrollments` recorded only that a user clicked "enroll"
-- (user_id, course_slug, course_title, enrolled_at) with NO notion of how far
-- they've gotten. That makes a real "Continue Learning" experience impossible.
--
-- This table is the per-(user, course) progress record that powers Continue
-- Learning, resume points, and the readiness inputs for recommendations. It is
-- source-agnostic: `course_slug` keys both static "official" courses and
-- DB-backed "community" courses, exactly like `enrollments` already does.
--
-- `percent` is a GENERATED column so it can never drift from lessons_done/total.
-- Existing `enrollments` rows are backfilled as status 'enrolled' (0%), with
-- source inferred from whether the slug exists in user_courses.
--
-- Idempotent. The app reads this table best-effort and falls back to
-- `enrollments` if it is absent, so shipping the frontend before this migration
-- runs degrades gracefully rather than breaking.

CREATE TABLE IF NOT EXISTS public.course_progress (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  course_slug      text NOT NULL,
  course_title     text,
  source           text NOT NULL DEFAULT 'community',  -- 'official' | 'community'
  status           text NOT NULL DEFAULT 'enrolled',   -- enrolled|in_progress|paused|completed
  lessons_total    integer NOT NULL DEFAULT 0,
  lessons_done     integer NOT NULL DEFAULT 0,
  current_block_id text,                                -- opaque resume token (uuid for community, null for official)
  percent          integer GENERATED ALWAYS AS (
                     CASE WHEN lessons_total > 0
                          THEN GREATEST(0, LEAST(100, round(100.0 * lessons_done / lessons_total)::int))
                          ELSE 0 END
                   ) STORED,
  last_opened_at   timestamptz NOT NULL DEFAULT now(),
  completed_at     timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, course_slug)
);

CREATE INDEX IF NOT EXISTS course_progress_user_idx
  ON public.course_progress (user_id, last_opened_at DESC);

-- ── RLS: a learner sees and edits only their own progress ──────────────────
ALTER TABLE public.course_progress ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own course_progress: select" ON public.course_progress;
CREATE POLICY "own course_progress: select" ON public.course_progress
  FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "own course_progress: insert" ON public.course_progress;
CREATE POLICY "own course_progress: insert" ON public.course_progress
  FOR INSERT WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "own course_progress: update" ON public.course_progress;
CREATE POLICY "own course_progress: update" ON public.course_progress
  FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "own course_progress: delete" ON public.course_progress;
CREATE POLICY "own course_progress: delete" ON public.course_progress
  FOR DELETE USING (auth.uid() = user_id);

-- ── Backfill existing enrollments as 0%-progress rows ──────────────────────
INSERT INTO public.course_progress (user_id, course_slug, course_title, source, status, last_opened_at, created_at)
SELECT
  e.user_id,
  e.course_slug,
  e.course_title,
  CASE WHEN EXISTS (SELECT 1 FROM public.user_courses uc WHERE uc.slug = e.course_slug)
       THEN 'community' ELSE 'official' END,
  'enrolled',
  e.enrolled_at,
  e.enrolled_at
FROM public.enrollments e
ON CONFLICT (user_id, course_slug) DO NOTHING;
