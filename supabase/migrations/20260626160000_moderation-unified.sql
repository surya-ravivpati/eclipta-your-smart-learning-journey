-- ════════════════════════════════════════════════════════════════════════
-- Unified content-moderation pipeline — one shared path for forums,
-- usernames, AND study-room chat. Builds ON TOP of the strong existing
-- primitives (normalize_for_moderation, moderation_match, moderation_terms,
-- moderation_actions, forum triggers) rather than replacing them.
--
-- What this migration ADDS to close the audited holes:
--   1. moderation_config        — ONE place for thresholds (Layer A/B cutoffs,
--                                  report-hide, repeat-offender window/limits).
--   2. moderation_pattern_scan  — Layer A deterministic PII / scam-link patterns
--      + moderation_scan          (dictionary + patterns, with a 'layer' tag).
--   3. moderation_decisions     — per-decision audit (allow/flag/block, category,
--                                  confidence, which layers, self-harm) for EVERY
--                                  check, not just actions taken.
--   4. review_queue             — unified, severity/confidence-ordered human queue
--                                  for FLAGGED items across all three surfaces.
--   5. user_violation_counts    — derived rolling-window view over decisions.
--   6. user_posting_pauses      — soft, temporary, pending-review posting pause
--                                  (repeat-offender SIGNAL; never an auto-ban).
--   7. wellbeing_alerts         — self-harm path: NON-punitive reviewer alert,
--                                  separate from moderation entirely.
--   8. moderation_rescan_queue  — fail-safe: Layer-B outage → allow + queue for
--                                  async re-scan once the classifier recovers.
--   9. study_room_messages       — moderation columns + a Layer-A hard-floor
--                                  trigger (chat had NONE before).
--  10. impersonation terms       — username-specific category (staff/official).
--  11. Pause enforcement + PII/scam + self-harm guard folded into the existing
--      forum/username triggers (recreated) so enforcement is consistent and
--      bypass-proof on all surfaces.
--
-- Idempotent. Depends on the forum-moderation-overhaul migration.
-- ════════════════════════════════════════════════════════════════════════

-- ── 1. Central config — thresholds & windows live here, not inline ─────────
CREATE TABLE IF NOT EXISTS public.moderation_config (
  key   text PRIMARY KEY,
  value jsonb NOT NULL,
  notes text
);
ALTER TABLE public.moderation_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admins manage mod config" ON public.moderation_config;
CREATE POLICY "admins manage mod config" ON public.moderation_config FOR ALL TO authenticated
  USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

INSERT INTO public.moderation_config(key, value, notes) VALUES
  ('thresholds', jsonb_build_object(
      'block_severity', 8,          -- Layer A dictionary/pattern hit at/above → block
      'flag_severity', 5,           -- at/above (but below block) → flag for review
      'ai_block_confidence', 80,    -- Layer B 'block' verdict needs this confidence to block
      'ai_flag_confidence', 45      -- Layer B at/above → flag
   ), 'Severity (1-10 *10 = 0-100) and AI-confidence cutoffs.'),
  ('repeat_offender', jsonb_build_object(
      'window_hours', 168,          -- rolling 7-day window
      'severe_count', 3,            -- this many severe violations in window →
      'pause_hours', 24,            -- temporary posting pause of this length
      'severe_categories', jsonb_build_array('slur','hate','sexual','violence','harassment','scam')
   ), 'Repeat-offender SIGNAL → soft pause pending human review. Never an auto-ban.'),
  ('categories', jsonb_build_array(
      'slur','hate','sexual','violence','harassment','self_harm',
      'pii','doxxing','scam','spam','generic_profanity','impersonation'
   ), 'Canonical category list shared by all surfaces.')
ON CONFLICT (key) DO NOTHING;

