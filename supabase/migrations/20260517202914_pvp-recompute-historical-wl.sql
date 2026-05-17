-- ════════════════════════════════════════════════════════════════════════
-- Recompute player_ratings.wins / losses from the authoritative tables.
--
-- Background: the W/L counts on player_ratings have been polluted by a
-- pile of historical events that the current code path no longer produces:
--   * The original update_pvp_rating() RPC (20260510000006) was one-sided —
--     it bumped wins for the caller but never bumped losses for the
--     opponent. Until update_pvp_rating was REVOKEd (20260516044300), many
--     real matches incremented one player's wins and zero players' losses.
--   * The "auto-fix" backfill in 20260515002226 inferred winners from
--     battle_sessions.won when battles got stuck active. If one side never
--     persisted a session row, the heuristic guessed — sometimes wrong.
--   * Earlier abortive complete_pvp_battle attempts (before the constraint
--     spelling was fixed) could end with apply_pvp_rating_pair's W/L write
--     committed in a different transaction than the pvp_battles UPDATE.
--
-- The result is rows like "5W-250L with 98% winrate badge" or "300 wins
-- on an account with <300 total games". The leaderboard sorts by rating
-- and uses wins / losses only as tiebreakers + display data, so this is
-- cosmetic, but it makes the whole board look untrustworthy.
--
-- The fix: recompute every player's W/L from the immutable source-of-truth
-- tables, then overwrite player_ratings.wins / losses. Rating itself is
-- NOT recomputed (we'd have to replay every match in chronological order
-- with the right K-factor sequencing, which we can't faithfully do); only
-- the count columns are corrected.
-- ════════════════════════════════════════════════════════════════════════

-- 1. Build the canonical per-user counts.
--
-- Live PvP source: pvp_battles where the match completed cleanly. Every
-- completed row contributes exactly +1 to the winner and +1 to the loser.
-- Ghost PvP source: battle_sessions rows the owner actually played
-- against a ghost AND that have been finalised through complete_ghost_battle
-- (rating_applied = true). The owner gets +1 win or +1 loss depending on
-- the recorded `won` flag. These rows can't be double-counted because
-- only the row owner can call the RPC.
--
-- Bot battles never affect rating, so they're excluded.

CREATE TEMP TABLE _pvp_true_counts AS
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
),
all_events AS (
  SELECT * FROM live UNION ALL SELECT * FROM ghost
)
SELECT user_id,
       SUM(wins)::integer   AS wins,
       SUM(losses)::integer AS losses
  FROM all_events
 GROUP BY user_id;

-- 2. Audit log so we can see what changed if anyone complains later.
CREATE TABLE IF NOT EXISTS public.pvp_wl_recompute_log (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ran_at      timestamptz NOT NULL DEFAULT now(),
  user_id     uuid NOT NULL,
  old_wins    integer,
  old_losses  integer,
  new_wins    integer,
  new_losses  integer
);

INSERT INTO public.pvp_wl_recompute_log(user_id, old_wins, old_losses, new_wins, new_losses)
SELECT pr.user_id, pr.wins, pr.losses, COALESCE(tc.wins, 0), COALESCE(tc.losses, 0)
  FROM public.player_ratings pr
  LEFT JOIN _pvp_true_counts tc ON tc.user_id = pr.user_id
 WHERE pr.wins   IS DISTINCT FROM COALESCE(tc.wins, 0)
    OR pr.losses IS DISTINCT FROM COALESCE(tc.losses, 0);

-- 3. Apply the corrected counts. Players with zero matches stay at 0/0.
UPDATE public.player_ratings pr
   SET wins   = COALESCE(tc.wins,   0),
       losses = COALESCE(tc.losses, 0),
       updated_at = now()
  FROM _pvp_true_counts tc
 WHERE pr.user_id = tc.user_id
   AND (pr.wins IS DISTINCT FROM tc.wins OR pr.losses IS DISTINCT FROM tc.losses);

-- Catch ghosts on the other side: any player_ratings row that had nonzero
-- W/L but no matching event in the truth tables (purely-fictional record).
UPDATE public.player_ratings pr
   SET wins = 0, losses = 0, updated_at = now()
 WHERE (pr.wins > 0 OR pr.losses > 0)
   AND NOT EXISTS (SELECT 1 FROM _pvp_true_counts tc WHERE tc.user_id = pr.user_id);

-- 4. There may be players who genuinely won/lost matches but whose
-- player_ratings row was never created (e.g. complete_pvp_battle aborted
-- mid-transaction). Seed those rows now so they appear correctly.
INSERT INTO public.player_ratings(user_id, rating, peak_rating, wins, losses)
SELECT tc.user_id, 1000, 1000, tc.wins, tc.losses
  FROM _pvp_true_counts tc
  LEFT JOIN public.player_ratings pr ON pr.user_id = tc.user_id
 WHERE pr.user_id IS NULL
   AND (tc.wins > 0 OR tc.losses > 0)
ON CONFLICT (user_id) DO NOTHING;

-- 5. Tighten the leaderboard to hide records that look obviously corrupt
-- if any slip through in the future. A record with > 500 losses but
-- < 5 wins is almost certainly the old one-sided-write artefact and
-- shouldn't sit at the top of the W/L tiebreaker.
CREATE OR REPLACE FUNCTION public.get_pvp_leaderboard(p_limit integer DEFAULT 10)
RETURNS TABLE(user_id uuid, username text, rating integer, wins integer, losses integer)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT pr.user_id, up.username, pr.rating, pr.wins, pr.losses
    FROM public.player_ratings pr
    LEFT JOIN public.user_profiles up ON up.user_id = pr.user_id
   WHERE pr.wins + pr.losses > 0
     -- Belt-and-braces: hide rows where wins/losses are wildly out of
     -- proportion to the number of completed-match rows we can actually
     -- attribute to them. If a recompute is overdue, the row simply
     -- doesn't render until truth catches up.
     AND pr.wins + pr.losses <= 10 * GREATEST(1, (
       SELECT count(*) FROM public.pvp_battles b
        WHERE b.status = 'completed'
          AND (b.challenger_id = pr.user_id OR b.opponent_id = pr.user_id)
     ) + (
       SELECT count(*) FROM public.battle_sessions bs
        WHERE bs.user_id = pr.user_id AND bs.opponent_type IN ('live','ghost')
     ))
   ORDER BY pr.rating DESC, pr.wins DESC, pr.losses ASC, pr.updated_at ASC
   LIMIT LEAST(GREATEST(coalesce(p_limit, 10), 1), 100);
$$;
GRANT EXECUTE ON FUNCTION public.get_pvp_leaderboard(integer) TO anon, authenticated;

DROP TABLE _pvp_true_counts;
