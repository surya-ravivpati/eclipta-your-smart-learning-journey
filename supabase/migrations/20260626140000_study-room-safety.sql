-- Safety & Infrastructure Essentials for Study Rooms — the access-control,
-- abuse-protection, and reliability layer under the room features. Invisible
-- when working; load-bearing when not.
--
--   1. Host powers      — host_id (mutable, succeeds on leave), regenerate code,
--                         remove member (+ per-room removed list), join guard.
--   2. Report & Block   — study_room_reports (mirrors forum_reports' durable,
--                         moderator-queryable shape) + account-level blocked_users.
--   3. AI rate limiting — ai_call_log + check_ai_rate_limit (per-user window).
--   5. Abandoned cleanup— cleanup_abandoned_rooms(), window in ONE place.
--
-- Reuses what already exists: last_activity_at + touch_room_activity (clock
-- migration), has_role() (forum moderation), is_study_member().
-- Idempotent. Depends on the study-rooms + clock migrations.

-- ── 1. Host powers + per-room removed list ─────────────────────────────────
ALTER TABLE public.study_rooms
  ADD COLUMN IF NOT EXISTS host_id          uuid,
  ADD COLUMN IF NOT EXISTS removed_user_ids uuid[] NOT NULL DEFAULT '{}';
UPDATE public.study_rooms SET host_id = owner_id WHERE host_id IS NULL;

-- Regenerate the join code (host only). The old code stops working for new
-- joins immediately; current members are untouched (membership, not the code,
-- is what keeps them in). Private rooms only — public rooms have no gate.
CREATE OR REPLACE FUNCTION public.regenerate_room_code(p_room uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_host uuid; v_public boolean; v_code text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT host_id, is_public INTO v_host, v_public FROM public.study_rooms WHERE id = p_room;
  IF v_host IS NULL THEN RAISE EXCEPTION 'Room not found'; END IF;
  IF v_host <> v_uid THEN RAISE EXCEPTION 'Only the host can regenerate the code'; END IF;
  IF v_public THEN RAISE EXCEPTION 'Public rooms do not use a join code'; END IF;
  v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 6));
  UPDATE public.study_rooms SET join_code = v_code, last_activity_at = now() WHERE id = p_room;
  RETURN v_code;
END; $$;

