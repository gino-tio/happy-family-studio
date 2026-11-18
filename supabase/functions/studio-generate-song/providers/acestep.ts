// ACE-Step 1.5 on our own Modal app (modal/acestep_app.py; Gino's pick 2026-11-18 after hearing
// it sing Cantonese). Async like MusicGPT: a submit returns a Modal job id, kept in
// songs.provider_song_id; the generate function polls while its worker lives and
// studio-acestep-hook finishes later ones. The hook body is only a nudge: the result is read
// back from Modal with our own token. Two versions per request; version 2 becomes "<title> (v2)".

// deno-lint-ignore-file no-explicit-any
import type { SongRequest } from "./types.ts";

export const ACESTEP_MODEL = "v15-xl-turbo";
export const JOB_ID = /^fc-[A-Za-z0-9]{8,70}$/;

export interface AceStepConfig {
  /** Base URL of the Modal web app, e.g. https://<workspace>--studio-acestep-api.modal.run */
  url: string;
  token: string;
}

export function aceStepConfig(): AceStepConfig | null {
  const url = (Deno.env.get("STUDIO_ACESTEP_URL") ?? "").replace(/\/+$/, "");
  const token = Deno.env.get("STUDIO_ACESTEP_TOKEN") ?? "";
  if (!url.startsWith("https://") || !token) return null;
  return { url, token };
}

export function aceStepBody(req: SongRequest, webhookUrl: string): Record<string, unknown> {
  const style = req.style.trim();
  const caption = req.instrumental ? style : `Cantopop, Hong Kong Cantonese vocals. ${style}`.trim();
  return {
    caption: caption.slice(0, 1000) || req.title,
    lyrics: req.instrumental ? "" : req.lyrics.trim(),
    instrumental: req.instrumental,
    vocal_language: "yue",
    duration: req.lengthMs ? Math.round(req.lengthMs / 1000) : null,
    webhook_url: webhookUrl,
  };
}

export async function submitAceStep(cfg: AceStepConfig, body: Record<string, unknown>): Promise<string> {
  const res = await fetch(`${cfg.url}/submit`, {
    method: "POST",
    headers: { Authorization: `Bearer ${cfg.token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const out = await res.json().catch(() => ({})) as any;
  const id = String(out.job_id ?? "");
  if (!res.ok || !JOB_ID.test(id)) {
    throw new Error(`ACE-Step ${res.status}: ${String(out.detail ?? "").slice(0, 300)}`);
  }
  return id;
}

export type AceStepState =
  | { state: "pending" }
  | { state: "failed"; error: string }
  | { state: "done"; count: number };

export function parseResultReply(out: any): AceStepState {
  const status = String(out?.status ?? "");
  if (status === "failed") return { state: "failed", error: String(out.error ?? "failed").slice(0, 300) };
  const count = Number(out?.count);
  if (status === "done" && Number.isInteger(count) && count > 0) return { state: "done", count: Math.min(count, 2) };
  return { state: "pending" };
}

export async function checkAceStep(cfg: AceStepConfig, jobId: string): Promise<AceStepState> {
  const res = await fetch(`${cfg.url}/result/${jobId}`, { headers: { Authorization: `Bearer ${cfg.token}` } });
  if (!res.ok) return { state: "pending" };
  return parseResultReply(await res.json().catch(() => ({})));
}

/**
 * Finishes an ACE-Step song once its job is done: version 1 fills the existing row, version 2
 * becomes a new row "<title> (v2)". Safe to call more than once (webhook and polling both do):
 * only the call that flips the row from 'generating' adds version 2. Returns the finished row ids.
 */
export async function finishAceStep(
  admin: any,
  schema: string,
  bucket: string,
  cfg: AceStepConfig,
  jobId: string,
): Promise<{ state: "pending" | "failed" | "unknown" } | { state: "done"; ids: string[] }> {
  const db = admin.schema(schema);
  const { data: song } = await db.from("songs").select("*")
    .eq("provider", "acestep").eq("provider_song_id", jobId).eq("status", "generating")
    .order("created_at", { ascending: true }).limit(1).maybeSingle();
  if (!song) return { state: "unknown" };
  const st = await checkAceStep(cfg, jobId);
  if (st.state === "pending") return { state: "pending" };
  if (st.state === "failed") {
    await db.from("songs").update({ status: "failed", error: `ACE-Step: ${st.error}` })
      .eq("id", song.id).eq("status", "generating");
    return { state: "failed" };
  }
  const ids = [song.id, crypto.randomUUID()];
  const paths: string[] = [];
  for (let i = 0; i < st.count; i++) {
    const audio = await fetch(`${cfg.url}/result/${jobId}/${i}`, { headers: { Authorization: `Bearer ${cfg.token}` } });
    if (!audio.ok) throw new Error(`ACE-Step download ${audio.status}`);
    const path = `${song.created_by}/${ids[i]}.mp3`;
    const { error } = await admin.storage.from(bucket)
      .upload(path, new Uint8Array(await audio.arrayBuffer()), { contentType: "audio/mpeg", upsert: true });
    if (error) throw error;
    paths.push(path);
  }
  const { data: flipped } = await db.from("songs")
    .update({ status: "done", audio_path: paths[0] })
    .eq("id", song.id).eq("status", "generating").select("id");
  if (!flipped?.length) return { state: "unknown" };
  if (paths[1]) {
    const { id: _id, created_at: _c, updated_at: _u, ...rest } = song;
    await db.from("songs").insert({
      ...rest,
      id: ids[1],
      title: `${song.title} (v2)`.slice(0, 120),
      status: "done",
      audio_path: paths[1],
      cover_path: null,
    });
  }
  return { state: "done", ids: ids.slice(0, paths.length) };
}
