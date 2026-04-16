/**
 * Maps archetype stat values (0-4) to concrete battle mechanics.
 */
import type { Difficulty } from "./types";

/** Health stat → max HP */
export function statToHp(health: number): number {
  const map: Record<number, number> = { 0: 50, 1: 75, 2: 100, 3: 125, 4: 150 };
  return map[health] ?? 100;
}

/** Time stat → timer multiplier applied to base TIMER_DURATIONS */
export function statToTimeMult(time: number): number {
  const map: Record<number, number> = { 0: 0.6, 1: 0.75, 2: 1.0, 3: 1.25, 4: 1.5 };
  return map[time] ?? 1.0;
}

/** Damage stat → damage multiplier on base action damage */
export function statToDmgMult(damage: number): number {
  const map: Record<number, number> = { 0: 0.5, 1: 0.75, 2: 1.0, 3: 1.3, 4: 1.6 };
  return map[damage] ?? 1.0;
}

/** Multiplier stat → streak bonus per combo hit */
export function statToStreakMult(multiplier: number): number {
  const map: Record<number, number> = { 0: 1.0, 1: 1.1, 2: 1.2, 3: 1.35, 4: 1.5 };
  return map[multiplier] ?? 1.2;
}

/** Difficulty stat → shift the action's base difficulty up/down */
export function statToDifficulty(baseDiff: Difficulty, diffStat: number): Difficulty {
  const order: Difficulty[] = ["easy", "medium", "hard"];
  const baseIdx = order.indexOf(baseDiff);
  if (diffStat <= 1) return order[Math.max(0, baseIdx - 1)]; // shift easier
  if (diffStat >= 3) return order[Math.min(2, baseIdx + 1)]; // shift harder
  return baseDiff; // stat 2 = no change
}

/** Self-damage multiplier based on health stat (tankier = less self-damage) */
export function statToSelfDmgMult(health: number): number {
  const map: Record<number, number> = { 0: 1.3, 1: 1.0, 2: 0.85, 3: 0.7, 4: 0.5 };
  return map[health] ?? 1.0;
}
