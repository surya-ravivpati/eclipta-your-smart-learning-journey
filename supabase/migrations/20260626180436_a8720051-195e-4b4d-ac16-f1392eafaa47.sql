-- Apply prerequisite foundation: forum moderation overhaul (idempotent).
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
DO $$ BEGIN ALTER TABLE public.forum_threads  ADD CONSTRAINT forum_threads_modstatus_chk  CHECK (moderation_status IN ('visible','pending','hidden','removed')); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE public.forum_answers  ADD CONSTRAINT forum_answers_modstatus_chk  CHECK (moderation_status IN ('visible','pending','hidden','removed')); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN ALTER TABLE public.forum_comments ADD CONSTRAINT forum_comments_modstatus_chk CHECK (moderation_status IN ('visible','pending','hidden','removed')); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
CREATE INDEX IF NOT EXISTS idx_forum_threads_modstatus  ON public.forum_threads(moderation_status)  WHERE moderation_status <> 'visible';
CREATE INDEX IF NOT EXISTS idx_forum_answers_modstatus  ON public.forum_answers(moderation_status)  WHERE moderation_status <> 'visible';
CREATE INDEX IF NOT EXISTS idx_forum_comments_modstatus ON public.forum_comments(moderation_status) WHERE moderation_status <> 'visible';

ALTER TABLE public.forum_reports
  ADD COLUMN IF NOT EXISTS resolver_id     uuid,
  ADD COLUMN IF NOT EXISTS resolution_note text;
DELETE FROM public.forum_reports a USING public.forum_reports b
 WHERE a.id > b.id AND a.reporter_id = b.reporter_id AND a.target_id = b.target_id AND a.target_type = b.target_type;
