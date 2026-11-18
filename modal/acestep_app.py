"""ACE-Step 1.5 singer for TIO Studio, on Modal (Gino's pick, 2026-11-18).

Same model Gino heard and approved for Cantonese: DiT `acestep-v15-xl-turbo` + LM
`acestep-5Hz-lm-4B` ("Thinking" on), vocal language `yue`. ACE-Step 1.5 is MIT; songs it makes
may be used commercially.

The GPU scales to zero: nothing is billed while no song is being made. Weights live in the Modal
Volume `acestep-models` (downloaded on the first run, about 20 GB).

HTTP API (every call needs `Authorization: Bearer $ACESTEP_TOKEN`, Modal secret `studio-acestep`):
  POST /submit  {caption, lyrics, instrumental, duration, vocal_language, webhook_url?}
                -> {"job_id": "fc-..."}
  GET  /result/{job_id}          -> {"status": "pending"} | {"status": "failed", "error": ...}
                                    | {"status": "done", "count": 2}
  GET  /result/{job_id}/{i}      -> audio/mpeg (version i, 0-based)
When a job ends, the worker POSTs {"job_id": ...} to webhook_url (a nudge only: Studio reads the
result back with its own token).

Deploy:  modal deploy modal/acestep_app.py   (see modal/README.md)
"""

import os
import modal

ACESTEP_REPO = "https://github.com/ace-step/ACE-Step-1.5"
ACESTEP_SHA = "ca1e85fe9430179831e6bc6be790c332190a3866"  # main on 2026-08-29
DIT_MODEL = "acestep-v15-xl-turbo"
LM_MODEL = "acestep-5Hz-lm-4B"
MODELS_DIR = "/models"
MAX_LYRICS = 4000
VERSIONS = 2  # like MusicGPT: two takes per request, the second becomes "<title> (v2)"

image = (
    modal.Image.debian_slim(python_version="3.11")
    .apt_install("git", "ffmpeg", "libsndfile1", "build-essential")
    .pip_install("uv")
    .run_commands(
        f"git clone {ACESTEP_REPO} /app && cd /app && git checkout {ACESTEP_SHA}",
        "cd /app && uv export --frozen --no-hashes --no-dev --no-emit-project -o /tmp/req.txt",
        "cd /app && uv pip install --system --index-strategy unsafe-best-match"
        " --extra-index-url https://download.pytorch.org/whl/cu128 -r /tmp/req.txt",
        "cd /app && uv pip install --system --no-deps -e .",
    )
    .pip_install("fastapi[standard]", "httpx")
    .env({"ACESTEP_CHECKPOINTS_DIR": MODELS_DIR, "HF_HOME": f"{MODELS_DIR}/hf"})
)

app = modal.App("studio-acestep")
models = modal.Volume.from_name("acestep-models", create_if_missing=True)
secret = modal.Secret.from_name("studio-acestep")  # ACESTEP_TOKEN


WEIGHTS = {
    "ACE-Step/Ace-Step1.5": MODELS_DIR,  # VAE, text encoder, default DiT and LM
    f"ACE-Step/{DIT_MODEL}": f"{MODELS_DIR}/{DIT_MODEL}",
    f"ACE-Step/{LM_MODEL}": f"{MODELS_DIR}/{LM_MODEL}",
}


@app.function(image=image, volumes={MODELS_DIR: models}, timeout=3600)
def download():
    """Fetch every weight into the Volume on a CPU machine (no GPU billed). Run once, and
    again after a partial download: `modal run modal/acestep_app.py::download`. snapshot_download
    resumes and re-checks files, so a container stopped half way can't leave a broken model
    behind (the GPU container then crash-loops on a missing shard)."""
    from huggingface_hub import snapshot_download

    for repo, local in WEIGHTS.items():
        print("downloading", repo, "->", local, flush=True)
        snapshot_download(repo_id=repo, local_dir=local)
        models.commit()
    print("all weights ready", flush=True)