-- Read a config blob from SQL (triggers, RPCs) regardless of RLS.
CREATE OR REPLACE FUNCTION public.moderation_cfg(p_key text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT value FROM public.moderation_config WHERE key = p_key;
$$;

-- ── 2. Allow the new categories on the shared dictionary, add impersonation ─
DO $$ BEGIN
  ALTER TABLE public.moderation_terms DROP CONSTRAINT IF EXISTS moderation_terms_category_check;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
ALTER TABLE public.moderation_terms
  ADD CONSTRAINT moderation_terms_category_check CHECK (category IN (
    'slur','hate','sexual','self_harm','violence','spam','generic_profanity',
    'harassment','pii','doxxing','scam','impersonation'
  ));

-- Self-harm reframing: the dictionary's 2nd-person "kill yourself" directives
-- are aggression AT another person → that's HARASSMENT (correctly blocks).
-- Genuine 1st-person distress ("I want to end my life") is not in the
-- dictionary and is judged by Layer B → the supportive path, never a block.
UPDATE public.moderation_terms SET category = 'harassment'
 WHERE term IN ('kys','killyourself','killurself','killyrself','hangyourself','hangurself');

-- Username-specific: impersonation of staff / official Eclipta accounts. Tight,
-- specific patterns to avoid false positives on ordinary handles.
INSERT INTO public.moderation_terms(term, category, severity) VALUES
  ('ecliptastaff','impersonation',7),('ecliptateam','impersonation',7),
  ('ecliptaadmin','impersonation',7),('ecliptamod','impersonation',7),
  ('ecliptaofficial','impersonation',7),('officialeclipta','impersonation',7),
  ('ecliptasupport','impersonation',7),('ecliptahelp','impersonation',7),
  ('ecliptamoderator','impersonation',7),('teameclipta','impersonation',7)
ON CONFLICT (term) DO UPDATE SET category = EXCLUDED.category, severity = EXCLUDED.severity;

-- ── 3. Layer A pattern scan (PII / scam) + combined scan ────────────────────
-- Dictionary matching can't see phone numbers, emails, or scam-link shapes.
-- These are deterministic and run with zero external dependency, same as the
-- dictionary. PII defaults to FLAG severity (context matters); scam links higher.
CREATE OR REPLACE FUNCTION public.moderation_pattern_scan(p_text text)
RETURNS TABLE(category text, severity integer) LANGUAGE plpgsql STABLE SET search_path = public AS $$
DECLARE v text := coalesce(p_text, '');
BEGIN
  -- Email address (doxxing/PII).
  IF v ~* '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' THEN
    RETURN QUERY SELECT 'pii'::text, 5; END IF;
  -- Phone number: 10+ digits allowing common separators.
  IF v ~ '(\+?\d[ .()\-]?){9,}\d' THEN
    RETURN QUERY SELECT 'pii'::text, 5; END IF;
  -- Street address shape ("123 Main Street/Ave/Rd ...").
  IF v ~* '\m\d{1,5}\s+([A-Za-z]+\s){1,3}(street|st|avenue|ave|road|rd|boulevard|blvd|lane|ln|drive|dr)\M' THEN
    RETURN QUERY SELECT 'doxxing'::text, 6; END IF;
  -- Scam/phishing: crypto-giveaway and free-currency lures, link shorteners.
  IF v ~* '(free\s*(robux|vbucks|nitro|crypto|bitcoin|gift\s*card))'
     OR v ~* '((crypto|bitcoin|btc|eth|ethereum)[^.]{0,24}(giveaway|airdrop|double|2x))'
     OR v ~* '(t\.me/|discord\.gg/|bit\.ly/|tinyurl\.com/)[^\s]*\s*(giveaway|crypto|free|nitro)' THEN
    RETURN QUERY SELECT 'scam'::text, 7; END IF;
END; $$;

-- Combined Layer A: dictionary + patterns, each row tagged with its layer.
CREATE OR REPLACE FUNCTION public.moderation_scan(p_text text)
RETURNS TABLE(category text, severity integer, layer text) LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT m.category, m.severity, 'dictionary'::text FROM public.moderation_match(p_text) m
  UNION ALL
  SELECT p.category, p.severity, 'pattern'::text   FROM public.moderation_pattern_scan(p_text) p
  ORDER BY 2 DESC, 1;
$$;

REVOKE ALL ON FUNCTION public.moderation_pattern_scan(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.moderation_scan(text)         FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.moderation_pattern_scan(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.moderation_scan(text)         TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.moderation_cfg(text)          TO authenticated, service_role;

-- ── 4. Per-decision audit log (allow / flag / block, all surfaces) ─────────
CREATE TABLE IF NOT EXISTS public.moderation_decisions (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  surface_type text NOT NULL,                       -- 'forum' | 'username' | 'chat'
  target_type  text NOT NULL,                       -- thread|answer|comment|username|chat_message
  content_ref  uuid,                                -- the row, when known
  author_id    uuid,
  decision     text NOT NULL CHECK (decision IN ('allow','flag','block')),
  category     text,
  confidence   integer,                             -- 0-100
  layers       text[] NOT NULL DEFAULT '{}',        -- which layers fired: dictionary/pattern/ai
  self_harm    boolean NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_moddec_author ON public.moderation_decisions(author_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_moddec_recent ON public.moderation_decisions(created_at DESC);
ALTER TABLE public.moderation_decisions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "mods read decisions" ON public.moderation_decisions;
CREATE POLICY "mods read decisions" ON public.moderation_decisions FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'moderator') OR public.has_role(auth.uid(),'admin'));

-- ── 5. Unified review queue (flagged items, severity/confidence ordered) ───
CREATE TABLE IF NOT EXISTS public.review_queue (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  surface_type text NOT NULL,
  target_type  text NOT NULL,
  content_ref  uuid,
  author_id    uuid,
  snapshot     text,
  category     text,
  confidence   integer NOT NULL DEFAULT 0,
  severity     integer NOT NULL DEFAULT 0,
  status       text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','reviewing','resolved','dismissed')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  resolved_at  timestamptz,
  resolver_id  uuid
);
CREATE INDEX IF NOT EXISTS idx_reviewq_priority ON public.review_queue(status, severity DESC, confidence DESC, created_at);
ALTER TABLE public.review_queue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "mods read review queue" ON public.review_queue;
CREATE POLICY "mods read review queue" ON public.review_queue FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'moderator') OR public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS "mods update review queue" ON public.review_queue;
CREATE POLICY "mods update review queue" ON public.review_queue FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(),'moderator') OR public.has_role(auth.uid(),'admin'));

