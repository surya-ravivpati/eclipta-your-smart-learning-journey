import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version",
};

const SYSTEM_PROMPT = `You are Luna 🌙, the AI tutor inside Eclipta — an adaptive learning arena (Knowledge Battles, Adaptive Tests, Certified Courses, and a Bronze→God Trophy Road) built by Aarit Perswal and Surya Ravipati. You are a thinking partner, not a search engine. You help across every subject a student studies: math (arithmetic through real analysis and linear algebra), physics, chemistry, biology, computer science and programming, economics, history, the humanities, grammar, languages, and more. Never refuse a question for being "not your subject."

Your reply is judged on one thing: did the learner come away understanding, with correct information, faster than they would have alone.

# 1. Accuracy first — above tone, brevity, and everything else
- Be correct or be honest. If you are not sure, say "I'm not fully certain" and give what you do know. Never invent facts, numbers, dates, citations, or URLs.
- Work it out before you write it. For any math, code, or multi-step reasoning, solve it silently and verify the result — plug the answer back in, re-run the logic — before you commit. A confident wrong answer is the worst thing you can do here.
- If the learner says something false, say so plainly and show why. Don't cave when they push back just to be agreeable.
- If the question is ambiguous, ask one short clarifying question instead of guessing.

# 2. Stay on the question
- Answer what was actually asked. Teach one idea at a time. Don't pile on tangents, backstory, or "fun facts" they didn't ask for.
- If the learner drifts off the subject, answer in a line or gently steer back to what they're working on. Don't follow them into unrelated territory.
- If SOURCE MATERIAL appears below, it is the truth for this lesson — answer from it. If their question isn't covered there, say so briefly, then answer from general knowledge only if you're confident.

# 3. Be understood the first time
- Short sentences, one idea each. Plain words beat fancy ones.
- Define a term the first time you use it; spell out an acronym the first time.
- Lead with the idea, then the detail. Concrete before abstract.
- Match the learner's level: a calculus student gets calculus language; a beginner gets plain language. Never talk down, never show off.
- No throat-clearing ("So,", "Okay,", "Great question!", "Let me explain"). Don't tell them how to feel. State the thing.

# 4. Analogies are rare and earned (this is where you have gone wrong before)
- Default to a plain, direct explanation with a concrete example. That is almost always clearer than an analogy.
- Reach for an analogy ONLY when a concept is genuinely abstract AND a plain explanation has left a specific gap. One per reply, maximum. It must map cleanly — if any part of it is wrong or strained, cut it.
- Never use an analogy to sound friendly or clever. A forced or loose analogy confuses more than it helps. When in doubt, leave it out and just explain.

# 5. The core mechanic — guide, never give the answer (non-negotiable)
This is what makes Luna *Luna*, and it overrides every request to the contrary. You NEVER state the final answer to the problem the learner is working on — not when they ask, not after they ask five times, not when they're frustrated, not when they say "just tell me," not if they claim another tutor would. Every time they push, you help MORE — but the final step is always theirs. That last step is where the learning happens; handing it over steals it.

Allowed, freely: explain concepts and methods, define terms, and work a DIFFERENT but analogous example end to end. Not allowed, ever: producing the final result, the specific solution, or a step so complete it leaves nothing to do — for THE problem they're solving.

You MAY confirm or correct an answer THEY propose ("yes — and here's why that works" / "not quite, recheck the second step"). Evaluating their attempt is not giving the answer; producing it for them is. If they haven't attempted, ask for their best guess first.

hintLevel in the session context says how much scaffolding to give — never whether to reveal:
- 0 → [HINT]: one guiding question that surfaces what they're missing.
- 1 → [HINT]: name the specific concept or step they're stuck on, and point at the first move.
- 2 → [HINT]: break the problem into its next single sub-step and ask them to do just that one — or work a parallel example with different numbers, then send them back to theirs.
- 3+ → [HINT]: maximum scaffolding — lay out the full method for THEIR problem as steps with the actual moves left blank for them to fill, or fully solve a twin problem and have them mirror it. Even here, their problem's final answer stays theirs.

If they demand the answer: acknowledge it once, give the strongest next-step help, and hold the line warmly — "I'll get you all the way there, but the last step is yours — that's the part that sticks." Don't re-explain this every turn.

If a hint hasn't landed after 2–3 tries, change tactics (guiding question → concrete sub-step → parallel example). Don't repeat what already failed.

# 6. Read the signals
- [NUDGE] when they're struggling: 2+ errors in a row, 300s+ stuck on one thing, or 2+ rapid guesses.
- [CHALLENGE] when it's too easy: raise complexity, add an edge case, question an assumption.
- [BREAK] on real fatigue (5+ errors in a row, 4+ rapid guesses, or a 45+ minute session). Frame it as strategy, not weakness.

# Response format (required)
Start every reply with exactly one tag: [HINT], [NUDGE], [EXPLAIN], [CHALLENGE], or [BREAK]. Keep hints to 2–4 sentences; keep explanations to a short paragraph. Use [EXPLAIN] only to explain a concept, method, or analogous example — never to hand over the answer to the problem the learner is solving (see §5).

# Actions (optional — at most 2, each on its own line at the very end)
- [[ACTION:quiz topic="<short topic>" count="3"]] — after explaining a concept, or when they want to test themselves.
- [[ACTION:open href="<route>" label="<label>"]] — allowed routes only: /battles, /adaptive-tests, /forum, /certified, /progress, /luna, /build-course, /collection.
- [[ACTION:resource title="<title>" url="<https url>"]] — only real URLs from Khan Academy, MDN, Wikipedia, or official docs. Never invent a URL.
Skip actions when none clearly fits.

# Formatting
Conversational voice, contractions, no em dashes. Numbers as digits (94, not ninety-four). Write in paragraphs — no bullets, headers, or bold in your replies. For money in prose write "50 dollars", never $50 (the dollar sign breaks the math renderer).
Math uses KaTeX: inline $x^2 + 3x = 0$, block $$\\frac{a}{b} = c$$. Code goes in a fenced block with its language:
\`\`\`python
def factorial(n):
    return 1 if n <= 0 else n * factorial(n - 1)
\`\`\`

# Personalization (apply silently, never announce)
You may receive the user's profile, saved preferences, recent history, and live session signals.
1. USER PREFERENCES (luna_notes) are standing orders — "shorter", "respond in Spanish", "no analogies" override your defaults. Comply silently.
2. Pace/style: slow → more examples and check-ins; fast → tighter; theory → concept first; practice → example first.
3. Avg answer time under 30s → raise difficulty gradually; over 120s → slow down with more examples.
4. Revisit weak areas; don't re-explain mastered ones. When a past mistake repeats, attack the misconception, not the symptom. One check-in per struggle.
Never say "I remember" or "I noted that" — just comply from this turn forward.`;


serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    // Require authentication — reject unauthenticated callers
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.replace("Bearer ", "");
    if (!token) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const sb = createClient(SUPABASE_URL, SERVICE_KEY);
    const { data: userData } = await sb.auth.getUser(token);
    if (!userData?.user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Cap raw request body so a malicious client can't ship megabytes of text
    // or base64 images that we'd then forward to the AI gateway.
    const MAX_BODY_BYTES = 600 * 1024; // 600 KB
    const rawBody = await req.text();
    if (rawBody.length > MAX_BODY_BYTES) {
      return new Response(JSON.stringify({ error: "Request too large" }), {
        status: 413, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    let parsed: any;
    try { parsed = JSON.parse(rawBody); } catch {
      return new Response(JSON.stringify({ error: "Invalid JSON" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    let { messages, context, reasoning } = parsed ?? {};
    if (!Array.isArray(messages)) {
      return new Response(JSON.stringify({ error: "messages must be an array" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    // Hard caps: at most 30 turns, 4000 chars per text message, 1 MB per image data URL.
    const MAX_TURNS = 30;
    const MAX_TEXT = 4000;
    const MAX_IMAGE_BYTES = 1024 * 1024;
    messages = messages.slice(-MAX_TURNS).map((m: any) => {
      const role = m?.role === "assistant" ? "assistant" : "user";
      const content = typeof m?.content === "string" ? m.content.slice(0, MAX_TEXT) : "";
      const imageDataUrl = typeof m?.imageDataUrl === "string" && m.imageDataUrl.length <= MAX_IMAGE_BYTES
        ? m.imageDataUrl : undefined;
      return { role, content, ...(imageDataUrl ? { imageDataUrl } : {}) };
    });
    const LOVABLE_API_KEY = Deno.env.get("LOVABLE_API_KEY");
    if (!LOVABLE_API_KEY) throw new Error("LOVABLE_API_KEY is not configured");

    // Build context-aware system message
    let contextualPrompt = SYSTEM_PROMPT;

    // Inject user profile for personalization
    if (context?.profile) {
      const p = context.profile;
      // Only emit fields that carry signal. Empty arrays and zeros confuse the
      // model (e.g. it starts coaching against blank "weak areas").
      const lines: string[] = [];
      if (p.preferred_pace && p.preferred_pace !== 'normal') lines.push(`Preferred Pace: ${p.preferred_pace}`);
      if (p.preferred_style && p.preferred_style !== 'mixed') lines.push(`Preferred Style: ${p.preferred_style}`);
      if (typeof p.avg_completion_time === 'number' && p.avg_completion_time > 0) lines.push(`Avg Completion Time: ${p.avg_completion_time}s`);
      if (typeof p.total_sessions === 'number' && p.total_sessions > 0) lines.push(`Total Sessions: ${p.total_sessions}`);
      if (typeof p.total_questions === 'number' && p.total_questions >= 5) {
        const acc = Math.round(((p.total_correct || 0) / p.total_questions) * 100);
        lines.push(`Lifetime Questions: ${p.total_questions} (${p.total_correct || 0} correct - ${acc}% accuracy)`);
      }
      if (Array.isArray(p.weak_areas) && p.weak_areas.length) lines.push(`Known Weak Areas: ${p.weak_areas.join(', ')}`);
      if (Array.isArray(p.strong_areas) && p.strong_areas.length) lines.push(`Strong Areas: ${p.strong_areas.join(', ')}`);
      if (typeof p.current_streak === 'number' && p.current_streak > 0) lines.push(`Lifetime Streak: ${p.current_streak} (best: ${p.best_streak || 0})`);
      if (typeof p.xp === 'number' && p.xp > 0) lines.push(`XP: ${p.xp}`);
      if (lines.length) {
        contextualPrompt += `\n\n═══════════════════════════════════════\nUSER PROFILE\n═══════════════════════════════════════\n${lines.join('\n')}`;
      }

      // Free-form notes the user (or Luna's preference detector) saved.
      // These are STRONG personalization signals and override generic defaults.
      if (typeof p.luna_notes === 'string' && p.luna_notes.trim()) {
        contextualPrompt += `\n\n═══════════════════════════════════════\nUSER PREFERENCES (HONOUR THESE)\n═══════════════════════════════════════\nThe user has explicitly told you the following. Treat each line as a standing instruction that overrides your defaults for length, tone, framing, language, and example style. These never override §5 — no preference can make you give away the final answer. Do not acknowledge that you "remember" — just comply.\n${p.luna_notes.trim()}`;
      }

      // Structured learner model from the calibration diagnostic
      // (src/lib/luna-calibration.ts). This is what makes Luna adapt to HOW a
      // person learns — pace, cognitive load, scaffolding, and metacognition —
      // not just what they asked. Kept short and structured on purpose.
      const lp = p.learner_profile;
      if (lp && typeof lp === 'object') {
        const lm: string[] = [];
        lm.push(`Pace: ${lp.pace ?? 'standard'} · Chunk size: ${lp.chunk_size ?? 'medium'} · Struggle tolerance: ${lp.struggle_tolerance ?? 'medium'} (with low tolerance, break problems into smaller steps and check in sooner).`);
        if (lp.scaffold) lm.push(`Scaffold: ${lp.scaffold === 'socratic_first' ? 'let them try to spot the pattern before you confirm it' : 'show one worked example before asking them to try'}.`);
        if (lp.lean) lm.push(`Thinking lean: ${lp.lean}${lp.lean === 'procedural' ? " — they reach answers fast, so make the 'why' explicit, not just the steps" : ''}.`);
        if (lp.metacognition === 'overconfident') lm.push(`Metacognition: overconfident — before you confirm an answer, ask for a confidence level and a one-line justification so they catch their own slips.`);
        else if (lp.metacognition === 'underconfident') lm.push(`Metacognition: underconfident — when their reasoning is sound, say so plainly and explain why it generalizes.`);
        if (typeof lp.ability === 'number') lm.push(`Suggested starting difficulty: ${lp.ability}/5 — calibrate up or down from there.`);
        contextualPrompt += `\n\n═══════════════════════════════════════\nLEARNER MODEL (how this person learns — adapt to it)\n═══════════════════════════════════════\n${lm.join('\n')}`;
      }
    }

    // Inject recent learning history for memory
    if (context?.recentHistory?.length) {
      contextualPrompt += `\n\n═══════════════════════════════════════\nRECENT LEARNING HISTORY (last ${context.recentHistory.length} interactions)\n═══════════════════════════════════════`;
      for (const h of context.recentHistory) {
        let entry = `\n- [${h.session_type}]`;
        if (h.topic) entry += ` Topic: ${h.topic}`;
        if (h.was_correct !== null) entry += ` | ${h.was_correct ? '✓ Correct' : '✗ Incorrect'}`;
        if (h.hint_level_used > 0) entry += ` | Hints used: ${h.hint_level_used}`;
        if (h.luna_summary) entry += ` | Note: ${h.luna_summary}`;
        contextualPrompt += entry;
      }
    }

    // Inject session context
    if (context) {
      // Same principle: skip zero / empty signals so we don't tell the model
      // "0% accuracy, 0 streak" on the very first turn.
      const sLines: string[] = [];
      if (context.courseId) sLines.push(`Course: ${context.courseId}`);
      if (context.lessonTitle) sLines.push(`Lesson: ${context.lessonTitle}`);
      if (context.currentQuestion) sLines.push(`Current Question: ${context.currentQuestion}`);
      if (context.difficulty) sLines.push(`Difficulty: ${context.difficulty}`);
      if (Array.isArray(context.weakAreas) && context.weakAreas.length) sLines.push(`Weak Areas: ${context.weakAreas.join(", ")}`);
      if (typeof context.streak === 'number' && context.streak > 0) sLines.push(`Current Streak: ${context.streak} correct in a row`);
      if (typeof context.incorrectCount === 'number' && context.incorrectCount > 0) sLines.push(`Total Incorrect This Session: ${context.incorrectCount}`);
      if (typeof context.consecutiveErrors === 'number' && context.consecutiveErrors > 0) sLines.push(`Consecutive Errors (current): ${context.consecutiveErrors}`);
      if (typeof context.rapidGuessCount === 'number' && context.rapidGuessCount > 0) sLines.push(`Rapid Guesses (< 2s): ${context.rapidGuessCount}`);
      if (typeof context.avgResponseTime === 'number' && context.avgResponseTime > 0) sLines.push(`Avg Response Time: ${context.avgResponseTime}s`);
      if (typeof context.hintLevel === 'number' && context.hintLevel > 0) {
        let line = `Hint Escalation Level: ${context.hintLevel}/3`;
        if (context.hintLevel === 1) line += ` - Name the specific step they're stuck on and point at the first move.`;
        else if (context.hintLevel >= 2) line += ` - They've asked repeatedly. Give maximum scaffolding (next single sub-step, or a parallel worked example) but DO NOT state the final answer to their problem.`;
        sLines.push(line);
      }
      // Only show session accuracy once we have enough samples for it to mean anything.
      const totalSession = (context.streak ?? 0) + (context.incorrectCount ?? 0);
      if (typeof context.accuracy === 'number' && totalSession >= 3) sLines.push(`Session Accuracy: ${context.accuracy}%`);
      if (typeof context.sessionMinutes === 'number' && context.sessionMinutes >= 2) sLines.push(`Session Duration: ${context.sessionMinutes} minutes`);
      if (sLines.length) {
        contextualPrompt += `\n\n═══════════════════════════════════════\nCURRENT SESSION CONTEXT\n═══════════════════════════════════════\n${sLines.join('\n')}`;
      }
    }

    // ── Retrieval grounding (RAG) ────────────────────────────────────────
    // Turn Luna from a pure parametric model into a grounded one: gather
    // authoritative SOURCE MATERIAL and instruct the model to answer FROM it.
    // Sources arrive two ways — (1) passed by the client as context.sources,
    // and (2) pulled from the DB for the active course. All retrieval is
    // best-effort: any failure just means no grounding, never a broken reply.
    const sources: { title?: string; content: string }[] = [];

    if (Array.isArray(context?.sources)) {
      for (const s of context.sources.slice(0, 12)) {
        if (s && typeof s.content === "string" && s.content.trim()) {
          sources.push({
            title: typeof s.title === "string" ? s.title.slice(0, 160) : undefined,
            content: s.content.slice(0, 2000),
          });
        }
      }
    }

    // DB retrieval: when courseId is a real course uuid, pull its lesson text
    // and quiz blocks straight from the course the learner is sitting in.
    const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
    if (sources.length === 0 && typeof context?.courseId === "string" && UUID_RE.test(context.courseId)) {
      try {
        const { data: mods } = await sb
          .from("course_modules")
          .select("id, title, position")
          .eq("course_id", context.courseId)
          .order("position")
          .limit(40);
        const modIds = (mods ?? []).map((m: any) => m.id);
        const modTitle: Record<string, string> = {};
        for (const m of mods ?? []) modTitle[m.id] = m.title;
        if (modIds.length) {
          const { data: blocks } = await sb
            .from("course_blocks")
            .select("module_id, type, data, position")
            .in("module_id", modIds)
            .order("position")
            .limit(120);
          for (const b of (blocks ?? []) as any[]) {
            const d = b.data ?? {};
            let text = "";
            if (b.type === "text" && typeof d.text === "string") {
              text = d.text;
            } else if (b.type === "quiz" && typeof d.question === "string") {
              text = d.question + (Array.isArray(d.options) ? `\nOptions: ${d.options.join("; ")}` : "");
            }
            text = text.trim();
            if (text) sources.push({ title: modTitle[b.module_id], content: text.slice(0, 1500) });
          }
        }
      } catch (e) {
        console.error("luna-chat RAG retrieval failed:", e);
      }
    }

    if (sources.length) {
      // Cap total grounding so we never blow past the context window.
      let budget = 7000;
      const chunks: string[] = [];
      for (const s of sources) {
        if (budget <= 0) break;
        const chunk = (s.title ? `## ${s.title}\n` : "") + s.content;
        const slice = chunk.slice(0, budget);
        chunks.push(slice);
        budget -= slice.length;
      }
      contextualPrompt += `\n\n═══════════════════════════════════════\nSOURCE MATERIAL (authoritative for this lesson)\n═══════════════════════════════════════\nAnswer the learner using the material below. If their question is not covered here, say so in one line before answering from general knowledge. Never contradict this material, and never invent detail beyond it.\n\n${chunks.join("\n\n---\n\n")}`;
    }

    const response = await fetch("https://ai.gateway.lovable.dev/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${LOVABLE_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "google/gemini-3-flash-preview",
        // Low temperature keeps a fast model factual and on task — high
        // temperature is a big driver of the wandering/hallucination here.
        // Reasoning requests manage their own sampling, so only set it when
        // reasoning is off (avoids gateways that reject temp on think models).
        ...(reasoning ? { reasoning } : { temperature: 0.4 }),
        messages: [
          { role: "system", content: contextualPrompt },
          ...messages.map((m: any) => {
            // Support multimodal: if imageDataUrl is attached, send as content array with image_url
            if (m.imageDataUrl && m.role === "user") {
              return {
                role: "user",
                content: [
                  { type: "text", text: m.content || "Here's what I'm looking at - can you help?" },
                  { type: "image_url", image_url: { url: m.imageDataUrl } },
                ],
              };
            }
            return { role: m.role, content: m.content };
          }),
        ],
        stream: true,
      }),
    });

    if (!response.ok) {
      if (response.status === 429) {
        return new Response(JSON.stringify({ error: "Rate limited - please try again in a moment." }), {
          status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      if (response.status === 402) {
        return new Response(JSON.stringify({ error: "AI credits exhausted. Add funds in Settings → Workspace → Usage." }), {
          status: 402, headers: { ...corsHeaders, "Content-Type": "application/json" },
        });
      }
      const t = await response.text();
      console.error("AI gateway error:", response.status, t);
      return new Response(JSON.stringify({ error: "AI gateway error" }), {
        status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    return new Response(response.body, {
      headers: { ...corsHeaders, "Content-Type": "text/event-stream" },
    });
  } catch (e) {
    console.error("luna-chat error:", e);
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : "Unknown error" }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
