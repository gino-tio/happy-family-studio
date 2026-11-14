// studio-song-cover — draws a song's cover (Gino, 2026-11-14). Claude draws it as SVG through the
// TIO AI Hub (_shared/cover.ts); the picture lands in the private studio-covers bucket and
// songs.cover_path points at it. The app sees the change over Realtime.
//
// Two callers:
//   - A member taps 換封面: POST { song_id } with their own token. Member check, the song must be
//     readable through RLS, quota STUDIO_COVERS_PER_DAY (default 10 per member per HK day) in
//     app_studio.ai_usage (kind 'cover'). Always draws a new picture.
//   - studio-generate-song (and backfills) with the service role key: POST { song_id, auto: true }.
//     For a MusicGPT song it first tries MusicGPT's own cover; then Claude draws one only if the
//     song still has no cover.
// Response: 202 { ok: true } (the drawing finishes in the background) · 400 · 401 · 403 · 404 · 429

import { createClient } from "jsr:@supabase/supabase-js@2";
import { drawAndStoreCover } from "../_shared/cover.ts";
import { enrichMusicGpt } from "../studio-generate-song/providers/musicgpt.ts";

const SCHEMA = "app_studio";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

const cors: HeadersInit = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

function hkDayStart(now = new Date()): string {
  const hk = new Date(now.getTime() + 8 * 3600_000);
  hk.setUTCHours(0, 0, 0, 0);
  return new Date(hk.getTime() - 8 * 3600_000).toISOString();
}

/**
 * The service role key, or a service_role JWT (the gateway has already checked its signature,
 * since verify_jwt is on for this function).
 */
function isServiceRole(token: string, serviceKey: string): boolean {
  if (token === serviceKey) return true;
  const part = token.split(".")[1];
  if (!part) return false;
  try {
    const payload = JSON.parse(atob(part.replace(/-/g, "+").replace(/_/g, "/")));
    return payload?.role === "service_role";
  } catch {
    return false;
  }
}

const VARIANTS = [
  "a different main motif and a different colour palette",
  "a night-time scene with glowing colours",
  "a bright daytime palette with warm colours",
  "a more abstract, geometric composition",
  "a close-up of one symbolic object from the lyrics",
  "a wide landscape with layered depth",
];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "POST only" });
  const url = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json(401, { error: "not signed in" });
  const admin = createClient(url, serviceKey, { auth: { persistSession: false } });
  const db = admin.schema(SCHEMA);

  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "body must be JSON" });
  }
  const songId = typeof body.song_id === "string" ? body.song_id : "";
  if (!/^[0-9a-f-]{36}$/i.test(songId)) return json(400, { error: "song_id is required" });

  const internal = isServiceRole(authHeader.slice(7), serviceKey);
  if (internal) {
    const { data: song } = await db.from("songs")
      .select("id, title, style, lyrics, instrumental, provider, provider_song_id, cover_path")
      .eq("id", songId).maybeSingle();
    if (!song) return json(404, { error: "no such song" });
    EdgeRuntime.waitUntil((async () => {
      const key = Deno.env.get("STUDIO_MUSICGPT_KEY");
      if (song.provider === "musicgpt" && song.provider_song_id && key) {
        await enrichMusicGpt(admin, SCHEMA, key, song.provider_song_id)
          .catch((e) => console.error("musicgpt enrich failed", (e as Error).message));
      }
      await drawAndStoreCover(admin, song.id, song, { onlyIfEmpty: true })
        .catch((e) => console.error("cover failed", (e as Error).message));
    })());
    return json(202, { ok: true });
  }

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

  // Read through the caller's RLS: a member sees every band song.
  const { data: song } = await userClient.schema(SCHEMA).from("songs")
    .select("id, title, style, lyrics, instrumental, status").eq("id", songId).maybeSingle();
  if (!song) return json(404, { error: "no such song" });

  const perDay = Number(Deno.env.get("STUDIO_COVERS_PER_DAY") ?? "10");
  const { count, error: countErr } = await db.from("ai_usage")
    .select("id", { count: "exact", head: true })
    .eq("user_id", user.id).eq("kind", "cover").gte("created_at", hkDayStart());
  if (countErr) return json(500, { error: "quota check failed" });
  if ((count ?? 0) >= perDay) return json(429, { error: `今日已經換咗 ${perDay} 次封面，聽日再試` });
  await db.from("ai_usage").insert({ user_id: user.id, kind: "cover" });

  const variant = VARIANTS[Math.floor(Math.random() * VARIANTS.length)];
  EdgeRuntime.waitUntil(
    drawAndStoreCover(admin, song.id, song, { variant })
      .catch((e) => console.error("cover failed", (e as Error).message)),
  );
  return json(202, { ok: true });
});
