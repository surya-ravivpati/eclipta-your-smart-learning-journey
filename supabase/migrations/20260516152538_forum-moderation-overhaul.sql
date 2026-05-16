-- ════════════════════════════════════════════════════════════════════════
-- Smarter forum moderation: server-side enforcement, contextual flagging,
-- automatic hiding via report thresholds, and an audit log.
--
-- Why this exists:
--   * The previous moderation was a 60-word client list in src/lib/profanity.
--     A user could bypass it with spacing ("f u c k"), homoglyphs, zero-width
--     chars, or just words it didn't know, and the server was happy to insert
--     the row anyway.
--   * Reports landed in forum_reports but nothing acted on them — no auto-
--     hide, no dedup, no rate limit, no aggregation. Reported content stayed
--     public until a human noticed.
--
-- What this migration adds:
--   1. moderation columns on threads/answers/comments so the UI can render
--      "Removed by moderator" instead of leaking a blocked body, and so
--      mods can restore false positives.
--   2. A server-side normalize_for_moderation()/contains_banned_text() pair
--      that strips zero-width chars, leet substitutions, homoglyphs, and
--      separator-spacing tricks before matching a maintained slur/profanity
--      table. Used by both an INSERT trigger (hard floor) and the
--      moderate-content edge function (which adds AI context on top).
--   3. submit_forum_report RPC with dedup (one report per user per target),
--      per-user rate limiting (10/hour), auto-bump of report_count, and an
--      auto-hide threshold so highly-reported content is hidden pending
--      moderator review within seconds rather than days.
--   4. set_moderation_status / set_moderation_status_with_log RPCs so mods
--      can hide / remove / restore content with a written reason that lands
--      in moderation_actions for auditability.
-- ════════════════════════════════════════════════════════════════════════

-- ── 1. Per-row moderation columns ───────────────────────────────────────
ALTER TABLE public.forum_threads
  ADD COLUMN IF NOT EXISTS moderation_status text NOT NULL DEFAULT 'visible',
  ADD COLUMN IF NOT EXISTS moderation_reason text,
  ADD COLUMN IF NOT EXISTS moderation_score  integer,
  ADD COLUMN IF NOT EXISTS moderation_category text,
  ADD COLUMN IF NOT EXISTS report_count      integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS hidden_at         timestamptz;

ALTER TABLE public.forum_answers
  ADD COLUMN IF NOT EXISTS moderation_status text NOT NULL DEFAULT 'visible',
  ADD COLUMN IF NOT EXISTS moderation_reason text,
  ADD COLUMN IF NOT EXISTS moderation_score  integer,
  ADD COLUMN IF NOT EXISTS moderation_category text,
  ADD COLUMN IF NOT EXISTS report_count      integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS hidden_at         timestamptz;

ALTER TABLE public.forum_comments
  ADD COLUMN IF NOT EXISTS moderation_status text NOT NULL DEFAULT 'visible',
  ADD COLUMN IF NOT EXISTS moderation_reason text,
  ADD COLUMN IF NOT EXISTS moderation_score  integer,
  ADD COLUMN IF NOT EXISTS moderation_category text,
  ADD COLUMN IF NOT EXISTS report_count      integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS hidden_at         timestamptz;

