// Retyping text in a screenshot so it looks like the original: finds the installed typeface, size, ink colour and position that best
// reproduce a recognised line, by rendering the string in each candidate and comparing glyph shapes pixel by pixel (the same idea as the
// native app's FontMatcher). Also erases the original text by interpolating the background across it.
(function () {
  'use strict';

  // Faces that are not installed are skipped (installed()), so one list serves macOS and Windows. Windows: Segoe UI (menus, dialogs),
  // Calibri / Aptos (Office), Cambria, Consolas; Thai: Leelawadee UI (Windows UI), TH Sarabun New / Angsana / Cordia / Browallia
  // (documents and forms), Tahoma, Microsoft Sans Serif (older programs).
  const LATIN = ['Helvetica Neue', 'Arial', 'Segoe UI', 'Verdana', 'Trebuchet MS', 'Georgia', 'Times New Roman', 'Menlo', 'Consolas', 'Courier New', 'Tahoma',
    'Avenir Next', 'Futura', 'Calibri', 'Aptos', 'Cambria', 'Microsoft Sans Serif', 'Roboto', 'Inter'];
  const THAI = ['Thonburi', 'Leelawadee UI', 'Leelawadee', 'Tahoma', 'TH Sarabun New', 'TH SarabunPSK', 'Angsana New', 'Cordia New', 'Browallia New',
    'Microsoft Sans Serif', 'Sukhumvit Set', 'Ayuthaya', 'Krungthep', 'Silom', 'Noto Sans Thai', 'Sarabun', 'Prompt', 'Kanit'];
  const SYSTEM = 'system-ui, -apple-system, "Segoe UI", sans-serif';
  // Most text in a Windows screenshot is the system face. When a look-alike (Trebuchet MS, Tahoma) scores almost the same — typical for
  // short UI strings, or menu items whose wide gaps OCR reports as single spaces — the system face wins.
  const WINDOWS = /^Win/.test(navigator.platform || '');
  const prior = c => (WINDOWS && c.label === 'Segoe UI' ? 0.03 : 0);

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

  /** Groups of ink columns separated by gaps wider than letter spacing: [{ x0, x1 }] in box coordinates. */
  function wordSegments(mask, w, h, ob) {
    const gapMin = Math.max(3, Math.round((ob.y1 - ob.y0 + 1) * 0.3));
    const segs = [];
    let start = null, lastInk = null;
    for (let x = ob.x0; x <= ob.x1; x++) {
      let ink = false;
      for (let y = ob.y0; y <= ob.y1 && !ink; y++) ink = mask[y * w + x] === 1;
      if (!ink) continue;
      if (start === null) start = x;
      else if (x - lastInk - 1 >= gapMin) { segs.push({ x0: start, x1: lastInk }); start = x; }
      lastInk = x;
    }
    if (start !== null) segs.push({ x0: start, x1: lastInk });
    return segs;
  }

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
    // Word mode: when the ink splits into exactly as many groups as the text has words, each word is sized and placed on its own group.
    // Menus, toolbars and table cells space words far wider than a space character, and OCR reports those gaps as single spaces, so
    // matching the line as one string would get both the size and the face wrong.
    const words = String(text).trim().split(/\s+/).filter(Boolean);
    const segs = wordSegments(original, w, h, ob);
    const wordMode = words.length > 1 && segs.length === words.length;
    const iou = (rendered, ox, oy, rw, rh) => {
      let inter = 0, union = 0;
      for (let y = 0; y < h; y++) {
        const by = y - oy + pad;
        for (let x = 0; x < w; x++) {
          const bx = x - ox + pad;
          const r = bx >= 0 && by >= 0 && bx < rw && by < rh && rendered[by * rw + bx] === 1;
          const o = original[y * w + x] === 1;
          if (r && o) inter++;
          if (r || o) union++;
        }
      }
      return union ? inter / union : 0;
    };
    let best = null, runnerUp = null;
    for (const c of candidates(text)) {
      // The size at which this face makes the same ink width as the original (summed per word in word mode).
      const probeH = 40 * 3 + 2 * pad;
      const inkW40 = s => { const pw = Math.ceil(40 * 0.9 * s.length) + 4 * pad + 40; const b = inkBounds(renderMask(s, c, 40, pw, probeH, pad), pw, probeH); return b ? b.x1 - b.x0 + 1 : 0; };
      const target = wordMode ? segs.reduce((n, s) => n + s.x1 - s.x0 + 1, 0) : inkWidth;
      const probe = wordMode ? words.reduce((n, wd) => n + inkW40(wd), 0) : inkW40(text);
      if (!probe) continue;
      const size = Math.round(40 * target / probe);
      if (size < 5 || size > 600) continue;

      const bh = Math.max(h + 2 * pad, Math.round(size * 2.4) + 2 * pad);
      const lineW = Math.max(w + 2 * pad, Math.ceil(size * 0.9 * text.length) + 4 * pad);
      const line = renderMask(text, c, size, lineW, bh, pad);
      const rb = inkBounds(line, lineW, bh);
      if (!rb) continue;
      const baseY = ob.y0 - (rb.y0 - pad);      // text-box top that puts the rendered ink on the original's

      let bestHere = null;
      if (wordMode) {
        // Stamp each word, ink-left on its own group, into one mask the size of the box (in the same coordinates as `line`).
        const bw = w + 2 * pad, stamp = new Uint8Array(bw * bh);
        let firstX = null;
        words.forEach((wd, i) => {
          const ww = Math.ceil(size * 0.9 * wd.length) + 4 * pad + size, m = renderMask(wd, c, size, ww, bh, pad), b = inkBounds(m, ww, bh);
          if (!b) return;
          const ox = segs[i].x0 - (b.x0 - pad);       // word origin in box coordinates
          if (firstX === null) firstX = ox;
          for (let y = 0; y < bh; y++) for (let x = 0; x < ww; x++) {
            if (!m[y * ww + x]) continue;
            const tx = x + ox;      // = (box x of this pixel) + pad, the column iou() reads for an origin of 0
            if (tx >= 0 && tx < bw) stamp[y * bw + tx] = 1;
          }
        });
        for (let dy = -3; dy <= 3; dy++) {
          const score = iou(stamp, 0, baseY + dy, bw, bh);
          if (!bestHere || score > bestHere.score) bestHere = { score, ox: firstX, oy: baseY + dy };
        }
      } else {
        const baseX = ob.x0 - (rb.x0 - pad);
        for (let dy = -3; dy <= 3; dy++) {
          for (let dx = -2; dx <= 2; dx++) {
            const score = iou(line, baseX + dx, baseY + dy, lineW, bh);
            if (!bestHere || score > bestHere.score) bestHere = { score, ox: baseX + dx, oy: baseY + dy };
          }
        }
      }
      if (bestHere) {
        const ranked = bestHere.score + prior(c);
        if (!best || ranked > best.ranked) { runnerUp = best; best = { c, size, ...bestHere, ranked }; }
        else if (!runnerUp || ranked > runnerUp.ranked) runnerUp = { c, size, ...bestHere, ranked };
      }
    }
    if (!best) return null;
    return {
      font: best.c.family, fontLabel: best.c.label, bold: best.c.bold, size: best.size, ink, background: hex(bg.r, bg.g, bg.b),
      x: rx + best.ox, y: ry + best.oy, score: best.score,
      runnerUp: runnerUp && { font: runnerUp.c.label, bold: runnerUp.c.bold, score: runnerUp.score },
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
