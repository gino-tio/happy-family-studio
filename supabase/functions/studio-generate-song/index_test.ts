// deno test supabase/functions/studio-generate-song/index_test.ts
import { assertEquals } from "jsr:@std/assert@1";
import { buildPrompt } from "./providers/elevenlabs.ts";
import { murekaBody } from "./providers/mureka.ts";

Deno.test("buildPrompt drops lyrics for instrumentals", () => {
  const p = buildPrompt({
    title: "t", style: "90s HK guitar rock", lyrics: "星期六", instrumental: true, lengthMs: null, provider: "",
  });
  assertEquals(p, "90s HK guitar rock");
});

Deno.test("buildPrompt includes lyrics after style", () => {
  const p = buildPrompt({
    title: "t", style: "rock", lyrics: "星期六 星期六", instrumental: false, lengthMs: null, provider: "",
  });
  assertEquals(p.startsWith("rock\n\nSung in Cantonese"), true);
  assertEquals(p.endsWith("星期六 星期六"), true);
});

Deno.test("murekaBody asks for Cantonese and keeps the style under 1,024 chars", () => {
  const b = murekaBody({
    title: "t", style: "x".repeat(2000), lyrics: "[Verse]\n星期六", instrumental: false, lengthMs: 60000, provider: "mureka",
  }, "mureka-9.5");
  assertEquals((b.prompt as string).startsWith("Vocals sung in Cantonese"), true);
  assertEquals((b.prompt as string).length, 1024);
  assertEquals(b.lyrics, "[Verse]\n星期六");
  assertEquals(b.duration, undefined); // under 120 s: the model decides
});

Deno.test("murekaBody: instrumental has no lyrics; duration only for 9.5 and 120–300 s", () => {
  const req = { title: "t", style: "lofi", lyrics: "唔好唱", instrumental: true, lengthMs: 400000, provider: "mureka" };
  const b = murekaBody(req, "mureka-9.5");
  assertEquals(b.lyrics, undefined);
  assertEquals(b.prompt, "Instrumental only, no vocals. lofi");
  assertEquals(b.duration, 300);
  assertEquals(murekaBody(req, "mureka-9").duration, undefined);
});
