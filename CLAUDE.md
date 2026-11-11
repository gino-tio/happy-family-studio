# happy-family-studio — Claude session handoff

AI song-generation app for the Happy Family Big Band (Vicky, Ding Ding 叮叮, Gino).
Flutter (web + iOS + Android) + Supabase. Modelled on `tio-help` — its CLAUDE.md
pitfalls list applies here too (viewport meta, implicit OAuth on web, dart-defines
in CI, `.order()` ascending, generic `set_updated_at` trigger).

## Live infra

- **Supabase**: project "TIO Studio Project", ref `ewvaukmegoyuvrtxvbhf`, region Tokyo
  (ap-northeast-1). URL `https://ewvaukmegoyuvrtxvbhf.supabase.co`. Migrations 0001–0002
  applied; `generate-song` deployed (verify_jwt on); band_members seeded.
- The `mcp__Supabase__*` connector is signed in to the account that owns this project.

## Status (2026-11-11) — handoff

Done: app scaffold, Supabase backend live, CI green, City Pop style preset, Beat 格仔 step
sequencer (BeatScreen) with "用呢個 beat 作歌" → ComposeScreen(initialStyle: pattern.toPrompt()).

Blocked on Gino (dashboard work, see `docs/muse-setup-tasks.md`): Google provider, redirect
URLs, `ELEVENLABS_API_KEY` secret, GitHub Actions secrets. No song has been generated yet;
Cantonese vocal quality untested. Web hosting (Cloudflare Pages) not set up.

Not yet verified by ear on a device: beat loop playback through `audioplayers` BytesSource
(web may leave a tiny gap at the WAV loop point; the file holds 2 loops to halve it).

Beat grid next ideas: save/share patterns (new `beats` table + RLS via is_band_member),
per-step velocity, >2 bars, sample-based instruments.

## Beat grid notes

- Timing lives in `BeatSynth.stepTime` (swing = where the odd 16th sits in each 8th pair).
  The playhead is a Ticker clock started with playback, not the player's position stream
  (too coarse for ~140 ms steps).
- Tails wrap round the loop end, so the rendered loop is seamless; edits re-render after a
  250 ms debounce and resume from the same spot.
- One chord per half bar (`BeatPattern.stepsPerChord = 8`). `chord.dart` parses the
  symbols a band chart uses; extend `_qualities` for more.

## Invariants

- **Vendor keys never reach the client.** Only `generate-song` talks to the AI
  music API; keys are Supabase secrets.
- **Membership, not sign-in, is the gate.** Every RLS policy checks
  `public.is_band_member()`; Google sign-in alone grants nothing.
- **Writes to `songs.status` / `audio_path` come only from the Edge Function**
  (service role). Clients may only rename / delete their own rows.
- **`Song.fromRow`** is the one parser for selects, Realtime and the function response.
- **Design tokens** live in `lib/theme.dart` (`StudioColors` / `StudioRadius` / `StudioSpacing`).
- **Separate Supabase project** from tio-help and tio-info — never run this
  repo's SQL against theirs.

## Layout

```
lib/models/        Song, SongDraft, SongStatus, StylePreset; BeatPattern, BeatTrack, BeatPresets, chord.dart
lib/audio/         BeatSynth — pure-Dart synth: BeatPattern → WAV loop (sample-exact timing, swing)
lib/services/      AuthService (Google + allowlist), SongsService (stream, generate, signed URLs)
lib/screens/       AuthGate → SignIn / Library → Compose → Song (player); Library → BeatScreen (step sequencer)
supabase/migrations/0001_initial_schema.sql   band_members, songs, songs bucket, RLS
supabase/functions/generate-song/             Edge Function + providers/
supabase/seed.sql  band allowlist (Gino, Vicky, Ding Ding)
```

## Checks

`flutter analyze && flutter test` · `deno check supabase/functions/generate-song/index.ts && deno test supabase/functions/`
