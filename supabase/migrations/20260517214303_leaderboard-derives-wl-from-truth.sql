-- ════════════════════════════════════════════════════════════════════════
-- Leaderboard reads W/L from the match-history tables directly.
--
-- The previous attempt fixed player_ratings.wins / losses with a one-shot
-- recompute, but the leaderboard still trusted the cached columns, so any
-- row that drifted again (or that the recompute missed) kept showing the
-- wrong record. From now on the leaderboard derives W and L on every call
-- from pvp_battles (live PvP) and battle_sessions (ghost PvP), and treats
-- player_ratings.wins / losses purely as denormalised cache that may or
-- may not be present.
--
-- We also re-run the recompute idempotently. This is safe because the
-- recompute targets the same canonical events the leaderboard now reads,
-- so after this migration the cache and the live view agree by
-- construction.
-- ════════════════════════════════════════════════════════════════════════

-- ── 1. Idempotent recompute (same logic as 20260517202914) ───────────────

CREATE TEMP TABLE _pvp_true_counts ON COMMIT DROP AS
WITH live AS (
  SELECT challenger_id AS user_id,
         CASE WHEN winner_id = challenger_id THEN 1 ELSE 0 END AS wins,
         CASE WHEN winner_id = challenger_id THEN 0 ELSE 1 END AS losses
    FROM public.pvp_battles
   WHERE status = 'completed' AND winner_id IS NOT NULL
  UNION ALL
  SELECT opponent_id   AS user_id,
         CASE WHEN winner_id = opponent_id   THEN 1 ELSE 0 END AS wins,
         CASE WHEN winner_id = opponent_id   THEN 0 ELSE 1 END AS losses
    FROM public.pvp_battles
   WHERE status = 'completed' AND winner_id IS NOT NULL
),
ghost AS (
  SELECT user_id,
         CASE WHEN won THEN 1 ELSE 0 END AS wins,
         CASE WHEN won THEN 0 ELSE 1 END AS losses
    FROM public.battle_sessions
   WHERE opponent_type = 'ghost'
     AND rating_applied = true
)
SELECT user_id,
       SUM(wins)::integer   AS wins,
       SUM(losses)::integer AS losses
  FROM (SELECT * FROM live UNION ALL SELECT * FROM ghost) e
 GROUP BY user_id;

INSERT INTO public.pvp_wl_recompute_log(user_id, old_wins, old_losses, new_wins, new_losses)
SELECT pr.user_id, pr.wins, pr.losses, COALESCE(tc.wins, 0), COALESCE(tc.losses, 0)
  FROM public.player_ratings pr
  LEFT JOIN _pvp_true_counts tc ON tc.user_id = pr.user_id
 WHERE pr.wins   IS DISTINCT FROM COALESCE(tc.wins, 0)
    OR pr.losses IS DISTINCT FROM COALESCE(tc.losses, 0);

UPDATE public.player_ratings pr
   SET wins   = COALESCE(tc.wins,   0),
       losses = COALESCE(tc.losses, 0),
       updated_at = now()
  FROM _pvp_true_counts tc
 WHERE pr.user_id = tc.user_id
   AND (pr.wins IS DISTINCT FROM tc.wins OR pr.losses IS DISTINCT FROM tc.losses);

UPDATE public.player_ratings pr
   SET wins = 0, losses = 0, updated_at = now()
 WHERE (pr.wins > 0 OR pr.losses > 0)
   AND NOT EXISTS (SELECT 1 FROM _pvp_true_counts tc WHERE tc.user_id = pr.user_id);

INSERT INTO public.player_ratings(user_id, rating, peak_rating, wins, losses)
SELECT tc.user_id, 1000, 1000, tc.wins, tc.losses
  FROM _pvp_true_counts tc
  LEFT JOIN public.player_ratings pr ON pr.user_id = tc.user_id
 WHERE pr.user_id IS NULL
   AND (tc.wins > 0 OR tc.losses > 0)
ON CONFLICT (user_id) DO NOTHING;

