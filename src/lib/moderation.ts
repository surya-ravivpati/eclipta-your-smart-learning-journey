/**
 * Client wrapper for the `moderate-content` edge function and related
 * moderation RPCs.
 *
 * The forum composer flow is:
 *   1. (Optional) Local pre-check with isCleanForumContent — instant feedback
 *      for the obvious cases.
 *   2. Call moderateContent() before INSERT. If verdict === 'block', refuse
 *      to submit. Otherwise insert the row normally.
 *   3. After INSERT, call moderateContent() again with targetId so the edge
 *      function can update the row's moderation_status (the AI verdict is
 *      what actually drives whether the post shows up publicly).
 *
 * Splitting the call in two means a slow LLM doesn't block the user's
 * "Posted!" confirmation — the post lands immediately, and within a second
 * or two its visibility flips if the AI decides to hide it.
 */
import { supabase } from "@/integrations/supabase/client";

export type ModerationVerdict = "allow" | "hide" | "block" | "pending";
export type ModerationTarget = "thread" | "answer" | "comment" | "username";

export interface ModerationResult {
  verdict: ModerationVerdict;
  category: string;
  score: number;
  reason: string;
}

const SAFE_FALLBACK: ModerationResult = {
  verdict: "pending",
  category: "unknown",
  score: 50,
  reason: "Moderation service unavailable — your post will be reviewed.",
};

export async function moderateContent(
  text: string,
  targetType: ModerationTarget,
  targetId?: string | null,
): Promise<ModerationResult> {
  try {
    const { data, error } = await supabase.functions.invoke("moderate-content", {
      body: { text, targetType, targetId: targetId ?? null },
    });
    if (error) {
      console.error("moderateContent: invoke error", error);
      return SAFE_FALLBACK;
    }
    if (!data || typeof data !== "object" || !("verdict" in data)) {
      console.warn("moderateContent: malformed response", data);
      return SAFE_FALLBACK;
    }
    const result = data as Partial<ModerationResult>;
    return {
      verdict: (result.verdict as ModerationVerdict) ?? "pending",
      category: result.category ?? "unknown",
      score: typeof result.score === "number" ? result.score : 0,
      reason: result.reason ?? "",
    };
  } catch (e) {
    console.error("moderateContent threw", e);
    return SAFE_FALLBACK;
  }
}

/**
 * Run the AI pass *after* insert so the row gets its final moderation_status
 * without blocking the user's UI. Best-effort: any failure is logged but the
 * post stays in whatever state the synchronous pass left it.
 */
export async function moderateAfterInsert(
  text: string,
  targetType: Exclude<ModerationTarget, "username">,
  targetId: string,
): Promise<void> {
  try {
    await supabase.functions.invoke("moderate-content", {
      body: { text, targetType, targetId },
    });
  } catch (e) {
    // Don't surface to the user — the trigger already gated obvious bad
    // content; this is the contextual second pass.
    console.warn("moderateAfterInsert failed", e);
  }
}

/**
 * Submit a report through the authoritative RPC (which enforces dedup,
 * rate limiting, and auto-hide thresholds).
 */
export async function submitForumReport(
  targetType: "thread" | "answer" | "comment",
  targetId: string,
  reason: string,
): Promise<{ ok: true; deduplicated?: boolean; autoHidden?: boolean; reportCount?: number } | { ok: false; error: string }> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { data, error } = await supabase.rpc("submit_forum_report" as any, {
    p_target_type: targetType,
    p_target_id: targetId,
    p_reason: reason,
  });
  if (error) return { ok: false, error: error.message };
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const d = data as any;
  return {
    ok: true,
    deduplicated: !!d?.deduplicated,
    autoHidden: !!d?.auto_hidden,
    reportCount: d?.report_count ?? undefined,
  };
}

/**
 * Moderator-only: change visibility of a forum item. Always logs.
 */
export async function setModerationStatus(
  targetType: "thread" | "answer" | "comment",
  targetId: string,
  status: "visible" | "hidden" | "removed",
  reason?: string,
): Promise<{ ok: true } | { ok: false; error: string }> {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const { error } = await supabase.rpc("set_moderation_status" as any, {
    p_target_type: targetType,
    p_target_id: targetId,
    p_status: status,
    p_reason: reason ?? null,
  });
  if (error) return { ok: false, error: error.message };
  return { ok: true };
}

/**
 * Human-friendly placeholder rendered in place of removed content. Centralised
 * so every surface (thread list, thread detail, comments, search) uses the
 * exact same string — making it obvious to users that the system is active.
 */
export const REMOVED_PLACEHOLDER = "Removed by moderator";

export function isContentVisible(
  status: string | null | undefined,
  isOwnContent: boolean,
  isModerator: boolean,
): boolean {
  if (!status || status === "visible") return true;
  // Authors and moderators can always see their hidden content (with a banner)
  // so they understand what happened and can edit / restore.
  return isOwnContent || isModerator;
}
