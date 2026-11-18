// studio-generate-song — Supabase Edge Function (Deno) on the shared Tio Hub project.
// Shared-DB rules (tio-ai-hub docs/SHARED_DB.md): tables live in schema app_studio, the first
// check is app_studio.me() with the caller's own token, secrets start with STUDIO_.
//
// The app never talks to the AI music vendor directly: the vendor key is a
// Supabase secret (same proxy pattern as tio-help's `geocode`).
//
// Flow:
//   1. Verify the caller is a member of the studio app (app_studio.me()).
//   2. Insert a `songs` row (status 'generating') and return it at once.
//   3. In the background (EdgeRuntime.waitUntil) call the provider, upload
//      the audio to the private `studio-songs` bucket and mark the row done/failed.
//      The app sees the change over Realtime — generation takes 1–3 min,
//      longer than we want an HTTP request held open.
//
// Request:  POST { title, style?, lyrics?, instrumental?, length_ms? }
// Response: 202 { song: <row> } · 400 bad input · 401 not signed in · 403 not a band member
//
// Secrets (supabase secrets set ...):
//   STUDIO_ELEVENLABS_API_KEY   required while STUDIO_MUSIC_PROVIDER=elevenlabs
//   STUDIO_MUSIC_PROVIDER       optional, default "elevenlabs"
//   STUDIO_MUSIC_MODEL          optional, default "music_v1"
//   STUDIO_MUSICGPT_KEY         required for provider "musicgpt" (async: task + webhook
//                               studio-musicgpt-hook + polling here, two versions per song)
//   STUDIO_MUSICGPT_MODEL       optional, default "v6"
//   STUDIO_ACESTEP_URL          our Modal ACE-Step app (modal/acestep_app.py) for provider "acestep"
//   STUDIO_ACESTEP_TOKEN        its bearer token (Modal secret studio-acestep, ACESTEP_TOKEN)
//                               (async: Modal job + webhook studio-acestep-hook + polling here)
// The app may pick the provider per song (request field `provider`).
// Every function in the Hub project can read every secret, hence the STUDIO_ prefix.
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected
// by the platform.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { aceStepBody, aceStepConfig, ACESTEP_MODEL, finishAceStep, submitAceStep } from "./providers/acestep.ts";
import { elevenLabsProvider } from "./providers/elevenlabs.ts";
import { enrichMusicGpt, finishMusicGpt, musicgptBody, submitMusicGpt } from "./providers/musicgpt.ts";
import { requestCover } from "../_shared/cover.ts";
import type { MusicProvider, SongRequest } from "./providers/types.ts";

const SCHEMA = "app_studio";
const BUCKET = "studio-songs";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

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

export const PROVIDERS = ["elevenlabs", "musicgpt", "acestep"];

function pickProvider(requested: string): MusicProvider {
  const name = requested || (Deno.env.get("STUDIO_MUSIC_PROVIDER") ?? "elevenlabs");
  switch (name) {
    case "elevenlabs": {
      const key = Deno.env.get("STUDIO_ELEVENLABS_API_KEY");
      if (!key) throw new Error("STUDIO_ELEVENLABS_API_KEY is not set");
      return elevenLabsProvider(key, Deno.env.get("STUDIO_MUSIC_MODEL") ?? "music_v1");
    }
    default:
      throw new Error(`Unknown STUDIO_MUSIC_PROVIDER: ${name}`);
  }
}

