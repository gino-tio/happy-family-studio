// deno test supabase/functions/studio-write-lyrics/lyrics_test.ts
import { assertEquals } from "jsr:@std/assert@1";
import { parseLyricsReply, parseLyricsRequest, sectionPlan, userPrompt } from "./lyrics.ts";

Deno.test("parseLyricsRequest checks the input", () => {
  assertEquals(parseLyricsRequest({ topic: "" }), "topic is required (1–500 chars)");
  assertEquals(parseLyricsRequest({ topic: "x", seconds: 5 }), "seconds must be between 10 and 300");
  assertEquals(parseLyricsRequest({ topic: " 去海邊 ", seconds: 60.4 }), {
    topic: "去海邊", style: "", title: "", seconds: 60,
  });
});

Deno.test("sectionPlan fits the length", () => {
  assertEquals(sectionPlan(30), "[Verse 1], [Chorus]");
  assertEquals(sectionPlan(120).includes("[Bridge]"), true);
});

Deno.test("userPrompt keeps a given title, else asks for one", () => {
  const base = { topic: "叮叮返學", style: "", title: "", seconds: 60 };
  assertEquals(userPrompt(base).includes("suggest a short Chinese title"), true);
  assertEquals(userPrompt({ ...base, title: "返學" }).includes("Title (keep it): 返學"), true);
});

Deno.test("parseLyricsReply reads fenced JSON and keeps the member's title", () => {
  const reply = '```json\n{"title": "海邊", "lyrics": "[Verse 1]\\n浪花拍岸"}\n```';
  assertEquals(parseLyricsReply(reply, ""), { title: "海邊", lyrics: "[Verse 1]\n浪花拍岸" });
  assertEquals(parseLyricsReply(reply, "我嘅歌")?.title, "我嘅歌");
  assertEquals(parseLyricsReply("sorry", ""), null);
  assertEquals(parseLyricsReply('{"title":"x","lyrics":""}', ""), null);
});