@app.cls(
    image=image,
    gpu="L40S",
    volumes={MODELS_DIR: models},
    secrets=[secret],
    timeout=600,
    scaledown_window=120,
    max_containers=1,
)
class AceStep:
    @modal.enter()
    def load(self):
        from acestep.handler import AceStepHandler
        from acestep.llm_inference import LLMHandler

        self.dit = AceStepHandler()
        msg, ok = self.dit.initialize_service(project_root="/app", config_path=DIT_MODEL, device="cuda")
        if not ok:
            raise RuntimeError(f"DiT init failed: {msg}")
        from acestep.model_downloader import ensure_lm_model

        ok, msg = ensure_lm_model(LM_MODEL, checkpoints_dir=MODELS_DIR)  # not in the main model repo
        if not ok:
            raise RuntimeError(f"LM download failed: {msg}")
        models.commit()
        self.llm = LLMHandler()
        msg, ok = self.llm.initialize(checkpoint_dir=MODELS_DIR, lm_model_path=LM_MODEL, backend="pt", device="cuda")
        if not ok:
            raise RuntimeError(f"LM init failed: {msg}")
        models.commit()  # keep weights downloaded on the first run

    @modal.method()
    def generate(self, req: dict) -> list[bytes]:
        import tempfile
        import httpx
        from acestep.inference import GenerationConfig, GenerationParams, generate_music

        out: list[bytes] = []
        error = ""
        try:
            params = GenerationParams(
                caption=req["caption"],
                lyrics=req["lyrics"],
                instrumental=req["instrumental"],
                vocal_language=req["vocal_language"],
                duration=req["duration"],
                thinking=True,
            )
            config = GenerationConfig(batch_size=VERSIONS, audio_format="mp3")
            with tempfile.TemporaryDirectory() as tmp:
                result = generate_music(self.dit, self.llm, params, config, save_dir=tmp)
                if not result.success:
                    raise RuntimeError(result.error or "generation failed")
                for a in result.audios:
                    if a.get("path"):
                        with open(a["path"], "rb") as f:
                            out.append(f.read())
            if not out:
                raise RuntimeError("no audio")
        except Exception as e:  # noqa: BLE001 - reported to Studio as the job's error
            error = str(e)[:300]
        hook = req.get("webhook_url") or ""
        if hook:
            try:
                httpx.post(hook, json={"job_id": modal.current_function_call_id()}, timeout=10)
            except Exception:  # noqa: BLE001 - Studio also polls
                pass
        if error:
            raise RuntimeError(error)
        return out


LANGS = {"yue", "zh", "en", "ja", "ko", "unknown"}


@app.function(image=image, secrets=[secret])
@modal.asgi_app()
def api():
    from fastapi import FastAPI, Header, HTTPException, Response

    web = FastAPI()

    def check(auth: str | None):
        token = os.environ["ACESTEP_TOKEN"]
        if not auth or auth != f"Bearer {token}":
            raise HTTPException(401, "unauthorized")

    @web.post("/submit")
    def submit(body: dict, authorization: str | None = Header(default=None)):
        check(authorization)
        caption = str(body.get("caption") or "")[:1000]
        lyrics = str(body.get("lyrics") or "")[:MAX_LYRICS]
        instrumental = body.get("instrumental") is True
        lang = str(body.get("vocal_language") or "yue")
        if lang not in LANGS:
            raise HTTPException(400, "bad vocal_language")
        duration = body.get("duration")
        duration = float(duration) if isinstance(duration, (int, float)) and 10 <= duration <= 300 else -1.0
        hook = str(body.get("webhook_url") or "")
        if hook and not hook.startswith("https://"):
            raise HTTPException(400, "webhook_url must be https")
        call = AceStep().generate.spawn({
            "caption": caption,
            "lyrics": "[Instrumental]" if instrumental else lyrics,
            "instrumental": instrumental,
            "vocal_language": "unknown" if instrumental else lang,
            "duration": duration,
            "webhook_url": hook,
        })
        return {"job_id": call.object_id}

    def outputs(job_id: str):
        if not job_id.startswith("fc-") or len(job_id) > 80:
            raise HTTPException(400, "bad job_id")
        try:
            return modal.FunctionCall.from_id(job_id).get(timeout=0)
        except TimeoutError:
            return None

    @web.get("/result/{job_id}")
    def result(job_id: str, authorization: str | None = Header(default=None)):
        check(authorization)
        try:
            audios = outputs(job_id)
        except HTTPException:
            raise
        except Exception as e:  # noqa: BLE001 - the job's own error
            return {"status": "failed", "error": str(e)[:300]}
        if audios is None:
            return {"status": "pending"}
        return {"status": "done", "count": len(audios)}

    @web.get("/result/{job_id}/{i}")
    def audio(job_id: str, i: int, authorization: str | None = Header(default=None)):
        check(authorization)
        audios = outputs(job_id)
        if audios is None or not 0 <= i < len(audios):
            raise HTTPException(404, "not ready")
        return Response(content=audios[i], media_type="audio/mpeg")

    return web
