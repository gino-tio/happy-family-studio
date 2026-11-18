# ACE-Step singer on Modal

`acestep_app.py` runs ACE-Step 1.5 (XL turbo + 4B LM, Cantonese `yue`) on one Modal L40S GPU
that scales to zero. Studio's `studio-generate-song` calls it for provider `acestep`.

## One-time setup (Gino)

Done 2026-11-18: workspace `gino-18339`, URL `https://gino-18339--studio-acestep-api.us-east.modal.run`.

1. Sign up at https://modal.com and add a payment method (without one Modal refuses L40S
   functions; with one, US$30 free credit a month). Store the Modal token in TioPassword,
   collection "Hub ops". Cloud sessions read it from env `MODAL_TOKEN_ID` / `MODAL_TOKEN_SECRET`.
2. `pip install "modal[api-proxy-support]"` (the extra is needed behind the cloud sandbox's
   HTTPS proxy), or `pip install modal` then `modal token new` on a Mac.
3. Make a random token for Studio → Modal calls and add it as a Modal secret:
   `modal secret create studio-acestep ACESTEP_TOKEN=$(openssl rand -hex 32)`
   (keep the value; it goes into Supabase in step 5).
4. Download the weights once on a CPU machine: `modal run modal/acestep_app.py::download`
   (about 25 GB into the Volume `acestep-models`; re-run it if a download was cut off).
   Then deploy: `modal deploy modal/acestep_app.py`. The output prints the web URL,
   `https://<workspace>--studio-acestep-api.modal.run`.
5. Supabase secrets on the Hub project (or ask Claude to set them with `SUPABASE_ACCESS_TOKEN`):
   `STUDIO_ACESTEP_URL=<that URL>` and `STUDIO_ACESTEP_TOKEN=<the token from step 3>`.
6. Deploy the functions: `studio-generate-song` and `studio-acestep-hook` (verify_jwt off).

Measured 2026-11-18: a 40 s song (two takes) took 264 s from a cold GPU (loading both models)
and comes back as two different 40 s mp3s. Don't let the GPU container download weights: a
container stopped half way left a shard missing and the class crash-looped (billed GPU) until
the app was stopped.

## Cost

L40S is US$0.000542/s on Modal. A song (two takes) is about 15–30 s of GPU when warm, plus a
cold start when the GPU has slept (it sleeps after 2 minutes idle). Estimate: US$0.02–0.05 a request.
