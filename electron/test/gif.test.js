'use strict';
// Run: node test/gif.test.js — the before/after GIF writer, decoded again by an independent reader written here from the GIF89a spec.
const GIF = require('../renderer/gif');

let passed = 0;
function check(name, ok, detail) {
  if (ok) { passed++; console.log('PASS  ' + name); } else { console.log('FAIL  ' + name + (detail !== undefined ? '  —  ' + JSON.stringify(detail) : '')); process.exitCode = 1; }
}

/** Minimal GIF89a reader: global palette, NETSCAPE loop, graphic-control delays, LZW frames → RGB arrays. */
function decode(bytes) {
  let p = 0;
  const u8 = () => bytes[p++], u16 = () => { const v = bytes[p] | bytes[p + 1] << 8; p += 2; return v; };
  const sig = String.fromCharCode(...bytes.slice(0, 6)); p = 6;
  const w = u16(), h = u16(), flags = u8(); u8(); u8();
  const pal = [];
  if (flags & 0x80) for (let i = 0; i < 1 << ((flags & 7) + 1); i++) pal.push([u8(), u8(), u8()]);
  const frames = [], delays = []; let loop = null;
  for (;;) {
    const b = u8();
    if (b === 0x3b) break;
    if (b === 0x21) {
      const label = u8();
      const sub = []; for (let n = u8(); n; n = u8()) { sub.push(...bytes.slice(p, p + n)); p += n; }
      if (label === 0xf9) delays.push(sub[1] | sub[2] << 8);
      if (label === 0xff && sub.length >= 14) loop = sub[12] | sub[13] << 8;
      continue;
    }
    if (b !== 0x2c) throw new Error('bad block ' + b);
    u16(); u16(); const fw = u16(), fh = u16(); u8();
    const min = u8(); const data = []; for (let n = u8(); n; n = u8()) { for (let i = 0; i < n; i++) data.push(bytes[p + i]); p += n; }
    // LZW decode
    const clear = 1 << min, eoi = clear + 1, out = [];
    let size = min + 1, dict = [], prev = null, bitPos = 0;
    const reset = () => { dict = []; for (let i = 0; i < clear; i++) dict[i] = [i]; dict[clear] = []; dict[eoi] = null; size = min + 1; prev = null; };
    reset();
    for (;;) {
      let code = 0; for (let i = 0; i < size; i++) { const bit = (data[(bitPos + i) >> 3] >> ((bitPos + i) & 7)) & 1; code |= bit << i; } bitPos += size;
      if (code === clear) { reset(); continue; }
      if (code === eoi) break;
      let entry;
      if (code < dict.length && dict[code]) entry = dict[code];
      else if (code === dict.length && prev) entry = prev.concat(prev[0]);
      else throw new Error('bad code ' + code);
      for (const v of entry) out.push(v);
      if (prev) { dict.push(prev.concat(entry[0])); if (dict.length === 1 << size && size < 12) size++; }
      prev = entry;
    }
    frames.push({ w: fw, h: fh, rgb: out.map(i => pal[i]) });
  }
  return { sig, w, h, pal, frames, delays, loop };
}

// Two "screenshots": a gradient with text-like noise, and the same with a red box drawn on it (the edit).
const W = 160, H = 90;
const before = new Uint8ClampedArray(W * H * 4), after = new Uint8ClampedArray(W * H * 4);
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
  const i = (y * W + x) * 4, ink = (x * 7 + y * 13) % 29 === 0;
  before[i] = ink ? 20 : 230 - y; before[i + 1] = ink ? 20 : 235 - x / 2; before[i + 2] = ink ? 30 : 245; before[i + 3] = 255;
  after.set(before.subarray(i, i + 4), i);
  if (x >= 40 && x < 100 && y >= 20 && y < 60 && (x < 44 || x >= 96 || y < 24 || y >= 56)) { after[i] = 255; after[i + 1] = 59; after[i + 2] = 48; }
}
const gif = GIF.encode([{ data: before, width: W, height: H }, { data: after, width: W, height: H }], { delayCs: 120 });
const d = decode(gif);
check('a GIF89a of the right size', d.sig === 'GIF89a' && d.w === W && d.h === H);
check('two frames, 1.2 s each, looping for ever', d.frames.length === 2 && d.delays.join() === '120,120' && d.loop === 0);
check('one shared palette of at most 256 colours', d.pal.length <= 256 && d.pal.length >= 2);
const err = (rgba, frame) => { let worst = 0; for (let k = 0; k < W * H; k++) for (let c = 0; c < 3; c++) worst = Math.max(worst, Math.abs(rgba[k * 4 + c] - frame.rgb[k][c])); return worst; };
check('every pixel decodes close to the original (before)', err(before, d.frames[0]) <= 24, err(before, d.frames[0]));
check('every pixel decodes close to the original (after)', err(after, d.frames[1]) <= 24, err(after, d.frames[1]));
const red = d.frames[1].rgb[22 * W + 41], same = d.frames[0].rgb[22 * W + 41];
check('the edit (red box) is in the second frame only', red[0] > 230 && red[1] < 90 && same[0] < 230);
// A large flat-ish frame forces the LZW table to fill and restart (4096 codes): it must still decode exactly.
const BW = 640, BH = 400, big = new Uint8ClampedArray(BW * BH * 4);
for (let k = 0; k < BW * BH; k++) { const v = (k * 2654435761 >>> 24) & 0x0f; big[k * 4] = v * 16; big[k * 4 + 1] = 255 - v * 16; big[k * 4 + 2] = 128; big[k * 4 + 3] = 255; }
const dbig = decode(GIF.encode([{ data: big, width: BW, height: BH }]));
let exact = dbig.frames[0].rgb.length === BW * BH;
for (let k = 0; exact && k < BW * BH; k++) exact = Math.abs(dbig.frames[0].rgb[k][0] - big[k * 4]) <= 2 && Math.abs(dbig.frames[0].rgb[k][1] - big[k * 4 + 1]) <= 2;
check('a 640 × 400 frame with 16 colours survives table resets exactly', exact);

console.log(`\n${process.exitCode ? 'SOME CHECKS FAILED' : 'All checks passed.'} (${passed} passed)`);
