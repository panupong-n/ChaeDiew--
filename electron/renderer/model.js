// Pure editor logic (no DOM): counter numbering, geometry, hit testing. Loaded by the editor page and by test/editor-model.test.js.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.Model = factory();
})(this, function () {
  'use strict';

  /** Counter labels are text: "7", "1.1", "A2", "3.6.2". The last run of digits is the one that steps. */
  const CounterText = {
    step(text, delta) {
      const s = String(text);
      const m = /(\d+)(?!.*\d)/.exec(s);          // the last run of ASCII digits
      if (!m) return delta >= 0 ? '1' : '0';
      const value = Math.max(0, parseInt(m[1], 10) + delta);
      const padded = String(value).padStart(m[1].length, '0');   // "007" → "008"
      return s.slice(0, m.index) + padded + s.slice(m.index + m[1].length);
    },
    next(text) { return CounterText.step(text, 1); },
  };

  const BOX_TYPES = ['rect', 'ellipse', 'highlight', 'blur'];

  function normBox(s) {
    const x = Math.min(s.x, s.x + s.w), y = Math.min(s.y, s.y + s.h);
    return { x, y, w: Math.abs(s.w), h: Math.abs(s.h) };
  }

  function distToSegment(px, py, x1, y1, x2, y2) {
    const dx = x2 - x1, dy = y2 - y1;
    const len2 = dx * dx + dy * dy;
    let t = len2 === 0 ? 0 : ((px - x1) * dx + (py - y1) * dy) / len2;
    t = Math.max(0, Math.min(1, t));
    return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy));
  }

  /** Counter geometry: a circle, stretched into a capsule when the label is long ("1.1.3"). `measure(text, px)` gives text width. */
  function counterGeometry(s, measure) {
    const d = s.size;
    const w = Math.max(d, measure(s.label, d * 0.54, true) + d * 0.5);
    return { x: s.x - w / 2, y: s.y - d / 2, w, h: d, d };
  }

  function textLines(s) { return String(s.text).split('\n'); }
  function textMetrics(s, measure) {
    const lines = textLines(s);
    const lineHeight = s.size * 1.25;
    const width = Math.max(1, ...lines.map(l => measure(l, s.size, s.bold, s.font)));
    return { lines, lineHeight, w: width, h: lineHeight * lines.length };
  }

  function boundsOf(s, measure) {
    switch (s.type) {
      case 'rect': case 'ellipse': case 'highlight': case 'blur': return normBox(s);
      case 'line': case 'arrow': {
        const x = Math.min(s.x1, s.x2), y = Math.min(s.y1, s.y2);
        return { x, y, w: Math.abs(s.x2 - s.x1), h: Math.abs(s.y2 - s.y1) };
      }
      case 'pen': {
        const xs = s.pts.map(p => p[0]), ys = s.pts.map(p => p[1]);
        const x = Math.min(...xs), y = Math.min(...ys);
        return { x, y, w: Math.max(...xs) - x, h: Math.max(...ys) - y };
      }
      case 'text': { const m = textMetrics(s, measure); return { x: s.x, y: s.y, w: m.w, h: m.h }; }
      case 'counter': { const g = counterGeometry(s, measure); return { x: g.x, y: g.y, w: g.w, h: g.h }; }
    }
    return { x: 0, y: 0, w: 0, h: 0 };
  }

  /** Is the point (x, y) on / in the shape? `tol` is the pick slack in image pixels. */
  function hit(s, x, y, tol, measure) {
    switch (s.type) {
      case 'rect': {
        const b = normBox(s);
        if (s.fill) return x >= b.x - tol && x <= b.x + b.w + tol && y >= b.y - tol && y <= b.y + b.h + tol;
        const inner = x > b.x + tol && x < b.x + b.w - tol && y > b.y + tol && y < b.y + b.h - tol;
        const outer = x >= b.x - tol && x <= b.x + b.w + tol && y >= b.y - tol && y <= b.y + b.h + tol;
        return outer && !inner;
      }
      case 'ellipse': {
        const b = normBox(s);
        const rx = b.w / 2 + tol, ry = b.h / 2 + tol;
        if (rx <= 0 || ry <= 0) return false;
        const nx = (x - (b.x + b.w / 2)) / rx, ny = (y - (b.y + b.h / 2)) / ry;
        const d = nx * nx + ny * ny;
        if (s.fill) return d <= 1;
        const rx2 = Math.max(1, b.w / 2 - tol), ry2 = Math.max(1, b.h / 2 - tol);
        const mx = (x - (b.x + b.w / 2)) / rx2, my = (y - (b.y + b.h / 2)) / ry2;
        return d <= 1 && mx * mx + my * my >= 1;
      }
      case 'highlight': case 'blur': case 'text': case 'counter': {
        const b = boundsOf(s, measure);
        return x >= b.x - tol && x <= b.x + b.w + tol && y >= b.y - tol && y <= b.y + b.h + tol;
      }
      case 'line': case 'arrow': return distToSegment(x, y, s.x1, s.y1, s.x2, s.y2) <= s.width / 2 + tol;
      case 'pen': {
        for (let i = 1; i < s.pts.length; i++) {
          if (distToSegment(x, y, s.pts[i - 1][0], s.pts[i - 1][1], s.pts[i][0], s.pts[i][1]) <= s.width / 2 + tol) return true;
        }
        return s.pts.length === 1 && Math.hypot(x - s.pts[0][0], y - s.pts[0][1]) <= s.width / 2 + tol;
      }
    }
    return false;
  }

  function moveShape(s, dx, dy) {
    switch (s.type) {
      case 'line': case 'arrow': s.x1 += dx; s.y1 += dy; s.x2 += dx; s.y2 += dy; break;
      case 'pen': s.pts = s.pts.map(p => [p[0] + dx, p[1] + dy]); break;
      default: s.x += dx; s.y += dy;
    }
  }

  const HANDLE_NAMES = ['nw', 'n', 'ne', 'e', 'se', 's', 'sw', 'w'];
  function handlePoints(s, measure) {
    if (s.type === 'line' || s.type === 'arrow') return [{ name: 'p1', x: s.x1, y: s.y1 }, { name: 'p2', x: s.x2, y: s.y2 }];
    if (!BOX_TYPES.includes(s.type)) return [];
    const b = normBox(s);
    const cx = b.x + b.w / 2, cy = b.y + b.h / 2, r = b.x + b.w, bt = b.y + b.h;
    return [
      { name: 'nw', x: b.x, y: b.y }, { name: 'n', x: cx, y: b.y }, { name: 'ne', x: r, y: b.y }, { name: 'e', x: r, y: cy },
      { name: 'se', x: r, y: bt }, { name: 's', x: cx, y: bt }, { name: 'sw', x: b.x, y: bt }, { name: 'w', x: b.x, y: cy },
    ];
  }

  /** Drags handle `name` of a box shape to (x, y). */
  function resizeBox(s, name, x, y) {
    const b = normBox(s);
    let x0 = b.x, y0 = b.y, x1 = b.x + b.w, y1 = b.y + b.h;
    if (name.includes('w')) x0 = x; if (name.includes('e')) x1 = x;
    if (name.includes('n')) y0 = y; if (name.includes('s')) y1 = y;
    s.x = Math.min(x0, x1); s.y = Math.min(y0, y1); s.w = Math.abs(x1 - x0); s.h = Math.abs(y1 - y0);
  }

  /** Black or white, whichever reads better on a #rrggbb colour (WCAG contrast). */
  function readableOn(hex) {
    const m = /^#?([0-9a-f]{6})$/i.exec(hex || '');
    if (!m) return '#ffffff';
    const v = parseInt(m[1], 16);
    const lin = c => { c /= 255; return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
    const L = 0.2126 * lin(v >> 16 & 255) + 0.7152 * lin(v >> 8 & 255) + 0.0722 * lin(v & 255);
    return (L + 0.05) / 0.05 >= 1.05 / (L + 0.05) ? '#000000' : '#ffffff';
  }

  return { CounterText, BOX_TYPES, HANDLE_NAMES, normBox, distToSegment, counterGeometry, textMetrics, boundsOf, hit, moveShape, handlePoints, resizeBox, readableOn };
});
