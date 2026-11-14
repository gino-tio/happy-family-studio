# happy-family-studio — Claude session handoff

AI song-generation app for the Happy Family Big Band (Vicky, Ding Ding 叮叮, Gino).
Flutter (web + iOS + Android) + Supabase. Modelled on `tio-help` — its CLAUDE.md
pitfalls list applies here too (viewport meta, implicit OAuth on web, dart-defines
in CI, `.order()` ascending, generic `set_updated_at` trigger).

## Live infra

- **Supabase**: the shared **Tio Hub Project**, ref `ddzwhmcxeokkwzmhglft`, region Tokyo
  (org "Tio Hub Org"; moved here 2026-11-14, Gino). URL `https://ddzwhmcxeokkwzmhglft.supabase.co`.
  It follows tio-ai-hub `docs/SHARED_DB.md`: this app is app id `studio`, its tables live in
  schema `app_studio`, membership is `core.app_members`, bucket `studio-songs`, Edge Function
  `studio-generate-song`, secrets `STUDIO_*`. Hub and TIO Bot share the same project.
- Live changes: Gino pastes SQL in the SQL Editor (connector writes don't reach him), then runs
  tio-ai-hub `supabase/app-template/checks.sql` (must return 0 rows).
- The old project "TIO Studio Project" (`ewvaukmegoyuvrtxvbhf`, never generated a song) is
  retired; don't delete it until the app works on the Hub project.

## Status (2026-11-11) — handoff

Done: app scaffold, Supabase backend live, CI green, City Pop style preset, Beat 格仔 step
sequencer (BeatScreen) with "用呢個 beat 作歌" → ComposeScreen(initialStyle: pattern.toPrompt()).

Blocked on Gino (dashboard work, see `docs/muse-setup-tasks.md`): Google provider, redirect
URLs, `STUDIO_ELEVENLABS_API_KEY` secret, GitHub Actions secrets (now on the Hub project; docs/muse-setup-tasks.md still names the old one). No song has been generated yet;
Cantonese vocal quality untested. Web hosting (Cloudflare Pages) not set up.

Not yet verified by ear on a device: beat loop playback through `audioplayers` BytesSource
(web may leave a tiny gap at the WAV loop point; the file holds 2 loops to halve it).

Beat grid next ideas: save/share patterns (new `beats` table in app_studio + RLS via core.is_member('studio')),
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

- **AI lyrics go through the Hub.** `studio-write-lyrics` calls `POST <hub>/api/v1/llm/studio/chat`
  with secret `STUDIO_HUB_API_KEY` (portal key kind `app`, Hub app `studio` is chat only via
  `HUB_CHAT_APPS`). Topic and lyrics are never logged. Quota rows are inserted before the call.
- **Vendor keys never reach the client.** Only `studio-generate-song` talks to the AI
  music API; keys are Supabase secrets.
- **Membership, not sign-in, is the gate.** Every RLS policy checks
  `core.is_member('studio')`; the app asks `app_studio.me()`. Google sign-in alone grants
  nothing (and the sign-in is shared with every app on the Hub project).
- **Never add tables to `public`**; everything goes in `app_studio` (exposed in Data API).
- **Writes to `songs.status` / `audio_path` come only from the Edge Function**
  (service role). Clients may only rename / delete their own rows.
- **`Song.fromRow`** is the one parser for selects, Realtime and the function response.
- **Design tokens** live in `lib/theme.dart` (`StudioColors` / `StudioRadius` / `StudioSpacing`).
- **Migrations touch only Studio's things**: `app_studio`, `studio-*` buckets, `studio_*`
  storage policies, `core` rows for app id `studio`. Never Hub/Bot tables or other apps.

## Layout

```
lib/models/        Song, SongDraft, SongStatus, StylePreset; BeatPattern, BeatTrack, BeatPresets, chord.dart
lib/audio/         BeatSynth — pure-Dart synth: BeatPattern → WAV loop (sample-exact timing, swing)
lib/services/      AuthService (Google + allowlist), SongsService (stream, generate, signed URLs)
lib/screens/       AuthGate → SignIn / Library → Compose → Song (player); Library → BeatScreen (step sequencer)
supabase/migrations/studio_0001_init.sql      app_studio schema, songs, studio-songs bucket, RLS
supabase/functions/studio-generate-song/      Edge Function + providers/
supabase/functions/studio-write-lyrics/       AI 寫歌詞: Claude via TIO AI Hub chat (app `studio`, chat only), 30/member/HK day in app_studio.ai_usage
supabase/seed.sql  band membership (Gino owner, Vicky, Ding Ding) after they sign in once
```

## Checks

`flutter analyze && flutter test` · `deno check supabase/functions/*/index.ts && deno test supabase/functions/`