-- Remove a member (host only). They leave immediately and land on the room's
-- removed list, so the still-valid code won't let them back in — only a fresh
-- code or being taken off the list lets them return.
CREATE OR REPLACE FUNCTION public.remove_room_member(p_room uuid, p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_host uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT host_id INTO v_host FROM public.study_rooms WHERE id = p_room;
  IF v_host IS NULL THEN RAISE EXCEPTION 'Room not found'; END IF;
  IF v_host <> v_uid THEN RAISE EXCEPTION 'Only the host can remove members'; END IF;
  IF p_user = v_host THEN RAISE EXCEPTION 'The host cannot remove themselves'; END IF;
  DELETE FROM public.study_room_members WHERE room_id = p_room AND user_id = p_user;
  UPDATE public.study_rooms
     SET removed_user_ids = (SELECT array_agg(DISTINCT u)
                             FROM unnest(removed_user_ids || p_user) AS u),
         last_activity_at = now()
   WHERE id = p_room;
END; $$;

-- Take a member off the removed list (host only) so they can rejoin.
CREATE OR REPLACE FUNCTION public.allow_room_member(p_room uuid, p_user uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_host uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT host_id INTO v_host FROM public.study_rooms WHERE id = p_room;
  IF v_host IS NULL OR v_host <> v_uid THEN RAISE EXCEPTION 'Only the host can do this'; END IF;
  UPDATE public.study_rooms
     SET removed_user_ids = array_remove(removed_user_ids, p_user)
   WHERE id = p_room;
END; $$;

-- Join: now blocks removed users, and the host succession rule "first into an
-- empty room becomes host". Otherwise identical to the base join.
CREATE OR REPLACE FUNCTION public.join_study_room(
  p_room uuid, p_code text, p_display_name text, p_ecliptar_slug text
) RETURNS public.study_rooms
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_room public.study_rooms; v_count integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_room IS NOT NULL THEN
    SELECT * INTO v_room FROM public.study_rooms WHERE id = p_room;
  ELSIF coalesce(trim(p_code), '') <> '' THEN
    SELECT * INTO v_room FROM public.study_rooms WHERE join_code = upper(trim(p_code));
  END IF;
  IF v_room.id IS NULL THEN RAISE EXCEPTION 'Room not found'; END IF;
  IF v_uid = ANY(v_room.removed_user_ids) THEN
    RAISE EXCEPTION 'You have been removed from this room';
  END IF;
  IF NOT v_room.is_public
     AND (coalesce(trim(p_code), '') = '' OR upper(trim(p_code)) <> v_room.join_code) THEN
    RAISE EXCEPTION 'This room is private — a join code is required';
  END IF;

  -- Succession: an empty room hands the host seat to whoever walks in next.
  SELECT count(*) INTO v_count FROM public.study_room_members WHERE room_id = v_room.id;
  IF v_count = 0 THEN
    UPDATE public.study_rooms SET host_id = v_uid WHERE id = v_room.id;
  END IF;

  INSERT INTO public.study_room_members(room_id, user_id, display_name, ecliptar_slug)
  VALUES (v_room.id, v_uid, p_display_name, p_ecliptar_slug)
  ON CONFLICT (room_id, user_id)
    DO UPDATE SET ecliptar_slug = coalesce(excluded.ecliptar_slug, study_room_members.ecliptar_slug),
                  display_name  = coalesce(excluded.display_name,  study_room_members.display_name);
  RETURN v_room;
END; $$;

-- Leave: now with host succession — the longest-present remaining member takes
-- over so a room is never left host-less. Empty rooms are still cleaned up.
CREATE OR REPLACE FUNCTION public.leave_study_room(p_room uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_host uuid; v_next uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  DELETE FROM public.study_room_members WHERE room_id = p_room AND user_id = v_uid;

  SELECT host_id INTO v_host FROM public.study_rooms WHERE id = p_room;
  IF v_host = v_uid THEN
    SELECT user_id INTO v_next FROM public.study_room_members
      WHERE room_id = p_room ORDER BY joined_at ASC LIMIT 1;
    IF v_next IS NOT NULL THEN
      UPDATE public.study_rooms SET host_id = v_next, last_activity_at = now() WHERE id = p_room;
    END IF;
  END IF;

  -- Clean up an empty room so the lobby doesn't fill with ghosts.
  DELETE FROM public.study_rooms r
   WHERE r.id = p_room
     AND NOT EXISTS (SELECT 1 FROM public.study_room_members m WHERE m.room_id = r.id);
END; $$;

-- ── 2a. Reports — durable, moderator-queryable (mirrors forum_reports) ──────
CREATE TABLE IF NOT EXISTS public.study_room_reports (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id          uuid REFERENCES public.study_rooms(id) ON DELETE SET NULL,  -- survive room cleanup
  reporter_id      uuid NOT NULL,
  reported_user_id uuid,                         -- null for AI/system-authored content
  author_kind      text NOT NULL DEFAULT 'human' CHECK (author_kind IN ('human','ai','system')),
  message_snapshot text NOT NULL,                -- frozen copy of what was reported
  reason           text,
  status           text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','reviewed','dismissed')),
  created_at       timestamptz NOT NULL DEFAULT now(),
  resolved_at      timestamptz
);
CREATE INDEX IF NOT EXISTS idx_srr_status ON public.study_room_reports(status, created_at);
ALTER TABLE public.study_room_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "create room reports" ON public.study_room_reports;
CREATE POLICY "create room reports" ON public.study_room_reports FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = reporter_id);
DROP POLICY IF EXISTS "view room reports" ON public.study_room_reports;
CREATE POLICY "view room reports" ON public.study_room_reports FOR SELECT TO authenticated
  USING (auth.uid() = reporter_id
         OR public.has_role(auth.uid(), 'moderator')
         OR public.has_role(auth.uid(), 'admin'));
DROP POLICY IF EXISTS "mods update room reports" ON public.study_room_reports;
CREATE POLICY "mods update room reports" ON public.study_room_reports FOR UPDATE TO authenticated
  USING (public.has_role(auth.uid(), 'moderator') OR public.has_role(auth.uid(), 'admin'));

-- Report a message (human OR AI-authored). Silent — the reported user is never
-- notified. Works for any rendered item by snapshotting what the reporter saw.
CREATE OR REPLACE FUNCTION public.report_room_message(
  p_room uuid, p_reported_user uuid, p_author_kind text, p_snapshot text, p_reason text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_kind text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF NOT public.is_study_member(p_room) THEN RAISE EXCEPTION 'Not a room member'; END IF;
  v_kind := lower(coalesce(p_author_kind, 'human'));
  IF v_kind NOT IN ('human','ai','system') THEN v_kind := 'human'; END IF;
  INSERT INTO public.study_room_reports(room_id, reporter_id, reported_user_id, author_kind, message_snapshot, reason)
  VALUES (p_room, v_uid,
          CASE WHEN v_kind = 'human' THEN p_reported_user ELSE NULL END,
          v_kind,
          left(coalesce(p_snapshot, ''), 2000),
          nullif(btrim(left(coalesce(p_reason, ''), 500)), ''));
END; $$;

-- ── 2b. Block — account-level personal preference ──────────────────────────
CREATE TABLE IF NOT EXISTS public.blocked_users (
  blocker_id uuid NOT NULL,
  blocked_id uuid NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id)
);
ALTER TABLE public.blocked_users ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "manage own blocks" ON public.blocked_users;
CREATE POLICY "manage own blocks" ON public.blocked_users FOR ALL TO authenticated
  USING (blocker_id = auth.uid()) WITH CHECK (blocker_id = auth.uid());

-- ── 3. AI rate limiting — per-user sliding window ──────────────────────────
CREATE TABLE IF NOT EXISTS public.ai_call_log (
  id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id   uuid NOT NULL,
  called_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ai_call_user ON public.ai_call_log(user_id, called_at);
ALTER TABLE public.ai_call_log ENABLE ROW LEVEL SECURITY;  -- service-role only; no client policy

-- Returns true and records the call if under the cap; false if over. Called by
-- the edge functions with the service role (passes the user id explicitly).
-- Stuck AI fallbacks deliberately DO NOT call this — they are a room-level
-- safety net, not a user-initiated request, so they aren't charged to anyone.
CREATE OR REPLACE FUNCTION public.check_ai_rate_limit(p_user uuid, p_max integer, p_window_secs integer)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_count integer;
BEGIN
  IF p_user IS NULL THEN RETURN true; END IF;
  DELETE FROM public.ai_call_log
   WHERE user_id = p_user AND called_at < now() - make_interval(secs => p_window_secs);
  SELECT count(*) INTO v_count FROM public.ai_call_log
   WHERE user_id = p_user AND called_at > now() - make_interval(secs => p_window_secs);
  IF v_count >= p_max THEN RETURN false; END IF;
  INSERT INTO public.ai_call_log(user_id) VALUES (p_user);
  RETURN true;
END; $$;

-- ── 5. Abandoned-room cleanup — window in ONE place ────────────────────────
CREATE OR REPLACE FUNCTION public.room_inactivity_window()
RETURNS interval LANGUAGE sql IMMUTABLE AS $$ SELECT interval '48 hours'; $$;

-- Clear live/ephemeral state for rooms that are empty AND stale. Deletes cascade
-- to members/messages/clock/stuck/teach-back; reports keep their history (room_id
-- nulls out). Safe to call opportunistically (check-on-access) or from a cron.
CREATE OR REPLACE FUNCTION public.cleanup_abandoned_rooms()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_n integer;
BEGIN
  WITH gone AS (
    DELETE FROM public.study_rooms r
     WHERE r.last_activity_at < now() - public.room_inactivity_window()
       AND NOT EXISTS (SELECT 1 FROM public.study_room_members m WHERE m.room_id = r.id)
    RETURNING r.id
  )
  SELECT count(*) INTO v_n FROM gone;
  RETURN v_n;
END; $$;

-- ── Re-expose get_study_rooms with host_id (superset of all room columns) ───
DROP FUNCTION IF EXISTS public.get_study_rooms();
CREATE OR REPLACE FUNCTION public.get_study_rooms()
RETURNS TABLE(
  id uuid, name text, topic text, is_public boolean, owner_id uuid,
  created_at timestamptz, member_count bigint, am_member boolean, join_code text,
  work_minutes integer, break_minutes integer, phase text,
  phase_started_at timestamptz, last_activity_at timestamptz,
  goal_text text, resource_links jsonb,
  teach_back_enabled boolean, tb_queue uuid[], tb_position integer,
  host_id uuid
) LANGUAGE sql SECURITY DEFINER SET search_path = public STABLE AS $$
  SELECT r.id, r.name, r.topic, r.is_public, r.owner_id, r.created_at,
    (SELECT count(*) FROM public.study_room_members m WHERE m.room_id = r.id) AS member_count,
    EXISTS(SELECT 1 FROM public.study_room_members m
           WHERE m.room_id = r.id AND m.user_id = auth.uid()) AS am_member,
    CASE WHEN r.owner_id = auth.uid()
              OR EXISTS(SELECT 1 FROM public.study_room_members m
                        WHERE m.room_id = r.id AND m.user_id = auth.uid())
         THEN r.join_code ELSE NULL END AS join_code,
    r.work_minutes, r.break_minutes, r.phase, r.phase_started_at, r.last_activity_at,
    r.goal_text, COALESCE(r.resource_links, '[]'::jsonb),
    r.teach_back_enabled, COALESCE(r.tb_queue, '{}'), r.tb_position,
    r.host_id
  FROM public.study_rooms r
  WHERE r.is_public
     OR r.owner_id = auth.uid()
     OR EXISTS(SELECT 1 FROM public.study_room_members m
               WHERE m.room_id = r.id AND m.user_id = auth.uid())
  ORDER BY member_count DESC, r.created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.regenerate_room_code(uuid)                   TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_room_member(uuid, uuid)              TO authenticated;
GRANT EXECUTE ON FUNCTION public.allow_room_member(uuid, uuid)              TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_study_room(uuid, text, text, text)    TO authenticated;
GRANT EXECUTE ON FUNCTION public.leave_study_room(uuid)                     TO authenticated;
GRANT EXECUTE ON FUNCTION public.report_room_message(uuid, uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_abandoned_rooms()                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_study_rooms()                          TO authenticated;
-- Re-apply the upstream hardening: DROP+CREATE above reset the function ACL, so
-- keep anon/PUBLIC locked out of the room read.
REVOKE EXECUTE ON FUNCTION public.get_study_rooms() FROM PUBLIC, anon;
-- check_ai_rate_limit is intentionally NOT granted to authenticated — only the
-- edge functions (service role) may call it, so a client can't probe/bypass it.

NOTIFY pgrst, 'reload schema';
