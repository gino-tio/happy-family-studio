// MusicGPT — https://docs.musicgpt.com (Music AI v2). Async: a submit returns a task_id; the
// two finished versions arrive by webhook and can be read back with GET /v1/byId.
// Its docs show several payload shapes, so finishing reads byId (with our key) and accepts
// either `conversion_path_1/_2` or `audio_url`. The webhook is unsigned, so it is only a nudge:
// nothing in its body is trusted.

// deno-lint-ignore-file no-explicit-any
import type { SongRequest } from "./types.ts";
import { fetchCoverImage, storeCover } from "../../_shared/cover.ts";

const API = "https://api.musicgpt.com/api/public";

export function musicgptBody(req: SongRequest, model: string, webhookUrl: string): Record<string, unknown> {
  const vocal = req.instrumental ? "Instrumental." : "Cantonese (Hong Kong Cantopop) vocals, not Mandarin.";
  const style = req.style.trim();
  const body: Record<string, unknown> = {
    prompt: (style ? `${vocal} ${style}` : vocal).slice(0, 1000),
    title: req.title.slice(0, 120),
    make_instrumental: req.instrumental,
    model,
    webhook_url: webhookUrl,
    // Cover picture and per-line timings for the song screen (Gino, 2026-11-14).
    generate_album_cover: true,
    lyrics_timestamps: !req.instrumental,
  };
  if (!req.instrumental && req.lyrics.trim()) body.lyrics = req.lyrics.trim();
  if (/\bfemale\b|女聲/i.test(style)) body.gender = "female";
  else if (/\bmale\b|男聲/i.test(style)) body.gender = "male";
  return body;
}