export function parseRequest(raw: unknown): SongRequest | string {
  if (typeof raw !== "object" || raw === null) return "body must be a JSON object";
  const b = raw as Record<string, unknown>;
  const title = typeof b.title === "string" ? b.title.trim() : "";
  const style = typeof b.style === "string" ? b.style : "";
  const lyrics = typeof b.lyrics === "string" ? b.lyrics : "";
  const instrumental = b.instrumental === true;
  const lengthMs = typeof b.length_ms === "number" ? Math.round(b.length_ms) : null;
  const provider = typeof b.provider === "string" ? b.provider : "";
  if (provider && !PROVIDERS.includes(provider)) return "unknown provider";
  if (!title || title.length > 120) return "title is required (1–120 chars)";
  if (style.length > 1000) return "style is too long (max 1000 chars)";
  if (lyrics.length > 6000) return "lyrics are too long (max 6000 chars)";
  if (!style.trim() && !lyrics.trim()) return "give a style or some lyrics";
  if (lengthMs !== null && (lengthMs < 10000 || lengthMs > 300000)) {
    return "length_ms must be between 10000 and 300000";
  }
  return { title, style, lyrics, instrumental, lengthMs, provider };
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
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  // Table access is pinned to this app's schema only (service role bypasses RLS).
  const db = admin.schema(SCHEMA);

  const { data: userData } = await userClient.auth.getUser();
  const user = userData?.user;
  if (!user) return json(401, { error: "not signed in" });

  // First check of every shared-DB function: the caller's role in this app, or null.
  const { data: role, error: memberErr } = await userClient.schema(SCHEMA).rpc("me");
  if (memberErr) return json(500, { error: "membership check failed" });
  if (!role) return json(403, { error: "not a band member" });

  let parsed: SongRequest | string;
  try {
    parsed = parseRequest(await req.json());
  } catch {
    parsed = "body must be JSON";
  }
  if (typeof parsed === "string") return json(400, { error: parsed });
  const songReq = parsed;

  if (songReq.provider === "musicgpt") {
    const key = Deno.env.get("STUDIO_MUSICGPT_KEY");
    if (!key) return json(500, { error: "MusicGPT 未設定（缺 STUDIO_MUSICGPT_KEY）" });
    const model = Deno.env.get("STUDIO_MUSICGPT_MODEL") ?? "v6";
    let taskId: string;
    try {
      taskId = await submitMusicGpt(key, musicgptBody(songReq, model, `${url}/functions/v1/studio-musicgpt-hook`));
    } catch (e) {
      return json(502, { error: (e as Error).message });
    }
    const { data: song, error: insertErr } = await db.from("songs").insert({
      created_by: user.id,
      title: songReq.title,
      style: songReq.style,
      lyrics: songReq.lyrics,
      instrumental: songReq.instrumental,
      length_ms: songReq.lengthMs,
      provider: "musicgpt",
      model,
      status: "generating",
      provider_song_id: taskId,
    }).select().single();
    if (insertErr) return json(500, { error: insertErr.message });
    // Poll while this worker lives (150 s); the webhook finishes it if it takes longer. After the
    // audio, keep polling for MusicGPT's cover and timed lyrics; with no cover by the end, Claude
    // draws one in studio-song-cover (only if the row still has none, so a late MusicGPT cover
    // isn't overwritten; its own worker, since drawing takes up to two minutes).
    EdgeRuntime.waitUntil((async () => {
      const started = Date.now();
      let done = false;
      while (Date.now() - started < 120_000) {
        await new Promise((r) => setTimeout(r, 8_000));
        try {
          if (!done) {
            const r = await finishMusicGpt(admin, SCHEMA, BUCKET, key, taskId);
            if (r === "failed") return;
            if (r === "pending") continue;
            done = true;
          }
          if (await enrichMusicGpt(admin, SCHEMA, key, taskId)) return;
        } catch (e) {
          console.error("musicgpt finish failed", (e as Error).message);
        }
      }
      if (!done) return;
      const { data: rows } = await db.from("songs").select("id")
        .eq("provider_song_id", taskId).eq("status", "done").is("cover_path", null);
      for (const row of rows ?? []) await requestCover(row.id);
    })());
    return json(202, { song });
  }

  if (songReq.provider === "acestep") {
    const cfg = aceStepConfig();
    if (!cfg) return json(500, { error: "ACE-Step 未設定（缺 STUDIO_ACESTEP_URL / STUDIO_ACESTEP_TOKEN）" });
    let jobId: string;
    try {
      jobId = await submitAceStep(cfg, aceStepBody(songReq, `${url}/functions/v1/studio-acestep-hook`));
    } catch (e) {
      return json(502, { error: (e as Error).message });
    }
    const { data: song, error: insertErr } = await db.from("songs").insert({
      created_by: user.id,
      title: songReq.title,
      style: songReq.style,
      lyrics: songReq.lyrics,
      instrumental: songReq.instrumental,
      length_ms: songReq.lengthMs,
      provider: "acestep",
      model: ACESTEP_MODEL,
      status: "generating",
      provider_song_id: jobId,
    }).select().single();
    if (insertErr) return json(500, { error: insertErr.message });
    // Poll while this worker lives (150 s); a cold GPU start can take longer, and then the
    // webhook finishes it. Claude draws the covers once the audio is in.
    EdgeRuntime.waitUntil((async () => {
      const started = Date.now();
      while (Date.now() - started < 130_000) {
        await new Promise((r) => setTimeout(r, 6_000));
        try {
          const r = await finishAceStep(admin, SCHEMA, BUCKET, cfg, jobId);
          if (r.state === "pending") continue;
          if (r.state === "done") for (const id of r.ids) await requestCover(id);
          return;
        } catch (e) {
          console.error("acestep finish failed", (e as Error).message);
        }
      }
    })());
    return json(202, { song });
  }

  let provider: MusicProvider;
  try {
    provider = pickProvider(songReq.provider);
  } catch (e) {
    return json(500, { error: (e as Error).message });
  }

  const { data: song, error: insertErr } = await db
    .from("songs")
    .insert({
      created_by: user.id,
      title: songReq.title,
      style: songReq.style,
      lyrics: songReq.lyrics,
      instrumental: songReq.instrumental,
      length_ms: songReq.lengthMs,
      provider: provider.name,
      model: provider.model,
      status: "generating",
    })
    .select()
    .single();
  if (insertErr) return json(500, { error: insertErr.message });

  EdgeRuntime.waitUntil((async () => {
    try {
      const out = await provider.generate(songReq);
      const path = `${user.id}/${song.id}.${out.extension}`;
      const { error: upErr } = await admin.storage
        .from(BUCKET)
        .upload(path, out.audio, { contentType: out.contentType, upsert: true });
      if (upErr) throw upErr;
      await db.from("songs").update({
        status: "done",
        audio_path: path,
        provider_song_id: out.providerSongId,
      }).eq("id", song.id);
      await requestCover(song.id);
    } catch (e) {
      await db.from("songs").update({
        status: "failed",
        error: String((e as Error)?.message ?? e).slice(0, 1000),
      }).eq("id", song.id);
    }
  })());

  return json(202, { song });
});
