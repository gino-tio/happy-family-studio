# 開心家庭大樂隊 Studio · Happy Family Studio

Vicky、叮叮同 Gino 用嚟 **AI 作歌** 嘅 app 同網頁：寫低風格同廣東話歌詞 →
AI 生成成首歌 → 喺歌曲庫一齊聽。

樂隊嘅歌、譜同 stems 喺 [`happy-family-big-band`](https://github.com/gino-tio/happy-family-big-band)。
架構參考 `tio-help`：Flutter（Web + iOS + Android 一套 code）+ Supabase。

## Beat 格仔（Step Sequencer）

歌曲庫右上角 ▦ 掣。好似 beat maker 咁逐格砌節奏：Kick、Snare、Hats、Bass、E. Piano、Guitar、Horns，
兩小節 32 格（16 分音符），每半小節一個和弦。

- 撳格仔開／關；Bass 撳一下用嗰段和弦嘅根音，長撳揀音；撳和弦名改和弦
- 調 BPM（60–180）同 Swing（50–75%），撳 ▶ 即刻循環播放
- 範例：**City Pop**（105 BPM · swing 54% · Am7 → Dm9 · 銅管喺頂）、**星期六返嚟 Rock**、空白
- **「用呢個 beat 作歌」**：將格仔轉做風格 prompt（BPM、和弦、鼓、bass line、樂器），帶去「作新歌」

聲音係 app 自己用 Dart 合成（`lib/audio/beat_synth.dart`），唔使素材、唔使網絡，
每一下都準到 sample，所以網頁、iOS、Android 一樣準。聲音係簡單合成音色，用嚟聽 groove 同和弦，唔係成品混音。

## 點運作

```
Flutter app ──invoke──▶ Edge Function `studio-generate-song` ──▶ AI music API (ElevenLabs)
     ▲                         │  (vendor key 只喺 server)
     │ Realtime                ▼
     └──────── songs table ◀── upload mp3 → private `songs` bucket
```

1. App 叫 `studio-generate-song`，佢檢查你係唔係 Studio 成員（`app_studio.me()`），開一行 `songs`（status `generating`），即刻返回。
2. Function 喺背景叫 AI，將 mp3 擺入 private bucket，然後將 status 改做 `done` / `failed`。
3. App 用 Realtime 睇住張 table，搞掂即刻出播放器；播放用 signed URL。

| | |
|---|---|
| Frontend | Flutter 3 · `provider` · `audioplayers` |
| Auth | Supabase Auth — Google（web 用 implicit flow；native 用 deep link `net.toolution.happyfamilystudio://login-callback`）|
| 權限 | `core.app_members`（app id `studio`）+ RLS。任何人都可以用 Google 登入，但唔係成員乜都睇唔到 |
| AI | `supabase/functions/studio-generate-song/providers/` — 一個 provider 一個檔案，用 `STUDIO_MUSIC_PROVIDER` secret 切換 |
| Deploy | Cloudflare Pages（`.github/workflows/deploy.yml`）|

## AI 供應商

暫時用 **ElevenLabs Music**（`POST /v1/music`，要付費 plan）。佢冇列廣東話做支援語言，
所以正式用之前先試唱一段《星期六返嚟》。Suno 未有正式公開 API；MiniMax 2026-08-20 起唔收新用戶。
想換供應商：喺 `providers/` 加一個檔案，喺 `index.ts` 嘅 `pickProvider()` 加一個 case。

## 第一次設定

1. **Supabase**：用共用嘅 Tio Hub Project（`ddzwhmcxeokkwzmhglft`），規則睇 tio-ai-hub `docs/SHARED_DB.md`。
   - SQL Editor 貼 `supabase/migrations/studio_0001_init.sql`，Run（可以重跑）；再跑 tio-ai-hub 嘅 `supabase/app-template/checks.sql`，要 0 行。
   - Project Settings → Data API → Exposed schemas 加 `app_studio`。
   - 三位成員各自登入 app 一次之後，SQL Editor 跑 `supabase/seed.sql`。
   ```sh
   supabase secrets set --project-ref ddzwhmcxeokkwzmhglft STUDIO_ELEVENLABS_API_KEY=<key>
   supabase functions deploy studio-generate-song --project-ref ddzwhmcxeokkwzmhglft
   ```
2. **Auth**：Google 登入同 Hub 共用，唔使再開。URL Configuration → Redirect URLs 加 Studio 網頁網址同
   `net.toolution.happyfamilystudio://login-callback`。
3. **本機跑**：
   ```sh
   flutter run -d chrome \
     --dart-define=SUPABASE_URL=https://ddzwhmcxeokkwzmhglft.supabase.co \
     --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
   ```
4. **Deploy**：開 Cloudflare Pages project `happy-family-studio`，加 repo secrets
   `CLOUDFLARE_API_TOKEN`、`CLOUDFLARE_ACCOUNT_ID`、`SUPABASE_URL`、`SUPABASE_PUBLISHABLE_KEY`。
   未加 secrets 之前 deploy job 會自動跳過。

## 檢查

```sh
flutter analyze && flutter test
deno check supabase/functions/studio-generate-song/index.ts && deno test supabase/functions/
```

## 下一步（未做）

- Beat 格仔：儲存／分享 pattern（Supabase table）、每格力度、更多小節、真樂器素材

- 用 ElevenLabs `composition_plan` 按 [Verse]/[Chorus] 分段生成，控制每段長度
- 俾分、留言、「呢個 take 最好」
- 將 `happy-family-big-band` 嘅歌、stems、彈唱頁搬入嚟
- 生成完推送通知（FCM，跟 tio-help `notify-nearby`）
- Apple 登入（上 App Store 一定要）
