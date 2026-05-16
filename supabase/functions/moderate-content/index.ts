/* eslint-disable @typescript-eslint/no-explicit-any */
// moderate-content
//
// Contextual moderation for forum posts, answers, comments, and usernames.
// Replaces the trivial banned-word list with a layered check:
//
//   1. Auth gate + per-user rate limit.
//   2. Dictionary pre-filter via moderation_match() RPC. Severity >= 8 means
//      the post almost certainly contains a slur regardless of context, and
//      we short-circuit with verdict='block' before paying for an LLM call.
//   3. AI gateway pass that classifies the cleaned text into one of
//      {allow, hide, block}. The model is prompted to ignore obvious math /
//      programming jargon and only flag genuinely harmful content. JSON is
//      schema-validated; anything malformed falls back to 'pending' so we
//      err on the side of caution.
//   4. (Optional) If a target_id is supplied, the verdict is applied to the
//      row via apply_ai_moderation_result so the row's moderation_status is
//      updated immediately.
//
// The function is designed to be called from the client right before INSERT
// (allow/hide/block decision), and also from a post-insert step to push the
// AI verdict back to the row.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type TargetType = "thread" | "answer" | "comment" | "username";

interface Verdict {
  verdict: "allow" | "hide" | "block" | "pending";
  category: string;
  score: number;          // 0–100, severity of detected issue
  reason: string;
}

const SAFE_FALLBACK: Verdict = {
  verdict: "pending",
  category: "unknown",
  score: 50,
  reason: "Moderation classifier unavailable",
};

const SYSTEM_PROMPT = `You are a strict content moderator for a learning platform's community forum. Users post questions about math, programming, science, and study skills.

Classify the user's submitted text into exactly one of three verdicts:
- "allow": Safe. Normal forum content. Includes technical discussions, frustration ("ugh this is so confusing"), mild venting, debate.
- "hide": Borderline. Profanity used aggressively, mild harassment, off-topic spam, suggestive but not explicit content, low-effort posts, attempts to dodge filters with spacing/symbols. Hide pending human review.
- "block": Clearly harmful and must never be public. Slurs, hate speech against a protected group, sexual content involving minors, explicit graphic sex, doxxing, credible threats, self-harm encouragement, scams/phishing, mass spam.

Rules:
- Math/code with words like "kill the process", "abort", "execute" → allow.
- Profanity directed at concepts ("this problem is fucking hard") → hide. Directed at a person ("you're a fucking idiot") → block.
- Edge-cases bias toward "hide" (a human can restore later) over "block".
- Detect filter evasion: spaced letters (f u c k), homoglyphs, leet (fck, fuk, f4g), zero-width chars between letters. Judge based on the obvious intent.
- A username submission ("targetType":"username") is held to a stricter bar: any slur, sexual term, or impersonation of staff → block.

Return ONLY a single JSON object, no prose:
{"verdict":"allow|hide|block","category":"hate|sexual|self_harm|harassment|spam|profanity|safe","score":0-100,"reason":"<one short sentence>"}`;

// In-process per-user rate limiter. Edge functions reset between cold starts
// but within a warm instance this prevents one client from hammering the
// moderation pipeline. Acts as a defence-in-depth alongside the DB-side
// reporter rate limit.
const rateBucket = new Map<string, number[]>();
function checkRate(userId: string, maxPerMinute = 30): boolean {
  const now = Date.now();
  const window = 60_000;
  const bucket = (rateBucket.get(userId) || []).filter((t) => now - t < window);
  if (bucket.length >= maxPerMinute) return false;
  bucket.push(now);
  rateBucket.set(userId, bucket);
  return true;
}

