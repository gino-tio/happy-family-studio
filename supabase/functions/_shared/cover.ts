// Song covers (Gino, 2026-11-14). A cover is one object in the private `studio-covers` bucket,
// named in songs.cover_path. MusicGPT songs get MusicGPT's own album cover (.jpg); every other
// song, and "換封面", gets a picture Claude draws as SVG through the TIO AI Hub chat route
// (the same Hub key as studio-write-lyrics). The SVG is rebuilt from an allow-list of shapes and
// attributes, so nothing but shapes, gradients and colours ever reaches the bucket.

// deno-lint-ignore-file no-explicit-any

export const COVER_BUCKET = "studio-covers";

/** What the cover prompt needs from a song row. */
export interface CoverSong {
  title: string;
  style: string;
  lyrics: string;
  instrumental: boolean;
}

export const COVER_SYSTEM = `You design square album covers as SVG for a Hong Kong family band's songs.
Reply with ONE complete SVG document and nothing else: <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">…</svg>.
Style: bold modern album art, like a streaming-service cover. Fill the whole 512x512 square edge to edge (start with a full-size background rect or gradient). Use 3–6 harmonious colours, smooth linear/radial gradients, large simple shapes and a clear focal motif that fits the song's mood and story (a sunset, a city skyline, a wave, a heart, a guitar, stars, a bus, a moon…). Depth from overlapping shapes and opacity.
Allowed elements only: svg, g, defs, linearGradient, radialGradient, stop, rect, circle, ellipse, path, polygon, polyline, line.
No text, no letters, no numbers, no <text>, no images, no filters, no masks, no clipPath, no scripts, no CSS, no style attribute, no external links. Under 12000 characters.`;

export function coverPrompt(song: CoverSong, variant = ""): string {
  const lyrics = song.instrumental ? "(instrumental, no lyrics)" : song.lyrics.trim().slice(0, 1500);
  return [
    `Song title: ${song.title.slice(0, 120)}`,
    `Style: ${song.style.trim().slice(0, 400) || "(not given)"}`,
    `Lyrics:\n${lyrics || "(none)"}`,
    variant ? `Make this one different from earlier covers: ${variant}` : "",
    "Draw the cover now. Reply with the SVG only.",
  ].filter(Boolean).join("\n\n");
}

const ELEMENTS = new Set([
  "svg", "g", "defs", "lineargradient", "radialgradient", "stop",
  "rect", "circle", "ellipse", "path", "polygon", "polyline", "line",
]);
const CANON: Record<string, string> = { lineargradient: "linearGradient", radialgradient: "radialGradient" };
const ATTRS = new Set([
  "id", "viewbox", "width", "height", "x", "y", "x1", "y1", "x2", "y2", "cx", "cy", "r", "rx", "ry",
  "fx", "fy", "d", "points", "fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin",
  "opacity", "fill-opacity", "stroke-opacity", "offset", "stop-color", "stop-opacity",
  "gradientunits", "gradienttransform", "transform", "fill-rule", "spreadmethod",
]);
const ATTR_CANON: Record<string, string> = {
  viewbox: "viewBox", gradientunits: "gradientUnits", gradienttransform: "gradientTransform",
  spreadmethod: "spreadMethod",
};

