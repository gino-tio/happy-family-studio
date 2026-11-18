// Pure parts of the 出譜 page (no DOM): turn MusicGPT's Audio-to-MIDI notes, or the drum
// track's audio, into alphaTex for alphaTab. Tested with `deno test web/sheet/`.
//
// AI transcription is rough (Gino was told "大致啱、要人手執"), so this keeps it simple:
// one voice, a 16th-note grid, notes cut at the next onset, out-of-range notes moved by octaves.

export const STEPS_PER_BAR = 16; // 4/4 in 16ths

/** Tunings, low string first, as MIDI numbers. alphaTex lists them high string first. */
export const TUNINGS = {
  guitar: { midi: [40, 45, 50, 55, 59, 64], tex: "e4 b3 g3 d3 a2 e2" },
  bass: { midi: [28, 33, 38, 43], tex: "g2 d2 a1 e1" },
};
export const MAX_FRET = 15;

const NAMES = ["c", "c#", "d", "d#", "e", "f", "f#", "g", "g#", "a", "a#", "b"];
/** MIDI 60 → "c4" (alphaTex pitched note names). */
export function noteName(midi) {
  return `${NAMES[midi % 12]}${Math.floor(midi / 12) - 1}`;
}

/** Seconds → 16th-note step at a tempo, counted from t0. */
export function toStep(t, bpm, t0 = 0) {
  return Math.round(((t - t0) * bpm) / 60 * 4);
}

/**
 * Notes [{midi, time, duration}] (seconds) → events [{step, len, notes:[midi]}] on a 16th grid.
 * Notes starting on the same step become a chord; each event lasts until the next one starts or
 * its longest note ends (at least one step, at most a bar).
 */
export function quantize(notes, bpm, t0 = 0) {
  const byStep = new Map();
  for (const n of notes) {
    if (!(n.duration > 0.03)) continue; // drop blips
    const step = Math.max(0, toStep(n.time, bpm, t0));
    const end = Math.max(step + 1, toStep(n.time + n.duration, bpm, t0));
    const e = byStep.get(step) ?? { step, end, notes: [] };
    e.end = Math.max(e.end, end);
    if (!e.notes.includes(n.midi)) e.notes.push(n.midi);
    byStep.set(step, e);
  }
  const events = [...byStep.values()].sort((a, b) => a.step - b.step);
  return events.map((e, i) => {
    const next = events[i + 1]?.step ?? Infinity;
    const len = Math.max(1, Math.min(e.end, next, e.step + STEPS_PER_BAR) - e.step);
    return { step: e.step, len, notes: e.notes.sort((a, b) => a - b).slice(0, 6) };
  });
}

/** Moves a note by octaves into [lo, hi]. */
export function fold(midi, lo, hi) {
  let m = midi;
  while (m < lo) m += 12;
  while (m > hi) m -= 12;
  return m < lo ? lo : m;
}

/**
 * Frets for a chord on a stringed instrument: [{fret, string}] with string 1 = highest.
 * Greedy: lowest note on the lowest string that can play it, each string once.
 */
export function assignFrets(notes, tuningMidi) {
  const lo = tuningMidi[0];
  const hi = tuningMidi[tuningMidi.length - 1] + MAX_FRET;
  const used = new Set();
  const out = [];
  for (const raw of [...notes].sort((a, b) => a - b)) {
    const m = fold(raw, lo, hi);
    let best = -1;
    for (let s = 0; s < tuningMidi.length; s++) {
      const fret = m - tuningMidi[s];
      if (fret < 0 || fret > MAX_FRET || used.has(s)) continue;
      // Prefer the lowest fret that keeps hands near the nut.
      if (best < 0 || fret < m - tuningMidi[best]) best = s;
    }
    if (best < 0) continue;
    used.add(best);
    out.push({ fret: m - tuningMidi[best], string: tuningMidi.length - best });
  }
  return out;
}

/** Splits a length in 16ths into alphaTex durations (16 → 1, 8 → 2, 4 → 4, 2 → 8, 1 → 16). */
export function splitLen(len) {
  const parts = [];
  for (const [steps, dur] of [[16, 1], [8, 2], [4, 4], [2, 8], [1, 16]]) {
    while (len >= steps) {
      parts.push(dur);
      len -= steps;
    }
  }
  return parts;
}

/**
 * Events → alphaTex beats for one bar-ordered voice. `noteText(notes, tied)` writes one beat's
 * notes ("3.2" or "(3.2 5.1)"); rests fill gaps; a note held across a split or a barline is tied.
 */
export function eventsToBars(events, noteText, totalSteps) {
  const bars = [];
  let cur = [];
  let pos = 0;
  const end = Math.max(totalSteps ?? 0, events.length ? events[events.length - 1].step + events[events.length - 1].len : 0);
  const barsNeeded = Math.max(1, Math.ceil(end / STEPS_PER_BAR));
  const push = (text, steps, tiedFirst) => {
    // Split at barlines, then into note values.
    let first = true;
    while (steps > 0) {
      const room = STEPS_PER_BAR - (pos % STEPS_PER_BAR);
      const take = Math.min(room, steps);
      for (const dur of splitLen(take)) {
        cur.push(text(first ? tiedFirst : true) + `.${dur}`);
        first = false;
      }
      pos += take;
      steps -= take;
      if (pos % STEPS_PER_BAR === 0) {
        bars.push(cur.join(" "));
        cur = [];
      }
    }
  };
  for (const e of events) {
    if (e.step > pos) push(() => "r", e.step - pos, false);
    if (e.step < pos) continue; // overlaps the previous event: drop
    push((tied) => noteText(e.notes, tied), e.len, false);
  }
  const fill = barsNeeded * STEPS_PER_BAR - pos;
  if (fill > 0) push(() => "r", fill, false);
  return bars;
}

