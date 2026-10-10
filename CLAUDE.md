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
lib/models/        Song, SongDraft, SongStatus, StylePreset
lib/services/      AuthService (Google + allowlist), SongsService (stream, generate, signed URLs)
lib/screens/       AuthGate → SignIn / Library → Compose → Song (player)
supabase/migrations/0001_initial_schema.sql   band_members, songs, songs bucket, RLS
supabase/functions/generate-song/             Edge Function + providers/
supabase/seed.sql  band allowlist (Gino, Vicky, Ding Ding)
```

## Checks

`flutter analyze && flutter test` · `deno check supabase/functions/generate-song/index.ts && deno test supabase/functions/`
