// deno test supabase/functions/_shared/cover_test.ts
import { assert, assertEquals } from "jsr:@std/assert@1";
import { coverPrompt, sanitizeSvg } from "./cover.ts";

const good = `Here you go:
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" onload="alert(1)">
  <defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ff4f8b"/><stop offset="1" stop-color="#2ec4b6"/></linearGradient></defs>
  <rect width="512" height="512" fill="url(#g)"/>
  <circle cx="256" cy="200" r="80" fill="#ffb627" style="fill:red"/>
  <path d="M0 400 L512 380 L512 512 L0 512 Z" fill="#14121a"/>
  <script>alert(1)</script>
  <text x="10" y="10">Title</text>
  <image href="https://evil.example/x.png"/>
  <rect width="10" height="10" fill="url(https://evil.example/x)"/>
</svg> enjoy`;

Deno.test("sanitizeSvg keeps shapes and gradients, drops scripts, text, images and outside urls", () => {
  const svg = sanitizeSvg(good)!;
  assert(svg.startsWith('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">'));
  assert(svg.includes('<linearGradient id="g"'));
  assert(svg.includes('fill="url(#g)"'));
  assert(svg.includes("<circle"));
  for (const bad of ["script", "alert", "onload", "<text", "Title", "<image", "evil", "style="]) {
    assert(!svg.includes(bad), bad);
  }
  assert(svg.endsWith("</svg>"));
});

Deno.test("sanitizeSvg rejects replies without a picture", () => {
  assertEquals(sanitizeSvg("sorry, I can't"), null);
  assertEquals(sanitizeSvg('<svg viewBox="0 0 512 512"><rect width="1" height="1"/></svg>'), null);
});

Deno.test("sanitizeSvg closes unclosed groups and adds a viewBox", () => {
  const svg = sanitizeSvg('<svg><g><rect width="1" height="1"/><circle r="1"/><ellipse rx="1" ry="1"/></svg>')!;
  assertEquals(
    svg,
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><g><rect width="1" height="1"/><circle r="1"/><ellipse rx="1" ry="1"/></g></svg>',
  );
});

Deno.test("coverPrompt leaves lyrics out of instrumentals", () => {
  const p = coverPrompt({ title: "海邊", style: "City Pop", lyrics: "浪花", instrumental: true });
  assert(p.includes("instrumental"));
  assert(!p.includes("浪花"));
});
