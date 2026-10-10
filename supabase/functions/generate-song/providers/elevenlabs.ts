// ElevenLabs Music — POST https://api.elevenlabs.io/v1/music
// Docs: https://elevenlabs.io/docs/api-reference/music/compose
//
// The endpoint is synchronous: it returns the finished audio file in the
// response body (song id in a response header). Requires a paid plan.
// Cantonese vocals are not on ElevenLabs' language list — test before
// relying on them.

import type { GeneratedSong, MusicProvider, SongRequest } from "./types.ts";

const ENDPOINT = "https://api.elevenlabs.io/v1/music";

export function buildPrompt(req: SongRequest): string {
  const parts: string[] = [];
  if (req.style.trim()) parts.push(req.style.trim());
  if (!req.instrumental && req.lyrics.trim()) {
    parts.push(
      "Sung in Cantonese (Hong Kong). Use exactly these lyrics, in order:\n" +
        req.lyrics.trim(),
    );
  }
  return parts.join("\n\n") || req.title;
}

export function elevenLabsProvider(apiKey: string, model: string): MusicProvider {
  return {
    name: "elevenlabs",
    model,
    async generate(req: SongRequest): Promise<GeneratedSong> {
      const body: Record<string, unknown> = {
        prompt: buildPrompt(req),
        model_id: model,
        force_instrumental: req.instrumental,
      };
      if (req.lengthMs) body.music_length_ms = req.lengthMs;

      const resp = await fetch(`${ENDPOINT}?output_format=mp3_44100_128`, {
        method: "POST",
        headers: { "xi-api-key": apiKey, "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      if (!resp.ok) {
        const text = await resp.text();
        throw new Error(`ElevenLabs ${resp.status}: ${text.slice(0, 500)}`);
      }
      return {
        audio: new Uint8Array(await resp.arrayBuffer()),
        contentType: "audio/mpeg",
        extension: "mp3",
        providerSongId: resp.headers.get("song-id"),
      };
    },
  };
}
