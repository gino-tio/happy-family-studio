// studio-song-tools — MusicGPT tools on finished songs (Gino, 2026-11-18, all recommended answers).
// Shared-DB rules as in studio-generate-song: the caller must be a band member (app_studio.me()),
// tables are written with the service role, the MusicGPT key never leaves the server.
//
// POST { action: "stems", song_id }
//   拆樂器: six tracks (vocals, instrumental, piano, bass, drums, guitar) into song_stems.
//   202 { stems: <row> }; an existing live split is returned as is (200), no quota used.
// POST { action: "swap", song_id, lyrics, title?, style? }
//   換歌詞: new lyrics sung over the song's instrumental track (needs a finished split).
//   202 { song: <row> } — a new song "<title>（新詞）", two versions like MusicGPT songs.
// POST { action: "remix", upload_path, title, style?, lyrics?, instrumental? }
//   由一首歌開始: a new song in the style of an uploaded one (studio-uploads/<caller>/...).
//   202 { song: <row> }
// Errors: 400 bad input · 401 not signed in · 403 not a band member · 404 no such song ·
//         409 split not ready · 429 daily quota · 502 MusicGPT refused.
//
// Quotas per member per Hong Kong day (app_studio.ai_usage): STUDIO_STEMS_PER_DAY (10),
// STUDIO_SWAPS_PER_DAY (10), STUDIO_REMIXES_PER_DAY (10).
// Finishing: this worker polls ~130 s; studio-musicgpt-hook finishes anything slower.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { requestCover } from "../_shared/cover.ts";
import {
  enrichMusicGpt,
  finishMusicGpt,
  REMIX_MODEL,
  SING_OVER_MODEL,
} from "../studio-generate-song/providers/musicgpt.ts";
import {
  addSongFields,
  audioForm,
  audioTypeFor,
  finishStems,
  genderFrom,
  hkDayStart,
  parseToolRequest,
  submitForm,
  type ToolRequest,
  vocalPrompt,
} from "./tools.ts";

const SCHEMA = "app_studio";
const BUCKET = "studio-songs";
const UPLOADS = "studio-uploads";

declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void };

const cors: HeadersInit = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

