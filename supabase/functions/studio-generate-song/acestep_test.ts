// deno test supabase/functions/studio-generate-song/acestep_test.ts
import { assertEquals } from "jsr:@std/assert@1";
import { aceStepBody, JOB_ID, parseResultReply } from "./providers/acestep.ts";

Deno.test("aceStepBody sings in Cantonese with the lyrics, length in seconds and the webhook", () => {
  const b = aceStepBody({
    title: "舊街", style: "90s ballad, female vocal", lyrics: "[Verse]\n放學後", instrumental: false, lengthMs: 60000,
    provider: "acestep",
  }, "https://x.supabase.co/functions/v1/studio-acestep-hook");
  assertEquals(b.vocal_language, "yue");
  assertEquals((b.caption as string).startsWith("Cantopop, Hong Kong Cantonese vocals. 90s ballad"), true);
  assertEquals(b.lyrics, "[Verse]\n放學後");
  assertEquals(b.duration, 60);
  assertEquals(b.webhook_url, "https://x.supabase.co/functions/v1/studio-acestep-hook");
});

Deno.test("aceStepBody drops lyrics for instrumentals and lets the model pick the length", () => {
  const b = aceStepBody({
    title: "t", style: "city pop", lyrics: "唔使驚", instrumental: true, lengthMs: null, provider: "acestep",
  }, "https://h");
  assertEquals(b.lyrics, "");
  assertEquals(b.caption, "city pop");
  assertEquals(b.duration, null);
});

Deno.test("parseResultReply reads pending, failed and done", () => {
  assertEquals(parseResultReply({ status: "pending" }), { state: "pending" });
  assertEquals(parseResultReply({}), { state: "pending" });
  assertEquals(parseResultReply({ status: "failed", error: "OOM" }), { state: "failed", error: "OOM" });
  assertEquals(parseResultReply({ status: "done", count: 2 }), { state: "done", count: 2 });
  assertEquals(parseResultReply({ status: "done", count: 5 }), { state: "done", count: 2 });
  assertEquals(parseResultReply({ status: "done", count: 0 }), { state: "pending" });
});

Deno.test("JOB_ID accepts Modal call ids only", () => {
  assertEquals(JOB_ID.test("fc-01JABCDEFGH123456"), true);
  assertEquals(JOB_ID.test("../etc/passwd"), false);
  assertEquals(JOB_ID.test("fc-abc/../x"), false);
});
