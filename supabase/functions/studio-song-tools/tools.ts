// MusicGPT tools for finished songs (Gino, 2026-11-18): split a song into six tracks (Extraction,
// stem_preset 6_stems, free on paid plans during November 2026), sing new lyrics over a song's
// instrumental track (Sing Over Instrumental), and make a new song from an uploaded one (Remix).
// Every call uploads the audio as a file (MusicGPT's audio_url only takes YouTube links).
// Results are read back with GET /v1/byId and our key; webhooks are only nudges.

// deno-lint-ignore-file no-explicit-any
const API = "https://api.musicgpt.com/api/public";

export const STEM_KINDS = ["vocals", "instrumental", "piano", "bass", "drums", "guitar"] as const;
export type StemKind = typeof STEM_KINDS[number];
export interface Stem {
  kind: StemKind;
  path: string;
}

/** POSTs a multipart form to MusicGPT and returns its task id. */
export async function submitForm(key: string, endpoint: string, form: FormData): Promise<string> {
  const res = await fetch(`${API}${endpoint}`, { method: "POST", headers: { Authorization: key }, body: form });
  const out = await res.json().catch(() => ({})) as any;
  if (!res.ok || out.success === false || !out.task_id) {
    const msg = String(out.message ?? out.detail ?? out.error_code ?? "").slice(0, 300);
    throw new Error(`MusicGPT ${res.status}${msg ? `: ${msg}` : ""}`);
  }
  return String(out.task_id);
}

export function audioForm(bytes: Uint8Array<ArrayBuffer>, fileName: string, contentType: string): FormData {
  const form = new FormData();
  form.append("audio_file", new Blob([bytes], { type: contentType }), fileName);
  return form;
}

/** Vocal prompt shared by 換歌詞 and remix: keep the vocals Cantonese, then the member's style. */
export function vocalPrompt(style: string, instrumental = false): string {
  const vocal = instrumental ? "Instrumental." : "Cantonese (Hong Kong Cantopop) vocals, not Mandarin.";
  const s = style.trim();
  return (s ? `${vocal} ${s}` : vocal).slice(0, 1000);
}

export function genderFrom(style: string): string | null {
  if (/\bfemale\b|女聲/i.test(style)) return "female";
  if (/\bmale\b|男聲/i.test(style)) return "male";
  return null;
}

/** Adds the fields Sing Over Instrumental and Remix share. */
export function addSongFields(
  form: FormData,
  f: { prompt: string; lyrics: string; title: string; gender: string | null; webhookUrl: string },
): FormData {
  form.append("prompt", f.prompt);
  if (f.lyrics.trim()) form.append("lyrics", f.lyrics.trim().slice(0, 5000));
  form.append("title", f.title.slice(0, 120));
  if (f.gender) form.append("gender", f.gender);
  form.append("generate_album_cover", "true");
  form.append("lyrics_timestamps", f.lyrics.trim() ? "true" : "false");
  form.append("webhook_url", f.webhookUrl);
  return form;
}

export type StemsState =
  | { state: "pending" }
  | { state: "failed"; error: string }
  | { state: "done"; urls: Partial<Record<StemKind, string>> };

const AUDIO_URL = /^https:\/\/[^\s"]+\.(mp3|wav|flac|m4a|ogg)(\?[^\s"]*)?$/i;

/** Which stem a key or URL names, by the stem's word in it ("instrumental" before the rest). */
function stemOf(text: string): StemKind | null {
  const t = text.toLowerCase();
  if (/instrument|accompan|no[_-]?vocal/.test(t)) return "instrumental";
  for (const k of ["vocals", "piano", "bass", "drums", "guitar"] as const) {
    if (t.includes(k.replace(/s$/, ""))) return k;
  }
  return null;
}

/**
 * Finds one URL per stem anywhere in a byId reply. MusicGPT's docs don't show the Extraction
 * shape, so this walks every field (and JSON strings inside them) and names a URL by its key or,
 * failing that, by its file name.
 */
export function findStemUrls(conversion: unknown): Partial<Record<StemKind, string>> {
  const found: Partial<Record<StemKind, string>> = {};
  const seen = new Set<unknown>();
  const walk = (v: unknown, key: string, depth: number) => {
    if (depth > 6 || v === null || v === undefined || seen.has(v)) return;
    if (typeof v === "string") {
      const s = v.trim();
      if (AUDIO_URL.test(s)) {
        const kind = stemOf(key) ?? stemOf(decodeURIComponent(s.split("?")[0].split("/").pop() ?? ""));
        if (kind && !found[kind]) found[kind] = s;
      } else if ((s.startsWith("{") || s.startsWith("[")) && s.length < 100_000) {
        try {
          walk(JSON.parse(s), key, depth + 1);
        } catch {
          // not JSON
        }
      }
      return;
    }
    if (typeof v !== "object") return;
    seen.add(v);
    if (Array.isArray(v)) {
      for (const x of v) {
        const name = typeof x === "object" && x !== null
          ? String((x as any).stem ?? (x as any).name ?? (x as any).type ?? key)
          : key;
        walk(x, name, depth + 1);
      }
      return;
    }
    // A field named after a stem wins; otherwise the stem named by the parent carries down.
    for (const [k, x] of Object.entries(v as Record<string, unknown>)) walk(x, stemOf(k) ? k : `${key}/${k}`, depth + 1);
  };
  walk(conversion, "", 0);
  return found;
}

