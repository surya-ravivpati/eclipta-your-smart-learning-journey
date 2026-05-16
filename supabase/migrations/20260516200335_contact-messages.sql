-- ════════════════════════════════════════════════════════════════════════
-- Contact messages from the About page "Send us a message" form.
--
-- Previously the form built a `mailto:` link and shoved the user into their
-- email client — which silently fails when no client is configured, gives
-- the operator no record of the submission, and breaks completely on
-- mobile browsers that route mailto: nowhere. This migration replaces it
-- with a real backend: messages land in contact_messages, a small RPC
-- enforces validation + rate limiting + moderation, and the admin role
-- can browse the inbox via RLS.
-- ════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.contact_messages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at  timestamptz NOT NULL DEFAULT now(),
  -- Anonymous submitters are allowed; user_id is filled in when authenticated.
  user_id     uuid,
  name        text NOT NULL,
  email       text NOT NULL,
  subject     text,
  message     text NOT NULL,
  status      text NOT NULL DEFAULT 'new'
                CHECK (status IN ('new','read','replied','archived','spam')),
  user_agent  text,
  -- Mirror of the moderation pipeline used by forum content.
  moderation_status   text NOT NULL DEFAULT 'visible'
                        CHECK (moderation_status IN ('visible','hidden','removed')),
  moderation_score    integer,
  moderation_category text,
  read_at     timestamptz,
  replied_at  timestamptz,
  replied_by  uuid
);

CREATE INDEX IF NOT EXISTS idx_contact_messages_created   ON public.contact_messages(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_contact_messages_status    ON public.contact_messages(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_contact_messages_email     ON public.contact_messages(email, created_at DESC);

ALTER TABLE public.contact_messages ENABLE ROW LEVEL SECURITY;

-- Public form: no client-side INSERT. All inserts go through the RPC so we
-- can enforce rate limiting + moderation + length checks.
DROP POLICY IF EXISTS "Admins read messages" ON public.contact_messages;
CREATE POLICY "Admins read messages" ON public.contact_messages
  FOR SELECT USING (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Admins update messages" ON public.contact_messages;
CREATE POLICY "Admins update messages" ON public.contact_messages
  FOR UPDATE USING (public.has_role(auth.uid(), 'admin'));

-- ── submit_contact_message RPC ───────────────────────────────────────────
-- Accepts both signed-in and anonymous submitters. Enforces:
--   * Length bounds on every field.
--   * Crude email shape check (don't try to validate RFC 5322 in pgsql).
--   * Per-email rate limit: max 3 submissions per hour, max 10 per day.
--   * Moderation: runs the same banned-term filter the forum uses so
--     spammers can't slide slurs into the inbox.
CREATE OR REPLACE FUNCTION public.submit_contact_message(
  p_name    text,
  p_email   text,
  p_subject text,
  p_message text,
  p_user_agent text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_name      text := btrim(coalesce(p_name, ''));
  v_email     text := lower(btrim(coalesce(p_email, '')));
  v_subject   text := btrim(coalesce(p_subject, ''));
  v_message   text := btrim(coalesce(p_message, ''));
  v_recent    integer;
  v_match     record;
  v_mod_status text := 'visible';
  v_id        uuid;
BEGIN
  IF length(v_name) < 2     OR length(v_name)    > 80   THEN RAISE EXCEPTION 'Name must be 2–80 characters'; END IF;
  IF length(v_email) < 5    OR length(v_email)   > 200  THEN RAISE EXCEPTION 'Invalid email length'; END IF;
  IF v_email !~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' THEN
    RAISE EXCEPTION 'Please enter a valid email address';
  END IF;
  IF length(v_message) < 10 OR length(v_message) > 4000 THEN RAISE EXCEPTION 'Message must be 10–4000 characters'; END IF;
  IF length(v_subject) > 200 THEN v_subject := left(v_subject, 200); END IF;

  -- Rate limit per email so a bot can't fill the inbox.
  SELECT count(*) INTO v_recent
    FROM public.contact_messages
   WHERE email = v_email
     AND created_at > now() - interval '1 hour';
  IF v_recent >= 3 THEN
    RAISE EXCEPTION 'You''ve sent several messages recently — please wait a bit before sending another.';
  END IF;
  SELECT count(*) INTO v_recent
    FROM public.contact_messages
   WHERE email = v_email
     AND created_at > now() - interval '1 day';
  IF v_recent >= 10 THEN
    RAISE EXCEPTION 'Daily message limit reached for this email.';
  END IF;

  -- Run the forum moderation matcher against the combined text.
  SELECT * INTO v_match
    FROM public.moderation_match(v_name || E'\n' || coalesce(v_subject,'') || E'\n' || v_message)
   LIMIT 1;

  IF v_match.term IS NOT NULL THEN
    IF v_match.severity >= 8 THEN
      RAISE EXCEPTION 'Message rejected by moderation';
    END IF;
    v_mod_status := 'hidden';
  END IF;

  INSERT INTO public.contact_messages(
    user_id, name, email, subject, message, user_agent,
    moderation_status, moderation_category, moderation_score
  )
  VALUES (
    v_uid, v_name, v_email, NULLIF(v_subject, ''), v_message,
    NULLIF(left(coalesce(p_user_agent,''), 500), ''),
    v_mod_status, v_match.category, COALESCE(v_match.severity * 10, NULL)
  )
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('ok', true, 'id', v_id, 'moderation_status', v_mod_status);
END;
$$;

-- Open to anyone — that's the whole point of a public contact form.
REVOKE ALL ON FUNCTION public.submit_contact_message(text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_contact_message(text, text, text, text, text) TO anon, authenticated;