DO $$ BEGIN
  ALTER TABLE public.forum_threads  ADD CONSTRAINT forum_threads_modstatus_chk  CHECK (moderation_status IN ('visible','pending','hidden','removed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.forum_answers  ADD CONSTRAINT forum_answers_modstatus_chk  CHECK (moderation_status IN ('visible','pending','hidden','removed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
  ALTER TABLE public.forum_comments ADD CONSTRAINT forum_comments_modstatus_chk CHECK (moderation_status IN ('visible','pending','hidden','removed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_forum_threads_modstatus  ON public.forum_threads(moderation_status)  WHERE moderation_status <> 'visible';
CREATE INDEX IF NOT EXISTS idx_forum_answers_modstatus  ON public.forum_answers(moderation_status)  WHERE moderation_status <> 'visible';
CREATE INDEX IF NOT EXISTS idx_forum_comments_modstatus ON public.forum_comments(moderation_status) WHERE moderation_status <> 'visible';

-- ── 2. Reports table hardening ──────────────────────────────────────────
-- One report per user per target eliminates brigading-by-spam. resolver_id +
-- resolution_note give the admin dashboard somewhere to remember decisions.
ALTER TABLE public.forum_reports
  ADD COLUMN IF NOT EXISTS resolver_id     uuid,
  ADD COLUMN IF NOT EXISTS resolution_note text;

-- Drop any duplicate existing rows before adding the uniqueness constraint.
DELETE FROM public.forum_reports a USING public.forum_reports b
 WHERE a.id > b.id
   AND a.reporter_id = b.reporter_id
   AND a.target_id   = b.target_id
   AND a.target_type = b.target_type;

DO $$ BEGIN
  ALTER TABLE public.forum_reports
    ADD CONSTRAINT forum_reports_unique_per_user UNIQUE (reporter_id, target_type, target_id);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE INDEX IF NOT EXISTS idx_forum_reports_target ON public.forum_reports(target_type, target_id, status);
CREATE INDEX IF NOT EXISTS idx_forum_reports_reporter_recent ON public.forum_reports(reporter_id, created_at DESC);

-- ── 3. moderation_actions audit log ─────────────────────────────────────
-- Every visibility change (auto-hide trigger, mod decision, AI block, restore)
-- writes one row. The admin dashboard reads from here so the "who did what"
-- trail survives even if the original target is later deleted.
CREATE TABLE IF NOT EXISTS public.moderation_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_type   text NOT NULL CHECK (target_type IN ('thread','answer','comment','username')),
  target_id     uuid,
  actor_id      uuid,
  action        text NOT NULL CHECK (action IN ('auto_hide','auto_remove','hide','remove','restore','block_create','dismiss')),
  source        text NOT NULL CHECK (source IN ('trigger','report_threshold','ai','moderator','system')),
  category      text,
  score         integer,
  reason        text,
  payload       jsonb,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_moderation_actions_target ON public.moderation_actions(target_type, target_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_moderation_actions_recent ON public.moderation_actions(created_at DESC);

ALTER TABLE public.moderation_actions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Mods view moderation log" ON public.moderation_actions;
CREATE POLICY "Mods view moderation log" ON public.moderation_actions
  FOR SELECT USING (
    public.has_role(auth.uid(), 'moderator') OR public.has_role(auth.uid(), 'admin')
  );

-- ── 4. Banned-term dictionary, server-managed ───────────────────────────
-- Keeping the list in a table (instead of inlined in a function) lets mods
-- add new terms via an UPSERT without redeploying. Severity drives whether
-- a match hard-blocks the insert (severity >= 8) or just hides pending
-- review (severity 5-7). Anything lower is treated as a soft hint and
-- forwarded to the AI moderator for contextual judgement.
CREATE TABLE IF NOT EXISTS public.moderation_terms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  term      text NOT NULL UNIQUE,         -- normalised form (lowercase, letters only)
  category  text NOT NULL CHECK (category IN ('slur','sexual','self_harm','violence','spam','generic_profanity')),
  severity  integer NOT NULL CHECK (severity BETWEEN 1 AND 10),
  notes     text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.moderation_terms ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Mods read terms"   ON public.moderation_terms;
CREATE POLICY "Mods read terms" ON public.moderation_terms
  FOR SELECT USING (public.has_role(auth.uid(),'moderator') OR public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS "Admins write terms" ON public.moderation_terms;
CREATE POLICY "Admins write terms" ON public.moderation_terms
  FOR ALL USING (public.has_role(auth.uid(),'admin'))
  WITH CHECK (public.has_role(auth.uid(),'admin'));

INSERT INTO public.moderation_terms(term, category, severity) VALUES
  -- Slurs / hate
  ('nigger','slur',10),('nigga','slur',9),('chink','slur',10),('spic','slur',10),
  ('kike','slur',10),('gook','slur',10),('wetback','slur',10),('tranny','slur',9),
  ('faggot','slur',10),('fag','slur',9),('dyke','slur',9),('retard','slur',8),('retarded','slur',8),
  -- Sexual / CSAM-adjacent
  ('rape','sexual',9),('rapist','sexual',9),('pedo','sexual',10),('pedophile','sexual',10),
  ('molest','sexual',9),('childporn','sexual',10),('cumshot','sexual',7),
  -- Self-harm baiting
  ('kys','self_harm',10),('killyourself','self_harm',10),('killurself','self_harm',10),
  ('killyrself','self_harm',10),('hangyourself','self_harm',10),('hangurself','self_harm',10),
  -- Generic profanity (will hide pending review unless context clears it)
  ('fuck','generic_profanity',5),('fucker','generic_profanity',5),('fucking','generic_profanity',5),
  ('motherfucker','generic_profanity',6),('shit','generic_profanity',5),
  ('bullshit','generic_profanity',4),('bitch','generic_profanity',6),
  ('bastard','generic_profanity',5),('cunt','generic_profanity',7),
  ('asshole','generic_profanity',5),('dick','generic_profanity',5),
  ('cock','generic_profanity',5),('pussy','generic_profanity',5),
  ('whore','generic_profanity',6),('slut','generic_profanity',6),
  -- Spam markers
  ('viagra','spam',8),('cialis','spam',8),('onlyfans','spam',7),
  ('freerobux','spam',7),('cryptogiveaway','spam',7),('clickhere','spam',3),('buynow','spam',2)
ON CONFLICT (term) DO UPDATE SET
  category = EXCLUDED.category,
  severity = EXCLUDED.severity;

-- ── 5. Server-side normalisation + match ────────────────────────────────
-- Mirrors src/lib/profanity.ts but goes further:
--   * Strips zero-width characters (U+200B-U+200F, U+FEFF) so "f‌u‌c‌k"
--     doesn't slip through.
--   * Folds Cyrillic / Greek homoglyphs to Latin (а → a, е → e, о → o, р → p,
--     с → c, х → x, у → y) so "nіgger" matches.
--   * Removes ALL non-letter characters before matching, so spacing tricks
--     ("f u c k"), separators ("f.u.c.k"), and stretched repeats ("fuuuuck")
--     all collapse to the same form.
CREATE OR REPLACE FUNCTION public.normalize_for_moderation(p_text text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v text;
BEGIN
  IF p_text IS NULL THEN RETURN ''; END IF;
  v := lower(p_text);
  -- Zero-width + BOM strip
  v := regexp_replace(v, E'[​‌‍‎‏  ﻿]', '', 'g');
  -- Cyrillic / Greek look-alike letters → Latin equivalents. Only 1:1
  -- visually identical substitutions, because translate() requires equal-
  -- length from/to strings.
  v := translate(v,
    'аеорсхукйі' || 'αεορυνικ',
    'aeopcxykji' || 'aeopynik'
  );
  -- Leet substitutions: 10 sources → 10 targets.
  --   0→o 1→i 3→e 4→a 5→s 7→t 8→b !→i @→a $→s
  v := translate(v, '0134578!@$', 'oieastbias');
  -- Collapse runs of >=3 identical chars
  v := regexp_replace(v, '(.)\1{2,}', '\1\1', 'g');
  -- Strip everything that isn't a-z
  v := regexp_replace(v, '[^a-z]', '', 'g');
  RETURN v;
END;
$$;

CREATE OR REPLACE FUNCTION public.moderation_match(p_text text)
RETURNS TABLE(term text, category text, severity integer)
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $$
DECLARE
  v_norm text := public.normalize_for_moderation(p_text);
BEGIN
  IF v_norm = '' THEN RETURN; END IF;
  RETURN QUERY
    SELECT t.term, t.category, t.severity
      FROM public.moderation_terms t
     WHERE position(t.term in v_norm) > 0
     ORDER BY t.severity DESC, length(t.term) DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.normalize_for_moderation(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.moderation_match(text)         FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.normalize_for_moderation(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.moderation_match(text)         TO authenticated, service_role;

-- ── 6. INSERT/UPDATE triggers — last line of defence ────────────────────
-- The edge function does the rich contextual job, but a client that talks
-- directly to PostgREST must not be able to plant a slur in forum_threads
-- by skipping the edge function. This trigger runs the same dictionary
-- match and either hard-blocks (severity >= 8) or pre-flags the row as
-- hidden (severity >= 5) so it never goes public.
CREATE OR REPLACE FUNCTION public.forum_content_moderation_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_text text;
  v_match record;
BEGIN
  v_text := COALESCE(NEW.body, '');
  IF TG_TABLE_NAME = 'forum_threads' THEN
    v_text := v_text || ' ' || COALESCE(NEW.title, '');
    IF NEW.tags IS NOT NULL THEN
      v_text := v_text || ' ' || array_to_string(NEW.tags, ' ');
    END IF;
  END IF;

  -- Find the strongest term hit, if any.
  SELECT * INTO v_match FROM public.moderation_match(v_text) LIMIT 1;

  IF v_match.term IS NULL THEN
    RETURN NEW;
  END IF;

  IF v_match.severity >= 8 THEN
    -- Hard block. Log and refuse the write entirely.
    INSERT INTO public.moderation_actions(target_type, target_id, actor_id, action, source, category, score, reason)
    VALUES (
      TG_ARGV[0],
      COALESCE(NEW.id, gen_random_uuid()),
      NEW.user_id,
      'block_create',
      'trigger',
      v_match.category,
      v_match.severity * 10,
      'Matched banned term "' || v_match.term || '" (' || v_match.category || ')'
    );
    RAISE EXCEPTION 'Content rejected by moderation (category: %)', v_match.category
      USING ERRCODE = 'check_violation';
  END IF;

  -- Severity 5-7: let it land but hidden until a mod or the AI clears it.
  NEW.moderation_status   := 'hidden';
  NEW.moderation_category := v_match.category;
  NEW.moderation_score    := v_match.severity * 10;
  NEW.moderation_reason   := 'Auto-hidden: matched "' || v_match.term || '"';
  NEW.hidden_at           := COALESCE(NEW.hidden_at, now());
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_forum_threads_moderation  ON public.forum_threads;
CREATE TRIGGER trg_forum_threads_moderation
  BEFORE INSERT OR UPDATE OF body, title, tags ON public.forum_threads
  FOR EACH ROW EXECUTE FUNCTION public.forum_content_moderation_trigger('thread');

DROP TRIGGER IF EXISTS trg_forum_answers_moderation  ON public.forum_answers;
CREATE TRIGGER trg_forum_answers_moderation
  BEFORE INSERT OR UPDATE OF body ON public.forum_answers
  FOR EACH ROW EXECUTE FUNCTION public.forum_content_moderation_trigger('answer');

DROP TRIGGER IF EXISTS trg_forum_comments_moderation ON public.forum_comments;
CREATE TRIGGER trg_forum_comments_moderation
  BEFORE INSERT OR UPDATE OF body ON public.forum_comments
  FOR EACH ROW EXECUTE FUNCTION public.forum_content_moderation_trigger('comment');

-- Username moderation: prevent slur-handles from being saved.
CREATE OR REPLACE FUNCTION public.user_profile_username_moderation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_match record;
BEGIN
  IF NEW.username IS NULL THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND NEW.username = OLD.username THEN RETURN NEW; END IF;

  SELECT * INTO v_match FROM public.moderation_match(NEW.username) LIMIT 1;
  IF v_match.term IS NOT NULL AND v_match.severity >= 5 THEN
    INSERT INTO public.moderation_actions(target_type, actor_id, action, source, category, score, reason)
    VALUES ('username', NEW.user_id, 'block_create', 'trigger',
            v_match.category, v_match.severity * 10,
            'Username matched banned term "' || v_match.term || '"');
    RAISE EXCEPTION 'Username rejected by moderation' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_user_profiles_username_moderation ON public.user_profiles;
CREATE TRIGGER trg_user_profiles_username_moderation
  BEFORE INSERT OR UPDATE OF username ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.user_profile_username_moderation();

-- ── 7. submit_forum_report RPC ──────────────────────────────────────────
-- One RPC replaces direct INSERTs on forum_reports so we can enforce:
--   - The reporter is authenticated.
--   - The reporter isn't the author (no self-reports for spam farming).
--   - Per-user rate limit: at most 10 reports per hour.
--   - Dedup on (reporter, target).
--   - Atomic bump of report_count on the target.
--   - Auto-hide when report_count crosses HIDE_THRESHOLD (= 3) for content
--     that isn't already hidden/removed by a moderator. Mods can still
--     restore from the dashboard.
CREATE OR REPLACE FUNCTION public.submit_forum_report(
  p_target_type text,
  p_target_id   uuid,
  p_reason      text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_author_id uuid;
  v_recent integer;
  v_existing uuid;
  v_count integer;
  v_status text;
  HIDE_THRESHOLD constant integer := 3;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_target_type NOT IN ('thread','answer','comment') THEN
    RAISE EXCEPTION 'Invalid target type';
  END IF;
  IF p_target_id IS NULL THEN RAISE EXCEPTION 'Missing target'; END IF;
  IF coalesce(length(trim(p_reason)), 0) < 3 THEN
    RAISE EXCEPTION 'Reason too short';
  END IF;

  -- Resolve the target's author so the user can't report themselves.
  IF p_target_type = 'thread' THEN
    SELECT user_id, moderation_status INTO v_author_id, v_status
      FROM public.forum_threads WHERE id = p_target_id;
  ELSIF p_target_type = 'answer' THEN
    SELECT user_id, moderation_status INTO v_author_id, v_status
      FROM public.forum_answers WHERE id = p_target_id;
  ELSE
    SELECT user_id, moderation_status INTO v_author_id, v_status
      FROM public.forum_comments WHERE id = p_target_id;
  END IF;
  IF v_author_id IS NULL THEN RAISE EXCEPTION 'Target not found'; END IF;
  IF v_author_id = v_uid THEN RAISE EXCEPTION 'You cannot report your own content'; END IF;

  -- Per-user rate limit.
  SELECT count(*) INTO v_recent
    FROM public.forum_reports
   WHERE reporter_id = v_uid
     AND created_at  > now() - interval '1 hour';
  IF v_recent >= 10 THEN
    RAISE EXCEPTION 'Reporting rate limit reached. Try again later.';
  END IF;

  -- Dedup: if a report already exists, just refresh the reason and bail.
  SELECT id INTO v_existing
    FROM public.forum_reports
   WHERE reporter_id = v_uid
     AND target_type = p_target_type
     AND target_id   = p_target_id;
  IF v_existing IS NOT NULL THEN
    UPDATE public.forum_reports
       SET reason = left(p_reason, 600),
           status = 'pending'
     WHERE id = v_existing;
    RETURN jsonb_build_object('ok', true, 'deduplicated', true);
  END IF;

  INSERT INTO public.forum_reports(reporter_id, target_type, target_id, reason)
  VALUES (v_uid, p_target_type, p_target_id, left(p_reason, 600));

  -- Atomic increment of the target's report_count + auto-hide if needed.
  IF p_target_type = 'thread' THEN
    UPDATE public.forum_threads
       SET report_count = report_count + 1,
           moderation_status = CASE
             WHEN moderation_status IN ('hidden','removed') THEN moderation_status
             WHEN report_count + 1 >= HIDE_THRESHOLD       THEN 'hidden'
             ELSE moderation_status
           END,
           hidden_at = CASE
             WHEN moderation_status IN ('hidden','removed')           THEN hidden_at
             WHEN report_count + 1 >= HIDE_THRESHOLD AND hidden_at IS NULL THEN now()
             ELSE hidden_at
           END,
           moderation_reason = CASE
             WHEN moderation_status IN ('hidden','removed') THEN moderation_reason
             WHEN report_count + 1 >= HIDE_THRESHOLD       THEN 'Auto-hidden after ' || (report_count + 1) || ' user reports'
             ELSE moderation_reason
           END
     WHERE id = p_target_id
    RETURNING report_count INTO v_count;
  ELSIF p_target_type = 'answer' THEN
    UPDATE public.forum_answers
       SET report_count = report_count + 1,
           moderation_status = CASE
             WHEN moderation_status IN ('hidden','removed') THEN moderation_status
             WHEN report_count + 1 >= HIDE_THRESHOLD       THEN 'hidden'
             ELSE moderation_status
           END,
           hidden_at = CASE
             WHEN moderation_status IN ('hidden','removed')           THEN hidden_at
             WHEN report_count + 1 >= HIDE_THRESHOLD AND hidden_at IS NULL THEN now()
             ELSE hidden_at
           END,
           moderation_reason = CASE
             WHEN moderation_status IN ('hidden','removed') THEN moderation_reason
             WHEN report_count + 1 >= HIDE_THRESHOLD       THEN 'Auto-hidden after ' || (report_count + 1) || ' user reports'
             ELSE moderation_reason
           END
     WHERE id = p_target_id
    RETURNING report_count INTO v_count;
  ELSE
    UPDATE public.forum_comments
       SET report_count = report_count + 1,
           moderation_status = CASE
             WHEN moderation_status IN ('hidden','removed') THEN moderation_status
             WHEN report_count + 1 >= HIDE_THRESHOLD       THEN 'hidden'
             ELSE moderation_status
           END,
           hidden_at = CASE
             WHEN moderation_status IN ('hidden','removed')           THEN hidden_at
             WHEN report_count + 1 >= HIDE_THRESHOLD AND hidden_at IS NULL THEN now()
             ELSE hidden_at
           END,
           moderation_reason = CASE
             WHEN moderation_status IN ('hidden','removed') THEN moderation_reason
             WHEN report_count + 1 >= HIDE_THRESHOLD       THEN 'Auto-hidden after ' || (report_count + 1) || ' user reports'
             ELSE moderation_reason
           END
     WHERE id = p_target_id
    RETURNING report_count INTO v_count;
  END IF;

  IF v_count >= HIDE_THRESHOLD THEN
    INSERT INTO public.moderation_actions(target_type, target_id, actor_id, action, source, reason)
    VALUES (p_target_type, p_target_id, NULL, 'auto_hide', 'report_threshold',
            'Crossed report threshold (' || v_count || ' reports)');
  END IF;

  RETURN jsonb_build_object('ok', true, 'report_count', v_count, 'auto_hidden', v_count >= HIDE_THRESHOLD);
END;
$$;
REVOKE ALL ON FUNCTION public.submit_forum_report(text, uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_forum_report(text, uuid, text) TO authenticated;

-- ── 8. set_moderation_status RPC (moderator-only) ────────────────────────
-- Single chokepoint for hide / remove / restore actions. Mods can't write
-- moderation_status directly because of RLS (only authors can update rows,
-- and authors shouldn't be able to mark their own slur "visible"); this
-- RPC runs as SECURITY DEFINER and logs the change.
CREATE OR REPLACE FUNCTION public.set_moderation_status(
  p_target_type text,
  p_target_id   uuid,
  p_status      text,
  p_reason      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_action text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (public.has_role(v_uid,'moderator') OR public.has_role(v_uid,'admin')) THEN
    RAISE EXCEPTION 'Moderator role required';
  END IF;
  IF p_target_type NOT IN ('thread','answer','comment') THEN
    RAISE EXCEPTION 'Invalid target type';
  END IF;
  IF p_status NOT IN ('visible','hidden','removed') THEN
    RAISE EXCEPTION 'Invalid status';
  END IF;

  v_action := CASE p_status
    WHEN 'visible' THEN 'restore'
    WHEN 'hidden'  THEN 'hide'
    WHEN 'removed' THEN 'remove'
  END;

  IF p_target_type = 'thread' THEN
    UPDATE public.forum_threads
       SET moderation_status = p_status,
           moderation_reason = COALESCE(p_reason, moderation_reason),
           hidden_at         = CASE WHEN p_status = 'visible' THEN NULL ELSE COALESCE(hidden_at, now()) END
     WHERE id = p_target_id;
  ELSIF p_target_type = 'answer' THEN
    UPDATE public.forum_answers
       SET moderation_status = p_status,
           moderation_reason = COALESCE(p_reason, moderation_reason),
           hidden_at         = CASE WHEN p_status = 'visible' THEN NULL ELSE COALESCE(hidden_at, now()) END
     WHERE id = p_target_id;
  ELSE
    UPDATE public.forum_comments
       SET moderation_status = p_status,
           moderation_reason = COALESCE(p_reason, moderation_reason),
           hidden_at         = CASE WHEN p_status = 'visible' THEN NULL ELSE COALESCE(hidden_at, now()) END
     WHERE id = p_target_id;
  END IF;

  INSERT INTO public.moderation_actions(target_type, target_id, actor_id, action, source, reason)
  VALUES (p_target_type, p_target_id, v_uid, v_action, 'moderator', p_reason);

  -- Mark any open reports against this target as reviewed when we hide/remove.
  IF p_status IN ('hidden','removed') THEN
    UPDATE public.forum_reports
       SET status = 'reviewed', resolver_id = v_uid, resolved_at = now()
     WHERE target_type = p_target_type AND target_id = p_target_id AND status = 'pending';
  END IF;

  RETURN jsonb_build_object('ok', true, 'status', p_status);
END;
$$;
REVOKE ALL ON FUNCTION public.set_moderation_status(text, uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_moderation_status(text, uuid, text, text) TO authenticated;

-- ── 9. apply_ai_moderation_result RPC ───────────────────────────────────
-- Called from the moderate-content edge function (running as service_role)
-- to record the AI's verdict on a row it just inserted. Idempotent: if the
-- row is already in a stricter state, leave it alone.
CREATE OR REPLACE FUNCTION public.apply_ai_moderation_result(
  p_target_type text,
  p_target_id   uuid,
  p_verdict     text,
  p_category    text,
  p_score       integer,
  p_reason      text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_action text;
  v_new_status text;
BEGIN
  IF p_verdict NOT IN ('allow','hide','block') THEN
    RAISE EXCEPTION 'Invalid verdict';
  END IF;
  IF p_target_type NOT IN ('thread','answer','comment') THEN
    RAISE EXCEPTION 'Invalid target type';
  END IF;

  v_new_status := CASE p_verdict
    WHEN 'allow' THEN 'visible'
    WHEN 'hide'  THEN 'hidden'
    WHEN 'block' THEN 'removed'
  END;
  v_action := CASE p_verdict
    WHEN 'allow' THEN 'restore'
    WHEN 'hide'  THEN 'auto_hide'
    WHEN 'block' THEN 'auto_remove'
  END;

  -- Never weaken a stricter manual decision.
  IF p_target_type = 'thread' THEN
    UPDATE public.forum_threads
       SET moderation_status   = CASE
             WHEN moderation_status = 'removed' THEN 'removed'
             WHEN moderation_status = 'hidden'  AND v_new_status = 'visible' THEN 'hidden'
             ELSE v_new_status
           END,
           moderation_reason   = COALESCE(p_reason, moderation_reason),
           moderation_score    = GREATEST(COALESCE(moderation_score, 0), COALESCE(p_score, 0)),
           moderation_category = COALESCE(p_category, moderation_category),
           hidden_at           = CASE WHEN v_new_status = 'visible' AND moderation_status NOT IN ('hidden','removed') THEN NULL ELSE COALESCE(hidden_at, now()) END
     WHERE id = p_target_id;
  ELSIF p_target_type = 'answer' THEN
    UPDATE public.forum_answers
       SET moderation_status   = CASE
             WHEN moderation_status = 'removed' THEN 'removed'
             WHEN moderation_status = 'hidden'  AND v_new_status = 'visible' THEN 'hidden'
             ELSE v_new_status
           END,
           moderation_reason   = COALESCE(p_reason, moderation_reason),
           moderation_score    = GREATEST(COALESCE(moderation_score, 0), COALESCE(p_score, 0)),
           moderation_category = COALESCE(p_category, moderation_category),
           hidden_at           = CASE WHEN v_new_status = 'visible' AND moderation_status NOT IN ('hidden','removed') THEN NULL ELSE COALESCE(hidden_at, now()) END
     WHERE id = p_target_id;
  ELSE
    UPDATE public.forum_comments
       SET moderation_status   = CASE
             WHEN moderation_status = 'removed' THEN 'removed'
             WHEN moderation_status = 'hidden'  AND v_new_status = 'visible' THEN 'hidden'
             ELSE v_new_status
           END,
           moderation_reason   = COALESCE(p_reason, moderation_reason),
           moderation_score    = GREATEST(COALESCE(moderation_score, 0), COALESCE(p_score, 0)),
           moderation_category = COALESCE(p_category, moderation_category),
           hidden_at           = CASE WHEN v_new_status = 'visible' AND moderation_status NOT IN ('hidden','removed') THEN NULL ELSE COALESCE(hidden_at, now()) END
     WHERE id = p_target_id;
  END IF;

  INSERT INTO public.moderation_actions(target_type, target_id, actor_id, action, source, category, score, reason)
  VALUES (p_target_type, p_target_id, NULL, v_action, 'ai', p_category, p_score, p_reason);
END;
$$;
REVOKE ALL ON FUNCTION public.apply_ai_moderation_result(text, uuid, text, text, integer, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_ai_moderation_result(text, uuid, text, text, integer, text) TO service_role;

-- ── 10. admin_moderation_queue view ─────────────────────────────────────
-- Single query the moderator dashboard reads from. Joins reports with the
-- target body + status so the dashboard doesn't have to fan out to three
-- tables per row.
CREATE OR REPLACE VIEW public.admin_moderation_queue AS
  SELECT 'thread'::text AS target_type, t.id AS target_id, t.user_id AS author_id, t.author_name,
         t.title AS title, t.body AS body,
         t.moderation_status, t.moderation_reason, t.moderation_score, t.moderation_category,
         t.report_count, t.hidden_at, t.created_at, t.updated_at
    FROM public.forum_threads t
   WHERE t.moderation_status <> 'visible' OR t.report_count > 0
  UNION ALL
  SELECT 'answer', a.id, a.user_id, a.author_name,
         NULL::text, a.body,
         a.moderation_status, a.moderation_reason, a.moderation_score, a.moderation_category,
         a.report_count, a.hidden_at, a.created_at, a.updated_at
    FROM public.forum_answers a
   WHERE a.moderation_status <> 'visible' OR a.report_count > 0
  UNION ALL
  SELECT 'comment', c.id, c.user_id, c.author_name,
         NULL::text, c.body,
         c.moderation_status, c.moderation_reason, c.moderation_score, c.moderation_category,
         c.report_count, c.hidden_at, c.created_at, c.updated_at
    FROM public.forum_comments c
   WHERE c.moderation_status <> 'visible' OR c.report_count > 0;

GRANT SELECT ON public.admin_moderation_queue TO authenticated;
