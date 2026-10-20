// Animated GIF writer for the before/after export (native GIFExport: two frames, 1.2 s each, looping). One palette of up to 256
// colours shared by all frames (median cut over a sample of their pixels), LZW-compressed. Pure: used by the editor page and by
// test/gif.test.js.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.GIF = factory();
})(this, function () {
  'use strict';

  /** Median cut: up to `max` colours from [r, g, b] samples. */
  function palette(samples, max = 256) {
    let boxes = [samples];
    const range = (box, c) => { let lo = 255, hi = 0; for (const p of box) { if (p[c] < lo) lo = p[c]; if (p[c] > hi) hi = p[c]; } return hi - lo; };
    while (boxes.length < max) {
      let best = -1, bi = -1, bc = 0;
      boxes.forEach((box, i) => { if (box.length < 2) return; for (let c = 0; c < 3; c++) { const r = range(box, c) * Math.sqrt(box.length); if (r > best) { best = r; bi = i; bc = c; } } });
      if (bi < 0 || best === 0) break;
      const box = boxes[bi].sort((a, b) => a[bc] - b[bc]), mid = box.length >> 1;
      boxes.splice(bi, 1, box.slice(0, mid), box.slice(mid));
    }
    return boxes.filter(b => b.length).map(b => {
      const s = [0, 0, 0]; for (const p of b) { s[0] += p[0]; s[1] += p[1]; s[2] += p[2]; }
      return s.map(v => Math.round(v / b.length));
    });
  }

  /** Nearest palette index for every pixel; a 15-bit cache keeps big screenshots fast. */
  function indexPixels(rgba, pal) {
    const out = new Uint8Array(rgba.length / 4), cache = new Int16Array(32768).fill(-1);
    for (let i = 0, j = 0; i < rgba.length; i += 4, j++) {
      const key = (rgba[i] >> 3) << 10 | (rgba[i + 1] >> 3) << 5 | (rgba[i + 2] >> 3);
      let idx = cache[key];
      if (idx < 0) {
        let bd = Infinity;
        for (let k = 0; k < pal.length; k++) {
          const dr = rgba[i] - pal[k][0], dg = rgba[i + 1] - pal[k][1], db = rgba[i + 2] - pal[k][2], d = dr * dr * 2 + dg * dg * 4 + db * db * 3;
          if (d < bd) { bd = d; idx = k; }
        }
        cache[key] = idx;
      }
      out[j] = idx;
    }
    return out;
  }

  /** GIF LZW for one frame's indices; returns the image-data sub-blocks. */
  function lzw(indices, minCode) {
    const bytes = [];
    let cur = 0, nbits = 0;
    const emit = (code, size) => { cur |= code << nbits; nbits += size; while (nbits >= 8) { bytes.push(cur & 255); cur >>>= 8; nbits -= 8; } };
    const clear = 1 << minCode, eoi = clear + 1;
    let size = minCode + 1, next = eoi + 1, dict = new Map();
    emit(clear, size);
    let prefix = indices[0];
    for (let i = 1; i < indices.length; i++) {
      const k = indices[i], key = prefix << 8 | k, hit = dict.get(key);
      if (hit !== undefined) { prefix = hit; continue; }
      emit(prefix, size);
      if (next < 4096) { dict.set(key, next++); if (next > (1 << size) && size < 12) size++; }
      else { emit(clear, size); dict = new Map(); size = minCode + 1; next = eoi + 1; }
      prefix = k;
    }
    emit(prefix, size); emit(eoi, size);
    if (nbits > 0) bytes.push(cur & 255);
    const blocks = [];
    for (let i = 0; i < bytes.length; i += 255) { const n = Math.min(255, bytes.length - i); blocks.push(n, ...bytes.slice(i, i + n)); }
    blocks.push(0);
    return blocks;
  }

  /** frames: [{ data: RGBA (Uint8ClampedArray), width, height }] of one size. Returns a Uint8Array. */
  function encode(frames, { delayCs = 120, loop = 0 } = {}) {
    const { width: w, height: h } = frames[0];
    const samples = [];
    const step = Math.max(1, Math.floor((w * h * frames.length) / 60000));
    for (const f of frames) for (let p = 0; p < w * h; p += step) samples.push([f.data[p * 4], f.data[p * 4 + 1], f.data[p * 4 + 2]]);
    const pal = palette(samples, 256);
    while (pal.length < 2) pal.push([0, 0, 0]);
    const bits = Math.max(1, Math.ceil(Math.log2(pal.length))), size = 1 << bits;
    const out = [];
    const word = v => out.push(v & 255, (v >> 8) & 255);
    out.push(...[...'GIF89a'].map(c => c.charCodeAt(0)));
    word(w); word(h); out.push(0x80 | 0x70 | (bits - 1), 0, 0);       // global colour table, 8-bit colour resolution
    for (let i = 0; i < size; i++) out.push(...(pal[i] || [0, 0, 0]));
    out.push(0x21, 0xff, 11, ...[...'NETSCAPE2.0'].map(c => c.charCodeAt(0)), 3, 1); word(loop); out.push(0);   // loop forever
    const minCode = Math.max(2, bits);
    for (const f of frames) {
      out.push(0x21, 0xf9, 4, 0x04); word(delayCs); out.push(0, 0);    // graphic control: keep the frame, delay
      out.push(0x2c); word(0); word(0); word(w); word(h); out.push(0);
      out.push(minCode);
      for (const b of lzw(indexPixels(f.data, pal), minCode)) out.push(b);     // no spread: a full-screen frame is far more than the argument limit
    }
    out.push(0x3b);
    return Uint8Array.from(out);
  }

  return { encode, palette, indexPixels };
});
