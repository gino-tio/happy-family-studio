// deno test supabase/functions/generate-song/index_test.ts
import { assertEquals } from "jsr:@std/assert@1";
import { buildPrompt } from "./providers/elevenlabs.ts";

Deno.test("buildPrompt drops lyrics for instrumentals", () => {
  const p = buildPrompt({
    title: "t", style: "90s HK guitar rock", lyrics: "星期六", instrumental: true, lengthMs: null,
  });
  assertEquals(p, "90s HK guitar rock");
});

Deno.test("buildPrompt includes lyrics after style", () => {
  const p = buildPrompt({
    title: "t", style: "rock", lyrics: "星期六 星期六", instrumental: false, lengthMs: null,
  });
  assertEquals(p.startsWith("rock\n\nSung in Cantonese"), true);
  assertEquals(p.endsWith("星期六 星期六"), true);
});
