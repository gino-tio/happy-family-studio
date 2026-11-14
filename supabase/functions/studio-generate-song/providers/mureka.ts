// Mureka (Skywork) through fal.ai's queue — https://fal.ai/models/mureka/api/generate/song
// Tried as a second voice because ElevenLabs sings Chinese lyrics in Mandarin (Cantonese is
// not on its language list). Mureka doesn't document Cantonese either: test by ear.
//
// Queue flow (https://fal.ai/docs/documentation/model-apis/inference/queue): POST the request,
// then poll the status_url / response_url the submit answer gives (never build them by hand).

import type { GeneratedSong, MusicProvider, SongRequest } from "./types.ts";

const MODEL_PATH = "mureka/api/generate/song";
const QUEUE = "https://queue.fal.run";

/** Mureka's prompt is a style control of at most 1,024 characters when lyrics are given. */
export function murekaBody(req: SongRequest, model: string): Record<string, unknown> {
  const vocal = req.instrumental
    ? "Instrumental only, no vocals."
    : "Vocals sung in Cantonese (Hong Kong Cantopop), not Mandarin.";
  const style = req.style.trim();
  const limit = req.instrumental ? 2000 : 1024;
  const prompt = (style ? `${vocal} ${style}` : vocal).slice(0, limit);
  const body: Record<string, unknown> = { prompt, model };
  if (!req.instrumental && req.lyrics.trim()) body.lyrics = req.lyrics.trim().slice(0, 5000);
  // Only mureka-9.5 takes a duration, and only 120–300 s; shorter requests let the model decide.
  if (model === "mureka-9.5" && req.lengthMs && req.lengthMs >= 120_000) {
    body.duration = Math.min(300, Math.round(req.lengthMs / 1000));
  }
  return body;
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export function murekaProvider(falKey: string, model: string, deadlineMs = 135_000): MusicProvider {
  const auth = { Authorization: `Key ${falKey}` };
  return {
    name: "mureka",
    model,
    async generate(req: SongRequest): Promise<GeneratedSong> {
      const started = Date.now();
      const submit = await fetch(`${QUEUE}/${MODEL_PATH}`, {
        method: "POST",
        headers: { ...auth, "Content-Type": "application/json" },
        body: JSON.stringify(murekaBody(req, model)),
      });
      if (!submit.ok) throw new Error(`Mureka submit ${submit.status}: ${(await submit.text()).slice(0, 300)}`);
      const job = await submit.json() as { request_id: string; status_url: string; response_url: string };

      for (;;) {
        if (Date.now() - started > deadlineMs) throw new Error(`Mureka too slow (request ${job.request_id})`);
        await sleep(5000);
        const s = await fetch(job.status_url, { headers: auth });
        if (!s.ok) continue;
        const st = await s.json() as { status: string; error?: string };
        if (st.status === "COMPLETED") {
          if (st.error) throw new Error(`Mureka failed: ${String(st.error).slice(0, 300)}`);
          break;
        }
      }
      const r = await fetch(job.response_url, { headers: auth });
      if (!r.ok) throw new Error(`Mureka result ${r.status}: ${(await r.text()).slice(0, 300)}`);
      const out = await r.json() as { audio?: { url?: string; content_type?: string }; song_id?: string };
      const url = out.audio?.url;
      if (!url) throw new Error("Mureka returned no audio");
      const audio = await fetch(url);
      if (!audio.ok) throw new Error(`Mureka audio download ${audio.status}`);
      const type = audio.headers.get("content-type") ?? out.audio?.content_type ?? "audio/mpeg";
      const ext = type.includes("wav") ? "wav" : type.includes("flac") ? "flac" : "mp3";
      return {
        audio: new Uint8Array(await audio.arrayBuffer()),
        contentType: type.startsWith("audio/") ? type : "audio/mpeg",
        extension: ext,
        providerSongId: out.song_id ?? job.request_id,
      };
    },
  };
}