DO $$ BEGIN ALTER TABLE public.forum_reports ADD CONSTRAINT forum_reports_unique_per_user UNIQUE (reporter_id, target_type, target_id); EXCEPTION WHEN duplicate_object THEN NULL; END $$;
CREATE INDEX IF NOT EXISTS idx_forum_reports_target ON public.forum_reports(target_type, target_id, status);
CREATE INDEX IF NOT EXISTS idx_forum_reports_reporter_recent ON public.forum_reports(reporter_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.moderation_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_type   text NOT NULL CHECK (target_type IN ('thread','answer','comment','username')),
  target_id     uuid,
  actor_id      uuid,
  action        text NOT NULL CHECK (action IN ('auto_hide','auto_remove','hide','remove','restore','block_create','dismiss')),
  source        text NOT NULL CHECK (source IN ('trigger','report_threshold','ai','moderator','system')),
  category      text, score integer, reason text, payload jsonb,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_moderation_actions_target ON public.moderation_actions(target_type, target_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_moderation_actions_recent ON public.moderation_actions(created_at DESC);
GRANT SELECT ON public.moderation_actions TO authenticated;
GRANT ALL ON public.moderation_actions TO service_role;
ALTER TABLE public.moderation_actions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Mods view moderation log" ON public.moderation_actions;
CREATE POLICY "Mods view moderation log" ON public.moderation_actions
  FOR SELECT USING (public.has_role(auth.uid(),'moderator') OR public.has_role(auth.uid(),'admin'));

CREATE TABLE IF NOT EXISTS public.moderation_terms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  term      text NOT NULL UNIQUE,
  category  text NOT NULL CHECK (category IN ('slur','sexual','self_harm','violence','spam','generic_profanity')),
  severity  integer NOT NULL CHECK (severity BETWEEN 1 AND 10),
  notes     text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.moderation_terms TO authenticated;
GRANT ALL ON public.moderation_terms TO service_role;
ALTER TABLE public.moderation_terms ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Mods read terms" ON public.moderation_terms;
CREATE POLICY "Mods read terms" ON public.moderation_terms FOR SELECT USING (public.has_role(auth.uid(),'moderator') OR public.has_role(auth.uid(),'admin'));
DROP POLICY IF EXISTS "Admins write terms" ON public.moderation_terms;
CREATE POLICY "Admins write terms" ON public.moderation_terms FOR ALL USING (public.has_role(auth.uid(),'admin')) WITH CHECK (public.has_role(auth.uid(),'admin'));

INSERT INTO public.moderation_terms(term, category, severity) VALUES
  ('nigger','slur',10),('nigga','slur',9),('chink','slur',10),('spic','slur',10),
  ('kike','slur',10),('gook','slur',10),('wetback','slur',10),('tranny','slur',9),
  ('faggot','slur',10),('fag','slur',9),('dyke','slur',9),('retard','slur',8),('retarded','slur',8),
  ('rape','sexual',9),('rapist','sexual',9),('pedo','sexual',10),('pedophile','sexual',10),
  ('molest','sexual',9),('childporn','sexual',10),('cumshot','sexual',7),
  ('kys','self_harm',10),('killyourself','self_harm',10),('killurself','self_harm',10),
  ('killyrself','self_harm',10),('hangyourself','self_harm',10),('hangurself','self_harm',10),
  ('fuck','generic_profanity',5),('fucker','generic_profanity',5),('fucking','generic_profanity',5),
  ('motherfucker','generic_profanity',6),('shit','generic_profanity',5),
  ('bullshit','generic_profanity',4),('bitch','generic_profanity',6),
  ('bastard','generic_profanity',5),('cunt','generic_profanity',7),
  ('asshole','generic_profanity',5),('dick','generic_profanity',5),
  ('cock','generic_profanity',5),('pussy','generic_profanity',5),
  ('whore','generic_profanity',6),('slut','generic_profanity',6),
  ('viagra','spam',8),('cialis','spam',8),('onlyfans','spam',7),
  ('freerobux','spam',7),('cryptogiveaway','spam',7),('clickhere','spam',3),('buynow','spam',2)
ON CONFLICT (term) DO UPDATE SET category = EXCLUDED.category, severity = EXCLUDED.severity;

CREATE OR REPLACE FUNCTION public.normalize_for_moderation(p_text text)
RETURNS text LANGUAGE plpgsql IMMUTABLE SET search_path = public AS $$
DECLARE v text;
BEGIN
  IF p_text IS NULL THEN RETURN ''; END IF;
  v := lower(p_text);
  v := regexp_replace(v, E'[\u200B\u200C\u200D\u200E\u200F\u2060\uFEFF]', '', 'g');
  v := translate(v, 'аеорсхукйі' || 'αεορυνικ', 'aeopcxykji' || 'aeopynik');
  v := translate(v, '0134578!@$', 'oieastbias');
  v := regexp_replace(v, '(.)\1{2,}', '\1\1', 'g');
  v := regexp_replace(v, '[^a-z]', '', 'g');
  RETURN v;
END; $$;

CREATE OR REPLACE FUNCTION public.moderation_match(p_text text)
RETURNS TABLE(term text, category text, severity integer)
LANGUAGE plpgsql STABLE SET search_path = public AS $$
DECLARE v_norm text := public.normalize_for_moderation(p_text);
BEGIN
  IF v_norm = '' THEN RETURN; END IF;
  RETURN QUERY SELECT t.term, t.category, t.severity FROM public.moderation_terms t
    WHERE position(t.term in v_norm) > 0 ORDER BY t.severity DESC, length(t.term) DESC;
END; $$;
REVOKE ALL ON FUNCTION public.normalize_for_moderation(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.moderation_match(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.normalize_for_moderation(text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.moderation_match(text) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.forum_content_moderation_trigger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_text text; v_match record;
BEGIN
  v_text := COALESCE(NEW.body, '');
  IF TG_TABLE_NAME = 'forum_threads' THEN
    v_text := v_text || ' ' || COALESCE(NEW.title, '');
    IF NEW.tags IS NOT NULL THEN v_text := v_text || ' ' || array_to_string(NEW.tags, ' '); END IF;
  END IF;
  SELECT * INTO v_match FROM public.moderation_match(v_text) LIMIT 1;
  IF v_match.term IS NULL THEN RETURN NEW; END IF;
  IF v_match.severity >= 8 THEN
    INSERT INTO public.moderation_actions(target_type, target_id, actor_id, action, source, category, score, reason)
    VALUES (TG_ARGV[0], COALESCE(NEW.id, gen_random_uuid()), NEW.user_id, 'block_create','trigger',
            v_match.category, v_match.severity*10, 'Matched banned term');
    RAISE EXCEPTION 'Content rejected by moderation (category: %)', v_match.category USING ERRCODE='check_violation';
  END IF;
  NEW.moderation_status := 'hidden';
  NEW.moderation_category := v_match.category;
  NEW.moderation_score := v_match.severity*10;
  NEW.moderation_reason := 'Auto-hidden';
  NEW.hidden_at := COALESCE(NEW.hidden_at, now());
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_forum_threads_moderation ON public.forum_threads;
CREATE TRIGGER trg_forum_threads_moderation BEFORE INSERT OR UPDATE OF body, title, tags ON public.forum_threads
  FOR EACH ROW EXECUTE FUNCTION public.forum_content_moderation_trigger('thread');
DROP TRIGGER IF EXISTS trg_forum_answers_moderation ON public.forum_answers;
CREATE TRIGGER trg_forum_answers_moderation BEFORE INSERT OR UPDATE OF body ON public.forum_answers
  FOR EACH ROW EXECUTE FUNCTION public.forum_content_moderation_trigger('answer');
DROP TRIGGER IF EXISTS trg_forum_comments_moderation ON public.forum_comments;
CREATE TRIGGER trg_forum_comments_moderation BEFORE INSERT OR UPDATE OF body ON public.forum_comments
  FOR EACH ROW EXECUTE FUNCTION public.forum_content_moderation_trigger('comment');

CREATE OR REPLACE FUNCTION public.user_profile_username_moderation()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_match record;
BEGIN
  IF NEW.username IS NULL THEN RETURN NEW; END IF;
  IF TG_OP='UPDATE' AND NEW.username = OLD.username THEN RETURN NEW; END IF;
  SELECT * INTO v_match FROM public.moderation_match(NEW.username) LIMIT 1;
  IF v_match.term IS NOT NULL AND v_match.severity >= 5 THEN
    INSERT INTO public.moderation_actions(target_type, actor_id, action, source, category, score, reason)
    VALUES ('username', NEW.user_id, 'block_create', 'trigger', v_match.category, v_match.severity*10, 'Username matched');
    RAISE EXCEPTION 'Username rejected by moderation' USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_user_profiles_username_moderation ON public.user_profiles;
CREATE TRIGGER trg_user_profiles_username_moderation BEFORE INSERT OR UPDATE OF username ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.user_profile_username_moderation();

CREATE OR REPLACE FUNCTION public.submit_forum_report(p_target_type text, p_target_id uuid, p_reason text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_author_id uuid; v_recent integer; v_existing uuid; v_count integer; v_status text;
  HIDE_THRESHOLD constant integer := 3;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_target_type NOT IN ('thread','answer','comment') THEN RAISE EXCEPTION 'Invalid target type'; END IF;
  IF p_target_id IS NULL THEN RAISE EXCEPTION 'Missing target'; END IF;
  IF coalesce(length(trim(p_reason)),0) < 3 THEN RAISE EXCEPTION 'Reason too short'; END IF;
  IF p_target_type='thread' THEN SELECT user_id, moderation_status INTO v_author_id, v_status FROM public.forum_threads WHERE id=p_target_id;
  ELSIF p_target_type='answer' THEN SELECT user_id, moderation_status INTO v_author_id, v_status FROM public.forum_answers WHERE id=p_target_id;
  ELSE SELECT user_id, moderation_status INTO v_author_id, v_status FROM public.forum_comments WHERE id=p_target_id; END IF;
  IF v_author_id IS NULL THEN RAISE EXCEPTION 'Target not found'; END IF;
  IF v_author_id=v_uid THEN RAISE EXCEPTION 'You cannot report your own content'; END IF;
  SELECT count(*) INTO v_recent FROM public.forum_reports WHERE reporter_id=v_uid AND created_at > now()-interval '1 hour';
  IF v_recent >= 10 THEN RAISE EXCEPTION 'Reporting rate limit reached.'; END IF;
  SELECT id INTO v_existing FROM public.forum_reports WHERE reporter_id=v_uid AND target_type=p_target_type AND target_id=p_target_id;
  IF v_existing IS NOT NULL THEN
    UPDATE public.forum_reports SET reason=left(p_reason,600), status='pending' WHERE id=v_existing;
    RETURN jsonb_build_object('ok', true, 'deduplicated', true);
  END IF;
  INSERT INTO public.forum_reports(reporter_id, target_type, target_id, reason)
  VALUES (v_uid, p_target_type, p_target_id, left(p_reason,600));
  RETURN jsonb_build_object('ok', true);
END; $$;
REVOKE ALL ON FUNCTION public.submit_forum_report(text,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_forum_report(text,uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_moderation_status(p_target_type text, p_target_id uuid, p_status text, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_action text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT (public.has_role(v_uid,'moderator') OR public.has_role(v_uid,'admin')) THEN RAISE EXCEPTION 'Moderator role required'; END IF;
  IF p_target_type NOT IN ('thread','answer','comment') THEN RAISE EXCEPTION 'Invalid target type'; END IF;
  IF p_status NOT IN ('visible','hidden','removed') THEN RAISE EXCEPTION 'Invalid status'; END IF;
  v_action := CASE p_status WHEN 'visible' THEN 'restore' WHEN 'hidden' THEN 'hide' ELSE 'remove' END;
  IF p_target_type='thread' THEN UPDATE public.forum_threads SET moderation_status=p_status, moderation_reason=COALESCE(p_reason,moderation_reason), hidden_at=CASE WHEN p_status='visible' THEN NULL ELSE COALESCE(hidden_at,now()) END WHERE id=p_target_id;
  ELSIF p_target_type='answer' THEN UPDATE public.forum_answers SET moderation_status=p_status, moderation_reason=COALESCE(p_reason,moderation_reason), hidden_at=CASE WHEN p_status='visible' THEN NULL ELSE COALESCE(hidden_at,now()) END WHERE id=p_target_id;
  ELSE UPDATE public.forum_comments SET moderation_status=p_status, moderation_reason=COALESCE(p_reason,moderation_reason), hidden_at=CASE WHEN p_status='visible' THEN NULL ELSE COALESCE(hidden_at,now()) END WHERE id=p_target_id; END IF;
  INSERT INTO public.moderation_actions(target_type, target_id, actor_id, action, source, reason)
  VALUES (p_target_type, p_target_id, v_uid, v_action, 'moderator', p_reason);
  RETURN jsonb_build_object('ok', true, 'status', p_status);
END; $$;
REVOKE ALL ON FUNCTION public.set_moderation_status(text,uuid,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_moderation_status(text,uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.apply_ai_moderation_result(p_target_type text, p_target_id uuid, p_verdict text, p_category text, p_score integer, p_reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_action text; v_new_status text;
BEGIN
  IF p_verdict NOT IN ('allow','hide','block') THEN RAISE EXCEPTION 'Invalid verdict'; END IF;
  IF p_target_type NOT IN ('thread','answer','comment') THEN RAISE EXCEPTION 'Invalid target type'; END IF;
  v_new_status := CASE p_verdict WHEN 'allow' THEN 'visible' WHEN 'hide' THEN 'hidden' ELSE 'removed' END;
  v_action := CASE p_verdict WHEN 'allow' THEN 'restore' WHEN 'hide' THEN 'auto_hide' ELSE 'auto_remove' END;
  IF p_target_type='thread' THEN UPDATE public.forum_threads SET moderation_status=v_new_status, moderation_reason=COALESCE(p_reason,moderation_reason), moderation_score=GREATEST(COALESCE(moderation_score,0),COALESCE(p_score,0)), moderation_category=COALESCE(p_category,moderation_category) WHERE id=p_target_id;
  ELSIF p_target_type='answer' THEN UPDATE public.forum_answers SET moderation_status=v_new_status, moderation_reason=COALESCE(p_reason,moderation_reason), moderation_score=GREATEST(COALESCE(moderation_score,0),COALESCE(p_score,0)), moderation_category=COALESCE(p_category,moderation_category) WHERE id=p_target_id;
  ELSE UPDATE public.forum_comments SET moderation_status=v_new_status, moderation_reason=COALESCE(p_reason,moderation_reason), moderation_score=GREATEST(COALESCE(moderation_score,0),COALESCE(p_score,0)), moderation_category=COALESCE(p_category,moderation_category) WHERE id=p_target_id; END IF;
  INSERT INTO public.moderation_actions(target_type, target_id, actor_id, action, source, category, score, reason)
  VALUES (p_target_type, p_target_id, NULL, v_action, 'ai', p_category, p_score, p_reason);
END; $$;
REVOKE ALL ON FUNCTION public.apply_ai_moderation_result(text,uuid,text,text,integer,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.apply_ai_moderation_result(text,uuid,text,text,integer,text) TO service_role;

NOTIFY pgrst, 'reload schema';