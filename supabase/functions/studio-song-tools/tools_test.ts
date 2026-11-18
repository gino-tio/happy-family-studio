// deno test supabase/functions/studio-song-tools/tools_test.ts
import { assertEquals } from "jsr:@std/assert@1";
import { audioTypeFor, findStemUrls, parseStemsReply, parseToolRequest, vocalPrompt } from "./tools.ts";
import { conversionTypeFor } from "../studio-generate-song/providers/musicgpt.ts";

const U = "00000000-0000-4000-8000-00000000000a";
const S = "11111111-1111-4111-8111-111111111111";

Deno.test("findStemUrls names urls by key", () => {
  const urls = findStemUrls({
    status: "COMPLETED",
    vocals_path: "https://cdn.example/x/a.mp3",
    instrumental_path: "https://cdn.example/x/b.mp3",
    bass: "https://cdn.example/x/c.wav",
    title: "not a url",
  });
  assertEquals(urls, {
    vocals: "https://cdn.example/x/a.mp3",
    instrumental: "https://cdn.example/x/b.mp3",
    bass: "https://cdn.example/x/c.wav",
  });
});

Deno.test("findStemUrls reads JSON strings and file names", () => {
  const urls = findStemUrls({
    conversion_path: JSON.stringify({ stems: ["https://c/1/drums.mp3", "https://c/1/guitar.mp3?sig=1"] }),
    other: [{ name: "piano", url: "https://c/1/p.mp3" }],
  });
  assertEquals(urls.drums, "https://c/1/drums.mp3");
  assertEquals(urls.guitar, "https://c/1/guitar.mp3?sig=1");
  assertEquals(urls.piano, "https://c/1/p.mp3");
});

Deno.test("parseStemsReply states", () => {
  assertEquals(parseStemsReply({ conversion: { status: "IN_QUEUE" } }), { state: "pending" });
  assertEquals(parseStemsReply({ conversion: { status: "FAILED", status_msg: "bad" } }), { state: "failed", error: "bad" });
  assertEquals(parseStemsReply({ conversion: { status: "COMPLETED", vocals: "https://c/v.mp3" } }), {
    state: "done",
    urls: { vocals: "https://c/v.mp3" },
  });
});

Deno.test("parseToolRequest", () => {
  assertEquals(parseToolRequest({ action: "stems", song_id: S }, U), { action: "stems", songId: S });
  assertEquals(typeof parseToolRequest({ action: "swap", song_id: S, lyrics: " " }, U), "string");
  assertEquals(parseToolRequest({ action: "swap", song_id: S, lyrics: "新詞" }, U), {
    action: "swap",
    songId: S,
    lyrics: "新詞",
    title: "",
    style: null,
  });
  assertEquals(typeof parseToolRequest({ action: "remix", upload_path: `other/${S}.mp3`, title: "x" }, U), "string");
  assertEquals(typeof parseToolRequest({ action: "remix", upload_path: `${U}/a.exe`, title: "x" }, U), "string");
  assertEquals(parseToolRequest({ action: "remix", upload_path: `${U}/a.m4a`, title: "x", style: "rock" }, U), {
    action: "remix",
    uploadPath: `${U}/a.m4a`,
    title: "x",
    style: "rock",
    lyrics: "",
    instrumental: false,
  });
});

Deno.test("helpers", () => {
  assertEquals(audioTypeFor("a/b.M4A"), "audio/mp4");
  assertEquals(audioTypeFor("a/b.txt"), null);
  assertEquals(vocalPrompt(""), "Cantonese (Hong Kong Cantopop) vocals, not Mandarin.");
  assertEquals(conversionTypeFor("sing_over_instrumental"), "SING_OVER_INSTRUMENTAL");
  assertEquals(conversionTypeFor("remix"), "REMIX");
  assertEquals(conversionTypeFor("v6"), "MUSIC_AI");
});
