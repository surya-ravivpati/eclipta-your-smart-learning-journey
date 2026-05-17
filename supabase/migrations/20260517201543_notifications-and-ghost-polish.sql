-- ════════════════════════════════════════════════════════════════════════
-- Two small polishes:
--
-- 1. respond_pvp_challenge previously inserted a 'challenge_rejected'
--    notification with link = NULL, so clicking it on the new notifications
--    page did nothing. Link it back to /battles so the user lands somewhere
--    sensible (and the notification feels actionable).
--
-- 2. get_ghost_session: prefer sessions where the original player was
--    facing a real live or ghost opponent. Bot-facing sessions are still
--    eligible (they're real per-turn data from a real human), but they
--    sort behind sessions recorded from competitive play. This makes
--    ghost matches feel more like "you're up against someone who tried"
--    instead of "you're up against someone's bot warm-up".
-- ════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.respond_pvp_challenge(
  p_challenge_id uuid,
  p_accept       boolean,
  p_archetype    text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ch  record;
  v_battle_id uuid;
  v_my_username text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO v_ch FROM public.pvp_challenges WHERE id = p_challenge_id FOR UPDATE;
  IF v_ch.id IS NULL THEN RAISE EXCEPTION 'Challenge not found'; END IF;
  IF v_ch.challenged_id <> v_uid THEN RAISE EXCEPTION 'Not your challenge to respond to'; END IF;
  IF v_ch.status <> 'pending' THEN RAISE EXCEPTION 'Challenge no longer pending'; END IF;
  IF v_ch.expires_at < now() THEN
    UPDATE public.pvp_challenges SET status = 'expired' WHERE id = p_challenge_id;
    RAISE EXCEPTION 'Challenge expired';
  END IF;

  SELECT username INTO v_my_username FROM public.user_profiles WHERE user_id = v_uid;

  IF p_accept THEN
    v_battle_id := gen_random_uuid();
    INSERT INTO public.pvp_battles(id, challenger_id, opponent_id, challenger_archetype, opponent_archetype, status)
    VALUES (v_battle_id, v_ch.challenger_id, v_uid, v_ch.challenger_archetype,
            COALESCE(p_archetype, v_ch.challenger_archetype), 'active');
    UPDATE public.pvp_challenges SET status = 'accepted', battle_id = v_battle_id WHERE id = p_challenge_id;

    INSERT INTO public.notifications(user_id, actor_id, type, link, meta)
    VALUES (v_ch.challenger_id, v_uid, 'challenge_accepted',
            '/battles?battle=' || v_battle_id::text,
            jsonb_build_object(
              'opponent_username',  v_my_username,
              'battle_id',          v_battle_id,
              'opponent_archetype', COALESCE(p_archetype, v_ch.challenger_archetype)
            ));

    RETURN jsonb_build_object(
      'accepted', true,
      'battle_id', v_battle_id,
      'challenger_archetype', v_ch.challenger_archetype,
      'opponent_archetype', COALESCE(p_archetype, v_ch.challenger_archetype),
      'challenger_id', v_ch.challenger_id
    );
  ELSE
    UPDATE public.pvp_challenges SET status = 'rejected' WHERE id = p_challenge_id;
    INSERT INTO public.notifications(user_id, actor_id, type, link, meta)
    VALUES (v_ch.challenger_id, v_uid, 'challenge_rejected',
            '/battles',  -- previously NULL; now lands the user on the arena page
            jsonb_build_object('opponent_username', v_my_username));
    RETURN jsonb_build_object('accepted', false);
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.respond_pvp_challenge(uuid, boolean, text) TO authenticated;

-- Ghost session selection now weights competitive sessions ahead of
-- bot-warmup sessions. Still random within the chosen tier so the same
-- popular session doesn't get served to every player.
CREATE OR REPLACE FUNCTION public.get_ghost_session(p_player_rating integer)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE r record;
BEGIN
  -- Tier A: nearby rating, recent, opponent_type = live or ghost.
  SELECT bs.id, bs.archetype, bs.won, bs.rating, bs.total_questions,
         bs.correct_answers, bs.best_streak, bs.question_records,
         up.username
    INTO r
    FROM public.battle_sessions bs
    LEFT JOIN public.user_profiles up ON up.user_id = bs.user_id
   WHERE bs.user_id <> COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
     AND bs.total_questions >= 3
     AND bs.opponent_type IN ('live','ghost')
     AND abs(bs.rating - p_player_rating) <= 200
     AND bs.created_at > now() - interval '60 days'
   ORDER BY random()
   LIMIT 1;

  -- Tier B: nearby rating, recent, any opponent_type.
  IF r.id IS NULL THEN
    SELECT bs.id, bs.archetype, bs.won, bs.rating, bs.total_questions,
           bs.correct_answers, bs.best_streak, bs.question_records,
           up.username
      INTO r
      FROM public.battle_sessions bs
      LEFT JOIN public.user_profiles up ON up.user_id = bs.user_id
     WHERE bs.user_id <> COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
       AND bs.total_questions >= 3
       AND abs(bs.rating - p_player_rating) <= 200
     ORDER BY random()
     LIMIT 1;
  END IF;

  -- Tier C: anything we have, sorted random.
  IF r.id IS NULL THEN
    SELECT bs.id, bs.archetype, bs.won, bs.rating, bs.total_questions,
           bs.correct_answers, bs.best_streak, bs.question_records,
           up.username
      INTO r
      FROM public.battle_sessions bs
      LEFT JOIN public.user_profiles up ON up.user_id = bs.user_id
     WHERE bs.user_id <> COALESCE(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)
       AND bs.total_questions >= 3
     ORDER BY random()
     LIMIT 1;
  END IF;

  IF r.id IS NULL THEN RETURN NULL; END IF;

  RETURN jsonb_build_object(
    'id',               r.id,
    'archetype',        r.archetype,
    'won',              r.won,
    'rating',           r.rating,
    'total_questions',  r.total_questions,
    'correct_answers',  r.correct_answers,
    'best_streak',      r.best_streak,
    'question_records', r.question_records,
    'username',         r.username
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_ghost_session(integer) TO authenticated;
