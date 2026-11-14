// deno test supabase/functions/studio-generate-song/index_test.ts
import { assertEquals } from "jsr:@std/assert@1";
import { buildPrompt } from "./providers/elevenlabs.ts";
import { musicgptBody, parseByIdReply } from "./providers/musicgpt.ts";

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



Deno.test("musicgptBody asks for Cantonese, picks the voice from the style, adds the webhook", () => {
  const b = musicgptBody({
    title: "海邊", style: "City Pop, female vocal", lyrics: "[Verse]\n浪花", instrumental: false, lengthMs: 60000, provider: "musicgpt",
  }, "v6", "https://x.supabase.co/functions/v1/studio-musicgpt-hook");
  assertEquals((b.prompt as string).startsWith("Cantonese (Hong Kong Cantopop) vocals"), true);
  assertEquals(b.gender, "female");
  assertEquals(b.lyrics, "[Verse]\n浪花");
  assertEquals(b.make_instrumental, false);
  assertEquals(b.webhook_url, "https://x.supabase.co/functions/v1/studio-musicgpt-hook");
});

Deno.test("parseByIdReply reads both documented shapes", () => {
  assertEquals(parseByIdReply({ conversion: { status: "IN_QUEUE" } }), { state: "pending" });
  assertEquals(parseByIdReply({ conversion: { status: "FAILED", status_msg: "flagged" } }), { state: "failed", error: "flagged" });
  assertEquals(
    parseByIdReply({ conversion: { status: "COMPLETED", conversion_path_1: "https://c/a.mp3", conversion_path_2: "https://c/b.mp3" } }),
    { state: "done", urls: ["https://c/a.mp3", "https://c/b.mp3"] },
  );
  assertEquals(parseByIdReply({ conversion: { status: "COMPLETED", audio_url: "https://c/a.mp3" } }), { state: "done", urls: ["https://c/a.mp3"] });
  assertEquals(parseByIdReply({ conversion: { status: "COMPLETED" } }), { state: "pending" });
});
