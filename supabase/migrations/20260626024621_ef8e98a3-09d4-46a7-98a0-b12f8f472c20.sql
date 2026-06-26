
DROP FUNCTION IF EXISTS public.get_study_rooms();

CREATE FUNCTION public.get_study_rooms()
RETURNS TABLE (
  id uuid,
  name text,
  topic text,
  is_public boolean,
  join_code text,
  owner_id uuid,
  created_at timestamptz,
  member_count bigint,
  is_member boolean,
  work_minutes integer,
  break_minutes integer,
  phase text,
  phase_started_at timestamptz,
  last_activity_at timestamptz,
  last_idle_nudge_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    r.id, r.name, r.topic, r.is_public,
    CASE WHEN r.owner_id = auth.uid() THEN r.join_code ELSE NULL END AS join_code,
    r.owner_id, r.created_at,
    (SELECT count(*) FROM public.study_room_members m WHERE m.room_id = r.id) AS member_count,
    EXISTS(SELECT 1 FROM public.study_room_members m WHERE m.room_id = r.id AND m.user_id = auth.uid()) AS is_member,
    r.work_minutes, r.break_minutes, r.phase, r.phase_started_at, r.last_activity_at, r.last_idle_nudge_at
  FROM public.study_rooms r
  WHERE r.is_public
     OR r.owner_id = auth.uid()
     OR EXISTS(SELECT 1 FROM public.study_room_members m WHERE m.room_id = r.id AND m.user_id = auth.uid());
$$;

REVOKE EXECUTE ON FUNCTION public.get_study_rooms() FROM anon, PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_study_rooms() TO authenticated;
