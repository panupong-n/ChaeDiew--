// Scrolling capture: joins successive frames of a scrolling region into one tall picture by matching row hashes. A port of the native
// app's ScrollStitcher.swift (same thresholds). Pure: frames are { data: RGBA, width, height }; used by the capture page and the tests.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.Stitch = factory();
})(this, function () {
  'use strict';

  /** One number per pixel row (every other pixel): two 32-bit FNV-1a hashes packed into 53 bits, so collisions stay negligible. */
  function rowHashes(f) {
    const { data, width: w, height: h } = f, out = new Array(h);
    for (let y = 0; y < h; y++) {
      let a = 0x811c9dc5, b = 0x9dc5811c;     // two different seeds and primes
      for (let x = 0, i = y * w * 4; x < w; x += 2, i += 8) {
        for (let k = 0; k < 4; k++) { a = Math.imul(a ^ data[i + k], 0x01000193) >>> 0; b = Math.imul(b ^ data[i + k], 0x0100019d) >>> 0; }
      }
      out[y] = a * 2097152 + (b & 0x1fffff);
    }
    return out;
  }

  /** How far `next` scrolled relative to `previous`: { kind: 'none' | 'scrolled' | 'unknown', rows } (rows > 0: content moved up). */
  function detectShift(previous, next) {
    const h = previous.length;
    if (h !== next.length || h < 16) return { kind: 'unknown' };
    if (previous.every((v, i) => v === next[i])) return { kind: 'none' };
    const counts = new Map();
    for (const v of previous) counts.set(v, (counts.get(v) || 0) + 1);
    for (const v of next) counts.set(v, (counts.get(v) || 0) + 1);
    let background = 0, most = -1;
    for (const [v, n] of counts) if (n > most) { most = n; background = v; }      // blank rows cannot vote
    // Rows that did not move (a sticky header or toolbar) say nothing about the scroll; on a page with a lot of white space they would
    // outvote the content. (An addition to the native algorithm, which only skips the background row.)
    const fixed = next.map((v, i) => v === previous[i] && v !== background);
    const score = s => {
      let m = 0, x = 0;
      for (let i = Math.max(0, -s); i < Math.min(h, h - s); i++) {
        const a = next[i], b = previous[i + s];
        if ((a === background && b === background) || (s !== 0 && fixed[i])) continue;
        if (a === b) m++; else x++;
      }
      return [m, x];
    };
    const minMatches = Math.max(6, Math.floor(h / 50));
    const [zm, zx] = score(0);
    if (zm + zx > 0 && zm / (zm + zx) >= 0.98) return { kind: 'none' };
    const minOverlap = Math.max(8, Math.floor(h / 10));
    let best = null;
    for (let s = -(h - minOverlap); s <= h - minOverlap; s++) {
      if (s === 0) continue;
      const [m, x] = score(s);
      if (m < minMatches || m / (m + x) < 0.8) continue;
      const value = m - 3 * x;
      if (!best || value > best.value) best = { s, value };
    }
    return best ? { kind: 'scrolled', rows: best.s } : { kind: 'unknown' };
  }

  const rows = (f, y0, n) => ({ data: f.data.slice(y0 * f.width * 4, (y0 + n) * f.width * 4), width: f.width, height: n });

  class Stitcher {
    constructor(maxHeight = 40000) { this.maxHeight = maxHeight; this.strips = []; this.prev = null; this.size = null; this.totalHeight = 0; }
    get isEmpty() { return !this.strips.length; }
    /** Returns 'first' | 'appended' | 'prepended' | 'noChange' | 'unmatched' | 'limitReached'. */
    add(frame) {
      const hashes = rowHashes(frame);
      if (!hashes.length) return 'unmatched';
      if (!this.size) { this.size = [frame.width, frame.height]; this.strips = [frame]; this.totalHeight = frame.height; this.prev = hashes; return 'first'; }
      if (frame.width !== this.size[0] || frame.height !== this.size[1]) return 'unmatched';
      const shift = detectShift(this.prev, hashes);
      if (shift.kind === 'none') return 'noChange';
      if (shift.kind === 'unknown') return 'unmatched';
      const n = Math.abs(shift.rows);
      if (this.totalHeight + n > this.maxHeight) return 'limitReached';
      if (shift.rows > 0) this.strips.push(rows(frame, frame.height - n, n)); else this.strips.unshift(rows(frame, 0, n));
      this.totalHeight += n; this.prev = hashes;
      return shift.rows > 0 ? 'appended' : 'prepended';
    }
    /** The joined picture, top to bottom. */
    finish() {
      if (!this.strips.length) return null;
      const w = this.strips[0].width, data = new Uint8ClampedArray(w * this.totalHeight * 4);
      let top = 0;
      for (const s of this.strips) { data.set(s.data, top * w * 4); top += s.height; }
      return { data, width: w, height: this.totalHeight };
    }
  }

  return { Stitcher, rowHashes, detectShift };
});