/** Plain value: colours, numbers, path data, ids, or a local gradient reference url(#id). */
function safeValue(v: string): boolean {
  if (v.length > 6000) return false;
  if (/[<>"'`\\]/.test(v)) return false;
  const urls = v.match(/url\(([^)]*)\)/gi) ?? [];
  if (urls.some((u) => !/^url\(#[A-Za-z0-9_-]{1,40}\)$/i.test(u))) return false;
  if (/(javascript|data|expression|https?)\s*:/i.test(v)) return false;
  return true;
}

/**
 * Rebuilds the model's SVG from allowed elements and attributes only. Returns null when there is
 * no usable picture (no svg root, nothing drawn, or too big).
 */
export function sanitizeSvg(raw: string): string | null {
  const start = raw.search(/<svg[\s>]/i);
  const end = raw.toLowerCase().lastIndexOf("</svg>");
  if (start < 0 || end < start) return null;
  const src = raw.slice(start, end + 6).replace(/<!--[\s\S]*?-->/g, "");
  const out: string[] = [];
  const stack: string[] = [];
  let skipDepth = 0; // inside an element we drop, with all its children
  let shapes = 0;
  const tagRe = /<(\/?)([A-Za-z][A-Za-z0-9:-]*)((?:\s+[A-Za-z_:][A-Za-z0-9_.:-]*\s*=\s*(?:"[^"]*"|'[^']*'))*)\s*(\/?)>/g;
  let m: RegExpExecArray | null;
  while ((m = tagRe.exec(src)) !== null) {
    const closing = m[1] === "/";
    const name = m[2].toLowerCase();
    const selfClose = m[4] === "/";
    const allowed = ELEMENTS.has(name);
    if (closing) {
      if (skipDepth > 0) {
        skipDepth--;
        continue;
      }
      if (allowed && stack.includes(name)) {
        // Close anything left open inside it, then the element itself.
        while (stack.length) {
          const n = stack.pop()!;
          out.push(`</${CANON[n] ?? n}>`);
          if (n === name) break;
        }
        if (!stack.length) break; // the root <svg> is closed: ignore anything after it
      }
      continue;
    }
    if (skipDepth > 0 || !allowed) {
      if (!selfClose) skipDepth++;
      continue;
    }
    if (name === "svg" && stack.length > 0) {
      if (!selfClose) skipDepth++;
      continue;
    }
    if (name !== "svg" && stack.length === 0) continue;
    const attrs: string[] = [];
    if (name === "svg") attrs.push('xmlns="http://www.w3.org/2000/svg"');
    const attrRe = /([A-Za-z_:][A-Za-z0-9_.:-]*)\s*=\s*(?:"([^"]*)"|'([^']*)')/g;
    let a: RegExpExecArray | null;
    while ((a = attrRe.exec(m[3])) !== null) {
      const an = a[1].toLowerCase();
      const av = (a[2] ?? a[3] ?? "").trim();
      if (!ATTRS.has(an) || !safeValue(av)) continue;
      if (name === "svg" && (an === "width" || an === "height")) continue;
      attrs.push(`${ATTR_CANON[an] ?? an}="${av}"`);
    }
    if (name === "svg" && !attrs.some((x) => x.startsWith("viewBox="))) attrs.push('viewBox="0 0 512 512"');
    if (["rect", "circle", "ellipse", "path", "polygon", "polyline", "line"].includes(name)) shapes++;
    const tag = `<${CANON[name] ?? name}${attrs.length ? " " + attrs.join(" ") : ""}`;
    if (selfClose) {
      out.push(`${tag}/>`);
    } else {
      out.push(`${tag}>`);
      stack.push(name);
    }
  }
  while (stack.length) {
    const n = stack.pop()!;
    out.push(`</${CANON[n] ?? n}>`);
  }
  const svg = out.join("");
  if (!svg.startsWith("<svg") || shapes < 3 || svg.length > 60_000) return null;
  return svg;
}

/** Asks Claude (through the Hub) for a cover and returns the cleaned SVG. */
export async function drawCoverSvg(song: CoverSong, variant = ""): Promise<string> {
  const hubKey = Deno.env.get("STUDIO_HUB_API_KEY");
  if (!hubKey) throw new Error("STUDIO_HUB_API_KEY is not set");
  const hub = Deno.env.get("STUDIO_HUB_URL") ?? "https://tio-ai-hub.fly.dev";
  const res = await fetch(`${hub}/api/v1/llm/studio/chat`, {
    method: "POST",
    headers: { Authorization: `Bearer ${hubKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: "smart",
      max_tokens: 6000,
      timeoutMs: 110_000,
      messages: [
        { role: "system", content: COVER_SYSTEM },
        { role: "user", content: coverPrompt(song, variant) },
      ],
    }),
    signal: AbortSignal.timeout(120_000),
  });
  if (!res.ok) throw new Error(`hub ${res.status}`);
  const body = await res.json() as any;
  const svg = sanitizeSvg(String(body?.choices?.[0]?.message?.content ?? ""));
  if (!svg) throw new Error("the AI reply had no usable picture");
  return svg;
}

/**
 * Stores a cover for one song and points songs.cover_path at it; the song's earlier cover file
 * is removed. `admin` is a service-role client.
 */
export async function storeCover(
  admin: any,
  songId: string,
  bytes: Uint8Array,
  ext: "svg" | "jpg" | "png" | "webp",
  onlyIfEmpty = false,
): Promise<string | null> {
  const db = admin.schema("app_studio");
  const { data: song } = await db.from("songs").select("cover_path").eq("id", songId).maybeSingle();
  if (!song) return null;
  if (onlyIfEmpty && song.cover_path) return null;
  const type = { svg: "image/svg+xml", jpg: "image/jpeg", png: "image/png", webp: "image/webp" }[ext];
  const path = `${songId}/${crypto.randomUUID()}.${ext}`;
  const { error } = await admin.storage.from(COVER_BUCKET).upload(path, bytes, { contentType: type, upsert: false });
  if (error) throw error;
  let q = db.from("songs").update({ cover_path: path }).eq("id", songId);
  if (onlyIfEmpty) q = q.is("cover_path", null);
  const { data: updated } = await q.select("id");
  if (!updated?.length) {
    await admin.storage.from(COVER_BUCKET).remove([path]);
    return null;
  }
  if (song.cover_path) await admin.storage.from(COVER_BUCKET).remove([song.cover_path]);
  return path;
}

/** Draws an SVG cover with Claude and stores it. */
export async function drawAndStoreCover(admin: any, songId: string, song: CoverSong, opts: {
  onlyIfEmpty?: boolean;
  variant?: string;
} = {}): Promise<string | null> {
  const svg = await drawCoverSvg(song, opts.variant ?? "");
  return storeCover(admin, songId, new TextEncoder().encode(svg), "svg", opts.onlyIfEmpty ?? false);
}

/** Downloads a picture from a vendor URL (https only, image types, at most 5 MB). */
export async function fetchCoverImage(url: string): Promise<{ bytes: Uint8Array; ext: "jpg" | "png" | "webp" } | null> {
  if (!/^https:\/\//.test(url)) return null;
  const res = await fetch(url, { signal: AbortSignal.timeout(30_000) });
  if (!res.ok) return null;
  const bytes = new Uint8Array(await res.arrayBuffer());
  if (bytes.length < 100 || bytes.length > 5 * 1024 * 1024) return null;
  if (bytes[0] === 0xff && bytes[1] === 0xd8) return { bytes, ext: "jpg" };
  if (bytes[0] === 0x89 && bytes[1] === 0x50) return { bytes, ext: "png" };
  if (String.fromCharCode(...bytes.slice(8, 12)) === "WEBP") return { bytes, ext: "webp" };
  return null;
}

/**
 * Asks studio-song-cover (its own worker, 150 s of its own) to give a song a cover if it still
 * has none. Uses the service role key; never throws.
 */
export async function requestCover(songId: string): Promise<void> {
  try {
    const res = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/studio-song-cover`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ song_id: songId, auto: true }),
      signal: AbortSignal.timeout(15_000),
    });
    if (res.status !== 202) console.error("cover request status", res.status);
  } catch (e) {
    console.error("cover request failed", (e as Error).name);
  }
}
