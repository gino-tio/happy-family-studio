// studio-acestep-hook — our Modal ACE-Step worker calls this when a job ends.
// verify_jwt is off because Modal can't send a Supabase token, and the call is unsigned, so the
// body is only a nudge: we take its job_id, then read the real result from Modal with our own
// token (finishAceStep). A job id that isn't one of our 'generating' songs does nothing.
// The worker sends the nudge just before its result is stored, so a few short retries cover
// that gap.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { aceStepConfig, finishAceStep, JOB_ID } from "../studio-generate-song/providers/acestep.ts";
import { requestCover } from "../_shared/cover.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("POST only", { status: 405 });
  const cfg = aceStepConfig();
  if (!cfg) return new Response("not configured", { status: 503 });
  let jobId = "";
  try {
    const text = await req.text();
    if (text.length > 10_000) return new Response("too large", { status: 413 });
    const body = JSON.parse(text);
    jobId = typeof body?.job_id === "string" ? body.job_id : "";
  } catch {
    // fall through
  }
  if (!JOB_ID.test(jobId)) return new Response("ok", { status: 200 });
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  try {
    for (let i = 0; i < 6; i++) {
      const r = await finishAceStep(admin, "app_studio", "studio-songs", cfg, jobId);
      if (r.state === "done") {
        for (const id of r.ids) await requestCover(id);
        return new Response("done", { status: 200 });
      }
      if (r.state !== "pending") return new Response(r.state, { status: 200 });
      await new Promise((res) => setTimeout(res, 3_000));
    }
    return new Response("pending", { status: 200 });
  } catch (e) {
    console.error("acestep hook finish failed", (e as Error).message);
    return new Response("retry", { status: 500 });
  }
});
