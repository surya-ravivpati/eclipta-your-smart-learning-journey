
-- ============================================================
-- 1. Profanity filter (server-side, bypass-proof)
-- ============================================================
CREATE OR REPLACE FUNCTION public.normalize_text(t text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE r text;
BEGIN
  IF t IS NULL THEN RETURN ''; END IF;
  r := lower(t);
  -- approximate leet-speak collapse (translate requires equal-length pairs)
  r := translate(r, '0134578!@$', 'oieasbtias');
  -- collapse 3+ repeated chars to 2 ("fuuuuck" -> "fuuck")
  r := regexp_replace(r, '(.)\1{2,}', '\1\1', 'g');
  -- drop everything but a-z so "f.u_c.k" -> "fuck"
  r := regexp_replace(r, '[^a-z]', '', 'g');
  RETURN r;
END $$;

CREATE OR REPLACE FUNCTION public.contains_profanity(t text)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  n text;
  w text;
  words text[] := ARRAY[
    -- slurs
    'nigger','nigga','chink','spic','kike','gook','wetback','tranny','faggot','fag','dyke',
    'retard','retarded','cripple','spaz','homo',
    -- profanity
    'fuck','fucker','fucking','shit','bitch','bastard','cunt','asshole','arsehole',
    'dick','cock','pussy','whore','slut','motherfucker','bullshit','bollocks','wank','wanker',
    'twat','prick','damnit','goddamn','jackass',
    -- sexual / abuse
    'rape','rapist','pedo','pedophile','molest','incest',
    -- self-harm baiting
    'kys','killyourself','killurself'
  ];
BEGIN
  IF t IS NULL OR length(t) = 0 THEN RETURN false; END IF;
  n := public.normalize_text(t);
  IF n = '' THEN RETURN false; END IF;
  FOREACH w IN ARRAY words LOOP
    IF position(w in n) > 0 THEN RETURN true; END IF;
  END LOOP;
  RETURN false;
END $$;

-- BEFORE INSERT/UPDATE guards on user content
CREATE OR REPLACE FUNCTION public.reject_profanity_thread()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF public.contains_profanity(NEW.title) OR public.contains_profanity(NEW.body) THEN
    RAISE EXCEPTION 'Content contains language we don''t allow.' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.reject_profanity_answer()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF public.contains_profanity(NEW.body) THEN
    RAISE EXCEPTION 'Content contains language we don''t allow.' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.reject_profanity_comment()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF public.contains_profanity(NEW.body) THEN
    RAISE EXCEPTION 'Content contains language we don''t allow.' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.reject_profanity_profile()
RETURNS trigger LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NEW.username IS NOT NULL AND public.contains_profanity(NEW.username) THEN
    RAISE EXCEPTION 'Username contains language we don''t allow.' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.bio IS NOT NULL AND public.contains_profanity(NEW.bio) THEN
    RAISE EXCEPTION 'Bio contains language we don''t allow.' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS forum_threads_profanity ON public.forum_threads;
CREATE TRIGGER forum_threads_profanity
BEFORE INSERT OR UPDATE OF title, body ON public.forum_threads
FOR EACH ROW EXECUTE FUNCTION public.reject_profanity_thread();

DROP TRIGGER IF EXISTS forum_answers_profanity ON public.forum_answers;
CREATE TRIGGER forum_answers_profanity
BEFORE INSERT OR UPDATE OF body ON public.forum_answers
FOR EACH ROW EXECUTE FUNCTION public.reject_profanity_answer();

DROP TRIGGER IF EXISTS forum_comments_profanity ON public.forum_comments;
CREATE TRIGGER forum_comments_profanity
BEFORE INSERT OR UPDATE OF body ON public.forum_comments
FOR EACH ROW EXECUTE FUNCTION public.reject_profanity_comment();

DROP TRIGGER IF EXISTS user_profiles_profanity ON public.user_profiles;
CREATE TRIGGER user_profiles_profanity
BEFORE INSERT OR UPDATE OF username, bio ON public.user_profiles
FOR EACH ROW EXECUTE FUNCTION public.reject_profanity_profile();

-- ============================================================
-- 2. Notifications table
-- ============================================================
CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  actor_id uuid,
  type text NOT NULL,         -- follow | reply | comment | accepted | mention_thread | mention_answer | mention_comment
  link text,
  meta jsonb NOT NULL DEFAULT '{}'::jsonb,
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users view own notifications" ON public.notifications;
CREATE POLICY "Users view own notifications"
ON public.notifications FOR SELECT USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users update own notifications" ON public.notifications;
CREATE POLICY "Users update own notifications"
ON public.notifications FOR UPDATE USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users delete own notifications" ON public.notifications;
CREATE POLICY "Users delete own notifications"
ON public.notifications FOR DELETE USING (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
  ON public.notifications(user_id, read, created_at DESC);

-- ============================================================
-- 3. Mention parsing helper
-- ============================================================
CREATE OR REPLACE FUNCTION public.notify_mentions(
  p_text text,
  p_actor_id uuid,
  p_link text,
  p_kind text,
  p_meta jsonb
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  rec record;
  uid uuid;
BEGIN
  IF p_text IS NULL OR length(p_text) = 0 THEN RETURN; END IF;
  FOR rec IN
    SELECT DISTINCT lower(m[1]) AS u
    FROM regexp_matches(p_text, '@([a-zA-Z0-9_]{3,20})', 'g') AS m
  LOOP
    SELECT user_id INTO uid FROM public.user_profiles WHERE lower(username) = rec.u;
    IF uid IS NOT NULL AND uid != p_actor_id THEN
      INSERT INTO public.notifications(user_id, actor_id, type, link, meta)
      VALUES (uid, p_actor_id, 'mention_'||p_kind, p_link, p_meta);
    END IF;
  END LOOP;
END $$;

-- ============================================================
-- 4. Activity triggers
-- ============================================================
CREATE OR REPLACE FUNCTION public.notify_on_thread()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.notify_mentions(
    NEW.title || E'\n' || NEW.body,
    NEW.user_id,
    '/forum/'||NEW.id,
    'thread',
    jsonb_build_object('title', NEW.title, 'author', NEW.author_name)
  );
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.notify_on_answer()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t_owner uuid; t_title text;
BEGIN
  SELECT user_id, title INTO t_owner, t_title FROM public.forum_threads WHERE id = NEW.thread_id;
  IF t_owner IS NOT NULL AND t_owner != NEW.user_id THEN
    INSERT INTO public.notifications(user_id, actor_id, type, link, meta)
    VALUES (t_owner, NEW.user_id, 'reply', '/forum/'||NEW.thread_id,
      jsonb_build_object('title', t_title, 'author', NEW.author_name));
  END IF;
  PERFORM public.notify_mentions(NEW.body, NEW.user_id, '/forum/'||NEW.thread_id, 'answer',
    jsonb_build_object('title', t_title, 'author', NEW.author_name));
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.notify_on_comment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE a_owner uuid; t_id uuid; t_title text;
BEGIN
  SELECT user_id, thread_id INTO a_owner, t_id FROM public.forum_answers WHERE id = NEW.answer_id;
  IF t_id IS NOT NULL THEN
    SELECT title INTO t_title FROM public.forum_threads WHERE id = t_id;
  END IF;
  IF a_owner IS NOT NULL AND a_owner != NEW.user_id THEN
    INSERT INTO public.notifications(user_id, actor_id, type, link, meta)
    VALUES (a_owner, NEW.user_id, 'comment', '/forum/'||t_id,
      jsonb_build_object('title', t_title, 'author', NEW.author_name));
  END IF;
  PERFORM public.notify_mentions(NEW.body, NEW.user_id, '/forum/'||t_id, 'comment',
    jsonb_build_object('title', t_title, 'author', NEW.author_name));
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.notify_on_follow()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE follower_name text;
BEGIN
  SELECT username INTO follower_name FROM public.user_profiles WHERE user_id = NEW.follower_id;
  INSERT INTO public.notifications(user_id, actor_id, type, link, meta)
  VALUES (
    NEW.following_id, NEW.follower_id, 'follow',
    CASE WHEN follower_name IS NOT NULL THEN '/u/'||follower_name ELSE NULL END,
    jsonb_build_object('username', follower_name)
  );
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.notify_on_accept()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE t_title text;
BEGIN
  IF NEW.accepted = true AND (OLD.accepted IS DISTINCT FROM true) AND NEW.user_id != COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid) THEN
    SELECT title INTO t_title FROM public.forum_threads WHERE id = NEW.thread_id;
    INSERT INTO public.notifications(user_id, actor_id, type, link, meta)
    VALUES (NEW.user_id, auth.uid(), 'accepted', '/forum/'||NEW.thread_id,
      jsonb_build_object('title', t_title));
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS forum_threads_notify ON public.forum_threads;
CREATE TRIGGER forum_threads_notify
AFTER INSERT ON public.forum_threads
FOR EACH ROW EXECUTE FUNCTION public.notify_on_thread();

DROP TRIGGER IF EXISTS forum_answers_notify ON public.forum_answers;
CREATE TRIGGER forum_answers_notify
AFTER INSERT ON public.forum_answers
FOR EACH ROW EXECUTE FUNCTION public.notify_on_answer();

DROP TRIGGER IF EXISTS forum_comments_notify ON public.forum_comments;
CREATE TRIGGER forum_comments_notify
AFTER INSERT ON public.forum_comments
FOR EACH ROW EXECUTE FUNCTION public.notify_on_comment();

DROP TRIGGER IF EXISTS user_follows_notify ON public.user_follows;
CREATE TRIGGER user_follows_notify
AFTER INSERT ON public.user_follows
FOR EACH ROW EXECUTE FUNCTION public.notify_on_follow();

DROP TRIGGER IF EXISTS forum_answers_accept_notify ON public.forum_answers;
CREATE TRIGGER forum_answers_accept_notify
AFTER UPDATE OF accepted ON public.forum_answers
FOR EACH ROW EXECUTE FUNCTION public.notify_on_accept();