async function classifyWithAi(
  text: string,
  targetType: TargetType,
  apiKey: string,
): Promise<Verdict> {
  // Cap the prompt budget. Forum bodies cap at 4000 chars on the client; we
  // truncate again here as defence in depth so a tampered client can't ship
  // a 1MB payload to the model.
  const trimmed = text.slice(0, 4000);

  try {
    const response = await fetch("https://ai.gateway.lovable.dev/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "google/gemini-3-flash-preview",
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          {
            role: "user",
            content: `targetType: ${targetType}\n---\n${trimmed}`,
          },
        ],
        temperature: 0,
      }),
    });

    if (!response.ok) {
      console.error("moderate-content: AI gateway returned", response.status, await response.text());
      return SAFE_FALLBACK;
    }

    const data = await response.json();
    const raw = data?.choices?.[0]?.message?.content ?? "";

    // Extract the first JSON object from the response (the model may wrap it
    // in ```json fences or prose despite the instruction).
    const match = String(raw).match(/\{[\s\S]*?\}/);
    if (!match) {
      console.warn("moderate-content: model did not return JSON, raw:", raw);
      return SAFE_FALLBACK;
    }
    let parsed: Partial<Verdict>;
    try {
      parsed = JSON.parse(match[0]);
    } catch (e) {
      console.warn("moderate-content: JSON parse failed", e, match[0]);
      return SAFE_FALLBACK;
    }

    const verdict = parsed.verdict;
    if (verdict !== "allow" && verdict !== "hide" && verdict !== "block") {
      return SAFE_FALLBACK;
    }

    return {
      verdict,
      category: typeof parsed.category === "string" ? parsed.category : "unknown",
      score: typeof parsed.score === "number" ? Math.min(100, Math.max(0, parsed.score)) : 50,
      reason: typeof parsed.reason === "string" ? parsed.reason.slice(0, 240) : "",
    };
  } catch (e) {
    console.error("moderate-content: AI call threw", e);
    return SAFE_FALLBACK;
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace("Bearer ", "");
    if (!token) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const sb = createClient(SUPABASE_URL, SERVICE_KEY);
    const { data: userData } = await sb.auth.getUser(token);
    if (!userData?.user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const userId = userData.user.id;

    if (!checkRate(userId)) {
      return new Response(
        JSON.stringify({ error: "Rate limit exceeded — slow down." }),
        { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Body parsing + bounds.
    const raw = await req.text();
    if (raw.length > 32 * 1024) {
      return new Response(JSON.stringify({ error: "Request too large" }), {
        status: 413, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    let payload: { text?: string; targetType?: TargetType; targetId?: string | null };
    try { payload = JSON.parse(raw); } catch {
      return new Response(JSON.stringify({ error: "Invalid JSON" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const text = (payload.text ?? "").toString();
    const targetType: TargetType = (payload.targetType as TargetType) ?? "thread";
    const targetId = payload.targetId ?? null;

    if (!text.trim()) {
      return new Response(
        JSON.stringify({ verdict: "allow", category: "safe", score: 0, reason: "Empty text" }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    if (!["thread","answer","comment","username"].includes(targetType)) {
      return new Response(JSON.stringify({ error: "Invalid targetType" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 1. Dictionary pre-filter. The DB function uses the same normalisation
    //    as the trigger so the client sees the exact verdict the trigger
    //    would have enforced.
    const { data: matches, error: matchErr } = await sb.rpc(
      "moderation_match" as any,
      { p_text: text },
    );
    if (matchErr) {
      console.error("moderate-content: moderation_match failed", matchErr);
      // Don't fail the user's post on a DB hiccup; fall through to AI.
    }
    const topMatch = Array.isArray(matches) && matches.length > 0 ? matches[0] as { term: string; category: string; severity: number } : null;
    if (topMatch && topMatch.severity >= 8) {
      const verdict: Verdict = {
        verdict: "block",
        category: topMatch.category,
        score: topMatch.severity * 10,
        reason: `Matched banned term "${topMatch.term}"`,
      };
      // If a row already exists (post-insert moderation), mark it removed.
      if (targetId && targetType !== "username") {
        await sb.rpc("apply_ai_moderation_result" as any, {
          p_target_type: targetType,
          p_target_id: targetId,
          p_verdict: "block",
          p_category: verdict.category,
          p_score: verdict.score,
          p_reason: verdict.reason,
        });
      }
      return new Response(JSON.stringify(verdict), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // 2. AI contextual classification.
    const apiKey = Deno.env.get("LOVABLE_API_KEY");
    if (!apiKey) {
      // No AI key configured — fall back to the dictionary pre-filter result.
      // Anything not hit by the dictionary is allowed.
      const verdict: Verdict = topMatch
        ? {
            verdict: "hide",
            category: topMatch.category,
            score: topMatch.severity * 10,
            reason: `Matched term "${topMatch.term}" — held for review (AI unavailable)`,
          }
        : { verdict: "allow", category: "safe", score: 0, reason: "Passed dictionary check" };
      return new Response(JSON.stringify(verdict), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const aiVerdict = await classifyWithAi(text, targetType, apiKey);

    // Combine: if the dictionary already flagged the post, never let the AI
    // weaken the verdict to "allow".
    let finalVerdict: Verdict = aiVerdict;
    if (topMatch && aiVerdict.verdict === "allow") {
      finalVerdict = {
        verdict: "hide",
        category: topMatch.category,
        score: topMatch.severity * 10,
        reason: `Matched term "${topMatch.term}" — overriding AI allow to hide`,
      };
    }

    // 3. If a target_id was supplied, push the verdict to the row.
    if (targetId && targetType !== "username") {
      const { error: applyErr } = await sb.rpc("apply_ai_moderation_result" as any, {
        p_target_type: targetType,
        p_target_id: targetId,
        p_verdict: finalVerdict.verdict === "pending" ? "hide" : finalVerdict.verdict,
        p_category: finalVerdict.category,
        p_score: finalVerdict.score,
        p_reason: finalVerdict.reason,
      });
      if (applyErr) {
        console.error("moderate-content: apply_ai_moderation_result failed", applyErr);
      }
    }

    return new Response(JSON.stringify(finalVerdict), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("moderate-content fatal error:", e);
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : "Unknown error" }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
