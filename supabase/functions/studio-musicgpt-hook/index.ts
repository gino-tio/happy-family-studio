// studio-musicgpt-hook — MusicGPT calls this when a task (or part of it) is ready.
// verify_jwt is off because MusicGPT can't send a Supabase token, and its webhooks are unsigned,
// so the body is only a nudge: we take its task_id, then read the real result from MusicGPT with
// our own key (finishMusicGpt). A task id that isn't one of our 'generating' songs does nothing.

import { createClient } from "jsr:@supabase/supabase-js@2";
import { finishMusicGpt } from "../studio-generate-song/providers/musicgpt.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("POST only", { status: 405 });
  const key = Deno.env.get("STUDIO_MUSICGPT_KEY");
  if (!key) return new Response("not configured", { status: 503 });
  let taskId = "";
  try {
    const text = await req.text();
    if (text.length > 200_000) return new Response("too large", { status: 413 });
    let body: Record<string, unknown> = {};
    try {
      body = JSON.parse(text);
    } catch {
      body = Object.fromEntries(new URLSearchParams(text));
    }
    taskId = typeof body.task_id === "string" ? body.task_id : "";
  } catch {
    // fall through
  }
  if (!/^[A-Za-z0-9-]{8,80}$/.test(taskId)) return new Response("ok", { status: 200 });
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  try {
    const r = await finishMusicGpt(admin, "app_studio", "studio-songs", key, taskId);
    return new Response(r, { status: 200 });
  } catch (e) {
    console.error("musicgpt hook finish failed", (e as Error).message);
    return new Response("retry", { status: 500 });
  }
});
