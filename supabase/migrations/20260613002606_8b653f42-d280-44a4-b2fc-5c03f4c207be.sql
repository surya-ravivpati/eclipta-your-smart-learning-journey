
-- 1. archetype_mastery: drop client write, keep own-row select
DROP POLICY IF EXISTS "Users manage own mastery" ON public.archetype_mastery;
CREATE POLICY "Users view own mastery" ON public.archetype_mastery
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- 2. battle_sessions: restrict select to owner (ghost RPC bypasses via SECURITY DEFINER)
DROP POLICY IF EXISTS "Anyone can view battle sessions" ON public.battle_sessions;
CREATE POLICY "Users view own sessions" ON public.battle_sessions
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

-- 3. player_ratings: drop client write
DROP POLICY IF EXISTS "Users can manage own rating" ON public.player_ratings;
-- SELECT policy "Anyone can view ratings" stays (leaderboard reads)

-- 4. pvp_battles: drop participant UPDATE
DROP POLICY IF EXISTS "Participants update battles" ON public.pvp_battles;

-- 5. pvp_queue: drop client write, keep visibility, allow self-delete via DELETE policy
DROP POLICY IF EXISTS "Users manage own queue entry" ON public.pvp_queue;
CREATE POLICY "Users leave own queue entry" ON public.pvp_queue
  FOR DELETE TO authenticated USING (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.enqueue_pvp(p_archetype text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_username text;
  v_rating integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_archetype IS NULL OR length(p_archetype) < 2 OR length(p_archetype) > 40 THEN
    RAISE EXCEPTION 'Invalid archetype';
  END IF;

  SELECT username INTO v_username FROM public.user_profiles WHERE user_id = v_uid;

  INSERT INTO public.player_ratings(user_id) VALUES (v_uid) ON CONFLICT (user_id) DO NOTHING;
  SELECT rating INTO v_rating FROM public.player_ratings WHERE user_id = v_uid;

  INSERT INTO public.pvp_queue(user_id, username, archetype, rating, queued_at)
  VALUES (v_uid, COALESCE(v_username, 'player_'||substr(v_uid::text, 1, 6)), p_archetype, COALESCE(v_rating, 1000), now())
  ON CONFLICT (user_id) DO UPDATE SET
    username = EXCLUDED.username,
    archetype = EXCLUDED.archetype,
    rating = EXCLUDED.rating,
    queued_at = EXCLUDED.queued_at;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.enqueue_pvp(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.enqueue_pvp(text) TO authenticated;

-- 6. pvp_turn_actions: drop client insert (RPC handles)
DROP POLICY IF EXISTS "Participants submit own turn actions" ON public.pvp_turn_actions;

-- 7. user_chest_claims: drop client insert (claim_chest RPC handles)
DROP POLICY IF EXISTS "Users insert own chest claims" ON public.user_chest_claims;

-- 8. user_ecliptars: drop client insert and add claim RPCs
DROP POLICY IF EXISTS "Users can claim their own ecliptars" ON public.user_ecliptars;

CREATE OR REPLACE FUNCTION public.claim_ecliptar(
  p_slug text,
  p_archetype text,
  p_name text,
  p_node_id integer
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_allowed text[] := ARRAY[
    'speedster-a','speedster-b','tank-a','tank-b','chud-a','chud-b',
    'gambler-a','gambler-b','healer-a','healer-b','fulcrum-a','fulcrum-b',
    'accelerator-a','accelerator-b','god-a','god-b','newton','ecliptadon'
  ];
  v_exists boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  IF p_slug IS NULL OR NOT (p_slug = ANY (v_allowed)) THEN
    RAISE EXCEPTION 'Unknown ecliptar slug: %', p_slug;
  END IF;
  IF p_archetype IS NULL OR length(p_archetype) < 2 OR length(p_archetype) > 40 THEN
    RAISE EXCEPTION 'Invalid archetype';
  END IF;
  IF p_node_id IS NULL OR p_node_id < 0 OR p_node_id > 1000 THEN
    RAISE EXCEPTION 'Invalid node';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.user_ecliptars WHERE user_id = v_uid AND ecliptar_slug = p_slug
  ) INTO v_exists;
  IF v_exists THEN
    RETURN jsonb_build_object('already_claimed', true, 'slug', p_slug);
  END IF;

  INSERT INTO public.user_ecliptars(user_id, archetype, ecliptar_slug, ecliptar_name, node_id)
  VALUES (v_uid, p_archetype, p_slug, COALESCE(NULLIF(trim(p_name), ''), p_slug), p_node_id);

  RETURN jsonb_build_object('already_claimed', false, 'slug', p_slug);
END;
$$;

REVOKE EXECUTE ON FUNCTION public.claim_ecliptar(text,text,text,integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.claim_ecliptar(text,text,text,integer) TO authenticated;

-- 9. Remove user_profiles from realtime publication
ALTER PUBLICATION supabase_realtime DROP TABLE public.user_profiles;

-- 10. Tighten SECURITY DEFINER anon access on auth-required functions
REVOKE EXECUTE ON FUNCTION public.create_pvp_challenge(uuid, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.respond_pvp_challenge(uuid, boolean, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.record_battle_mastery(text, boolean, integer, integer, integer, boolean) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_ghost_session(integer) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.search_users(text, integer) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_pvp_leaderboard(integer) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION public.get_public_profile(text) FROM anon, PUBLIC;

GRANT EXECUTE ON FUNCTION public.create_pvp_challenge(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.respond_pvp_challenge(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_battle_mastery(text, boolean, integer, integer, integer, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_ghost_session(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.search_users(text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_pvp_leaderboard(integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_public_profile(text) TO authenticated;