-- ── 6. Soft posting pause (repeat-offender signal) ─────────────────────────
CREATE TABLE IF NOT EXISTS public.user_posting_pauses (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL,
  until         timestamptz NOT NULL,
  reason        text,
  pending_review boolean NOT NULL DEFAULT true,
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('active','lifted')),
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_pauses_user ON public.user_posting_pauses(user_id, status, until DESC);
ALTER TABLE public.user_posting_pauses ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "see own pause" ON public.user_posting_pauses;
CREATE POLICY "see own pause" ON public.user_posting_pauses FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.has_role(auth.uid(),'moderator') OR public.has_role(auth.uid(),'admin'));

-- Active pause end time for a user (NULL if not paused). Bypasses RLS so
-- triggers can enforce it.
CREATE OR REPLACE FUNCTION public.is_posting_paused(p_user uuid)
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT max(until) FROM public.user_posting_pauses
   WHERE user_id = p_user AND status = 'active' AND until > now();
$$;
GRANT EXECUTE ON FUNCTION public.is_posting_paused(uuid) TO authenticated, service_role;

-- Derived per-user / per-category rolling-window counts (single source = the
-- decisions log, so it can never drift out of sync).
CREATE OR REPLACE VIEW public.user_violation_counts AS
  SELECT author_id AS user_id, category,
         count(*) AS violations,
         max(created_at) AS last_at
    FROM public.moderation_decisions
   WHERE decision IN ('block','flag')
     AND created_at > now() - make_interval(hours =>
           COALESCE((public.moderation_cfg('repeat_offender')->>'window_hours')::int, 168))
   GROUP BY author_id, category;
GRANT SELECT ON public.user_violation_counts TO authenticated;

-- ── 7. Wellbeing alerts (self-harm path — NON-punitive, separate) ──────────
CREATE TABLE IF NOT EXISTS public.wellbeing_alerts (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL,
  surface_type text NOT NULL,
  content_ref  uuid,
  snapshot     text,
  reviewed     boolean NOT NULL DEFAULT false,
  reviewer_id  uuid,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_wellbeing_open ON public.wellbeing_alerts(reviewed, created_at DESC);
ALTER TABLE public.wellbeing_alerts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "mods read wellbeing" ON public.wellbeing_alerts;
CREATE POLICY "mods read wellbeing" ON public.wellbeing_alerts FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'moderator') OR public.has_role(auth.uid(),'admin'));

