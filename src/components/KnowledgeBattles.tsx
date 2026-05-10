import { useState, useEffect, useRef, useCallback } from "react";
import { motion, AnimatePresence } from "framer-motion";
import {
  Swords, Zap, Trophy, Shield, Flame, Timer, Sparkles,
  Target, Heart, Skull, Dices, User, Bot, HelpCircle, Info,
} from "lucide-react";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogDescription,
} from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";

import type { Phase, Action, ArchetypeId, Archetype, Fighter, MathQuestion, QuestionRecord, BattleStats, ActionConfig, GamblerRoll } from "./battles/types";
import { generateQuestion, TIMER_DURATIONS } from "./battles/questions";
import { levelToCategory, getActionDifficultyLevel, getEffectiveDamage, getEffectiveMultiplierStep, streakToMultiplier, hpToSelfDmgMult, botAccuracy } from "./battles/stat-mechanics";
import { ARCHETYPES, rollGamblerStats } from "./battles/archetypes";
import { ClassSelectDialog, type ClassSelection } from "./battles/ClassSelectDialog";
import { BattleReport } from "./battles/BattleReport";
import { ECLIPTARS, type Ecliptar } from "@/lib/ecliptars";
import { supabase } from "@/integrations/supabase/client";
import { getTodayChallenge } from "@/lib/daily-challenge";

/**
 * Pick a random opponent Ecliptar (excluding the player's own archetype when possible).
 * Rank-based matchmaking has been removed — every battle is a fair random draw.
 */
function pickOpponent(playerArch: ArchetypeId): Ecliptar {
  const candidates = ECLIPTARS.filter((e) => e.archetype !== playerArch);
  const pool = candidates.length > 0 ? candidates : ECLIPTARS;
  return pool[Math.floor(Math.random() * pool.length)];
}

// ─── Action Config ────────────────────────────────────────────────────────────────────
// Focus economy: Attack & Defend BUILD focus, Charge & Wild SPEND it.
// This gives Attack a real role (cheap, fast focus build) and makes Charge
// a payoff move that requires setup rather than a strictly-better Attack.
const ACTIONS: Record<Action, ActionConfig> = {
  attack:  { label: "Attack",  icon: Zap,     focusCost: -15, desc: "Your base DMG · +15 Focus" },
  defend:  { label: "Defend",  icon: Shield,  focusCost: -10, desc: "Heal · +10 Focus" },
  charge:  { label: "Charge",  icon: Flame,   focusCost:  30, desc: "1.8× DMG, hard Q · −30 Focus" },
  wild:    { label: "Wild",    icon: Sparkles, focusCost: 20, desc: "Random Q+DMG · −20 Focus" },
};

// ─── Leaderboard component ────────────────────────────────────────────────────────────────────
type LeaderboardEntry = { rank: number; name: string; xp: number; tier: string };

function xpToTier(xp: number): string {
  if (xp >= 40000) return "God Tier";
  if (xp >= 25000) return "Unreal";
  if (xp >= 16000) return "Champion";
  if (xp >= 10000) return "Platinum";
  if (xp >= 6000) return "Diamond";
  if (xp >= 3000) return "Gold";
  if (xp >= 1000) return "Silver";
  return "Bronze";
}

function Leaderboard() {
  const [entries, setEntries] = useState<LeaderboardEntry[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data } = await supabase.rpc("get_leaderboard" as any, { p_limit: 6 });
      if (cancelled) return;
      const rows: LeaderboardEntry[] = ((data ?? []) as { user_id: string; username?: string | null; xp: number | null }[]).map((r, i) => ({
        rank: i + 1,
        name: r.username || `learner_${r.user_id.slice(0, 6)}`,
        xp: r.xp ?? 0,
        tier: xpToTier(r.xp ?? 0),
      }));
      setEntries(rows);
      setLoading(false);
    })();
    return () => { cancelled = true; };
  }, []);

  return (
    <motion.div className="glass-panel p-6" initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: 0.3 }}>
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-sm font-bold font-display tracking-widest text-neon-cyan">LEADERBOARD</h3>
        <Trophy className="w-4 h-4 text-neon-cyan" />
      </div>
      <div className="space-y-2">
        {loading ? (
          <p className="text-xs text-muted-foreground text-center py-4">Loading...</p>
        ) : entries.length === 0 ? (
          <p className="text-xs text-muted-foreground text-center py-4">
            The arena is fresh. Win battles to be among the first names etched into the leaderboard.
          </p>
        ) : (
          entries.map((e) => (
            <div key={e.rank} className="flex items-center gap-3">
              <span className="text-xs font-bold text-muted-foreground w-4">{e.rank}</span>
              <div className="flex-1 min-w-0">
                <p className="text-xs font-bold truncate">{e.name}</p>
                <p className="text-[10px] text-muted-foreground">{e.tier}</p>
              </div>
              <span className="text-xs font-bold text-neon-cyan">{e.xp.toLocaleString()} XP</span>
            </div>
          ))
        )}
      </div>
    </motion.div>
  );
}

