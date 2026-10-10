# 開心家庭大樂隊 Studio · Happy Family Studio

Vicky、叮叮同 Gino 用嚟 **AI 作歌** 嘅 app 同網頁：寫低風格同廣東話歌詞 →
AI 生成成首歌 → 喺歌曲庫一齊聽。

樂隊嘅歌、譜同 stems 喺 [`happy-family-big-band`](https://github.com/gino-tio/happy-family-big-band)。
架構參考 `tio-help`：Flutter（Web + iOS + Android 一套 code）+ Supabase。

## 點運作

```
Flutter app ──invoke──▶ Edge Function `generate-song` ──▶ AI music API (ElevenLabs)
     ▲                         │  (vendor key 只喺 server)
     │ Realtime                ▼
     └──────── songs table ◀── upload mp3 → private `songs` bucket
```

1. App 叫 `generate-song`，佢檢查你係唔係 `band_members`，開一行 `songs`（status `generating`），即刻返回。
2. Function 喺背景叫 AI，將 mp3 擺入 private bucket，然後將 status 改做 `done` / `failed`。
3. App 用 Realtime 睇住張 table，搞掂即刻出播放器；播放用 signed URL。

| | |
|---|---|
| Frontend | Flutter 3 · `provider` · `audioplayers` |
| Auth | Supabase Auth — Google（web 用 implicit flow；native 用 deep link `net.toolution.happyfamilystudio://login-callback`）|
| 權限 | `band_members` 白名單 + RLS。任何人都可以用 Google 登入，但唔係成員乜都睇唔到 |
| AI | `supabase/functions/generate-song/providers/` — 一個 provider 一個檔案，用 `MUSIC_PROVIDER` secret 切換 |
| Deploy | Cloudflare Pages（`.github/workflows/deploy.yml`）|

## AI 供應商

暫時用 **ElevenLabs Music**（`POST /v1/music`，要付費 plan）。佢冇列廣東話做支援語言，
所以正式用之前先試唱一段《星期六返嚟》。Suno 未有正式公開 API；MiniMax 2026-08-20 起唔收新用戶。
想換供應商：喺 `providers/` 加一個檔案，喺 `index.ts` 嘅 `pickProvider()` 加一個 case。

## 第一次設定

1. **Supabase**：project `ewvaukmegoyuvrtxvbhf`（TIO Studio Project，東京）。migration、成員名單、`generate-song` 已經 set 好；以下係由零開始嘅步驟。
   ```sh
   supabase link --project-ref <ref>
   supabase db push                       # migrations/0001
   # 喺 SQL editor 行一次 supabase/seed.sql（成員名單）
   supabase secrets set ELEVENLABS_API_KEY=<key>
   supabase functions deploy generate-song
   ```
2. **Auth**：Supabase → Authentication → Providers 開 Google；
   URL Configuration 加網頁網址同 `net.toolution.happyfamilystudio://login-callback`。
3. **本機跑**：
   ```sh
   flutter run -d chrome \
     --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
     --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
   ```
4. **Deploy**：開 Cloudflare Pages project `happy-family-studio`，加 repo secrets
   `CLOUDFLARE_API_TOKEN`、`CLOUDFLARE_ACCOUNT_ID`、`SUPABASE_URL`、`SUPABASE_PUBLISHABLE_KEY`。
   未加 secrets 之前 deploy job 會自動跳過。

## 檢查

```sh
flutter analyze && flutter test
deno check supabase/functions/generate-song/index.ts && deno test supabase/functions/
```

## 下一步（未做）

- 用 ElevenLabs `composition_plan` 按 [Verse]/[Chorus] 分段生成，控制每段長度
- 俾分、留言、「呢個 take 最好」
- 將 `happy-family-big-band` 嘅歌、stems、彈唱頁搬入嚟
- 生成完推送通知（FCM，跟 tio-help `notify-nearby`）
- Apple 登入（上 App Store 一定要）