export async function submitMusicGpt(key: string, body: Record<string, unknown>): Promise<string> {
  const res = await fetch(`${API}/v2/MusicAI`, {
    method: "POST",
    headers: { Authorization: key, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const out = await res.json().catch(() => ({})) as any;
  if (!res.ok || !out.success || !out.task_id) {
    throw new Error(`MusicGPT ${res.status}: ${String(out.message ?? out.reason ?? "").slice(0, 300)}`);
  }
  return String(out.task_id);
}

export interface TimedLine {
  start: number;
  end: number;
  text: string;
}

export type MusicGptState =
  | { state: "pending" }
  | { state: "failed"; error: string }
  | {
    state: "done";
    urls: string[];
    /** MusicGPT's album cover, when it has drawn one yet. */
    cover?: string;
    /** Timed lyrics per version (index 0 = version 1), null where not ready. */
    timed?: (TimedLine[] | null)[];
  };

/**
 * MusicGPT's lyrics_timestamped (a JSON string or array of {start, end, text} in ms) as sung lines.
 * Section labels like "[Chorus]" and empty lines are dropped. Null when there is nothing usable.
 */
export function parseTimedLyrics(raw: unknown): TimedLine[] | null {
  let arr: unknown = raw;
  if (typeof raw === "string") {
    try {
      arr = JSON.parse(raw);
    } catch {
      return null;
    }
  }
  if (!Array.isArray(arr)) return null;
  const lines: TimedLine[] = [];
  for (const x of arr) {
    if (typeof x !== "object" || x === null) continue;
    const r = x as Record<string, unknown>;
    const text = typeof r.text === "string" ? r.text.trim().slice(0, 300) : "";
    const start = Number(r.start);
    const end = Number(r.end);
    if (!text || /^\[[^\]]*\]$/.test(text) || !Number.isFinite(start) || !Number.isFinite(end)) continue;
    lines.push({ start: Math.max(0, Math.round(start)), end: Math.max(0, Math.round(end)), text });
    if (lines.length >= 400) break;
  }
  lines.sort((a, b) => a.start - b.start);
  return lines.length ? lines : null;
}

/** Reads one task back. `urls` holds the finished MP3s, version 1 first. */
export function parseByIdReply(out: any): MusicGptState {
  const c = out?.conversion ?? {};
  const status = String(c.status ?? "").toUpperCase();
  if (status === "FAILED" || status === "ERROR") {
    return { state: "failed", error: String(c.status_msg ?? c.message ?? status).slice(0, 300) };
  }
  const urls = [c.conversion_path_1, c.conversion_path_2, c.audio_url, c.conversion_path]
    .filter((u): u is string => typeof u === "string" && u.startsWith("https://"));
  const unique = [...new Set(urls)];
  if (status === "COMPLETED" && unique.length) {
    const cover = [c.album_cover_path, c.album_cover_thumbnail]
      .find((u): u is string => typeof u === "string" && u.startsWith("https://"));
    const timed = [parseTimedLyrics(c.lyrics_timestamped_1 ?? c.lyrics_timestamped), parseTimedLyrics(c.lyrics_timestamped_2)];
    return { state: "done", urls: unique.slice(0, 2), ...(cover ? { cover } : {}), timed };
  }
  return { state: "pending" };
}

export async function checkMusicGpt(key: string, taskId: string): Promise<MusicGptState> {
  const u = `${API}/v1/byId?conversionType=MUSIC_AI&task_id=${encodeURIComponent(taskId)}`;
  const res = await fetch(u, { headers: { Authorization: key } });
  if (!res.ok) return { state: "pending" };
  return parseByIdReply(await res.json().catch(() => ({})));
}

/**
 * Finishes a MusicGPT song once its task is done: version 1 fills the existing row, version 2
 * becomes a new row "<title> (v2)". Safe to call more than once (webhook and polling both do):
 * only the call that flips the row from 'generating' adds version 2.
 */
export async function finishMusicGpt(
  admin: any,
  schema: string,
  bucket: string,
  key: string,
  taskId: string,
): Promise<"pending" | "done" | "failed" | "unknown"> {
  const db = admin.schema(schema);
  const { data: song } = await db.from("songs").select("*")
    .eq("provider", "musicgpt").eq("provider_song_id", taskId).eq("status", "generating")
    .order("created_at", { ascending: true }).limit(1).maybeSingle();
  if (!song) return "unknown";
  const st = await checkMusicGpt(key, taskId);
  if (st.state === "pending") return "pending";
  if (st.state === "failed") {
    await db.from("songs").update({ status: "failed", error: `MusicGPT: ${st.error}` })
      .eq("id", song.id).eq("status", "generating");
    return "failed";
  }
  const v2Id = crypto.randomUUID();
  const ids = [song.id, v2Id];
  const paths: string[] = [];
  for (let i = 0; i < st.urls.length; i++) {
    const audio = await fetch(st.urls[i]);
    if (!audio.ok) throw new Error(`MusicGPT download ${audio.status}`);
    const path = `${song.created_by}/${ids[i]}.mp3`;
    const { error } = await admin.storage.from(bucket)
      .upload(path, new Uint8Array(await audio.arrayBuffer()), { contentType: "audio/mpeg", upsert: true });
    if (error) throw error;
    paths.push(path);
  }
  const { data: flipped } = await db.from("songs")
    .update({ status: "done", audio_path: paths[0], lyrics_timed: st.timed?.[0] ?? null })
    .eq("id", song.id).eq("status", "generating").select("id");
  if (flipped?.length && paths[1]) {
    const { id: _id, created_at: _c, updated_at: _u, ...rest } = song;
    await db.from("songs").insert({
      ...rest,
      id: v2Id,
      title: `${song.title} (v2)`.slice(0, 120),
      status: "done",
      audio_path: paths[1],
      lyrics_timed: st.timed?.[1] ?? null,
      cover_path: null,
    });
  }
  if (flipped?.length && st.cover) await saveVendorCover(admin, st.cover, ids.slice(0, paths.length));
  return "done";
}

/** Copies MusicGPT's cover onto every given song that has none yet. */
async function saveVendorCover(admin: any, url: string, songIds: string[]): Promise<boolean> {
  const img = await fetchCoverImage(url).catch(() => null);
  if (!img) return false;
  for (const id of songIds) await storeCover(admin, id, img.bytes, img.ext, true);
  return true;
}

/**
 * Fills in what MusicGPT sends after the audio (cover, timed lyrics) on the finished rows of one
 * task. Returns true when nothing is missing any more (or there is nothing to fill).
 */
export async function enrichMusicGpt(admin: any, schema: string, key: string, taskId: string): Promise<boolean> {
  const db = admin.schema(schema);
  const { data: rows } = await db.from("songs").select("id, title, instrumental, cover_path, lyrics_timed")
    .eq("provider", "musicgpt").eq("provider_song_id", taskId).eq("status", "done")
    .order("created_at", { ascending: true });
  if (!rows?.length) return true;
  const needCover = rows.filter((r: any) => !r.cover_path);
  const needLyrics = rows.filter((r: any) => !r.instrumental && !r.lyrics_timed);
  if (!needCover.length && !needLyrics.length) return true;
  const st = await checkMusicGpt(key, taskId);
  if (st.state !== "done") return false;
  let complete = true;
  if (needCover.length) {
    if (st.cover) await saveVendorCover(admin, st.cover, needCover.map((r: any) => r.id));
    else complete = false;
  }
  for (const r of needLyrics) {
    // The second version's row is the one whose title ends in "(v2)".
    const i = / \(v2\)$/.test(r.title) ? 1 : 0;
    const lines = st.timed?.[i] ?? null;
    if (lines) await db.from("songs").update({ lyrics_timed: lines }).eq("id", r.id).is("lyrics_timed", null);
    else complete = false;
  }
  return complete;
}
