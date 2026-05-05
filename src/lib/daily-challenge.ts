/**
 * Daily challenge definitions — rotated deterministically by UTC date.
 * Each variant changes the goal, target, and bonus copy so it actually
 * feels different from one day to the next.
 */
export type DailyChallenge = {
  id: string;
  title: string;
  goal: string;
  target: number;
  reward: string;
  /** Counted unit for progress UI */
  unit: string;
};

const VARIANTS: DailyChallenge[] = [
  { id: "wins-3",     title: "Triple Threat",      goal: "Win 3 battles today",                    target: 3, reward: "+2x XP bonus",            unit: "wins" },
  { id: "wins-5",     title: "Arena Marathon",     goal: "Win 5 battles today",                    target: 5, reward: "+500 XP + Combo Token",   unit: "wins" },
  { id: "wins-2",     title: "Warm-Up",            goal: "Win 2 battles today",                    target: 2, reward: "+150 XP boost",           unit: "wins" },
  { id: "wins-4",     title: "Steady Climb",       goal: "Win 4 battles today",                    target: 4, reward: "+300 XP + Focus Regen",   unit: "wins" },
  { id: "wins-1",     title: "First Blood",        goal: "Win 1 battle today",                     target: 1, reward: "+100 XP starter",         unit: "wins" },
  { id: "wins-6",     title: "Champion's Gauntlet",goal: "Win 6 battles today",                    target: 6, reward: "+750 XP + Shield Token",  unit: "wins" },
  { id: "wins-3-flow",title: "Flow State",         goal: "Win 3 battles today",                    target: 3, reward: "+250 XP + Streak Boost",  unit: "wins" },
];

/** Deterministic UTC-day index → variant. Same day = same challenge for everyone. */
export function getTodayChallenge(now: Date = new Date()): DailyChallenge {
  const utcDays = Math.floor(Date.UTC(
    now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()
  ) / 86_400_000);
  return VARIANTS[((utcDays % VARIANTS.length) + VARIANTS.length) % VARIANTS.length];
}