-- ── 2. Truth-derived leaderboard ─────────────────────────────────────────
--
-- W/L are computed each call from match history. Rating is read from
-- player_ratings because we don't try to replay it. Players with zero
-- attributable matches don't appear at all — no more "phantom" rows.
CREATE OR REPLACE FUNCTION public.get_pvp_leaderboard(p_limit integer DEFAULT 10)
RETURNS TABLE(user_id uuid, username text, rating integer, wins integer, losses integer)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH live AS (
    SELECT challenger_id AS user_id,
           CASE WHEN winner_id = challenger_id THEN 1 ELSE 0 END AS w,
           CASE WHEN winner_id = challenger_id THEN 0 ELSE 1 END AS l
      FROM public.pvp_battles
     WHERE status = 'completed' AND winner_id IS NOT NULL
    UNION ALL
    SELECT opponent_id,
           CASE WHEN winner_id = opponent_id THEN 1 ELSE 0 END,
           CASE WHEN winner_id = opponent_id THEN 0 ELSE 1 END
      FROM public.pvp_battles
     WHERE status = 'completed' AND winner_id IS NOT NULL
  ),
  ghost AS (
    SELECT user_id,
           CASE WHEN won THEN 1 ELSE 0 END,
           CASE WHEN won THEN 0 ELSE 1 END
      FROM public.battle_sessions
     WHERE opponent_type = 'ghost' AND rating_applied = true
  ),
  stats AS (
    SELECT user_id,
           SUM(w)::integer AS wins,
           SUM(l)::integer AS losses
      FROM (SELECT * FROM live UNION ALL SELECT * FROM ghost) e
     GROUP BY user_id
  )
  SELECT pr.user_id, up.username, pr.rating,
         s.wins, s.losses
    FROM public.player_ratings pr
    JOIN stats s ON s.user_id = pr.user_id
    LEFT JOIN public.user_profiles up ON up.user_id = pr.user_id
   WHERE s.wins + s.losses > 0
   ORDER BY pr.rating DESC, s.wins DESC, s.losses ASC, pr.updated_at ASC
   LIMIT LEAST(GREATEST(coalesce(p_limit, 10), 1), 100);
$$;
GRANT EXECUTE ON FUNCTION public.get_pvp_leaderboard(integer) TO anon, authenticated;

-- ── 3. Self-healing trigger ──────────────────────────────────────────────
-- Every time a pvp_battle completes or a ghost battle_session is
-- rating-applied, recompute that pair of users' cached counts from the
-- canonical events. The cache stays a cache, never the truth, but at
-- least it stops drifting.
CREATE OR REPLACE FUNCTION public.recompute_player_wl(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_wins   integer;
  v_losses integer;
BEGIN
  IF p_user_id IS NULL THEN RETURN; END IF;
  SELECT COALESCE(SUM(w), 0), COALESCE(SUM(l), 0)
    INTO v_wins, v_losses
    FROM (
      SELECT CASE WHEN winner_id = challenger_id THEN 1 ELSE 0 END AS w,
             CASE WHEN winner_id = challenger_id THEN 0 ELSE 1 END AS l
        FROM public.pvp_battles
       WHERE status='completed' AND winner_id IS NOT NULL AND challenger_id = p_user_id
      UNION ALL
      SELECT CASE WHEN winner_id = opponent_id THEN 1 ELSE 0 END,
             CASE WHEN winner_id = opponent_id THEN 0 ELSE 1 END
        FROM public.pvp_battles
       WHERE status='completed' AND winner_id IS NOT NULL AND opponent_id = p_user_id
      UNION ALL
      SELECT CASE WHEN won THEN 1 ELSE 0 END,
             CASE WHEN won THEN 0 ELSE 1 END
        FROM public.battle_sessions
       WHERE opponent_type='ghost' AND rating_applied=true AND user_id = p_user_id
    ) e;

  INSERT INTO public.player_ratings(user_id, rating, peak_rating, wins, losses)
  VALUES (p_user_id, 1000, 1000, v_wins, v_losses)
  ON CONFLICT (user_id) DO UPDATE
     SET wins = EXCLUDED.wins,
         losses = EXCLUDED.losses,
         updated_at = now();
END;
$$;
REVOKE ALL ON FUNCTION public.recompute_player_wl(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.recompute_player_wl(uuid) TO service_role;

CREATE OR REPLACE FUNCTION public.trg_pvp_battles_recompute()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only recompute when status transitions to completed and a winner is set.
  IF NEW.status = 'completed' AND NEW.winner_id IS NOT NULL
     AND (OLD.status IS DISTINCT FROM NEW.status OR OLD.winner_id IS DISTINCT FROM NEW.winner_id) THEN
    PERFORM public.recompute_player_wl(NEW.challenger_id);
    PERFORM public.recompute_player_wl(NEW.opponent_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pvp_battles_recompute_wl ON public.pvp_battles;
CREATE TRIGGER trg_pvp_battles_recompute_wl
  AFTER UPDATE OF status, winner_id ON public.pvp_battles
  FOR EACH ROW EXECUTE FUNCTION public.trg_pvp_battles_recompute();

CREATE OR REPLACE FUNCTION public.trg_battle_sessions_recompute()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.opponent_type = 'ghost' AND NEW.rating_applied = true
     AND (TG_OP = 'INSERT' OR OLD.rating_applied IS DISTINCT FROM NEW.rating_applied) THEN
    PERFORM public.recompute_player_wl(NEW.user_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_battle_sessions_recompute_wl ON public.battle_sessions;
CREATE TRIGGER trg_battle_sessions_recompute_wl
  AFTER INSERT OR UPDATE OF rating_applied ON public.battle_sessions
  FOR EACH ROW EXECUTE FUNCTION public.trg_battle_sessions_recompute();
