// Provider-agnostic AI gateway config for the Luna / moderation edge functions.
//
// These functions all speak the OpenAI-compatible REST shape
// (POST /chat/completions, /audio/speech, /audio/transcriptions), so they can
// point at any compatible provider: OpenRouter, OpenAI, Groq, Together, a
// self-hosted proxy, etc.
//
// To move off Lovable, set these in the Supabase project (Edge Function
// secrets):
//   AI_GATEWAY_URL       e.g. https://openrouter.ai/api/v1
//   AI_GATEWAY_API_KEY   your provider key
// and, for text-to-speech / speech-to-text (OpenRouter has no audio API, so
// point these at OpenAI directly):
//   AI_AUDIO_URL         e.g. https://api.openai.com/v1
//   AI_AUDIO_API_KEY     your OpenAI key
//
// Until AI_GATEWAY_* are set, these fall back to the legacy Lovable gateway so
// nothing breaks mid-migration. Model ids live in each function; some provider
// ids differ (e.g. OpenAI wants `gpt-4o-mini-tts`, not `openai/gpt-4o-mini-tts`),
// so adjust those per provider when you cut over.

const LEGACY_KEY = Deno.env.get("LOVABLE_API_KEY") ?? "";

export const AI_GATEWAY_URL =
  Deno.env.get("AI_GATEWAY_URL") ?? "https://ai.gateway.lovable.dev/v1";
export const AI_GATEWAY_API_KEY =
  Deno.env.get("AI_GATEWAY_API_KEY") ?? LEGACY_KEY;

// Audio (TTS/STT) can use a different provider than chat.
export const AI_AUDIO_URL = Deno.env.get("AI_AUDIO_URL") ?? AI_GATEWAY_URL;
export const AI_AUDIO_API_KEY =
  Deno.env.get("AI_AUDIO_API_KEY") ?? AI_GATEWAY_API_KEY;

export function assertAiConfigured() {
  if (!AI_GATEWAY_API_KEY) {
    throw new Error(
      "AI gateway is not configured. Set AI_GATEWAY_API_KEY (and AI_GATEWAY_URL) in the edge function secrets.",
    );
  }
}
