// generate-song — Supabase Edge Function (Deno).
//
// The app never talks to the AI music vendor directly: the vendor key is a
// Supabase secret (same proxy pattern as tio-help's `geocode`).
//
// Flow:
//   1. Verify the caller is in band_members.
//   2. Insert a `songs` row (status 'generating') and return it at once.
//   3. In the background (EdgeRuntime.waitUntil) call the provider, upload
//      the audio to the private `songs` bucket and mark the row done/failed.
//      The app sees the change over Realtime — generation takes 1–3 min,
//      longer than we want an HTTP request held open.
//
// Request:  POST { title, style?, lyrics?, instrumental?, length_ms? }
// Response: 202 { song: <row> } · 400 bad input · 403 not a band member
//
// Secrets (supabase secrets set ...):
//   ELEVENLABS_API_KEY   required while MUSIC_PROVIDER=elevenlabs
//   MUSIC_PROVIDER       optional, default "elevenlabs"
//   MUSIC_MODEL          optional, default "music_v1"
// SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are injected
// by the platform.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { elevenLabsProvider } from "./providers/elevenlabs.ts";
import type { MusicProvider, SongRequest } from "./providers/types.ts";

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

function pickProvider(): MusicProvider {
  const name = Deno.env.get("MUSIC_PROVIDER") ?? "elevenlabs";
  const model = Deno.env.get("MUSIC_MODEL") ?? "music_v1";
  switch (name) {
    case "elevenlabs": {
      const key = Deno.env.get("ELEVENLABS_API_KEY");
      if (!key) throw new Error("ELEVENLABS_API_KEY is not set");
      return elevenLabsProvider(key, model);
    }
    default:
      throw new Error(`Unknown MUSIC_PROVIDER: ${name}`);
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
  if (!title || title.length > 120) return "title is required (1–120 chars)";
  if (style.length > 1000) return "style is too long (max 1000 chars)";
  if (lyrics.length > 6000) return "lyrics are too long (max 6000 chars)";
  if (!style.trim() && !lyrics.trim()) return "give a style or some lyrics";
  if (lengthMs !== null && (lengthMs < 10000 || lengthMs > 300000)) {
    return "length_ms must be between 10000 and 300000";
  }
  return { title, style, lyrics, instrumental, lengthMs };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  const url = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const { data: userData } = await userClient.auth.getUser();
  const user = userData?.user;
  if (!user) return json(401, { error: "not signed in" });

  const { data: isMember, error: memberErr } = await userClient.rpc("is_band_member");
  if (memberErr) return json(500, { error: memberErr.message });
  if (!isMember) return json(403, { error: "not a band member" });

  let parsed: SongRequest | string;
  try {
    parsed = parseRequest(await req.json());
  } catch {
    parsed = "body must be JSON";
  }
  if (typeof parsed === "string") return json(400, { error: parsed });
  const songReq = parsed;

  let provider: MusicProvider;
  try {
    provider = pickProvider();
  } catch (e) {
    return json(500, { error: (e as Error).message });
  }

  const { data: song, error: insertErr } = await admin
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
        .from("songs")
        .upload(path, out.audio, { contentType: out.contentType, upsert: true });
      if (upErr) throw upErr;
      await admin.from("songs").update({
        status: "done",
        audio_path: path,
        provider_song_id: out.providerSongId,
      }).eq("id", song.id);
    } catch (e) {
      await admin.from("songs").update({
        status: "failed",
        error: String((e as Error)?.message ?? e).slice(0, 1000),
      }).eq("id", song.id);
    }
  })());

  return json(202, { song });
});