-- ── 8. Fail-safe re-scan queue (Layer B outage) ────────────────────────────
CREATE TABLE IF NOT EXISTS public.moderation_rescan_queue (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  surface_type text NOT NULL,
  target_type  text NOT NULL,
  content_ref  uuid,
  snapshot     text NOT NULL,
  author_id    uuid,
  reason       text NOT NULL DEFAULT 'classifier_unavailable',
  processed    boolean NOT NULL DEFAULT false,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_rescan_open ON public.moderation_rescan_queue(processed, created_at);
ALTER TABLE public.moderation_rescan_queue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "mods read rescan" ON public.moderation_rescan_queue;
CREATE POLICY "mods read rescan" ON public.moderation_rescan_queue FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(),'moderator') OR public.has_role(auth.uid(),'admin'));

-- ── 9. Outcome applier — ONE chokepoint for every decision's side effects ──
-- Called by the moderate() edge function (service role). Logs the decision,
-- queues flags, routes self-harm to wellbeing, enqueues re-scan if the
-- classifier was down, and applies the repeat-offender soft pause. Returns the
-- pause state so the caller can tell the user.
CREATE OR REPLACE FUNCTION public.apply_moderation_outcome(
  p_surface text, p_target_type text, p_content_ref uuid, p_author uuid,
  p_decision text, p_category text, p_confidence integer, p_layers text[],
  p_self_harm boolean, p_severity integer, p_snapshot text, p_needs_rescan boolean
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cfg jsonb := public.moderation_cfg('repeat_offender');
  v_severe text[]; v_count integer; v_until timestamptz := NULL; v_paused boolean := false;
BEGIN
  -- 1. Always log the decision (allow included).
  INSERT INTO public.moderation_decisions(surface_type, target_type, content_ref, author_id,
            decision, category, confidence, layers, self_harm)
  VALUES (p_surface, p_target_type, p_content_ref, p_author,
          p_decision, p_category, p_confidence, coalesce(p_layers,'{}'), coalesce(p_self_harm,false));

  -- 2. Self-harm → supportive/wellbeing path (NEVER punitive; runs even if the
  --    same content is independently a violation against someone else).
  IF coalesce(p_self_harm, false) THEN
    INSERT INTO public.wellbeing_alerts(user_id, surface_type, content_ref, snapshot)
    VALUES (p_author, p_surface, p_content_ref, left(coalesce(p_snapshot,''), 1000));
  END IF;

  -- 3. Flagged content → unified human review queue.
  IF p_decision = 'flag' THEN
    INSERT INTO public.review_queue(surface_type, target_type, content_ref, author_id,
              snapshot, category, confidence, severity)
    VALUES (p_surface, p_target_type, p_content_ref, p_author,
            left(coalesce(p_snapshot,''), 2000), p_category, coalesce(p_confidence,0), coalesce(p_severity,0));
  END IF;

  -- 4. Classifier was unavailable → queue an async re-scan (fail-open, not silent).
  IF coalesce(p_needs_rescan, false) THEN
    INSERT INTO public.moderation_rescan_queue(surface_type, target_type, content_ref, snapshot, author_id)
    VALUES (p_surface, p_target_type, p_content_ref, left(coalesce(p_snapshot,''), 4000), p_author);
  END IF;

  -- 5. Repeat-offender signal → soft, temporary, pending-review pause. Self-harm
  --    is excluded from the severe set (it is not a punitive category).
  IF p_decision IN ('block','flag') AND p_category IS NOT NULL THEN
    SELECT array_agg(cat) INTO v_severe
      FROM jsonb_array_elements_text(coalesce(v_cfg->'severe_categories','[]'::jsonb)) AS t(cat);
    IF p_category = ANY(coalesce(v_severe,'{}')) AND p_author IS NOT NULL THEN
      SELECT count(*) INTO v_count FROM public.moderation_decisions
       WHERE author_id = p_author AND decision IN ('block','flag')
         AND category = ANY(v_severe)
         AND created_at > now() - make_interval(hours => COALESCE((v_cfg->>'window_hours')::int,168));
      IF v_count >= COALESCE((v_cfg->>'severe_count')::int, 3)
         AND public.is_posting_paused(p_author) IS NULL THEN
        v_until := now() + make_interval(hours => COALESCE((v_cfg->>'pause_hours')::int, 24));
        INSERT INTO public.user_posting_pauses(user_id, until, reason)
        VALUES (p_author, v_until,
                'Auto soft-pause: ' || v_count || ' severe violations in window — pending human review.');
        v_paused := true;
      END IF;
    END IF;
  END IF;

  RETURN jsonb_build_object('paused', v_paused, 'pause_until', v_until);
END; $$;
REVOKE ALL ON FUNCTION public.apply_moderation_outcome(text,text,uuid,uuid,text,text,integer,text[],boolean,integer,text,boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_moderation_outcome(text,text,uuid,uuid,text,text,integer,text[],boolean,integer,text,boolean) TO service_role;

-- ── 10. Chat coverage — moderation columns + Layer-A hard-floor trigger ────
ALTER TABLE public.study_room_messages
  ADD COLUMN IF NOT EXISTS moderation_status   text NOT NULL DEFAULT 'visible',
  ADD COLUMN IF NOT EXISTS moderation_category text,
  ADD COLUMN IF NOT EXISTS moderation_reason   text,
  ADD COLUMN IF NOT EXISTS moderation_score    integer;
DO $$ BEGIN
  ALTER TABLE public.study_room_messages
    ADD CONSTRAINT srm_modstatus_chk CHECK (moderation_status IN ('visible','hidden','removed'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Shared hard-floor helper: returns the strongest blocking match, honoring the
-- self-harm carve-out (self-harm is NEVER a deterministic block) and the
-- configured block severity. NULL category = nothing to block.
CREATE OR REPLACE FUNCTION public.moderation_floor(p_text text)
RETURNS TABLE(category text, severity integer, term_layer text) LANGUAGE plpgsql STABLE SET search_path = public AS $$
DECLARE v_block int := COALESCE((public.moderation_cfg('thresholds')->>'block_severity')::int, 8);
BEGIN
  RETURN QUERY
    SELECT s.category, s.severity, s.layer FROM public.moderation_scan(p_text) s
     WHERE s.severity >= v_block AND s.category <> 'self_harm'
     ORDER BY s.severity DESC LIMIT 1;
END; $$;
GRANT EXECUTE ON FUNCTION public.moderation_floor(text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.study_room_message_moderation_trigger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_hit record;
BEGIN
  -- System lines (idle nudges, teach-back logs) are app-authored — never gate them.
  IF COALESCE(NEW.kind, 'chat') <> 'chat' THEN RETURN NEW; END IF;
  -- Enforce an active posting pause (bypass-proof, even via direct PostgREST).
  IF public.is_posting_paused(NEW.user_id) IS NOT NULL THEN
    RAISE EXCEPTION 'Posting is paused pending review' USING ERRCODE = 'check_violation';
  END IF;
  SELECT * INTO v_hit FROM public.moderation_floor(NEW.body) LIMIT 1;
  IF v_hit.category IS NOT NULL THEN
    INSERT INTO public.moderation_actions(target_type, actor_id, action, source, category, score, reason)
    VALUES ('chat_message', NEW.user_id, 'block_create', 'trigger', v_hit.category, v_hit.severity*10,
            'Chat blocked: ' || v_hit.category);
    RAISE EXCEPTION 'Message rejected by moderation (category: %)', v_hit.category USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_study_room_message_moderation ON public.study_room_messages;
CREATE TRIGGER trg_study_room_message_moderation
  BEFORE INSERT ON public.study_room_messages
  FOR EACH ROW EXECUTE FUNCTION public.study_room_message_moderation_trigger();

-- moderation_actions allows the 'chat_message' target_type now.
DO $$ BEGIN
  ALTER TABLE public.moderation_actions DROP CONSTRAINT IF EXISTS moderation_actions_target_type_check;
EXCEPTION WHEN undefined_object THEN NULL; END $$;
ALTER TABLE public.moderation_actions
  ADD CONSTRAINT moderation_actions_target_type_check
  CHECK (target_type IN ('thread','answer','comment','username','chat_message'));

-- ── 11. Recreate forum + username triggers: add pause enforcement, the PII/
--        scam pattern layer, and the self-harm carve-out. Same hard-floor
--        behavior otherwise (block >= block_severity, hide flag-range). ─────
CREATE OR REPLACE FUNCTION public.forum_content_moderation_trigger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_text text; v_hit record;
  v_block int := COALESCE((public.moderation_cfg('thresholds')->>'block_severity')::int, 8);
  v_flag  int := COALESCE((public.moderation_cfg('thresholds')->>'flag_severity')::int, 5);
BEGIN
  IF public.is_posting_paused(NEW.user_id) IS NOT NULL THEN
    RAISE EXCEPTION 'Posting is paused pending review' USING ERRCODE = 'check_violation';
  END IF;

  v_text := COALESCE(NEW.body, '');
  IF TG_TABLE_NAME = 'forum_threads' THEN
    v_text := v_text || ' ' || COALESCE(NEW.title, '');
    IF NEW.tags IS NOT NULL THEN v_text := v_text || ' ' || array_to_string(NEW.tags, ' '); END IF;
  END IF;

  -- Strongest hit across dictionary + patterns. Self-harm is never a block;
  -- casual profanity is not policed in forum content (non-goal: don't filter
  -- normal banter) — the AI layer judges directed harassment instead.
  SELECT s.category, s.severity INTO v_hit
    FROM public.moderation_scan(v_text) s
   WHERE s.category NOT IN ('self_harm','generic_profanity')
   ORDER BY s.severity DESC LIMIT 1;

  IF v_hit.category IS NULL THEN RETURN NEW; END IF;

  IF v_hit.severity >= v_block THEN
    INSERT INTO public.moderation_actions(target_type, target_id, actor_id, action, source, category, score, reason)
    VALUES (TG_ARGV[0], COALESCE(NEW.id, gen_random_uuid()), NEW.user_id, 'block_create', 'trigger',
            v_hit.category, v_hit.severity*10, 'Matched ' || v_hit.category);
    RAISE EXCEPTION 'Content rejected by moderation (category: %)', v_hit.category USING ERRCODE = 'check_violation';
  END IF;

  IF v_hit.severity >= v_flag THEN
    NEW.moderation_status   := 'hidden';
    NEW.moderation_category := v_hit.category;
    NEW.moderation_score    := v_hit.severity*10;
    NEW.moderation_reason   := 'Auto-hidden: ' || v_hit.category;
    NEW.hidden_at           := COALESCE(NEW.hidden_at, now());
  END IF;
  RETURN NEW;
END; $$;

CREATE OR REPLACE FUNCTION public.user_profile_username_moderation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_hit record;
  v_flag int := COALESCE((public.moderation_cfg('thresholds')->>'flag_severity')::int, 5);
BEGIN
  IF NEW.username IS NULL THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND NEW.username = OLD.username THEN RETURN NEW; END IF;
  IF public.is_posting_paused(NEW.user_id) IS NOT NULL THEN
    RAISE EXCEPTION 'Posting is paused pending review' USING ERRCODE = 'check_violation';
  END IF;
  -- Usernames: the deterministic layer carries more weight. Any hit at/above
  -- the flag severity (slur, sexual, impersonation, ...) blocks the save.
  SELECT s.category, s.severity INTO v_hit
    FROM public.moderation_scan(NEW.username) s
   WHERE s.category <> 'self_harm'
   ORDER BY s.severity DESC LIMIT 1;
  IF v_hit.category IS NOT NULL AND v_hit.severity >= v_flag THEN
    INSERT INTO public.moderation_actions(target_type, actor_id, action, source, category, score, reason)
    VALUES ('username', NEW.user_id, 'block_create', 'trigger', v_hit.category, v_hit.severity*10,
            'Username matched ' || v_hit.category);
    RAISE EXCEPTION 'Username rejected by moderation' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END; $$;

NOTIFY pgrst, 'reload schema';
