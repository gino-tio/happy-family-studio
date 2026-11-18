# ACE-Step singer on Modal

`acestep_app.py` runs ACE-Step 1.5 (XL turbo + 4B LM, Cantonese `yue`) on one Modal L40S GPU
that scales to zero. Studio's `studio-generate-song` calls it for provider `acestep`.

## One-time setup (Gino)

1. Sign up at https://modal.com (Starter plan: US$30 free credit a month). Store the Modal
   token in TioPassword, collection "Hub ops".
2. On a computer with Python: `pip install modal` then `modal token new`.
3. Make a random token for Studio → Modal calls and add it as a Modal secret:
   `modal secret create studio-acestep ACESTEP_TOKEN=$(openssl rand -hex 32)`
   (keep the value; it goes into Supabase in step 5).
4. Deploy: `modal deploy modal/acestep_app.py`. The output prints the web URL,
   `https://<workspace>--studio-acestep-api.modal.run`.
5. Supabase secrets on the Hub project (or ask Claude to set them with `SUPABASE_ACCESS_TOKEN`):
   `STUDIO_ACESTEP_URL=<that URL>` and `STUDIO_ACESTEP_TOKEN=<the token from step 3>`.
6. Deploy the functions: `studio-generate-song` and `studio-acestep-hook` (verify_jwt off).

The first song downloads the weights (about 20 GB) into the Volume `acestep-models` and takes a
few minutes; later cold starts load them from the Volume.

## Cost

L40S is US$0.000542/s on Modal. A song (two takes) is about 15–30 s of GPU when warm, plus a
cold start when the GPU has slept (it sleeps after 2 minutes idle). Estimate: US$0.02–0.05 a request.