export function parseStemsReply(out: any): StemsState {
  const c = out?.conversion ?? out ?? {};
  const status = String(c.status ?? "").toUpperCase();
  if (status === "FAILED" || status === "ERROR") {
    return { state: "failed", error: String(c.status_msg ?? c.message ?? status).slice(0, 300) };
  }
  if (status !== "COMPLETED") return { state: "pending" };
  const urls = findStemUrls(c);
  return Object.keys(urls).length ? { state: "done", urls } : { state: "pending" };
}

export async function checkStems(key: string, taskId: string): Promise<StemsState> {
  const u = `${API}/v1/byId?conversionType=EXTRACTION&task_id=${encodeURIComponent(taskId)}`;
  const res = await fetch(u, { headers: { Authorization: key } });
  if (!res.ok) return { state: "pending" };
  const out = await res.json().catch(() => ({})) as any;
  const st = parseStemsReply(out);
  if (st.state === "pending" && String(out?.conversion?.status ?? "").toUpperCase() === "COMPLETED") {
    // Completed but no stem URL recognised: log the field names (never values) to fix the parser.
    console.error("stems: completed without recognised urls; keys:", Object.keys(out.conversion ?? {}).join(","));
  }
  return st;
}

/**
 * Stores a finished split: downloads each track into the studio-songs bucket and marks the
 * song_stems row done. Safe to call more than once: only the call that flips the row wins.
 */
export async function finishStems(
  admin: any,
  schema: string,
  bucket: string,
  key: string,
  taskId: string,
): Promise<"pending" | "done" | "failed" | "unknown"> {
  const db = admin.schema(schema);
  const { data: row } = await db.from("song_stems").select("id, song_id, created_by")
    .eq("provider_task_id", taskId).eq("status", "generating").limit(1).maybeSingle();
  if (!row) return "unknown";
  const st = await checkStems(key, taskId);
  if (st.state === "pending") return "pending";
  if (st.state === "failed") {
    await db.from("song_stems").update({ status: "failed", error: `MusicGPT: ${st.error}` })
      .eq("id", row.id).eq("status", "generating");
    return "failed";
  }
  const stems: Stem[] = [];
  for (const kind of STEM_KINDS) {
    const url = st.urls[kind];
    if (!url) continue;
    const res = await fetch(url);
    if (!res.ok) throw new Error(`stem download ${res.status}`);
    const wav = /\.wav(\?|$)/i.test(url);
    const path = `${row.created_by}/stems/${row.song_id}/${kind}.${wav ? "wav" : "mp3"}`;
    const { error } = await admin.storage.from(bucket).upload(path, new Uint8Array(await res.arrayBuffer()), {
      contentType: wav ? "audio/wav" : "audio/mpeg",
      upsert: true,
    });
    if (error) throw error;
    stems.push({ kind, path });
  }
  await db.from("song_stems").update({ status: "done", stems }).eq("id", row.id).eq("status", "generating");
  return "done";
}

/** Track kinds that 出譜 turns into MIDI (drums are read from audio on the sheet page). */
export const MIDI_KINDS = ["vocals", "piano", "bass", "guitar"] as const;

const MIDI_URL = /^https:\/\/[^\s"]+\.midi?(\?[^\s"]*)?$/i;

/** The MIDI file URL anywhere in an Audio to MIDI byId reply. */
export function findMidiUrl(v: unknown, depth = 0): string | null {
  if (depth > 6 || v === null || v === undefined) return null;
  if (typeof v === "string") {
    const s = v.trim();
    if (MIDI_URL.test(s)) return s;
    if ((s.startsWith("{") || s.startsWith("[")) && s.length < 100_000) {
      try {
        return findMidiUrl(JSON.parse(s), depth + 1);
      } catch {
        return null;
      }
    }
    return null;
  }
  if (typeof v !== "object") return null;
  for (const x of Array.isArray(v) ? v : Object.values(v as Record<string, unknown>)) {
    const u = findMidiUrl(x, depth + 1);
    if (u) return u;
  }
  return null;
}

export type MidiState =
  | { state: "pending" }
  | { state: "failed"; error: string }
  | { state: "done"; url: string };

export function parseMidiReply(out: any): MidiState {
  const c = out?.conversion ?? out ?? {};
  const status = String(c.status ?? "").toUpperCase();
  if (status === "FAILED" || status === "ERROR") {
    return { state: "failed", error: String(c.status_msg ?? c.message ?? status).slice(0, 300) };
  }
  if (status !== "COMPLETED") return { state: "pending" };
  const url = findMidiUrl(c);
  return url ? { state: "done", url } : { state: "pending" };
}

