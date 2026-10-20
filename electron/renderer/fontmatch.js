// Retyping text in a screenshot so it looks like the original: finds the installed typeface, size, ink colour and position that best
// reproduce a recognised line, by rendering the string in each candidate and comparing glyph shapes pixel by pixel (the same idea as the
// native app's FontMatcher). Also erases the original text by interpolating the background across it.
(function () {
  'use strict';

  const LATIN = ['Helvetica Neue', 'Arial', 'Segoe UI', 'Verdana', 'Trebuchet MS', 'Georgia', 'Times New Roman', 'Menlo', 'Consolas', 'Courier New', 'Tahoma', 'Avenir Next', 'Futura', 'Calibri'];
  const THAI = ['Thonburi', 'Leelawadee UI', 'Tahoma', 'Sukhumvit Set', 'Ayuthaya', 'Krungthep', 'Silom'];
  const SYSTEM = 'system-ui, -apple-system, "Segoe UI", sans-serif';

  const probeCtx = document.createElement('canvas').getContext('2d');
  const installedCache = new Map();
  function installed(name) {
    if (installedCache.has(name)) return installedCache.get(name);
    const sample = 'mmmmmmmmmmlliWWกขค';
    const width = family => { probeCtx.font = `72px ${family}`; return probeCtx.measureText(sample).width; };
    const ok = width(`"${name}", monospace`) !== width('monospace') || width(`"${name}", serif`) !== width('serif');
    installedCache.set(name, ok);
    return ok;
  }

  function candidates(text) {
    const hasThai = /[฀-๿]/.test(text);
    const names = hasThai ? THAI : LATIN;
    const list = [{ family: SYSTEM, label: 'system' }];
    for (const n of names) if (installed(n)) list.push({ family: `"${n}"`, label: n });
    const out = [];
    for (const c of list) { out.push({ ...c, bold: false }); out.push({ ...c, bold: true }); }
    return out;
  }

  function fontString(c, size) { return `${c.bold ? 700 : 400} ${size}px ${c.family}`; }

  /** Black text on white, drawn with its top-left at (pad, pad); returns a boolean ink mask. */
  function renderMask(text, c, size, width, height, pad) {
    const cv = document.createElement('canvas');
    cv.width = width; cv.height = height;
    const ctx = cv.getContext('2d', { willReadFrequently: true });
    ctx.fillStyle = '#fff'; ctx.fillRect(0, 0, width, height);
    ctx.fillStyle = '#000'; ctx.textBaseline = 'top';
    ctx.font = fontString(c, size);
    ctx.fillText(text, pad, pad);
    const d = ctx.getImageData(0, 0, width, height).data;
    const mask = new Uint8Array(width * height);
    for (let i = 0; i < mask.length; i++) mask[i] = d[i * 4] < 140 ? 1 : 0;
    return mask;
  }

  function inkBounds(mask, w, h) {
    let x0 = w, y0 = h, x1 = -1, y1 = -1;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (mask[y * w + x]) { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; }
    return x1 >= 0 ? { x0, y0, x1, y1 } : null;
  }

  const hex = (r, g, b) => '#' + [r, g, b].map(v => Math.round(v).toString(16).padStart(2, '0')).join('');

  /**
   * base: canvas holding the screenshot; bbox: {x0,y0,x1,y1} of the recognised line in image pixels; text: the recognised string.
   * Returns { font (CSS family), bold, size (image px), ink (#rrggbb), background (#rrggbb), x, y (text-box top-left), score } or null.
   */
  function guess(base, bbox, text) {
    const rx = Math.max(0, Math.floor(bbox.x0) - 4), ry = Math.max(0, Math.floor(bbox.y0) - 4);
    const rx2 = Math.min(base.width, Math.ceil(bbox.x1) + 4), ry2 = Math.min(base.height, Math.ceil(bbox.y1) + 4);
    const w = rx2 - rx, h = ry2 - ry;
    if (w < 6 || h < 6) return null;
    const img = base.getContext('2d', { willReadFrequently: true }).getImageData(rx, ry, w, h).data;

    // Background = the most common (coarsely quantised) colour in the box.
    const bins = new Map();
    for (let i = 0; i < w * h; i++) {
      const k = (img[i * 4] >> 4) << 8 | (img[i * 4 + 1] >> 4) << 4 | (img[i * 4 + 2] >> 4);
      const b = bins.get(k) || { n: 0, r: 0, g: 0, b: 0 };
      b.n++; b.r += img[i * 4]; b.g += img[i * 4 + 1]; b.b += img[i * 4 + 2];
      bins.set(k, b);
    }
    let top = null;
    for (const b of bins.values()) if (!top || b.n > top.n) top = b;
    const bg = { r: top.r / top.n, g: top.g / top.n, b: top.b / top.n };

    const dist = new Int16Array(w * h);
    let maxD = 0;
    for (let i = 0; i < w * h; i++) {
      const d = Math.max(Math.abs(img[i * 4] - bg.r), Math.abs(img[i * 4 + 1] - bg.g), Math.abs(img[i * 4 + 2] - bg.b));
      dist[i] = d; if (d > maxD) maxD = d;
    }
    if (maxD < 40) return null;   // flat colour: no text to match
    let sr = 0, sg = 0, sb = 0, sn = 0;
    for (let i = 0; i < w * h; i++) if (dist[i] >= maxD * 0.85) { sr += img[i * 4]; sg += img[i * 4 + 1]; sb += img[i * 4 + 2]; sn++; }
    const ink = hex(sr / sn, sg / sn, sb / sn);
    const original = new Uint8Array(w * h);
    for (let i = 0; i < w * h; i++) original[i] = dist[i] >= maxD * 0.5 ? 1 : 0;
    const ob = inkBounds(original, w, h);
    if (!ob || ob.x1 - ob.x0 < 4) return null;
    const inkWidth = ob.x1 - ob.x0 + 1;

    const pad = 10;
    let best = null;
    for (const c of candidates(text)) {
      // The size at which this face makes the same ink width as the original.
      const probeW = Math.ceil(inkWidth * 2.5) + 4 * pad, probeH = 40 * 3 + 2 * pad;
      const pm = renderMask(text, c, 40, probeW, probeH, pad);
      const pb = inkBounds(pm, probeW, probeH);
      if (!pb) continue;
      const size = Math.round(40 * inkWidth / Math.max(1, pb.x1 - pb.x0 + 1));
      if (size < 5 || size > 600) continue;

      const bw = Math.max(w + 2 * pad, inkWidth + 4 * pad), bh = Math.max(h + 2 * pad, Math.round(size * 2.4) + 2 * pad);
      const big = renderMask(text, c, size, bw, bh, pad);
      const rb = inkBounds(big, bw, bh);
      if (!rb) continue;
      const baseX = ob.x0 - (rb.x0 - pad), baseY = ob.y0 - (rb.y0 - pad);   // text-box origin that puts the rendered ink on the original's

      let bestHere = null;
      for (let dy = -3; dy <= 3; dy++) {
        for (let dx = -2; dx <= 2; dx++) {
          const ox = baseX + dx, oy = baseY + dy;
          let inter = 0, union = 0;
          for (let y = 0; y < h; y++) {
            const by = y - oy + pad;
            for (let x = 0; x < w; x++) {
              const bx = x - ox + pad;
              const r = bx >= 0 && by >= 0 && bx < bw && by < bh && big[by * bw + bx] === 1;
              const o = original[y * w + x] === 1;
              if (r && o) inter++;
              if (r || o) union++;
            }
          }
          const score = union ? inter / union : 0;
          if (!bestHere || score > bestHere.score) bestHere = { score, ox, oy };
        }
      }
      if (bestHere && (!best || bestHere.score > best.score)) best = { c, size, ...bestHere };
    }
    if (!best) return null;
    return {
      font: best.c.family, fontLabel: best.c.label, bold: best.c.bold, size: best.size, ink, background: hex(bg.r, bg.g, bg.b),
      x: rx + best.ox, y: ry + best.oy, score: best.score,
    };
  }

  /**
   * Returns a copy of `base` with the box painted over by interpolating the colours just above and below it, column by column,
   * so flat and vertically-graded backgrounds close up without a visible patch.
   */
  function erase(base, bbox, margin = 3) {
    const out = document.createElement('canvas');
    out.width = base.width; out.height = base.height;
    const ctx = out.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(base, 0, 0);
    const x0 = Math.max(0, Math.floor(bbox.x0) - margin), x1 = Math.min(base.width, Math.ceil(bbox.x1) + margin);
    const y0 = Math.max(0, Math.floor(bbox.y0) - margin), y1 = Math.min(base.height, Math.ceil(bbox.y1) + margin);
    const w = x1 - x0, h = y1 - y0;
    if (w <= 0 || h <= 0) return out;
    const data = ctx.getImageData(0, Math.max(0, y0 - 2), base.width, Math.min(base.height, y1 + 2) - Math.max(0, y0 - 2));
    const off = Math.max(0, y0 - 2);
    const px = (x, y) => { const i = ((y - off) * base.width + x) * 4; return [data.data[i], data.data[i + 1], data.data[i + 2]]; };
    const patch = ctx.createImageData(w, h);
    const aboveY = y0 - 1 >= 0 ? y0 - 1 : null, belowY = y1 < base.height ? y1 : null;
    for (let x = 0; x < w; x++) {
      const a = aboveY !== null ? px(x0 + x, aboveY) : null;
      const b = belowY !== null ? px(x0 + x, belowY) : null;
      for (let y = 0; y < h; y++) {
        const t = h > 1 ? y / (h - 1) : 0;
        const c = a && b ? [0, 1, 2].map(k => a[k] + (b[k] - a[k]) * t) : (a || b || [255, 255, 255]);
        const i = (y * w + x) * 4;
        patch.data[i] = c[0]; patch.data[i + 1] = c[1]; patch.data[i + 2] = c[2]; patch.data[i + 3] = 255;
      }
    }
    ctx.putImageData(patch, x0, y0);
    return out;
  }

  window.FontMatch = { guess, erase, installed, candidates };
})();
