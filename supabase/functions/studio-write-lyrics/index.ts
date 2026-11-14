// studio-write-lyrics — Supabase Edge Function (Deno) on the shared Tio Hub project.
// Writes Cantonese lyrics for the compose screen with Claude, through the TIO AI Hub's
// chat route (tio-ai-hub docs/SHARED_DB.md section 4). The Hub key is a Supabase secret.
//
// Flow: member check (app_studio.me()) → daily quota (app_studio.ai_usage) → Hub chat → JSON.
// The request text and the lyrics are never logged.
//
// Request:  POST { topic, style?, title?, seconds? }
// Response: 200 { title, lyrics } · 400 bad input · 401 not signed in · 403 not a band member
//           · 429 daily limit · 502 the AI failed
//
// Secrets:
//   STUDIO_HUB_API_KEY   portal key of kind "app" for Hub app "studio" (chat only)
//   STUDIO_HUB_URL       optional, default https://tio-ai-hub.fly.dev
//   STUDIO_LYRICS_PER_DAY optional, default 30 per member per Hong Kong day

import { createClient } from "jsr:@supabase/supabase-js@2";
import { parseLyricsReply, parseLyricsRequest, SYSTEM_PROMPT, userPrompt } from "./lyrics.ts";

const SCHEMA = "app_studio";

const cors: HeadersInit = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

/** Start of today in Hong Kong (UTC+8, no DST), as an ISO time. */
function hkDayStart(now = new Date()): string {
  const hk = new Date(now.getTime() + 8 * 3600_000);
  hk.setUTCHours(0, 0, 0, 0);
  return new Date(hk.getTime() - 8 * 3600_000).toISOString();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json(401, { error: "not signed in" });
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData } = await userClient.auth.getUser();
  const user = userData?.user;
  if (!user) return json(401, { error: "not signed in" });
  const { data: role, error: memberErr } = await userClient.schema(SCHEMA).rpc("me");
  if (memberErr) return json(500, { error: "membership check failed" });
  if (!role) return json(403, { error: "not a band member" });

  let parsed;
  try {
    parsed = parseLyricsRequest(await req.json());
  } catch {
    parsed = "body must be JSON";
  }
  if (typeof parsed === "string") return json(400, { error: parsed });

  const hubKey = Deno.env.get("STUDIO_HUB_API_KEY");
  if (!hubKey) return json(500, { error: "STUDIO_HUB_API_KEY is not set" });

  // Quota: server-only table, service role pinned to this app's schema.
  const db = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  }).schema(SCHEMA);
  const perDay = Number(Deno.env.get("STUDIO_LYRICS_PER_DAY") ?? "30");
  const { count, error: countErr } = await db.from("ai_usage")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id).eq("kind", "lyrics").gte("created_at", hkDayStart());
  if (countErr) {
    console.error("studio-write-lyrics quota read failed", countErr.code);
    return json(500, { error: "quota check failed" });
  }
  if ((count ?? 0) >= perDay) return json(429, { error: `今日已經寫咗 ${perDay} 次，聽日再試` });
  await db.from("ai_usage").insert({ user_id: user.id, kind: "lyrics" });

  const hub = Deno.env.get("STUDIO_HUB_URL") ?? "https://tio-ai-hub.fly.dev";
  let content = "";
  try {
    const res = await fetch(`${hub}/api/v1/llm/studio/chat`, {
      method: "POST",
      headers: { Authorization: `Bearer ${hubKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: "smart",
        max_tokens: 3000,
        timeoutMs: 110_000,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: userPrompt(parsed) },
        ],
      }),
      signal: AbortSignal.timeout(120_000),
    });
    if (!res.ok) {
      console.error("studio-write-lyrics hub status", res.status);
      return json(502, { error: "AI 寫唔到，遲啲再試" });
    }
    const body = await res.json();
    content = String(body?.choices?.[0]?.message?.content ?? "");
  } catch (e) {
    console.error("studio-write-lyrics hub call failed", (e as Error).name);
    return json(502, { error: "AI 寫唔到，遲啲再試" });
  }
  const result = parseLyricsReply(content, parsed.title);
  if (!result) {
    console.error("studio-write-lyrics reply not usable", content.length);
    return json(502, { error: "AI 寫唔到，遲啲再試" });
  }
  return json(200, result);
});