const QUOTA = {
  stems: ["STUDIO_STEMS_PER_DAY", "拆樂器"],
  swap: ["STUDIO_SWAPS_PER_DAY", "換歌詞"],
  remix: ["STUDIO_REMIXES_PER_DAY", "上載作歌"],
} as const;

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
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const db = admin.schema(SCHEMA);

  const { data: userData } = await userClient.auth.getUser();
  const user = userData?.user;
  if (!user) return json(401, { error: "not signed in" });
  const { data: role, error: memberErr } = await userClient.schema(SCHEMA).rpc("me");
  if (memberErr) return json(500, { error: "membership check failed" });
  if (!role) return json(403, { error: "not a band member" });

  const key = Deno.env.get("STUDIO_MUSICGPT_KEY");
  if (!key) return json(500, { error: "MusicGPT 未設定（缺 STUDIO_MUSICGPT_KEY）" });

  let parsed: ToolRequest | string;
  try {
    parsed = parseToolRequest(await req.json(), user.id);
  } catch {
    parsed = "body must be JSON";
  }
  if (typeof parsed === "string") return json(400, { error: parsed });
  const tr = parsed;
  const hook = `${url}/functions/v1/studio-musicgpt-hook`;

  // A finished song the caller can use (every member may use every song).
  async function loadSong(id: string) {
    const { data } = await db.from("songs").select("*").eq("id", id).maybeSingle();
    return data;
  }

  // Counts today's uses; inserts the row before calling MusicGPT, like the other quotas.
  async function takeQuota(kind: "stems" | "swap" | "remix"): Promise<Response | null> {
    const [env, label] = QUOTA[kind];
    const perDay = Number(Deno.env.get(env) ?? "10") || 10;
    const { count, error } = await db.from("ai_usage").select("id", { count: "exact", head: true })
      .eq("user_id", user!.id).eq("kind", kind).gte("created_at", hkDayStart());
    if (error) return json(500, { error: "quota check failed" });
    if ((count ?? 0) >= perDay) return json(429, { error: `今日已經${label} ${perDay} 次，聽日再試` });
    await db.from("ai_usage").insert({ user_id: user!.id, kind });
    return null;
  }

  async function download(bucket: string, path: string): Promise<Uint8Array<ArrayBuffer>> {
    const { data, error } = await admin.storage.from(bucket).download(path);
    if (error || !data) throw new Error("讀唔到個音檔");
    return new Uint8Array(await data.arrayBuffer());
  }

  /** Polls a new MusicGPT song while this worker lives, then draws covers it still lacks. */
  function finishSongLater(taskId: string) {
    EdgeRuntime.waitUntil((async () => {
      const started = Date.now();
      let done = false;
      while (Date.now() - started < 120_000) {
        await new Promise((r) => setTimeout(r, 8_000));
        try {
          if (!done) {
            const r = await finishMusicGpt(admin, SCHEMA, BUCKET, key!, taskId);
            if (r === "failed") return;
            if (r === "pending") continue;
            done = true;
          }
          if (await enrichMusicGpt(admin, SCHEMA, key!, taskId)) return;
        } catch (e) {
          console.error("tools: song finish failed", (e as Error).message);
        }
      }
      if (!done) return;
      const { data: rows } = await db.from("songs").select("id")
        .eq("provider_song_id", taskId).eq("status", "done").is("cover_path", null);
      for (const row of rows ?? []) await requestCover(row.id);
    })());
  }

  if (tr.action === "stems") {
    const song = await loadSong(tr.songId);
    if (!song) return json(404, { error: "冇呢首歌" });
    if (song.status !== "done" || !song.audio_path) return json(409, { error: "首歌未整好" });
    const { data: live } = await db.from("song_stems").select("*").eq("song_id", song.id)
      .neq("status", "failed").maybeSingle();
    if (live) return json(200, { stems: live });
    const over = await takeQuota("stems");
    if (over) return over;
    let taskId: string;
    try {
      const bytes = await download(BUCKET, song.audio_path);
      const ext = song.audio_path.split(".").pop() ?? "mp3";
      const form = audioForm(bytes, `song.${ext}`, audioTypeFor(song.audio_path) ?? "audio/mpeg");
      form.append("stem_preset", "6_stems");
      form.append("webhook_url", hook);
      taskId = await submitForm(key, "/v2/Extraction", form);
    } catch (e) {
      return json(502, { error: (e as Error).message });
    }
    const { data: row, error } = await db.from("song_stems").insert({
      song_id: song.id,
      created_by: user.id,
      status: "generating",
      provider_task_id: taskId,
    }).select().single();
    if (error) return json(500, { error: error.message });
    EdgeRuntime.waitUntil((async () => {
      const started = Date.now();
      while (Date.now() - started < 130_000) {
        await new Promise((r) => setTimeout(r, 8_000));
        try {
          if (await finishStems(admin, SCHEMA, BUCKET, key, taskId) !== "pending") return;
        } catch (e) {
          console.error("tools: stems finish failed", (e as Error).message);
        }
      }
    })());
    return json(202, { stems: row });
  }

  if (tr.action === "swap") {
    const song = await loadSong(tr.songId);
    if (!song) return json(404, { error: "冇呢首歌" });
    const { data: split } = await db.from("song_stems").select("stems").eq("song_id", song.id)
      .eq("status", "done").maybeSingle();
    const inst = (split?.stems as { kind: string; path: string }[] | undefined)
      ?.find((s) => s.kind === "instrumental");
    if (!inst) return json(409, { error: "要先拆樂器，先有伴奏可以換歌詞" });
    const over = await takeQuota("swap");
    if (over) return over;
    const style = tr.style ?? song.style ?? "";
    const title = (tr.title || `${song.title}（新詞）`).slice(0, 120);
    let taskId: string;
    try {
      const bytes = await download(BUCKET, inst.path);
      const form = audioForm(bytes, inst.path.split("/").pop()!, audioTypeFor(inst.path) ?? "audio/mpeg");
      addSongFields(form, { prompt: vocalPrompt(style), lyrics: tr.lyrics, title, gender: genderFrom(style), webhookUrl: hook });
      taskId = await submitForm(key, "/v1/sing_over_instrumental", form);
    } catch (e) {
      return json(502, { error: (e as Error).message });
    }
    const { data: row, error } = await db.from("songs").insert({
      created_by: user.id,
      title,
      style: style.slice(0, 1000),
      lyrics: tr.lyrics,
      instrumental: false,
      length_ms: song.length_ms,
      provider: "musicgpt",
      model: SING_OVER_MODEL,
      status: "generating",
      provider_song_id: taskId,
      parent_song_id: song.id,
      source: "swap",
    }).select().single();
    if (error) return json(500, { error: error.message });
    finishSongLater(taskId);
    return json(202, { song: row });
  }

  // remix
  const over = await takeQuota("remix");
  if (over) return over;
  let taskId: string;
  try {
    const bytes = await download(UPLOADS, tr.uploadPath);
    const name = tr.uploadPath.split("/").pop()!;
    const form = audioForm(bytes, name, audioTypeFor(tr.uploadPath)!);
    addSongFields(form, {
      prompt: vocalPrompt(tr.style, tr.instrumental),
      lyrics: tr.instrumental ? "" : tr.lyrics,
      title: tr.title,
      gender: genderFrom(tr.style),
      webhookUrl: hook,
    });
    taskId = await submitForm(key, "/v1/Remix", form);
  } catch (e) {
    return json(502, { error: (e as Error).message });
  }
  const { data: row, error } = await db.from("songs").insert({
    created_by: user.id,
    title: tr.title,
    style: tr.style,
    lyrics: tr.instrumental ? "" : tr.lyrics,
    instrumental: tr.instrumental,
    provider: "musicgpt",
    model: REMIX_MODEL,
    status: "generating",
    provider_song_id: taskId,
    source: "remix",
  }).select().single();
  if (error) return json(500, { error: error.message });
  finishSongLater(taskId);
  return json(202, { song: row });
});
