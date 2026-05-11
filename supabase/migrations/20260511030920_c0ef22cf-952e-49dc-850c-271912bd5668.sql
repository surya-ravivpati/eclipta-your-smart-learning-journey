
-- ════════════════════════════════════════════════════════════════════════
-- Battles + Trophy Road Sync
-- 1) Re-create archetype_mastery table & record_battle_mastery RPC
-- 2) Update claim_chest with all 16 chest labels (new Trophy Road)
-- 3) Purge legacy "god-a"/"god-b" rows from user_ecliptars
-- ════════════════════════════════════════════════════════════════════════

-- ── 1. Archetype Mastery ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.archetype_mastery (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  archetype       text        NOT NULL,
  battles_played  integer     NOT NULL DEFAULT 0,
  wins            integer     NOT NULL DEFAULT 0,
  best_streak     integer     NOT NULL DEFAULT 0,
  total_correct   integer     NOT NULL DEFAULT 0,
  total_questions integer     NOT NULL DEFAULT 0,
  perfect_battles integer     NOT NULL DEFAULT 0,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, archetype)
);

ALTER TABLE public.archetype_mastery ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own mastery" ON public.archetype_mastery;
CREATE POLICY "Users manage own mastery"
  ON public.archetype_mastery FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION public.record_battle_mastery(
  p_archetype   text,
  p_won         boolean,
  p_best_streak integer,
  p_correct     integer,
  p_total       integer,
  p_perfect     boolean
)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  INSERT INTO public.archetype_mastery
    (user_id, archetype, battles_played, wins, best_streak, total_correct, total_questions, perfect_battles, updated_at)
  VALUES
    (v_user_id, p_archetype, 1, p_won::int, COALESCE(p_best_streak,0), COALESCE(p_correct,0), COALESCE(p_total,0), p_perfect::int, now())
  ON CONFLICT (user_id, archetype) DO UPDATE SET
    battles_played  = archetype_mastery.battles_played  + 1,
    wins            = archetype_mastery.wins            + (p_won::int),
    best_streak     = GREATEST(archetype_mastery.best_streak, COALESCE(p_best_streak,0)),
    total_correct   = archetype_mastery.total_correct   + COALESCE(p_correct,0),
    total_questions = archetype_mastery.total_questions + COALESCE(p_total,0),
    perfect_battles = archetype_mastery.perfect_battles + (p_perfect::int),
    updated_at      = now();
END $$;

GRANT EXECUTE ON FUNCTION public.record_battle_mastery(text, boolean, integer, integer, integer, boolean) TO authenticated;

-- ── 2. claim_chest: full 16-label trophy road redesign ───────────────────
CREATE OR REPLACE FUNCTION public.claim_chest(p_node_id integer, p_chest_label text)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_bonus integer; v_new integer;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  v_bonus := CASE p_chest_label
    WHEN 'Bronze Chest'    THEN 75
    WHEN 'Bronze Cache'    THEN 150
    WHEN 'Silver Chest'    THEN 200
    WHEN 'Silver Cache'    THEN 350
    WHEN 'Gold Chest'      THEN 450
    WHEN 'Gold Cache'      THEN 600
    WHEN 'Diamond Chest'   THEN 800
    WHEN 'Diamond Cache'   THEN 1000
    WHEN 'Platinum Chest'  THEN 1200
    WHEN 'Platinum Cache'  THEN 1500
    WHEN 'Champion Chest'  THEN 1800
    WHEN 'Champion Cache'  THEN 2200
    WHEN 'Unreal Chest'    THEN 2600
    WHEN 'Unreal Cache'    THEN 3000
    WHEN 'God Cache'       THEN 4000
    WHEN 'God Vault'       THEN 5500
    ELSE 0 END;
  IF v_bonus = 0 THEN RAISE EXCEPTION 'Unknown chest label: %', p_chest_label; END IF;
  INSERT INTO public.user_chest_claims(user_id, node_id, chest_label, bonus_xp)
    VALUES (v_uid, p_node_id, p_chest_label, v_bonus);
  INSERT INTO public.xp_award_log(user_id, event, amount)
    VALUES (v_uid, 'chest:'||p_chest_label, v_bonus);
  UPDATE public.user_profiles SET xp = xp + v_bonus WHERE user_id = v_uid RETURNING xp INTO v_new;
  RETURN v_bonus;
END $$;

GRANT EXECUTE ON FUNCTION public.claim_chest(integer, text) TO authenticated;

-- ── 3. Purge legacy god-a / god-b ecliptars (replaced by Newton/Ecliptadon)
DELETE FROM public.user_ecliptars
WHERE archetype = 'god' AND ecliptar_slug IN ('god-a','god-b');
