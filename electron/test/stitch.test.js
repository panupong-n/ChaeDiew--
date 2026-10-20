'use strict';
// Run: node test/stitch.test.js — scrolling-capture stitching, the same cases as the native ChaeDiewChecks "Scroll stitching" section.
const { Stitcher, rowHashes } = require('../renderer/stitch');

let passed = 0;
function check(name, ok, detail) {
  if (ok) { passed++; console.log('PASS  ' + name); } else { console.log('FAIL  ' + name + (detail !== undefined ? '  —  ' + JSON.stringify(detail) : '')); process.exitCode = 1; }
}

/** A tall "web page": blank margins, lines of text-like blocks of varying length, a few coloured bands. Deterministic per seed. */
function makePage(width, height, seed = 7) {
  let s = seed;
  const rnd = () => (s = (s * 1103515245 + 12345) >>> 0) / 4294967296;
  const data = new Uint8ClampedArray(width * height * 4).fill(255);
  let y = 0;
  while (y < height) {
    const kind = rnd();
    const h = 6 + Math.floor(rnd() * 14);
    if (kind < 0.55) {         // a text line
      const len = Math.floor(width * (0.3 + rnd() * 0.6));
      for (let yy = y; yy < Math.min(height, y + h); yy++) for (let x = 8; x < 8 + len; x++) {
        if (((x * 31 + yy * 17 + Math.floor(rnd() * 3)) % 7) < 3) { const i = (yy * width + x) * 4; data[i] = data[i + 1] = data[i + 2] = 30 + Math.floor(rnd() * 40); }
      }
    } else if (kind < 0.7) {   // a coloured band
      const c = [Math.floor(rnd() * 255), Math.floor(rnd() * 255), Math.floor(rnd() * 255)];
      for (let yy = y; yy < Math.min(height, y + h); yy++) for (let x = 0; x < width; x++) { const i = (yy * width + x) * 4; data[i] = c[0]; data[i + 1] = c[1]; data[i + 2] = (c[2] + yy) & 255; }
    }
    y += h + Math.floor(rnd() * 10);       // blank gap
  }
  return { data, width, height };
}
/** The native check's page: every row random, two blank bands (300–339, 900–959). */
function nativePage(width, height) {
  const data = new Uint8ClampedArray(width * height * 4).fill(255);
  let st = 0x9E3779B9n * 0x100000000n + 0x7F4A7C15n;
  for (let y = 0; y < height; y++) {
    if ((y >= 300 && y < 340) || (y >= 900 && y < 960)) continue;
    for (let x = 0; x < width; x++) {
      st = (st * 6364136223846793005n + 1442695040888963407n) & 0xFFFFFFFFFFFFFFFFn;
      const v = Number((st >> 33n) & 255n), i = (y * width + x) * 4;
      data[i] = v; data[i + 1] = (v + 40) & 255; data[i + 2] = (v + 90) & 255;
    }
  }
  return { data, width, height };
}
function frameOf(page, offset, height, sticky) {
  const f = { data: page.data.slice(offset * page.width * 4, (offset + height) * page.width * 4), width: page.width, height };
  if (sticky) f.data.set(sticky.data, 0);
  return f;
}
const same = (a, b) => a.length === b.length && a.every((v, i) => v === b[i]);

let j;
for (const [name, page] of [['native test page', nativePage(120, 1500)], ['page with white space', makePage(120, 1500)]]) {
  const pageHashes = rowHashes(page);
  const down = new Stitcher();
  for (const off of [0, 130, 260, 500, 640, 900, 1100]) down.add(frameOf(page, off, 400));
  j = down.finish();
  check(`${name}, scroll down: stitched height equals the page`, j && j.height === 1500, j && j.height);
  check(`${name}, scroll down: every row matches the original page`, j && same(rowHashes(j), pageHashes));
  const up = new Stitcher();
  for (const off of [1100, 900, 640, 500, 260, 130, 0]) up.add(frameOf(page, off, 400));
  j = up.finish();
  check(`${name}, scroll up: stitched height equals the page`, j && j.height === 1500, j && j.height);
  check(`${name}, scroll up: every row matches the original page`, j && same(rowHashes(j), pageHashes));
  const header = { data: page.data.slice(0, 120 * 30 * 4) };
  const sticky = new Stitcher();
  for (const off of [0, 130, 260, 500, 640]) sticky.add(frameOf(page, off, 400, header));
  j = sticky.finish();
  check(`${name}, sticky header: height is right`, j && j.height === 1040, j && j.height);
  check(`${name}, sticky header: content below the header is seamless`, j && same(rowHashes(j).slice(30, 1040), pageHashes.slice(30, 1040)));
}
const page = nativePage(120, 1500);

const probe = new Stitcher();
probe.add(frameOf(page, 0, 400));
check('identical frame reports no change', probe.add(frameOf(page, 0, 400)) === 'noChange');
check('a jump larger than the overlap is rejected, not guessed', probe.add(frameOf(page, 395, 400)) === 'unmatched');
check('an unrelated frame is rejected', probe.add(makePage(120, 400, 12345)) === 'unmatched');
check("a rejected frame doesn't grow the result", probe.totalHeight === 400);
const capped = new Stitcher(500);
capped.add(frameOf(page, 0, 400));
check('height limit stops growth', capped.add(frameOf(page, 200, 400)) === 'limitReached');

console.log(`\n${process.exitCode ? 'SOME CHECKS FAILED' : 'All checks passed.'} (${passed} passed)`);
