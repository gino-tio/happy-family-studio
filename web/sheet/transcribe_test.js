// deno test web/sheet/
import { assertEquals } from "jsr:@std/assert@1";
import {
  assignFrets,
  drumTex,
  estimateBpm,
  eventsToBars,
  noteName,
  onsets,
  pitchedTex,
  quantize,
  splitLen,
} from "./transcribe.js";

Deno.test("noteName", () => {
  assertEquals(noteName(60), "c4");
  assertEquals(noteName(40), "e2");
  assertEquals(noteName(70), "a#4");
});

Deno.test("quantize groups chords and cuts at the next onset", () => {
  const bpm = 120; // a 16th = 0.125 s
  const ev = quantize([
    { midi: 60, time: 0, duration: 1 },
    { midi: 64, time: 0.01, duration: 0.5 },
    { midi: 67, time: 0.5, duration: 0.25 },
    { midi: 50, time: 0.9, duration: 0.01 }, // blip
  ], bpm);
  assertEquals(ev, [
    { step: 0, len: 4, notes: [60, 64] },
    { step: 4, len: 2, notes: [67] },
  ]);
});

Deno.test("assignFrets uses each string once, low notes on low strings", () => {
  const g = [40, 45, 50, 55, 59, 64];
  assertEquals(assignFrets([40], g), [{ fret: 0, string: 6 }]);
  assertEquals(assignFrets([64], g), [{ fret: 0, string: 1 }]);
  // E major chord: E2 B2 E3 G#3 B3 E4
  const f = assignFrets([40, 47, 52, 56, 59, 64], g);
  assertEquals(new Set(f.map((x) => x.string)).size, f.length);
  // A note far below the guitar is moved up by octaves.
  assertEquals(assignFrets([28], g), [{ fret: 0, string: 6 }]);
});

Deno.test("splitLen", () => {
  assertEquals(splitLen(16), [1]);
  assertEquals(splitLen(7), [4, 8, 16]);
});

Deno.test("eventsToBars fills rests, splits at barlines and ties", () => {
  const bars = eventsToBars(
    [{ step: 2, len: 2, notes: [60] }, { step: 14, len: 4, notes: [62] }],
    (ns, tied) => `${ns[0]}${tied ? "t" : ""}`,
  );
  assertEquals(bars, ["r.8 60.8 r.2 r.8 62.8", "62t.8 r.2 r.4 r.8"]);
});

Deno.test("pitchedTex and drumTex make alphaTex", () => {
  const g = pitchedTex("guitar", [{ midi: 64, time: 0, duration: 0.5 }], 120, 0, "測試");
  assertEquals(g.includes("\\tuning (e4 b3 g3 d3 a2 e2)"), true);
  assertEquals(g.includes("0.1.4"), true);
  const p = pitchedTex("vocals", [{ midi: 72, time: 0, duration: 0.5 }], 120, 0, "x");
  assertEquals(p.includes("c5.4"), true);
  const d = drumTex([{ part: "kick", time: 0 }, { part: "hihat", time: 0 }, { part: "snare", time: 0.5 }], 120, 0, "x");
  assertEquals(d.includes("(hihat kick).4"), true);
  assertEquals(d.includes("snare.16"), true);
});

Deno.test("onsets and estimateBpm find a steady beat", () => {
  // 100 BPM: a hit every 0.6 s, envelope at 10 ms hops.
  const env = new Array(2000).fill(0.01);
  for (let t = 0.3; t < 19; t += 0.6) env[Math.round(t / 0.01)] = 1;
  const idx = onsets(env);
  assertEquals(idx.length >= 30, true);
  const bpm = estimateBpm(idx.map((i) => i * 0.01));
  assertEquals(Math.abs(bpm - 100) <= 1, true, `bpm ${bpm}`);
});