// ─── HP bar ─────────────────────────────────────────────────────────────────────────────────────
function HpBar({ hp, maxHp, color = "bg-neon-cyan" }: { hp: number; maxHp: number; color?: string }) {
  const pct = Math.max(0, Math.min(100, (hp / maxHp) * 100));
  return (
    <div className="h-2 bg-secondary/30 rounded-full overflow-hidden">
      <motion.div
        className={`h-full ${color} rounded-full`}
        animate={{ width: `${pct}%` }}
        transition={{ duration: 0.4, ease: "easeOut" }}
      />
    </div>
  );
}

// ─── Focus bar ───────────────────────────────────────────────────────────────────────────────
function FocusBar({ focus, maxFocus }: { focus: number; maxFocus: number }) {
  const pct = Math.max(0, Math.min(100, (focus / maxFocus) * 100));
  return (
    <div className="h-1.5 bg-secondary/30 rounded-full overflow-hidden">
      <motion.div
        className="h-full bg-neon-purple rounded-full"
        animate={{ width: `${pct}%` }}
        transition={{ duration: 0.4, ease: "easeOut" }}
      />
    </div>
  );
}

// ─── Fighter card ────────────────────────────────────────────────────────────────────────────
function FighterCard({
  fighter, isPlayer, showHeal, showDamage, damageAmt, archetype,
}: {
  fighter: Fighter;
  isPlayer: boolean;
  showHeal: boolean;
  showDamage: boolean;
  damageAmt: number;
  archetype?: Archetype;
}) {
  return (
    <div className="glass-panel p-4 relative overflow-hidden">
      <div className="flex items-center gap-3 mb-3">
        <div className={`w-10 h-10 rounded-full flex items-center justify-center ${isPlayer ? "bg-neon-cyan/20" : "bg-rose-500/20"}`}>
          <fighter.icon className={`w-6 h-6 ${isPlayer ? "text-neon-cyan" : "text-rose-400"}`} />
        </div>
        <div className="flex-1 min-w-0">
          <p className="text-sm font-bold font-display truncate">{fighter.name}</p>
          <p className="text-[10px] text-muted-foreground">
            {fighter.hp}/{fighter.maxHp} HP
            {archetype && <span className="ml-2 opacity-60">· {archetype.name}</span>}
          </p>
        </div>
        <div className="text-right">
          <p className="text-[10px] text-muted-foreground">Focus</p>
          <p className="text-xs font-bold text-neon-purple">{fighter.focus}/{fighter.maxFocus}</p>
        </div>
      </div>
      <HpBar hp={fighter.hp} maxHp={fighter.maxHp} color={isPlayer ? "bg-neon-cyan" : "bg-rose-500"} />
      <div className="mt-1">
        <FocusBar focus={fighter.focus} maxFocus={fighter.maxFocus} />
      </div>

      <AnimatePresence>
        {showHeal && (
          <motion.div
            className="absolute top-1 right-2 text-green-400 font-bold text-sm pointer-events-none"
            initial={{ opacity: 1, y: 0 }}
            animate={{ opacity: 0, y: -24 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.9 }}
          >
            +HEAL
          </motion.div>
        )}
        {showDamage && damageAmt > 0 && (
          <motion.div
            className="absolute top-1 right-2 text-rose-400 font-bold text-sm pointer-events-none"
            initial={{ opacity: 1, y: 0 }}
            animate={{ opacity: 0, y: -24 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.9 }}
          >
            -{damageAmt}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

// ─── Main export ──────────────────────────────────────────────────────────────────────────────
export function KnowledgeBattles() {
  // ─── State ────────────────────────────────────────────────────────────────────────────
  const [phase, setPhase] = useState<Phase>("idle");
  const [selectedClass, setSelectedClass] = useState<ClassSelection | null>(null);
  const [player, setPlayer] = useState<Fighter | null>(null);
  const [opponent, setOpponent] = useState<Fighter | null>(null);
  const [opponentEcliptar, setOpponentEcliptar] = useState<Ecliptar | null>(null);
  const [currentQuestion, setCurrentQuestion] = useState<MathQuestion | null>(null);
  const [timeLeft, setTimeLeft]   = useState(30);
  const [maxTime, setMaxTime]     = useState(30);
  const [currentAction, setCurrentAction] = useState<Action>("attack");
  const [momentum, setMomentum]   = useState(0);
  const [botMomentum, setBotMomentum] = useState(0);
  const [records, setRecords]     = useState<QuestionRecord[]>([]);
  const [log, setLog]             = useState<string[]>([]);
  const [battleStats, setBattleStats] = useState<BattleStats | null>(null);
  const [gamblerStats, setGamblerStats] = useState<GamblerRoll | null>(null);

  // UI flash states
  const [showPlayerHeal, setShowPlayerHeal]     = useState(false);
  const [showOppHeal, setShowOppHeal]           = useState(false);
  const [showPlayerDamage, setShowPlayerDamage] = useState(false);
  const [showOppDamage, setShowOppDamage]       = useState(false);
  const [playerDmgAmt, setPlayerDmgAmt]   = useState(0);
  const [oppDmgAmt, setOppDmgAmt]         = useState(0);

  const [playerXp, setPlayerXp] = useState(0);
  const [showRules, setShowRules] = useState(false);
  const [showActionInfo, setShowActionInfo] = useState<Action | null>(null);

  const timerRef   = useRef<ReturnType<typeof setInterval> | null>(null);
  const phaseRef   = useRef(phase);
  const logRef     = useRef(log);
  phaseRef.current = phase;
  logRef.current   = log;

  // ─── Helpers ─────────────────────────────────────────────────────────────────────────────
  const addLog = useCallback((msg: string) => {
    setLog((prev) => [msg, ...prev].slice(0, 20));
  }, []);

  const getArch = useCallback((id: ArchetypeId): Archetype => {
    const base = ARCHETYPES[id];
    if (id === "gambler" && gamblerStats) return { ...base, ...gamblerStats };
    return base;
  }, [gamblerStats]);

  // Load player XP once
  useEffect(() => {
    (async () => {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return;
      const { data } = await supabase
        .from("user_profiles")
        .select("xp")
        .eq("user_id", user.id)
        .maybeSingle();
      setPlayerXp((data as any)?.xp ?? 0);
    })();
  }, []);

  // ─── Timer ───────────────────────────────────────────────────────────────────────────────
  const stopTimer = useCallback(() => {
    if (timerRef.current) { clearInterval(timerRef.current); timerRef.current = null; }
  }, []);

  // ─── End battle ───────────────────────────────────────────────────────────────────────────
  const endBattle = useCallback((won: boolean, finalPlayer: Fighter, finalOpponent: Fighter, allRecords: QuestionRecord[]) => {
    stopTimer();
    setPhase("result");

    const correct  = allRecords.filter((r) => r.correct).length;
    const fastest  = allRecords.length ? Math.min(...allRecords.map((r) => r.timeSpent)) : 0;
    const longest  = allRecords.reduce((acc, r, i) => {
      const streak = r.correct ? (i > 0 && allRecords[i-1].correct ? acc + 1 : 1) : 0;
      return Math.max(acc, streak);
    }, 0);
    const totalScore = allRecords.reduce((acc, r) => {
      if (!r.correct) return acc;
      const base = 100;
      const timeBonus = Math.max(0, 30 - r.timeSpent) * 2;
      return acc + base + timeBonus;
    }, 0);
    const xp = won ? Math.floor(totalScore * 0.8) + 200 : Math.floor(totalScore * 0.2);
    const archId = selectedClass?.archetype ?? "fulcrum";

    const stats: BattleStats = {
      totalQuestions: allRecords.length,
      correctAnswers: correct,
      longestStreak:  longest,
      fastestAnswer:  fastest,
      records:        allRecords,
      archetype:      archId,
      won,
      score:          totalScore,
      xp,
    };
    setBattleStats(stats);
  }, [stopTimer, selectedClass]);

  // ─── Handle answer ───────────────────────────────────────────────────────────────────────────
  const handleAnswer = useCallback((
    isCorrect: boolean, question: MathQuestion, timeSpent: number,
    currentPlayer: Fighter, currentOpponent: Fighter, currentRecords: QuestionRecord[],
  ) => {
    stopTimer();
    if (!selectedClass) return;
    const arch = getArch(selectedClass.archetype);

    const record: QuestionRecord = { question, correct: isCorrect, timeSpent, action: currentAction };
    const newRecords = [...currentRecords, record];

    let newMomentum = isCorrect ? momentum + 1 : 0;
    const step      = getEffectiveMultiplierStep(arch, currentRecords.length);
    const mult      = streakToMultiplier(newMomentum, step);

    let newPlayer   = { ...currentPlayer };
    let newOpponent = { ...currentOpponent };

    if (isCorrect) {
      if (currentAction === "defend") {
        // Heal only if archetype can heal (Tank has null healAmount)
        if (arch.healAmount !== null) {
          const heal = Math.min(arch.healAmount, newPlayer.maxHp - newPlayer.hp);
          const gain = ACTIONS.defend.focusCost * -1;
          setPlayer(prev => prev ? { ...prev, hp: Math.min(prev.maxHp, prev.hp + arch.healAmount!), focus: Math.min(prev.maxFocus, prev.focus + gain) } : prev);
          setShowPlayerHeal(true);
          setTimeout(() => setShowPlayerHeal(false), 1000);
          addLog(`✅ Defend: +${heal} HP, +${gain} Focus.`);
        } else {
          const gain = ACTIONS.defend.focusCost * -1;
          setPlayer(prev => prev ? { ...prev, focus: Math.min(prev.maxFocus, prev.focus + gain) } : prev);
          addLog(`✅ Defend: +${gain} Focus (Tank cannot heal).`);
        }
        newPlayer = { ...newPlayer, hp: Math.min(newPlayer.maxHp, newPlayer.hp + (arch.healAmount ?? 0)), focus: Math.min(newPlayer.maxFocus, newPlayer.focus + (ACTIONS.defend.focusCost * -1)) };
      } else {
        const dmg = Math.round(
          getEffectiveDamage(arch, { action: currentAction, timeSpent, maxTime, recordCount: currentRecords.length }) * mult
        );
        newOpponent = { ...newOpponent, hp: Math.max(0, newOpponent.hp - dmg) };
        setOpponent(prev => prev ? { ...prev, hp: Math.max(0, prev.hp - dmg) } : prev);
        setOppDmgAmt(dmg);
        setShowOppDamage(true);
        setTimeout(() => setShowOppDamage(false), 900);
        // Focus delta: negative focusCost = gain, positive = spend
        const focusDelta = -ACTIONS[currentAction].focusCost;
        setPlayer(prev => prev ? { ...prev, focus: Math.max(0, Math.min(prev.maxFocus, prev.focus + focusDelta)) } : prev);
        newPlayer = { ...newPlayer, focus: Math.max(0, Math.min(newPlayer.maxFocus, newPlayer.focus + focusDelta)) };
        addLog(`✅ ${currentAction.charAt(0).toUpperCase() + currentAction.slice(1)}: −${dmg} HP to ${newOpponent.name} (×${mult.toFixed(2)} streak)`);
      }
    } else {
      // Wrong answer — self damage scaled by archetype tankiness
      const selfMult = hpToSelfDmgMult(arch.maxHp);
      const selfDmg  = Math.round(arch.baseDamage * selfMult * 0.6);
      newPlayer = { ...newPlayer, hp: Math.max(0, newPlayer.hp - selfDmg) };
      setPlayer(prev => prev ? { ...prev, hp: Math.max(0, prev.hp - selfDmg) } : prev);
      setPlayerDmgAmt(selfDmg);
      setShowPlayerDamage(true);
      setTimeout(() => setShowPlayerDamage(false), 900);

      // Healer passive: regain a small amount of HP on wrong answers
      if (arch.id === "healer" && arch.healAmount !== null) {
        const regenAmt = Math.round(arch.healAmount * 0.25);
        newPlayer = { ...newPlayer, hp: Math.min(newPlayer.maxHp, newPlayer.hp + regenAmt) };
        setPlayer(prev => prev ? { ...prev, hp: Math.min(prev.maxHp, prev.hp + regenAmt) } : prev);
      }

      addLog(`❌ Wrong! −${selfDmg} self-damage.`);
      newMomentum = 0;
    }

    setMomentum(newMomentum);
    setRecords(newRecords);

    if (newOpponent.hp <= 0) { endBattle(true, newPlayer, newOpponent, newRecords); return; }
    if (newPlayer.hp   <= 0) { endBattle(false, newPlayer, newOpponent, newRecords); return; }

    // ─── Bot turn ────────────────────────────────────────────────────────────────────────
    // Bot picks an action based on HP and focus
    const botArch = getArch(selectedClass.archetype); // mirror same archetype for bot
    const botActions: Action[] = ["attack", "defend", "charge", "wild"];
    const botHpPct = newOpponent.hp / newOpponent.maxHp;
    const botFocus = newOpponent.focus;
    let botAction: Action = "attack";
    if (botHpPct < 0.3 && botArch.healAmount !== null && botFocus >= Math.abs(ACTIONS.defend.focusCost)) {
      botAction = "defend";
    } else if (botFocus >= ACTIONS.charge.focusCost && Math.random() < 0.3) {
      botAction = "charge";
    } else if (botFocus >= ACTIONS.wild.focusCost && Math.random() < 0.2) {
      botAction = "wild";
    }

    const botSucceeds = Math.random() < botAccuracy(botArch);
    const botStep     = getEffectiveMultiplierStep(botArch, newRecords.length);
    let newBotMom     = botSucceeds ? botMomentum + 1 : 0;
    const botMult     = streakToMultiplier(newBotMom, botStep);

    if (botSucceeds) {
      if (botAction === "defend") {
        if (botArch.healAmount !== null) {
          const botHeal = Math.min(botArch.healAmount, newOpponent.maxHp - newOpponent.hp);
          newOpponent = { ...newOpponent, hp: Math.min(newOpponent.maxHp, newOpponent.hp + botHeal) };
          setOpponent(prev => prev ? { ...prev, hp: Math.min(prev.maxHp, prev.hp + botHeal) } : prev);
          setShowOppHeal(true);
          setTimeout(() => setShowOppHeal(false), 1000);
          addLog(`🤖 Bot defends: +${botHeal} HP.`);
        } else {
          addLog(`🤖 Bot defends (cannot heal).`);
        }
        const botFocusDelta = -ACTIONS.defend.focusCost;
        newOpponent = { ...newOpponent, focus: Math.min(newOpponent.maxFocus, newOpponent.focus + botFocusDelta) };
        setOpponent(prev => prev ? { ...prev, focus: Math.min(prev.maxFocus, prev.focus + botFocusDelta) } : prev);
      } else {
        const botDmg = Math.round(
          getEffectiveDamage(botArch, { action: botAction, timeSpent: 10, maxTime, recordCount: newRecords.length }) * botMult
        );
        newPlayer = { ...newPlayer, hp: Math.max(0, newPlayer.hp - botDmg) };
        setPlayer(prev => prev ? { ...prev, hp: Math.max(0, prev.hp - botDmg) } : prev);
        setPlayerDmgAmt(botDmg);
        setShowPlayerDamage(true);
        setTimeout(() => setShowPlayerDamage(false), 900);
        const botFocusDelta = -ACTIONS[botAction].focusCost;
        newOpponent = { ...newOpponent, focus: Math.max(0, Math.min(newOpponent.maxFocus, newOpponent.focus + botFocusDelta)) };
        setOpponent(prev => prev ? { ...prev, focus: Math.max(0, Math.min(prev.maxFocus, prev.focus + botFocusDelta)) } : prev);
        addLog(`🤖 Bot ${botAction}s: −${botDmg} HP (×${botMult.toFixed(2)})`);
      }
    } else {
      const botSelfMult = hpToSelfDmgMult(botArch.maxHp);
      const botSelfDmg  = Math.round(botArch.baseDamage * botSelfMult * 0.6);
      newOpponent = { ...newOpponent, hp: Math.max(0, newOpponent.hp - botSelfDmg) };
      setOpponent(prev => prev ? { ...prev, hp: Math.max(0, prev.hp - botSelfDmg) } : prev);
      addLog(`🤖 Bot failed! −${botSelfDmg} self-dmg.`);
      newBotMom = 0;
    }

    setBotMomentum(newBotMom);

    if (newOpponent.hp <= 0) { endBattle(true,  newPlayer, newOpponent, newRecords); return; }
    if (newPlayer.hp   <= 0) { endBattle(false, newPlayer, newOpponent, newRecords); return; }

    setPhase("select");
  }, [
    stopTimer, selectedClass, currentAction, momentum, botMomentum,
    maxTime, getArch, addLog, endBattle,
  ]);

  // ─── Select action ───────────────────────────────────────────────────────────────────────────
  const selectAction = useCallback((action: Action) => {
    if (!selectedClass || !player || !opponent) return;
    const arch = getArch(selectedClass.archetype);
    const focusCost = ACTIONS[action].focusCost;
    if (focusCost > 0 && player.focus < focusCost) {
      addLog(`⚠️ Not enough focus for ${action}. Build up with Attack or Defend first.`);
      return;
    }

    setCurrentAction(action);
    setPhase("question");

    // Difficulty based on action and archetype range
    const level    = getActionDifficultyLevel(arch, action);
    const category = levelToCategory(level);
    const q        = generateQuestion(category);
    setCurrentQuestion(q);

    // Timer scales with archetype time multiplier
    const baseTime = TIMER_DURATIONS[category];
    const t        = Math.max(4, Math.round(baseTime * arch.timeMultiplier));
    setTimeLeft(t);
    setMaxTime(t);
    stopTimer();
    timerRef.current = setInterval(() => {
      setTimeLeft((prev) => {
        if (prev <= 1) {
          clearInterval(timerRef.current!);
          timerRef.current = null;
          // Time out → treat as wrong answer
          setPhase((curPhase) => {
            if (curPhase !== "question") return curPhase;
            setPlayer((pl) => {
              setOpponent((op) => {
                setRecords((rec) => {
                  if (pl && op && q) {
                    handleAnswer(false, q, t, pl, op, rec);
                  }
                  return rec;
                });
                return op;
              });
              return pl;
            });
            return "animate";
          });
          return 0;
        }
        return prev - 1;
      });
    }, 1000);
  }, [selectedClass, player, opponent, getArch, addLog, stopTimer, handleAnswer]);

  // ─── Start battle ───────────────────────────────────────────────────────────────────────────
  const startBattle = useCallback(async (sel: ClassSelection) => {
    setSelectedClass(sel);
    const cls  = sel.archetype;
    const baseArch = ARCHETYPES[cls];

    // Roll Gambler stats before computing effective arch
    const rolledGambler = cls === "gambler" ? rollGamblerStats() : null;
    setGamblerStats(rolledGambler);

    const effectiveArch: Archetype = rolledGambler
      ? { ...baseArch, ...rolledGambler }
      : baseArch;

    const opp = pickOpponent(cls);
    setOpponentEcliptar(opp);
    const oppArch = ARCHETYPES[opp.archetype];

    const newPlayer: Fighter = {
      name:     sel.ecliptar.name,
      hp:       effectiveArch.maxHp,
      maxHp:    effectiveArch.maxHp,
      focus:    baseArch.startFocus,
      maxFocus: baseArch.focusPool,
      icon:     sel.ecliptar.icon,
    };
    const newOpponent: Fighter = {
      name:     opp.name,
      hp:       oppArch.maxHp,
      maxHp:    oppArch.maxHp,
      focus:    oppArch.startFocus,
      maxFocus: oppArch.focusPool,
      icon:     opp.icon,
    };

    setPlayer(newPlayer);
    setOpponent(newOpponent);
    setRecords([]);
    setMomentum(0);
    setBotMomentum(0);
    setLog([]);

    const logLines: string[] = [
      `⚔️ Battle start: ${sel.ecliptar.name} (${effectiveArch.name}) vs ${opp.name} (${oppArch.name})`,
    ];
    if (rolledGambler) {
      const { maxHp, baseDamage, multiplierStep, healAmount, diffMin, diffMax, timeMultiplier } = rolledGambler;
      const multPct = Math.round(multiplierStep * 100);
      logLines.push(`🎲 Gambler rolled: ${maxHp} HP · ${baseDamage} DMG · +${multPct}%/hit · Heal ${healAmount} · Diff ${diffMin}-${diffMax} · ${timeMultiplier}× time`);
    }

    // Track daily challenge
    const { data: { user } } = await supabase.auth.getUser();
    if (user) {
      const challenge = await getTodayChallenge();
      if (challenge) {
        logLines.push(`🎯 Daily challenge: Win ${challenge.target} battles today!`);
      }
    }

    setLog(logLines);
    setPhase("select");
  }, []);

  // ─── Reset ───────────────────────────────────────────────────────────────────────────────────
  const resetBattle = useCallback(() => {
    stopTimer();
    setPhase("idle");
    setSelectedClass(null);
    setPlayer(null);
    setOpponent(null);
    setOpponentEcliptar(null);
    setCurrentQuestion(null);
    setMomentum(0);
    setBotMomentum(0);
    setRecords([]);
    setLog([]);
    setBattleStats(null);
    setGamblerStats(null);
  }, [stopTimer]);

  // Cleanup on unmount
  useEffect(() => () => stopTimer(), [stopTimer]);

  // ─── Render ──────────────────────────────────────────────────────────────────────────────────
  // Phase: result
  if (phase === "result" && battleStats) {
    return (
      <BattleReport
        stats={battleStats}
        playerEcliptar={selectedClass?.ecliptar ?? null}
        opponentEcliptar={opponentEcliptar}
        onRematch={() => { resetBattle(); }}
        onNewBattle={() => { resetBattle(); }}
      />
    );
  }

  // Phase: idle — class select
  if (phase === "idle" || phase === "classSelect") {
    return (
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2">
          <ClassSelectDialog onSelect={(sel) => startBattle(sel)} />
        </div>
        <div className="space-y-6">
          <Leaderboard />
          {/* How to play */}
          <motion.div className="glass-panel p-6" initial={{ opacity: 0, x: 20 }} animate={{ opacity: 1, x: 0 }} transition={{ delay: 0.5 }}>
            <button
              onClick={() => setShowRules(true)}
              className="w-full flex items-center justify-between text-sm font-bold font-display tracking-widest hover:text-neon-cyan transition-colors"
            >
              HOW TO PLAY <HelpCircle className="w-4 h-4" />
            </button>
          </motion.div>
        </div>
      </div>
    );
  }

  // Phase: searching (brief transition)
  if (phase === "searching") {
    return (
      <div className="flex items-center justify-center min-h-[300px]">
        <motion.div
          className="text-center"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
        >
          <Swords className="w-12 h-12 text-neon-cyan mx-auto mb-4 animate-pulse" />
          <p className="text-lg font-bold font-display tracking-widest">FINDING OPPONENT...</p>
        </motion.div>
      </div>
    );
  }

  // Active battle phases
  if (!player || !opponent || !selectedClass) return null;
  const arch = getArch(selectedClass.archetype);
  const oppArch = opponentEcliptar ? ARCHETYPES[opponentEcliptar.archetype] : null;
  const step = getEffectiveMultiplierStep(arch, records.length);
  const currentMult = streakToMultiplier(momentum, step);

  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
      {/* Left: battle arena */}
      <div className="lg:col-span-2 space-y-4">
        {/* Fighter cards */}
        <div className="grid grid-cols-2 gap-4">
          <FighterCard
            fighter={player}
            isPlayer
            showHeal={showPlayerHeal}
            showDamage={showPlayerDamage}
            damageAmt={playerDmgAmt}
            archetype={arch}
          />
          <FighterCard
            fighter={opponent}
            isPlayer={false}
            showHeal={showOppHeal}
            showDamage={showOppDamage}
            damageAmt={oppDmgAmt}
            archetype={oppArch ?? undefined}
          />
        </div>

        {/* Streak + multiplier */}
        <div className="glass-panel p-3 flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Flame className="w-4 h-4 text-orange-400" />
            <span className="text-xs font-bold">{momentum} streak</span>
          </div>
          <div className="flex items-center gap-2">
            <Target className="w-4 h-4 text-neon-cyan" />
            <span className="text-xs font-bold text-neon-cyan">{currentMult.toFixed(2)}× DMG</span>
          </div>
          <div className="flex items-center gap-2">
            <Skull className="w-4 h-4 text-rose-400" />
            <span className="text-xs font-bold">{botMomentum} bot streak</span>
          </div>
        </div>

        {/* Question + Timer */}
        <AnimatePresence mode="wait">
          {phase === "question" && currentQuestion && (
            <motion.div
              key="question"
              className="glass-panel p-6 space-y-4"
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -20 }}
            >
              <div className="flex items-center justify-between mb-2">
                <span className={`text-[10px] font-bold tracking-widest px-2 py-0.5 rounded ${
                  currentAction === "charge" ? "bg-orange-500/20 text-orange-400" :
                  currentAction === "defend" ? "bg-blue-500/20 text-blue-400" :
                  currentAction === "wild"   ? "bg-purple-500/20 text-purple-400" :
                  "bg-neon-cyan/20 text-neon-cyan"
                }`}>
                  {currentAction.toUpperCase()}
                </span>
                <div className="flex items-center gap-2">
                  <Timer className="w-3.5 h-3.5 text-muted-foreground" />
                  <span className={`text-sm font-bold font-display ${
                    timeLeft <= 5 ? "text-rose-400" : timeLeft <= 10 ? "text-orange-400" : "text-foreground"
                  }`}>{timeLeft}s</span>
                </div>
              </div>

              {/* Timer bar */}
              <div className="h-1 bg-secondary/30 rounded-full overflow-hidden">
                <motion.div
                  className={`h-full rounded-full ${
                    timeLeft <= 5 ? "bg-rose-500" : timeLeft <= 10 ? "bg-orange-400" : "bg-neon-cyan"
                  }`}
                  animate={{ width: `${(timeLeft / maxTime) * 100}%` }}
                  transition={{ duration: 0.3 }}
                />
              </div>

              <p className="text-lg font-bold text-center">{currentQuestion.q}</p>

              <div className="grid grid-cols-2 gap-3">
                {currentQuestion.options.map((opt) => (
                  <Button
                    key={opt}
                    variant="outline"
                    className="h-12 text-base font-bold hover:bg-neon-cyan/10 hover:border-neon-cyan transition-colors"
                    onClick={() => {
                      const isCorrect = opt === currentQuestion.answer;
                      const ts = maxTime - timeLeft;
                      setPhase("animate");
                      handleAnswer(isCorrect, currentQuestion, ts, player, opponent, records);
                    }}
                  >
                    {opt}
                  </Button>
                ))}
              </div>
            </motion.div>
          )}

          {/* Action select */}
          {phase === "select" && (
            <motion.div
              key="select"
              className="glass-panel p-6 space-y-4"
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -20 }}
            >
              <div className="flex items-center justify-between mb-1">
                <p className="text-sm font-bold font-display tracking-widest">CHOOSE YOUR MOVE</p>
                <div className="flex items-center gap-1 text-[10px] text-muted-foreground">
                  <Dices className="w-3 h-3" /> Focus: {player.focus}/{player.maxFocus}
                </div>
              </div>
              <div className="grid grid-cols-2 gap-3">
                {(Object.entries(ACTIONS) as [Action, ActionConfig][]).map(([key, cfg]) => {
                  const canAfford = cfg.focusCost <= 0 || player.focus >= cfg.focusCost;
                  return (
                    <button
                      key={key}
                      disabled={!canAfford}
                      onClick={() => selectAction(key)}
                      className={`glass-panel p-4 text-left border transition-colors relative group ${
                        canAfford
                          ? "hover:border-neon-cyan/60 hover:bg-neon-cyan/5 cursor-pointer"
                          : "opacity-40 cursor-not-allowed border-border/20"
                      }`}
                    >
                      <div className="flex items-center gap-2 mb-1">
                        <cfg.icon className="w-4 h-4 text-neon-cyan" />
                        <span className="text-sm font-bold font-display">{cfg.label}</span>
                        <button
                          onClick={(e) => { e.stopPropagation(); setShowActionInfo(key); }}
                          className="ml-auto opacity-0 group-hover:opacity-100 transition-opacity"
                        >
                          <Info className="w-3 h-3 text-muted-foreground" />
                        </button>
                      </div>
                      <p className="text-[10px] text-muted-foreground">{cfg.desc}</p>
                      {cfg.focusCost > 0 && (
                        <span className="absolute top-2 right-2 text-[9px] font-bold text-neon-purple">
                          −{cfg.focusCost} Focus
                        </span>
                      )}
                    </button>
                  );
                })}
              </div>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Right: log */}
      <div className="space-y-4">
        <motion.div
          className="glass-panel p-4"
          initial={{ opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: 0.2 }}
        >
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-xs font-bold font-display tracking-widest">BATTLE LOG</h3>
            <Button variant="ghost" size="sm" onClick={resetBattle} className="text-xs text-muted-foreground hover:text-rose-400 h-auto py-0.5 px-2">
              Forfeit
            </Button>
          </div>
          <div className="space-y-1.5 max-h-80 overflow-y-auto">
            {log.map((entry, i) => (
              <p key={i} className="text-[11px] text-muted-foreground leading-relaxed">{entry}</p>
            ))}
          </div>
        </motion.div>

        {/* Archetype passive reminder */}
        <motion.div
          className="glass-panel p-4"
          initial={{ opacity: 0, x: 20 }}
          animate={{ opacity: 1, x: 0 }}
          transition={{ delay: 0.4 }}
        >
          <p className={`text-[10px] font-bold tracking-widest mb-1 ${arch.color}`}>{arch.name.toUpperCase()}</p>
          <p className="text-[11px] text-muted-foreground">{arch.passive}</p>
        </motion.div>
      </div>

      {/* Rules dialog */}
      <Dialog open={showRules} onOpenChange={setShowRules}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle className="font-display tracking-widest">HOW TO PLAY</DialogTitle>
            <DialogDescription asChild>
              <div className="space-y-3 text-sm text-muted-foreground mt-2">
                <p><strong className="text-foreground">Objective:</strong> Reduce the opponent's HP to 0 by answering math questions correctly.</p>
                <p><strong className="text-foreground">Actions:</strong></p>
                <ul className="space-y-1 ml-4">
                  <li>⚡ <strong className="text-foreground">Attack</strong> — Answer a mid-difficulty question. Deal base damage and build +15 Focus.</li>
                  <li>🛡️ <strong className="text-foreground">Defend</strong> — Answer an easy question. Restore HP and build +10 Focus (Tank cannot heal).</li>
                  <li>🔥 <strong className="text-foreground">Charge</strong> — Hard question, spend 30 Focus. Deal 1.8× damage.</li>
                  <li>✨ <strong className="text-foreground">Wild</strong> — Random question and damage, spend 20 Focus.</li>
                </ul>
                <p><strong className="text-foreground">Streak multiplier:</strong> Each correct answer in a row adds to your damage multiplier. Miss and it resets.</p>
                <p><strong className="text-foreground">Wrong answers:</strong> Deal self-damage. Glass cannons hurt more; tanks hurt less.</p>
                <p><strong className="text-foreground">Archetypes:</strong> Each class has unique HP, damage, healing, and difficulty ranges. The Gambler's stats are rolled fresh each battle.</p>
              </div>
            </DialogDescription>
          </DialogHeader>
        </DialogContent>
      </Dialog>

      {/* Action info dialog */}
      <Dialog open={!!showActionInfo} onOpenChange={() => setShowActionInfo(null)}>
        <DialogContent className="max-w-sm">
          {showActionInfo && (
            <>
              <DialogHeader>
                <DialogTitle className="font-display tracking-widest flex items-center gap-2">
                  {(() => { const Icon = ACTIONS[showActionInfo].icon; return <Icon className="w-5 h-5 text-neon-cyan" />; })()}
                  {ACTIONS[showActionInfo].label.toUpperCase()}
                </DialogTitle>
                <DialogDescription asChild>
                  <div className="text-sm text-muted-foreground space-y-2 mt-2">
                    <p>{ACTIONS[showActionInfo].desc}</p>
                    {showActionInfo === "attack"  && <p>Deals your archetype's base damage × streak multiplier. Generates +15 focus. Mid-difficulty question.</p>}
                    {showActionInfo === "defend"  && <p>Restores HP equal to your archetype's heal stat (Tank: none). Generates +10 focus. Easy question, lowest risk.</p>}
                    {showActionInfo === "charge"  && <p>Costs 30 Focus. Deals 1.8× base damage × streak multiplier. Hardest question in your archetype's range.</p>}
                    {showActionInfo === "wild"    && <p>Costs 20 Focus. Randomly selects both question difficulty and damage within your archetype's range.</p>}
                  </div>
                </DialogDescription>
              </DialogHeader>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