/** Stores a finished MIDI and marks its stem_midis row done. Safe to call more than once. */
export async function finishMidi(
  admin: any,
  schema: string,
  bucket: string,
  key: string,
  taskId: string,
): Promise<"pending" | "done" | "failed" | "unknown"> {
  const db = admin.schema(schema);
  const { data: row } = await db.from("stem_midis").select("id, song_id, kind, created_by")
    .eq("provider_task_id", taskId).eq("status", "generating").limit(1).maybeSingle();
  if (!row) return "unknown";
  const res = await fetch(`${API}/v1/byId?conversionType=AUDIO_TO_MIDI&task_id=${encodeURIComponent(taskId)}`, {
    headers: { Authorization: key },
  });
  const out = res.ok ? await res.json().catch(() => ({})) : {};
  const st = parseMidiReply(out);
  if (st.state === "pending") {
    if (String((out as any)?.conversion?.status ?? "").toUpperCase() === "COMPLETED") {
      console.error("midi: completed without a .mid url; keys:", Object.keys((out as any).conversion ?? {}).join(","));
    }
    return "pending";
  }
  if (st.state === "failed") {
    await db.from("stem_midis").update({ status: "failed", error: `MusicGPT: ${st.error}` })
      .eq("id", row.id).eq("status", "generating");
    return "failed";
  }
  const file = await fetch(st.url);
  if (!file.ok) throw new Error(`midi download ${file.status}`);
  const path = `${row.created_by}/stems/${row.song_id}/${row.kind}.mid`;
  const { error } = await admin.storage.from(bucket).upload(path, new Uint8Array(await file.arrayBuffer()), {
    contentType: "audio/midi",
    upsert: true,
  });
  if (error) throw error;
  await db.from("stem_midis").update({ status: "done", midi_path: path }).eq("id", row.id).eq("status", "generating");
  return "done";
}

/** Start of today in Hong Kong, for the daily quotas. */
export function hkDayStart(now = new Date()): string {
  const hk = new Date(now.getTime() + 8 * 3600_000);
  hk.setUTCHours(0, 0, 0, 0);
  return new Date(hk.getTime() - 8 * 3600_000).toISOString();
}

/** Content type from an uploaded file's extension (MusicGPT wants a typed file). */
export function audioTypeFor(path: string): string | null {
  const ext = path.split(".").pop()?.toLowerCase() ?? "";
  return ({
    mp3: "audio/mpeg",
    m4a: "audio/mp4",
    aac: "audio/aac",
    wav: "audio/wav",
    ogg: "audio/ogg",
    flac: "audio/flac",
  } as Record<string, string>)[ext] ?? null;
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export type ToolRequest =
  | { action: "stems"; songId: string }
  | { action: "midi"; songId: string; kind: typeof MIDI_KINDS[number] }
  | { action: "swap"; songId: string; lyrics: string; title: string; style: string | null }
  | { action: "remix"; uploadPath: string; title: string; style: string; lyrics: string; instrumental: boolean };

export function parseToolRequest(raw: unknown, userId: string): ToolRequest | string {
  if (typeof raw !== "object" || raw === null) return "body must be a JSON object";
  const b = raw as Record<string, unknown>;
  const str = (k: string) => (typeof b[k] === "string" ? (b[k] as string) : "");
  switch (b.action) {
    case "stems": {
      const songId = str("song_id");
      return UUID.test(songId) ? { action: "stems", songId } : "song_id is required";
    }
    case "midi": {
      const songId = str("song_id");
      if (!UUID.test(songId)) return "song_id is required";
      const kind = str("kind");
      if (!(MIDI_KINDS as readonly string[]).includes(kind)) return "kind must be vocals, piano, bass or guitar";
      return { action: "midi", songId, kind: kind as typeof MIDI_KINDS[number] };
    }
    case "swap": {
      const songId = str("song_id");
      if (!UUID.test(songId)) return "song_id is required";
      const lyrics = str("lyrics").trim();
      if (!lyrics) return "寫低新歌詞";
      if (lyrics.length > 5000) return "歌詞太長（最多 5000 字）";
      const title = str("title").trim();
      if (title.length > 120) return "歌名太長";
      const style = typeof b.style === "string" ? b.style.trim() : null;
      if (style && style.length > 1000) return "風格太長";
      return { action: "swap", songId, lyrics, title, style };
    }
    case "remix": {
      const uploadPath = str("upload_path");
      if (!uploadPath.startsWith(`${userId}/`) || uploadPath.includes("..") || uploadPath.length > 300) {
        return "upload_path must be in your own upload folder";
      }
      if (!audioTypeFor(uploadPath)) return "上載 mp3、m4a、wav、aac、ogg 或 flac";
      const title = str("title").trim();
      if (!title || title.length > 120) return "要有歌名（最多 120 字）";
      const style = str("style").trim();
      if (style.length > 1000) return "風格太長";
      const lyrics = str("lyrics").trim();
      if (lyrics.length > 5000) return "歌詞太長（最多 5000 字）";
      return { action: "remix", uploadPath, title, style, lyrics, instrumental: b.instrumental === true };
    }
    default:
      return "unknown action";
  }
}
