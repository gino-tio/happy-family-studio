// A music provider turns a request into audio bytes. Each provider lives in
// its own file so swapping vendors (ElevenLabs today; Suno if its official
// API opens up, a self-hosted model later) is a one-file change plus a
// MUSIC_PROVIDER secret flip.

export interface SongRequest {
  title: string;
  style: string;
  lyrics: string;
  instrumental: boolean;
  lengthMs: number | null;
}

export interface GeneratedSong {
  audio: Uint8Array;
  contentType: string;
  extension: string;
  providerSongId: string | null;
}

export interface MusicProvider {
  name: string;
  model: string;
  generate(req: SongRequest): Promise<GeneratedSong>;
}
