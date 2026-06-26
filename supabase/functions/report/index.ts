// report — the verified, auto-acting reporting processor.
//
// A report is a TRIGGER FOR RE-EVALUATION, never a decision. This function:
//   1. Persists the report (submit_report RPC — logs EVERY report, dedupes the
//      re-scan so 10 simultaneous reports cause exactly ONE re-scan).
//   2. Loads the target's CURRENT content and calls the SAME moderation
//      pipeline (moderate-content) on demand, passing the reporter's note as
//      non-authoritative context. No moderation logic is reimplemented here.
//   3. Applies the trust-weighted outcome (apply_report_outcome): the pipeline's
//      own verdict acts; clean-but-many-high-trust → human escalation; brigades
//      get surfaced. Reports never remove content by count.
//
// The reported party is never notified. The reporter only ever gets a generic
// acknowledgement.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type TargetType = "thread" | "answer" | "comment" | "username" | "chat_message";

// Load a target's current content text + author. null ⇒ gone/no scannable row.
async function loadContent(svc: any, targetType: TargetType, targetId: string | null):
  Promise<{ text: string; author: string | null } | null> {
  if (!targetId) return null;
  if (targetType === "thread") {
    const { data } = await svc.from("forum_threads").select("title, body, user_id").eq("id", targetId).maybeSingle();
    return data ? { text: `${data.title ?? ""}\n\n${data.body ?? ""}`, author: data.user_id } : null;
  }
  if (targetType === "answer") {
    const { data } = await svc.from("forum_answers").select("body, user_id").eq("id", targetId).maybeSingle();
    return data ? { text: data.body ?? "", author: data.user_id } : null;
  }
  if (targetType === "comment") {
    const { data } = await svc.from("forum_comments").select("body, user_id").eq("id", targetId).maybeSingle();
    return data ? { text: data.body ?? "", author: data.user_id } : null;
  }
  if (targetType === "chat_message") {
    const { data } = await svc.from("study_room_messages").select("body, user_id").eq("id", targetId).maybeSingle();
    return data ? { text: data.body ?? "", author: data.user_id } : null;
  }
  if (targetType === "username") {
    // The username target_id IS the user; re-scan their current handle.
    const { data } = await svc.from("user_profiles").select("username").eq("user_id", targetId).maybeSingle();
    return data?.username ? { text: data.username, author: targetId } : null;
  }
  return null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  const json = (b: unknown, status = 200) =>
    new Response(JSON.stringify(b), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  // Reporters only ever see this. Generic by design — never leaks the outcome.
  const ack = () => json({ ok: true, status: "submitted" });

  try {
    const token = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    if (!token) return json({ error: "Unauthorized" }, 401);
    const URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
    const svc = createClient(URL, SERVICE_KEY);
    const { data: userData } = await svc.auth.getUser(token);
    if (!userData?.user) return json({ error: "Unauthorized" }, 401);
    // User-scoped client so submit_report's auth.uid() resolves to the reporter.
    const userClient = createClient(URL, ANON_KEY, { global: { headers: { Authorization: `Bearer ${token}` } } });

    const body = await req.json().catch(() => ({}));
    const targetType = body?.target_type as TargetType;
    const targetId = (body?.target_id ?? null) as string | null;
    const category = typeof body?.category === "string" ? body.category : null;
    const note = typeof body?.note === "string" ? body.note : null;
    if (!["thread", "answer", "comment", "username", "chat_message"].includes(targetType)) {
      return json({ error: "Invalid target type" }, 400);
    }

    // 1. Persist + dedupe-claim.
    const { data: sub, error: subErr } = await userClient.rpc("submit_report", {
      p_target_type: targetType, p_target_id: targetId, p_category: category, p_note: note,
    });
    if (subErr) return json({ error: subErr.message }, 400);
    // Logged. If another scan just ran / is in flight, this report shares its
    // outcome — nothing more to do.
    if (!(sub as any)?.need_rescan) return ack();

    // 2. Load current content; gone ⇒ close gracefully (no error).
    const content = await loadContent(svc, targetType, targetId);
    if (!content) {
      await svc.rpc("mark_report_target_gone", { p_target_type: targetType, p_target_id: targetId });
      return ack();
    }

    // 3. Re-scan through the SAME pipeline (note as context, not authority).
    let mod: any = null;
    try {
      const r = await fetch(`${URL}/functions/v1/moderate-content`, {
        method: "POST",
        headers: { Authorization: `Bearer ${token}`, apikey: ANON_KEY, "Content-Type": "application/json" },
        body: JSON.stringify({ text: content.text, targetType, targetId, mode: "record", note }),
      });
      if (r.ok) mod = await r.json();
    } catch (e) {
      console.error("report: pipeline call failed", e);
    }
    // Pipeline unreachable → leave the open report(s) for a later retry (they go
    // stale after 2 min and the next report re-scans). Reporter still gets ack.
    if (!mod) return ack();

    // 4. Apply the verified, trust-weighted outcome.
    await svc.rpc("apply_report_outcome", {
      p_target_type: targetType, p_target_id: targetId, p_target_author: content.author,
      p_decision: mod.decision ?? "allow", p_category: mod.category === "none" ? null : mod.category,
      p_confidence: Math.round(mod.confidence ?? 0), p_decision_id: mod.decisionId ?? null,
      p_snapshot: content.text,
    });

    return ack();
  } catch (e) {
    console.error("report fatal:", e);
    // Never surface internals to the reporter.
    return json({ ok: true, status: "submitted" });
  }
});