const TITLES = {
  vocals: "人聲旋律",
  piano: "鋼琴",
  bass: "Bass",
  guitar: "結他",
  drums: "鼓",
};

function texString(s) {
  return `"${String(s).replace(/["\\]/g, "")}"`;
}

/** Pitched notes → full alphaTex (tab + staff for guitar and bass, staff for the rest). */
export function pitchedTex(kind, notes, bpm, t0, title) {
  const events = quantize(notes, bpm, t0);
  const tuning = TUNINGS[kind];
  let head = `\\title ${texString(title)}\n\\subtitle ${texString(TITLES[kind] ?? kind)}\n\\tempo ${Math.round(bpm)}\n`;
  head += `\\track ${texString(TITLES[kind] ?? kind)}\n`;
  let noteText;
  if (tuning) {
    head += `\\staff {score tabs}\n\\tuning (${tuning.tex})\n`;
    noteText = (ns, tied) => {
      const frets = assignFrets(ns, tuning.midi);
      if (!frets.length) return "r";
      const t = frets.map((f) => `${f.fret}.${f.string}${tied ? "{t}" : ""}`);
      return t.length === 1 ? t[0] : `(${t.join(" ")})`;
    };
  } else {
    const avg = notes.length ? notes.reduce((a, n) => a + n.midi, 0) / notes.length : 60;
    head += `\\staff {score}\n`;
    if (avg < 55) head += `\\clef F4\n`;
    noteText = (ns, tied) => {
      const t = ns.map((m) => `${noteName(fold(m, 21, 108))}${tied ? "{t}" : ""}`);
      return t.length === 1 ? t[0] : `(${t.join(" ")})`;
    };
  }
  const bars = eventsToBars(events, noteText);
  // A tie on a rest or a tie whose source changed pitch is ignored by alphaTab; keep it simple.
  return head + bars.join(" |\n") + " |";
}

/** Drum hits [{part:'kick'|'snare'|'hihat', time}] → percussion alphaTex. */
export function drumTex(hits, bpm, t0, title) {
  const byStep = new Map();
  for (const h of hits) {
    const step = Math.max(0, toStep(h.time, bpm, t0));
    const set = byStep.get(step) ?? new Set();
    set.add(h.part);
    byStep.set(step, set);
  }
  const events = [...byStep.entries()].sort((a, b) => a[0] - b[0]).map(([step, parts], i, all) => {
    const next = all[i + 1]?.[0] ?? step + 1;
    return { step, len: Math.max(1, Math.min(next - step, 4)), notes: [...parts].sort() };
  });
  let head = `\\title ${texString(title)}\n\\subtitle "鼓譜"\n\\tempo ${Math.round(bpm)}\n`;
  head += `\\track "鼓"\n\\instrument percussion\n\\staff {score}\n\\clef neutral\n`;
  head += `\\articulation (kick 36)\n\\articulation (snare 38)\n\\articulation (hihat 42)\n`;
  const noteText = (ns) => (ns.length === 1 ? ns[0] : `(${ns.join(" ")})`);
  return head + eventsToBars(events, (ns, tied) => (tied ? "r" : noteText(ns))).join(" |\n") + " |";
}

/**
 * Onsets in an energy envelope (one value per hop): local peaks of the positive change that stand
 * above a moving median. Returns frame indexes.
 */
export function onsets(env, { minGapFrames = 5, sensitivity = 1.5, floor = 0.02 } = {}) {
  const flux = env.map((v, i) => Math.max(0, v - (env[i - 1] ?? v)));
  const max = Math.max(...flux, 1e-9);
  const out = [];
  const W = 16;
  for (let i = 1; i < flux.length - 1; i++) {
    if (flux[i] < flux[i - 1] || flux[i] < flux[i + 1]) continue;
    const win = flux.slice(Math.max(0, i - W), i + W).sort((a, b) => a - b);
    const med = win[win.length >> 1];
    if (flux[i] < floor * max || flux[i] < sensitivity * med + floor * max * 0.5) continue;
    if (out.length && i - out[out.length - 1] < minGapFrames) continue;
    out.push(i);
  }
  return out;
}

/** Tempo (BPM, 70–180) from onset times, by the best-scoring beat grid. Null if too few. */
export function estimateBpm(times) {
  if (times.length < 8) return null;
  let best = null;
  for (let bpm = 70; bpm <= 180; bpm += 0.5) {
    const beat = 60 / bpm;
    // Score: how close onsets fall to 8th-note grid lines, for the best phase.
    let bestPhase = 0;
    for (let k = 0; k < 8; k++) {
      const phase = (k / 8) * (beat / 2);
      let s = 0;
      for (const t of times) {
        const x = ((t - phase) / (beat / 2)) % 1;
        const d = Math.min(x, 1 - x);
        s += Math.exp(-(d * d) / 0.005);
      }
      bestPhase = Math.max(bestPhase, s);
    }
    // Mild preference for common pop tempos so 2x / 0.5x ambiguity lands on 80–140.
    const score = bestPhase * (bpm >= 80 && bpm <= 140 ? 1.05 : 1);
    if (!best || score > best.score) best = { bpm, score };
  }
  return best.bpm;
}
