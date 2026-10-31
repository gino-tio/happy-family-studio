# Setup tasks for Muse 🤖

> **To Muse:** these are dashboard settings for the Happy Family Studio app
> (`gino-tio/happy-family-studio`). The code, database and Edge Function are
> already live — only the four settings below are missing. Work through them
> in order, tick each box, then report back what you did and anything you
> could not finish.
>
> **Ground rules**
> - Never write a secret (Google Client Secret, ElevenLabs key) into this file,
>   a commit, an issue, a PR or a chat message. Type secrets only into the
>   dashboard field that asks for them.
> - Don't change anything not listed here. Don't touch any other Supabase
>   project — only `ewvaukmegoyuvrtxvbhf` ("TIO Studio Project").
> - If a step needs a login or a value you don't have, stop and ask Gino.

| | |
|---|---|
| Supabase project | **TIO Studio Project** · ref `ewvaukmegoyuvrtxvbhf` · Tokyo |
| Supabase URL | `https://ewvaukmegoyuvrtxvbhf.supabase.co` |
| Publishable key (public, safe to share) | `sb_publishable__H4vdAx85cgwMT-y01ZAIw_KJc18KfD` |
| Owner | Gino · gino@toolution.net |

---

## 1. Turn on Google sign-in

- [ ] **Google Cloud** → https://console.cloud.google.com/apis/credentials
  - Create (or reuse) an **OAuth 2.0 Client ID**, type **Web application**.
  - Under **Authorized redirect URIs** add exactly:
    `https://ewvaukmegoyuvrtxvbhf.supabase.co/auth/v1/callback`
  - If asked for the OAuth consent screen: app name `開心家庭大樂隊 Studio`,
    support email `gino@toolution.net`, user type **External**. Add test users
    `gino@toolution.net`, `onbbin@gmail.com`, `onbbding@gmail.com` while the
    app is in testing.
- [ ] **Supabase** → https://supabase.com/dashboard/project/ewvaukmegoyuvrtxvbhf/auth/providers
  - Open **Google**, switch it **on**, paste the Client ID and Client Secret
    from the step above, **Save**.

**Done when:** the Google provider shows as Enabled in Supabase.

## 2. Allow the app's redirect URLs

- [ ] **Supabase** → https://supabase.com/dashboard/project/ewvaukmegoyuvrtxvbhf/auth/url-configuration
  - Under **Redirect URLs** add both:
    - `http://localhost:*`
    - `net.toolution.happyfamilystudio://login-callback`
  - Leave **Site URL** as it is for now (the web app isn't deployed yet).

**Done when:** both URLs are listed.

## 3. Add the ElevenLabs API key

- [ ] **ElevenLabs** → https://elevenlabs.io/app/settings/api-keys
  - The account needs a **paid plan** (the Music API is paid-only).
  - Create a key named `happy-family-studio`. If key permissions are offered,
    it only needs **Music**.
- [ ] **Supabase** → https://supabase.com/dashboard/project/ewvaukmegoyuvrtxvbhf/functions/secrets
  - Add secret: name `ELEVENLABS_API_KEY`, value = the key. **Save**.

**Done when:** `ELEVENLABS_API_KEY` appears in the secrets list (value hidden).

## 4. Add GitHub Actions secrets

- [ ] **GitHub** → https://github.com/gino-tio/happy-family-studio/settings/secrets/actions
  (needs admin on the repo)
  - New repository secret `SUPABASE_URL` = `https://ewvaukmegoyuvrtxvbhf.supabase.co`
  - New repository secret `SUPABASE_PUBLISHABLE_KEY` = `sb_publishable__H4vdAx85cgwMT-y01ZAIw_KJc18KfD`

**Done when:** both secrets are listed.

> Not part of this task: `CLOUDFLARE_API_TOKEN` / `CLOUDFLARE_ACCOUNT_ID`
> (web deploy). Gino will decide on hosting later.

---

## Report back

When finished, reply to Gino with:

1. Which boxes are ticked.
2. Anything skipped and why.
3. Confirmation that no secret was pasted anywhere except the dashboard fields.

Next step after this (for Gino, not Muse): run the app locally, sign in with
Google and generate a test song — see [README.md](../README.md#第一次設定).
