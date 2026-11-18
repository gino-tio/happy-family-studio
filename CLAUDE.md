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

## Player redesign (2026-11-14, Gino: "like musicgpt.com", all recommended answers)

- Home = rows of big covers (最新作品, 我鍾意, Playlists, 我嘅歌) + full track list; a mini player sits
  under every screen (MaterialApp.builder, outside the navigator) with prev/next/shuffle/repeat.
  Song screen = big cover + controls + tabs 歌詞 / 留言 / 資料; wide screens put the cover left.
- Covers (`songs.cover_path`, private bucket `studio-covers`): MusicGPT songs ask for
  `generate_album_cover` and keep MusicGPT's .jpg; others (and 換封面, any member, 10/day as
  ai_usage kind `cover`) get an SVG Claude draws via the Hub chat (`_shared/cover.ts`,
  `sanitizeSvg` rebuilds it from allowed shapes only). `studio-song-cover` draws in the background
  (202); with the service role and `auto: true` it only fills a song that has no cover.
- Timed lyrics (`songs.lyrics_timed`, [{start,end,text}] ms) from MusicGPT `lyrics_timestamps`;
  the app highlights the sung line. `enrichMusicGpt` fills cover/lyrics that arrive after the audio.
- Likes, comments (one level of replies), playlists (everyone plays, only the maker edits) and
  `members()` (names/avatars): migration studio_0003_player, test supabase/tests/studio_player_rls_test.sql.
- `LibraryStore` holds songs/likes/playlists/members for the whole app; `PlayerController` is the
  one AudioPlayer. `LibraryStore.seed` fills it without a backend (design previews, widget tests).
- Background play (2026-11-17): `PlayerController` plays through `lib/services/audio/AudioEngine`.
  Web uses ONE plain `<audio>` element + Media Session (lock-screen title, play/pause/next/prev/seek);
  never route it through Web Audio (audioplayers_web does, and iOS suspends that AudioContext when the
  screen locks). The next song's signed URL is fetched ahead so a locked phone moves on without a
  network wait. Native: audioplayers + `UIBackgroundModes: audio`, Android wake lock.
- Live changes are now applied from cloud sessions with `SUPABASE_ACCESS_TOKEN` (Management API SQL,
  `npx supabase functions deploy <fn> --project-ref ddzwhmcxeokkwzmhglft --use-api --yes`).

## Invariants

- **AI lyrics go through the Hub.** `studio-write-lyrics` calls `POST <hub>/api/v1/llm/studio/chat`
  with secret `STUDIO_HUB_API_KEY` (portal key kind `app`, Hub app `studio` is chat only via
  `HUB_CHAT_APPS`). Topic and lyrics are never logged. Quota rows are inserted before the call.
- **Two singers.** ElevenLabs sings Chinese lyrics in Mandarin (no Cantonese on its list), so
  the compose screen also offers MusicGPT (`providers/musicgpt.ts`, secret `STUDIO_MUSICGPT_KEY`,
  model `STUDIO_MUSICGPT_MODEL` default v6), Gino's pick 2026-11-14 after hearing it on
  musicgpt.com. Async: the song row keeps the task id in `provider_song_id`; the generate
  function polls ~135 s and `studio-musicgpt-hook` (verify_jwt off, unsigned webhook = nudge only,
  result re-read from MusicGPT with our key) finishes later ones. Version 2 becomes a second row
  "<title> (v2)".
- **Third singer: ACE-Step 1.5 on our own Modal GPU** (Gino 2026-11-18, after hearing it sing
  Cantonese: "not bad, can use"). `modal/acestep_app.py` (XL turbo + 4B LM, `yue`, two takes, L40S,
  scales to zero; setup in `modal/README.md`), `providers/acestep.ts`, secrets
  `STUDIO_ACESTEP_URL` / `STUDIO_ACESTEP_TOKEN`. Same async shape as MusicGPT: Modal job id in
  `provider_song_id`, polling ~130 s, then `studio-acestep-hook` (verify_jwt off, nudge only).
  Covers are Claude SVGs. Hidden from the compose screen since 2026-11-18 (Cantonese judged bad).
- **MusicGPT tools on songs** (Gino 2026-11-18, all recommended answers; ACE-Step was tried
  the same day and its Cantonese judged bad, so its compose button is hidden; the Modal app and
  provider stay for now). `studio-song-tools` (migration studio_0004_tools): 拆樂器 = Extraction
  `stem_preset=6_stems` into `song_stems` (tracks in studio-songs `<user>/stems/<song>/<kind>.mp3`);
  換歌詞 = Sing Over Instrumental on the split's instrumental → new song, model
  `sing_over_instrumental`, `source='swap'`, `parent_song_id`; 由一首歌開始 = member uploads to
  private bucket `studio-uploads/<user>/...`, then Remix → new song, model `remix`,
  `source='remix'`. Each is 10/member/HK day in ai_usage. MusicGPT's audio_url only takes YouTube
  links, so the function uploads files. byId conversionType follows the song's model
  (`conversionTypeFor`). The Extraction byId shape isn't documented: `findStemUrls` walks the
  reply and logs field names if it finds none. studio-musicgpt-hook finishes splits too.
  出譜 (migration studio_0005_sheets): vocals / piano / bass / guitar tracks → MusicGPT Audio to
  MIDI (action `midi`, 20/member/HK day) into `stem_midis` (`<user>/stems/<song>/<kind>.mid`);
  drums need no MIDI. The static page `web/sheet/` (alphaTab 1.8.4 + @tonejs/midi from jsDelivr,
  pure logic in `transcribe.js`, `deno test web/sheet/`) takes everything in the URL fragment,
  quantizes to a 16th grid (tempo guessed from the drum track's hits, editable), draws guitar /
  bass tab + staff, staff for piano / vocals, and finds kick / snare / hi-hat in the drum audio
  by frequency band for the 鼓譜. 列印 / PDF = alphaTab print. Transcription is rough by design.
- **Vendor keys never reach the client.** Only Edge Functions (`studio-generate-song`, `studio-song-tools`) talk to the AI
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
lib/services/      + LibraryStore (live library), PlayerController (queue player)
lib/widgets/       CoverArt, MiniPlayer/PlayerControls, LyricsView, CommentsView, song cards + playlist sheet
lib/screens/       AuthGate → SignIn / Home → Song / Playlist / Compose; Home → BeatScreen (step sequencer)
supabase/migrations/studio_0001_init.sql      app_studio schema, songs, studio-songs bucket, RLS
supabase/functions/studio-generate-song/      Edge Function + providers/
supabase/functions/studio-musicgpt-hook/      MusicGPT webhook → finishMusicGpt
supabase/functions/studio-song-cover/         換封面 / auto cover (Claude SVG via Hub; MusicGPT cover first)
supabase/functions/_shared/cover.ts           cover prompt, sanitizeSvg, storeCover
supabase/functions/studio-write-lyrics/       AI 寫歌詞: Claude via TIO AI Hub chat (app `studio`, chat only), 30/member/HK day in app_studio.ai_usage
supabase/seed.sql  band membership (Gino owner, Vicky, Ding Ding) after they sign in once
```

## Checks

`flutter analyze && flutter test` · `deno check supabase/functions/*/index.ts && deno test supabase/functions/`
