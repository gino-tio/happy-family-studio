// MusicGPT — https://docs.musicgpt.com (Music AI v2). Async: a submit returns a task_id; the
// two finished versions arrive by webhook and can be read back with GET /v1/byId.
// Its docs show several payload shapes, so finishing reads byId (with our key) and accepts
// either `conversion_path_1/_2` or `audio_url`. The webhook is unsigned, so it is only a nudge:
// nothing in its body is trusted.

// deno-lint-ignore-file no-explicit-any
import type { SongRequest } from "./types.ts";

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

export type MusicGptState =
  | { state: "pending" }
  | { state: "failed"; error: string }
  | { state: "done"; urls: string[] };

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
  if (status === "COMPLETED" && unique.length) return { state: "done", urls: unique.slice(0, 2) };
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
    .update({ status: "done", audio_path: paths[0] })
    .eq("id", song.id).eq("status", "generating").select("id");
  if (flipped?.length && paths[1]) {
    const { id: _id, created_at: _c, updated_at: _u, ...rest } = song;
    await db.from("songs").insert({
      ...rest,
      id: v2Id,
      title: `${song.title} (v2)`.slice(0, 120),
      status: "done",
      audio_path: paths[1],
    });
  }
  return "done";
}
