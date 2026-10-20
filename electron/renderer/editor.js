'use strict';
// Tenix-ChaeDiew editor (Electron). Canvas-based annotation: shapes live in image pixels; the bar, the context strip and the
// backdrop panel apply every change to the selected mark immediately.
(() => {
  const { CounterText, BOX_TYPES, LINE_TYPES, normBox, counterGeometry, magnifierGeometry, flatRun, textMetrics, boundsOf, hit, moveShape, handlePoints, dragHandle, readableOn, hexOf } = window.Model;
  const api = window.tenix;
  let lang = api.lang;      // changes live (Settings / home window) without reloading, so the marks are kept
  const t = key => (lang === 'th' && api.strings[key]) || key;
  const $ = (sel, el = document) => el.querySelector(sel);
  const mac = api.platform === 'darwin';

  document.body.classList.add(mac ? 'mac' : api.platform === 'win32' ? 'win' : 'other');
  document.documentElement.lang = lang;

  // ---------------------------------------------------------------- icons
  const ICON = {
    select: '<path d="M6 3.5l12 7.5-5.2 1.3L10.6 18z"/>',
    rect: '<rect x="4" y="5.5" width="16" height="13" rx="2"/>',
    ellipse: '<ellipse cx="12" cy="12" rx="8.5" ry="6.5"/>',
    arrow: '<path d="M5 19L19 5M9.5 5H19v9.5"/>',
    line: '<path d="M5 19L19 5"/>',
    pen: '<path d="M4.5 19.5l1-4L16.2 4.8a2.1 2.1 0 013 3L8.5 18.5z"/><path d="M14.5 6.5l3 3"/>',
    highlight: '<rect x="3.5" y="8" width="17" height="8" rx="1.5" fill="currentColor" fill-opacity=".3"/><path d="M6.5 12h11"/>',
    text: '<path d="M5.5 7V5.5h13V7M12 5.5v13M9 18.5h6"/>',
    counter: '<circle cx="12" cy="12" r="8.5"/><path d="M10.4 9.8L12.6 8.2v7.6"/>',
    blur: '<rect x="4" y="4" width="16" height="16" rx="2"/><path d="M4 9.3h16M4 14.7h16M9.3 4v16M14.7 4v16" opacity=".55"/>',
    crop: '<path d="M7 3.5v13.5h13.5M3.5 7H17v13.5"/>',
    editText: '<path d="M4 6.5V5.5h11v1M9.5 5.5v10M7 15.5h5"/><path d="M13.5 21l.8-3 5.6-5.6a1.5 1.5 0 012.1 2.1L16.4 20z" transform="translate(-2.2 -1.6)"/>',
    undo: '<path d="M9 14L4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 010 11H11"/>',
    redo: '<path d="M15 14l5-5-5-5"/><path d="M20 9H9.5a5.5 5.5 0 000 11H13"/>',
    copy: '<rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V6a2 2 0 012-2h8"/>',
    save: '<path d="M12 4v11M7 11l5 5 5-5M5 20h14"/>',
    ocr: '<path d="M4 8V5.5A1.5 1.5 0 015.5 4H8M16 4h2.5A1.5 1.5 0 0120 5.5V8M20 16v2.5a1.5 1.5 0 01-1.5 1.5H16M8 20H5.5A1.5 1.5 0 014 18.5V16M8 9h8M8 12h8M8 15h5"/>',
    backdrop: '<rect x="3" y="4" width="18" height="16" rx="2.5"/><rect x="7.5" y="8.5" width="9" height="7" rx="1.2"/>',
    zoomIn: '<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2M8.5 11h5M11 8.5v5"/>',
    zoomOut: '<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2M8.5 11h5"/>',
    fit: '<path d="M4 9V5h4M20 9V5h-4M4 15v4h4M20 15v4h-4"/>',
    trash: '<path d="M5 7h14M10 7V4.5h4V7M7 7l1 13h8l1-13"/>',
    key: '<circle cx="8" cy="15" r="4"/><path d="M11 12l8-8M16 7l3 3"/>',
    check: '<path d="M5 12.5l5 5 9-10.5"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    minus: '<path d="M5 12h14"/>',
    more: '<circle cx="5.5" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="12" cy="12" r="1.4" fill="currentColor" stroke="none"/><circle cx="18.5" cy="12" r="1.4" fill="currentColor" stroke="none"/>',
    spotlight: '<path d="M3.5 4h17v16h-17z" opacity=".45"/><ellipse cx="12" cy="12" rx="5.5" ry="4.2"/>',
    magnifier: '<circle cx="7.5" cy="15.5" r="3"/><circle cx="15.5" cy="9" r="5.5"/><path d="M9.8 13.6l1.9-1.6"/>',
    measure: '<path d="M3.5 15.5L15.5 3.5l5 5-12 12z"/><path d="M7 12l1.6 1.6M9.5 9.5l2.4 2.4M12 7l1.6 1.6"/>',
    eyedropper: '<path d="M13.5 6.5l4 4M15.4 4.6a2.1 2.1 0 013 3l-1.9 1.9-3-3z"/><path d="M14 9L6.2 16.8 5 20l3.2-1.2L16 11"/>',
    pii: '<path d="M3 12s3.3-6 9-6c1.6 0 3 .5 4.2 1.1M21 12s-3.3 6-9 6c-1.6 0-3-.5-4.2-1.1"/><path d="M9.6 14.4a3.4 3.4 0 014.8-4.8M4 20L20 4"/>',
    pin: '<path d="M9 4h6l-1 5 3 3H7l3-3z"/><path d="M12 12v8"/>',
    print: '<path d="M7 9V4h10v5M7 17H5a1.5 1.5 0 01-1.5-1.5v-5A1.5 1.5 0 015 9h14a1.5 1.5 0 011.5 1.5v5A1.5 1.5 0 0119 17h-2"/><path d="M7 14h10v6H7z"/>',
    upload: '<path d="M12 16V5M7 9.5L12 4.5l5 5M5 20h14"/>',
    gif: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M8.5 10.2a2 2 0 100 3.6M8.5 12h1M12.5 10v4M15.5 14v-4h2.2M15.5 12h1.8"/>',
  };
  const svg = name => `<svg viewBox="0 0 24 24" aria-hidden="true">${ICON[name]}</svg>`;

  // ---------------------------------------------------------------- state
  const PALETTE = ['#FF3B30', '#FF9500', '#FFCC00', '#34C759', '#1FA0FF', '#5856D6', '#FF2D92', '#FFFFFF', '#15171C'];
  // Font menu for text marks: the faces people expect on this platform, minus any that are not installed.
  const FONTS = [['system', 'System'], ...(mac
    ? ['Helvetica Neue', 'Arial', 'Georgia', 'Menlo', 'Tahoma', 'Thonburi']
    : ['Segoe UI', 'Arial', 'Calibri', 'Georgia', 'Consolas', 'Tahoma', 'Leelawadee UI', 'TH Sarabun New']
  ).filter(f => window.FontMatch.installed(f)).map(f => [f, f])];
  const BACKDROPS = [
    ['#6EE7F9', '#6366F1'], ['#F9A8D4', '#C084FC'], ['#FDE68A', '#FB923C'], ['#86EFAC', '#0EA5E9'], ['#FDA4AF', '#F43F5E'], ['#A5B4FC', '#312E81'],
    ['#E2E8F0', '#94A3B8'], ['#1E293B', '#0F172A'], ['#FFFFFF', '#E5E7EB'], ['#FEF3C7', '#FCA5A5'], ['#BBF7D0', '#14B8A6'], ['#15171C', '#1FA0FF'],
  ];
  const S = {
    base: null, w: 0, h: 0, pixelScale: 1,
    shapes: [], sel: null, tool: 'select',
    style: { color: '#FF3B30', textColor: 'auto', bg: null, width: 4, fill: false, textSize: 28, counterSize: 34, blur: 12, font: 'system', bold: true,
      level: 6, oval: false, zoom: 2 },
    zoom: 1, fitMode: true,
    undo: [], redo: [], nextId: 1,
    bd: { on: false, preset: 0, c1: BACKDROPS[0][0], c2: BACKDROPS[0][1], pad: 64, radius: 14, shadow: 32 },
    cropRect: null, ocr: null, editing: null, drag: null, hover: null, lastStyleGroup: null, lastStyleAt: 0, busy: false,
    // Ruler: what the pointer is on (live), and which direction is held (1 = height only, 2 = width only). Colour picker: pixel under the pointer.
    probe: null, measureAxis: 'both', pick: null,
  };
  try { Object.assign(S.bd, JSON.parse(localStorage.getItem('bd') || '{}')); S.bd.on = false; } catch { /* storage unavailable */ }

  const cv = $('#cv');
  const ctx = cv.getContext('2d');
  const measureCtx = document.createElement('canvas').getContext('2d');

  const fontFamily = f => (f === 'system' ? 'system-ui, -apple-system, "Segoe UI", sans-serif' : /[",]/.test(f) ? f : `"${f}", system-ui, sans-serif`);
  const fontCss = (size, bold, font) => `${bold ? 700 : 400} ${size}px ${fontFamily(font || 'system')}`;
  function measure(text, px, bold, font) {
    measureCtx.font = fontCss(px, !!bold, font);
    return measureCtx.measureText(text).width;
  }
  const meas = (text, px, bold, font) => measure(text, px, bold, font);

  // ---------------------------------------------------------------- history
  const snapshot = () => ({ base: S.base, w: S.w, h: S.h, shapes: JSON.parse(JSON.stringify(S.shapes)), sel: S.sel });
  function pushUndo() { S.undo.push(snapshot()); if (S.undo.length > 80) S.undo.shift(); S.redo.length = 0; S.lastStyleGroup = null; refreshChrome(); }
  function restore(snap) {
    S.base = snap.base; S.w = snap.w; S.h = snap.h; S.shapes = JSON.parse(JSON.stringify(snap.shapes)); S.sel = snap.sel;
    S.ocr = null; closeEditor(true); layout(); draw(); renderStrip(); refreshChrome();
  }
  function undo() { if (!S.undo.length) return; S.redo.push(snapshot()); restore(S.undo.pop()); }
  function redo() { if (!S.redo.length) return; S.undo.push(snapshot()); restore(S.redo.pop()); }
  /** One undo step for a burst of changes to the same property (dragging a slider, picking colours). */
  function coalesce(group) {
    const now = performance.now();
    if (S.lastStyleGroup !== group || now - S.lastStyleAt > 900) {
      S.undo.push(snapshot()); if (S.undo.length > 80) S.undo.shift(); S.redo.length = 0; refreshChrome();
    }
    S.lastStyleGroup = group; S.lastStyleAt = now;
  }

  // ---------------------------------------------------------------- helpers
  const selected = () => S.shapes.find(s => s.id === S.sel) || null;
  const pad = () => (S.bd.on ? S.bd.pad : 0);
  const scale = () => S.zoom / S.pixelScale;     // CSS pixels per image pixel
  function toast(text, warn) {
    const el = $('#toast');
    el.textContent = text; el.classList.toggle('warn', !!warn); el.classList.add('show');
    clearTimeout(toast.timer); toast.timer = setTimeout(() => el.classList.remove('show'), 2200);
  }
  function eventPoint(e) {
    const r = cv.getBoundingClientRect(), k = scale();
    return { x: (e.clientX - r.left) / k - pad(), y: (e.clientY - r.top) / k - pad() };
  }
  /**
   * What the next counter says (as in the native app): what the user typed for it, else one step on from the counter placed or edited
   * most recently (`serial`) — not the last in the list, which changes when marks come to the front.
   */
  const shapeCounterLabel = () => {
    if (S.counterNext) return S.counterNext;
    const counters = S.shapes.filter(s => s.type === 'counter');
    if (!counters.length) return '1';
    const latest = counters.reduce((a, b) => ((b.serial || 0) >= (a.serial || 0) ? b : a));
    return CounterText.next(latest.label);
  };
  const nextSerial = () => S.shapes.reduce((m, s) => (s.type === 'counter' ? Math.max(m, s.serial || 0) : m), 0) + 1;
  function ink(s) { return s.type === 'counter' ? (s.textColor === 'auto' ? readableOn(s.color) : s.textColor) : s.color; }

  // ---------------------------------------------------------------- layout & drawing
  function availableSize() {
    const sc = $('#scroller');
    return { w: sc.clientWidth - 56, h: sc.clientHeight - 56 };
  }
  function fitZoom() {
    if (!S.w) return 1;
    const a = availableSize();
    const totalW = (S.w + 2 * pad()) / S.pixelScale, totalH = (S.h + 2 * pad()) / S.pixelScale;
    return Math.max(0.05, Math.min(2, a.w / totalW, a.h / totalH));
  }
  function setZoom(z, fit) {
    S.fitMode = !!fit;
    S.zoom = Math.max(0.1, Math.min(8, z));
    layout(); draw(); refreshChrome();
  }
  function layout() {
    if (!S.w) return;
    if (S.fitMode) S.zoom = fitZoom();
    const k = scale(), W = S.w + 2 * pad(), H = S.h + 2 * pad(), dpr = window.devicePixelRatio || 1;
    cv.style.width = `${W * k}px`; cv.style.height = `${H * k}px`;
    cv.width = Math.max(1, Math.round(W * k * dpr)); cv.height = Math.max(1, Math.round(H * k * dpr));
    if (S.editing) positionEditor();
  }

  function roundRectPath(c, x, y, w, h, r) {
    r = Math.max(0, Math.min(r, w / 2, h / 2));
    c.beginPath(); c.moveTo(x + r, y); c.arcTo(x + w, y, x + w, y + h, r); c.arcTo(x + w, y + h, x, y + h, r);
    c.arcTo(x, y + h, x, y, r); c.arcTo(x, y, x + w, y, r); c.closePath();
  }

  function paintBackdrop(c, W, H) {
    const g = c.createLinearGradient(0, 0, W, H);
    g.addColorStop(0, S.bd.c1); g.addColorStop(1, S.bd.c2);
    c.fillStyle = g; c.fillRect(0, 0, W, H);
  }

  function drawArrow(c, s) {
    const dx = s.x2 - s.x1, dy = s.y2 - s.y1, len = Math.hypot(dx, dy);
    if (len < 1) return;
    const ux = dx / len, uy = dy / len, head = Math.min(len * 0.6, Math.max(14, s.width * 4.2)), spread = Math.PI / 7;
    c.strokeStyle = s.color; c.fillStyle = s.color; c.lineWidth = s.width; c.lineCap = 'round'; c.lineJoin = 'round';
    c.beginPath(); c.moveTo(s.x1, s.y1); c.lineTo(s.x2 - ux * head * 0.7, s.y2 - uy * head * 0.7); c.stroke();
    const a = Math.atan2(dy, dx);
    c.beginPath(); c.moveTo(s.x2, s.y2);
    c.lineTo(s.x2 - head * Math.cos(a - spread), s.y2 - head * Math.sin(a - spread));
    c.lineTo(s.x2 - head * Math.cos(a + spread), s.y2 - head * Math.sin(a + spread));
    c.closePath(); c.fill();
  }

  function drawPixelate(c, s) {
    const b = normBox(s);
    const x = Math.max(0, Math.round(b.x)), y = Math.max(0, Math.round(b.y));
    const w = Math.min(S.w - x, Math.round(b.w)), h = Math.min(S.h - y, Math.round(b.h));
    if (w < 2 || h < 2) return;
    const block = Math.max(2, s.strength || 12);
    const tmp = document.createElement('canvas');
    tmp.width = Math.max(1, Math.ceil(w / block)); tmp.height = Math.max(1, Math.ceil(h / block));
    const tc = tmp.getContext('2d');
    tc.imageSmoothingEnabled = true; tc.drawImage(S.base, x, y, w, h, 0, 0, tmp.width, tmp.height);
    c.save(); c.imageSmoothingEnabled = false; c.drawImage(tmp, 0, 0, tmp.width, tmp.height, x, y, w, h); c.restore();
  }

  function drawText(c, s) {
    const tm = textMetrics(s, meas);
    c.font = fontCss(s.size, s.bold, s.font); c.textBaseline = 'top';
    if (s.bg) {
      const p = s.size * 0.3;
      c.fillStyle = s.bg; roundRectPath(c, s.x - p, s.y - p * 0.6, tm.w + 2 * p, tm.h + p * 1.2, s.size * 0.25); c.fill();
    }
    if (S.editing && S.editing.id === s.id) return;     // the live text box shows the glyphs
    c.fillStyle = s.color;
    tm.lines.forEach((line, i) => c.fillText(line, s.x, s.y + i * tm.lineHeight));
  }

  /** Speech-bubble numeral, as the native app draws it: a filled circle (capsule for "1.2.3") and a pointer that turns with `angle`. */
  function drawCounter(c, s) {
    const g = counterGeometry(s, meas), spread = 0.55;
    const onOutline = a => ({ x: s.x + g.w / 2 * Math.cos(a), y: s.y + g.h / 2 * Math.sin(a) });
    c.fillStyle = s.color; roundRectPath(c, g.x, g.y, g.w, g.h, g.h / 2); c.fill();
    const p1 = onOutline(g.angle - spread), p2 = onOutline(g.angle + spread);
    c.beginPath(); c.moveTo(p1.x, p1.y); c.lineTo(g.tip.x, g.tip.y); c.lineTo(p2.x, p2.y); c.closePath(); c.fill();
    if (S.editing && S.editing.id === s.id) return;
    c.fillStyle = ink(s); c.textAlign = 'center'; c.textBaseline = 'middle';
    c.font = fontCss(s.size * 0.54, true, 'system');
    c.fillText(s.label, s.x, s.y + s.size * 0.03);
    c.textAlign = 'start';
  }

  function drawShape(c, s) {
    c.save();
    switch (s.type) {
      case 'rect': case 'ellipse': {
        const b = normBox(s);
        c.lineWidth = s.width; c.strokeStyle = s.color; c.lineJoin = 'round';
        if (s.type === 'rect') {
          roundRectPath(c, b.x, b.y, b.w, b.h, Math.min(8, s.width * 1.4));
        } else { c.beginPath(); c.ellipse(b.x + b.w / 2, b.y + b.h / 2, b.w / 2, b.h / 2, 0, 0, Math.PI * 2); }
        if (s.fill) { c.globalAlpha = 0.22; c.fillStyle = s.color; c.fill(); c.globalAlpha = 1; }
        c.stroke(); break;
      }
      case 'highlight': {
        const b = normBox(s);
        c.globalCompositeOperation = 'multiply'; c.fillStyle = s.color; c.globalAlpha = 0.45; c.fillRect(b.x, b.y, b.w, b.h); break;
      }
      case 'line':
        c.strokeStyle = s.color; c.lineWidth = s.width; c.lineCap = 'round';
        c.beginPath(); c.moveTo(s.x1, s.y1); c.lineTo(s.x2, s.y2); c.stroke(); break;
      case 'arrow': drawArrow(c, s); break;
      case 'pen':
        c.strokeStyle = s.color; c.lineWidth = s.width; c.lineCap = 'round'; c.lineJoin = 'round';
        c.beginPath(); s.pts.forEach((p, i) => (i ? c.lineTo(p[0], p[1]) : c.moveTo(p[0], p[1])));
        if (s.pts.length === 1) c.lineTo(s.pts[0][0] + 0.01, s.pts[0][1]);
        c.stroke(); break;
      case 'blur': drawPixelate(c, s); break;
      case 'text': drawText(c, s); break;
      case 'counter': drawCounter(c, s); break;
      case 'spotlight': {        // the darkening is drawn once for all spotlights (paint); here only the outline
        c.strokeStyle = s.color; c.lineWidth = Math.max(1.5, s.width / 2); spotPath(c, s); c.stroke(); break;
      }
      case 'magnifier': drawMagnifier(c, s); break;
      case 'measure': drawMeasure(c, s.x1, s.y1, s.x2, s.y2, s.color, s.labelT); break;
    }
    c.restore();
  }

  function spotPath(c, s) {
    const b = normBox(s);
    if (s.oval) { c.beginPath(); c.ellipse(b.x + b.w / 2, b.y + b.h / 2, b.w / 2, b.h / 2, 0, 0, Math.PI * 2); }
    else roundRectPath(c, b.x, b.y, b.w, b.h, Math.min(6, b.w / 2, b.h / 2));
  }
  /** Everything outside every spotlight darkens (1–9 = 10–90 %); the darkest level asked for wins. */
  function drawSpotlights(c) {
    const spots = S.shapes.filter(s => s.type === 'spotlight' && Math.abs(s.w) > 1 && Math.abs(s.h) > 1);
    if (!spots.length) return;
    const level = Math.max(...spots.map(s => s.level || 6));
    c.save();
    c.beginPath(); c.rect(-1, -1, S.w + 2, S.h + 2);
    for (const s of spots) {
      const b = normBox(s);
      if (s.oval) { c.moveTo(b.x + b.w, b.y + b.h / 2); c.ellipse(b.x + b.w / 2, b.y + b.h / 2, b.w / 2, b.h / 2, 0, 0, Math.PI * 2); }
      else c.rect(b.x, b.y, b.w, b.h);
    }
    c.fillStyle = `rgba(0,0,0,${Math.min(9, Math.max(1, level)) / 10})`; c.fill('evenodd');
    c.restore();
  }

  /** A ring around the source, a dashed connector and a bubble showing the source magnified (native drawMagnifier). */
  function drawMagnifier(c, s) {
    if (s.r < 3) return;
    const g = magnifierGeometry(s), ring = Math.max(2, s.width || 3);
    const dist = Math.hypot(g.bx - s.x, g.by - s.y);
    c.strokeStyle = s.color; c.lineWidth = ring;
    if (dist > s.r + g.br) {
      const ux = (g.bx - s.x) / dist, uy = (g.by - s.y) / dist;
      c.save(); c.setLineDash([6, 4]);
      c.beginPath(); c.moveTo(s.x + ux * s.r, s.y + uy * s.r); c.lineTo(g.bx - ux * g.br, g.by - uy * g.br); c.stroke();
      c.restore();
    }
    c.save();
    c.beginPath(); c.arc(g.bx, g.by, g.br, 0, Math.PI * 2); c.clip();
    c.fillStyle = '#fff'; c.fillRect(g.bx - g.br, g.by - g.br, 2 * g.br, 2 * g.br);
    c.translate(g.bx, g.by); c.scale(g.zoom, g.zoom); c.translate(-s.x, -s.y);
    c.imageSmoothingEnabled = false;      // magnified pixels stay crisp, like Shottr
    c.drawImage(S.base, 0, 0);
    c.restore();
    c.beginPath(); c.arc(g.bx, g.by, g.br, 0, Math.PI * 2); c.stroke();
    c.beginPath(); c.arc(s.x, s.y, s.r, 0, Math.PI * 2); c.stroke();
  }

  /** Length of a measurement as shown: logical pixels (image pixels ÷ display scale), like the native default. */
  const measureText = (x1, y1, x2, y2) => `${Math.round(Math.hypot(x2 - x1, y2 - y1) / S.pixelScale)} px`;
  /** A dimension line with end ticks and its length on a dark pill. Sizes are in screen pixels so it reads at any zoom. */
  function drawMeasure(c, x1, y1, x2, y2, color, labelT = 0.5) {
    const k = exportK || scale(), len = Math.hypot(x2 - x1, y2 - y1);
    if (len < 1) return;
    const nx = -(y2 - y1) / len, ny = (x2 - x1) / len, tick = 5 / k;
    c.save();
    c.strokeStyle = color || '#FF2D92'; c.lineWidth = 1.5 / k; c.lineCap = 'butt';
    c.beginPath(); c.moveTo(x1, y1); c.lineTo(x2, y2);
    c.moveTo(x1 - nx * tick, y1 - ny * tick); c.lineTo(x1 + nx * tick, y1 + ny * tick);
    c.moveTo(x2 - nx * tick, y2 - ny * tick); c.lineTo(x2 + nx * tick, y2 + ny * tick);
    c.stroke();
    const text = measureText(x1, y1, x2, y2);
    c.font = `600 ${12 / k}px system-ui, "Segoe UI", sans-serif`;
    c.fontVariantNumeric = 'tabular-nums';
    const tw = c.measureText(text).width, ph = 18 / k, pw = tw + 12 / k, mx = x1 + (x2 - x1) * labelT, my = y1 + (y2 - y1) * labelT;
    const off = Math.abs(nx) > Math.abs(ny) ? { x: 6 / k + pw / 2, y: 0 } : { x: 0, y: -(6 / k + ph / 2) };   // beside a vertical line, above a horizontal one
    // As the native ruler: a pill in the ruler's colour, lettering black or white for contrast.
    c.fillStyle = color || '#FF2D92'; roundRectPath(c, mx + off.x - pw / 2, my + off.y - ph / 2, pw, ph, 5 / k); c.fill();
    c.fillStyle = readableOn(color || '#FF2D92'); c.textAlign = 'center'; c.textBaseline = 'middle'; c.fillText(text, mx + off.x, my + off.y + 0.5 / k);
    c.restore();
  }
  /** Width and height measured through the same point: put the width's label in the middle of the longer side, clear of the crossing. */
  function crossingLabelT(hm, vm) {
    const cross = (vm.x1 - hm.x1) / (hm.x2 - hm.x1);
    if (!(cross > 0 && cross < 1)) return 0.5;
    return cross > 0.5 ? cross / 2 : (1 + cross) / 2;
  }

  /** Paints picture + marks (+ backdrop) onto `c`, whose origin is the top-left of the whole composite. */
  function paint(c, W, H, ui) {
    const p = pad();
    if (S.bd.on) {
      paintBackdrop(c, W, H);
      c.save();
      c.shadowColor = 'rgba(0,0,0,0.45)'; c.shadowBlur = S.bd.shadow; c.shadowOffsetY = S.bd.shadow * 0.35;
      c.fillStyle = '#000'; roundRectPath(c, p, p, S.w, S.h, S.bd.radius); c.fill();
      c.restore();
      c.save(); roundRectPath(c, p, p, S.w, S.h, S.bd.radius); c.clip();
    } else c.save();
    c.translate(p, p);
    c.drawImage(S.base, 0, 0);
    // Marks are clipped to the picture when a backdrop is on, as in the native app. Spotlights darken the picture first, so arrows and
    // labels drawn after them stay bright.
    drawSpotlights(c);
    for (const s of S.shapes) drawShape(c, s);
    if (ui) drawUi(c);
    c.restore();
  }

  function drawUi(c) {
    const k = scale();
    const sh = selected();
    if (S.tool === 'editText' && S.ocr && S.ocr.base === S.base) {
      for (const line of S.ocr.lines) for (const w of line.words || []) {      // every word is its own target
        const b = w.bbox, hov = S.hover === b.x0 + ',' + b.y0;
        c.strokeStyle = hov ? 'rgba(31,160,255,0.95)' : 'rgba(31,160,255,0.4)';
        c.lineWidth = (hov ? 2 : 1) / k;
        c.fillStyle = hov ? 'rgba(31,160,255,0.16)' : 'rgba(31,160,255,0.04)';
        c.fillRect(b.x0 - 1, b.y0 - 1, b.x1 - b.x0 + 2, b.y1 - b.y0 + 2);
        c.strokeRect(b.x0 - 1, b.y0 - 1, b.x1 - b.x0 + 2, b.y1 - b.y0 + 2);
      }
      if (S.drag && S.drag.mode === 'textRegion') {       // the frame being dragged over the part to change
        const r = normBox({ x: S.drag.start.x, y: S.drag.start.y, w: S.drag.end.x - S.drag.start.x, h: S.drag.end.y - S.drag.start.y });
        c.strokeStyle = '#1FA0FF'; c.lineWidth = 1.5 / k; c.setLineDash([5 / k, 4 / k]); c.strokeRect(r.x, r.y, r.w, r.h); c.setLineDash([]);
      }
    }
    if (sh) {
      const b = boundsOf(sh, meas);
      c.strokeStyle = '#1FA0FF'; c.lineWidth = 1.2 / k; c.setLineDash([5 / k, 4 / k]);
      const g = 4 / k;
      c.strokeRect(b.x - g, b.y - g, b.w + 2 * g, b.h + 2 * g);
      c.setLineDash([]);
      for (const hp of handlePoints(sh, meas)) {
        const r = 4.5 / k;
        c.fillStyle = '#fff'; c.strokeStyle = '#1FA0FF'; c.lineWidth = 1.5 / k;
        c.beginPath();
        if (hp.round) c.arc(hp.x, hp.y, r * 1.15, 0, Math.PI * 2);     // turn / move handles are round, resize handles square
        else c.rect(hp.x - r, hp.y - r, 2 * r, 2 * r);
        c.fill(); c.stroke();
      }
    }
    // Ruler: the element under the pointer measures itself (both ways, or one way while 1 / 2 is held).
    if (S.tool === 'measure' && S.probe && !S.drag) {
      for (const m of probeMarks()) drawMeasure(c, m.x1, m.y1, m.x2, m.y2, '#FF2D92', m.labelT);
    }
    if (S.drag && S.drag.mode === 'measure') drawMeasure(c, S.drag.start.x, S.drag.start.y, S.drag.end.x, S.drag.end.y, '#FF2D92');
    if (S.cropRect) {
      const b = normBox(S.cropRect);
      c.fillStyle = 'rgba(0,0,0,0.55)';
      c.beginPath(); c.rect(0, 0, S.w, S.h); c.rect(b.x, b.y, b.w, b.h); c.fill('evenodd');
      c.strokeStyle = '#fff'; c.lineWidth = 1.5 / k; c.strokeRect(b.x, b.y, b.w, b.h);
      c.fillStyle = '#fff'; c.font = `${12 / k}px system-ui`; c.textBaseline = 'bottom';
      c.fillText(`${Math.round(b.w)} × ${Math.round(b.h)}`, b.x, b.y - 4 / k);
    }
  }

  let drawPending = false;
  function draw() {
    if (!S.base || drawPending) return;
    drawPending = true;
    requestAnimationFrame(() => {
      drawPending = false;
      const W = S.w + 2 * pad(), H = S.h + 2 * pad();
      ctx.setTransform(cv.width / W, 0, 0, cv.height / H, 0, 0);
      ctx.clearRect(0, 0, W, H);
      ctx.imageSmoothingQuality = 'high';
      paint(ctx, W, H, true);
      renderReadout();
    });
  }
  /** Bar readout: picture size, or the colour under the pointer while the colour picker is active. */
  function renderReadout() {
    const el = $('#readout');
    if (S.tool === 'eyedropper' && S.pick) {
      el.textContent = '';
      const sw = document.createElement('span'); sw.className = 'pick-swatch'; sw.style.background = S.pick.hex;
      el.append(sw, S.pick.hex);
    } else el.textContent = `${S.w} × ${S.h}`;
  }
  function drawNow() {   // for tests and exports: draw synchronously
    const W = S.w + 2 * pad(), H = S.h + 2 * pad();
    ctx.setTransform(cv.width / W, 0, 0, cv.height / H, 0, 0);
    ctx.clearRect(0, 0, W, H);
    paint(ctx, W, H, true);
  }

  /** The picture as it will be saved: marks at their size when viewed at 100 %, whatever the zoom on screen. */
  let exportK = null;
  function exportCanvas() {
    const p = pad(), W = S.w + 2 * p, H = S.h + 2 * p;
    const out = document.createElement('canvas'); out.width = W; out.height = H;
    const c = out.getContext('2d');
    const keep = S.editing; S.editing = null; exportK = 1 / S.pixelScale;
    try { paint(c, W, H, false); } finally { S.editing = keep; exportK = null; }
    return out;
  }
  function exportDataURL() { return exportCanvas().toDataURL('image/png'); }

  // ---------------------------------------------------------------- bar
  // Keys as in the native app: V C R O A L P T B N H S M G E (+ I for the colour picker).
  const TOOLS = [
    ['select', 'Select', 'V'], ['rect', 'Rectangle', 'R'], ['ellipse', 'Ellipse', 'O'], ['arrow', 'Arrow', 'A'], ['line', 'Line', 'L'],
    ['pen', 'Pen', 'P'], ['highlight', 'Highlight', 'H'], ['text', 'Text', 'T'], ['counter', 'Counter', 'N'], ['blur', 'Hide (pixelate)', 'B'],
    ['spotlight', 'Spotlight', 'S'], ['magnifier', 'Magnifier', 'G'], ['measure', 'Ruler', 'M'], ['eyedropper', 'Colour picker', 'I'],
    ['crop', 'Crop', 'C'], ['editText', 'Edit text in picture', 'E'],
  ];
  const buttons = {};
  function button(id, icon, label, onClick, opts = {}) {
    const b = document.createElement('button');
    b.className = 'cb' + (opts.text ? ' text' : '') + (opts.primary ? ' primary' : '');
    b.type = 'button'; b.title = opts.shortcut ? `${t(label)}  (${opts.shortcut})` : t(label);
    b.setAttribute('aria-label', t(label));
    b.innerHTML = svg(icon) + (opts.text ? `<span>${t(opts.text)}</span>` : '');
    b.addEventListener('mousedown', e => e.preventDefault());   // keep focus (and the text box) where it is
    b.addEventListener('click', onClick);
    buttons[id] = b;
    return b;
  }
  const MOD = mac ? '⌘' : 'Ctrl+', SHIFT = mac ? '⇧' : 'Shift+';
  function buildBar() {
    for (const g of ['#g-history', '#g-tools', '#g-extras', '#g-zoom', '#g-share']) $(g).textContent = '';
    $('#g-tools').setAttribute('aria-label', t('Tools'));
    $('#g-history').append(button('undo', 'undo', 'Undo', undo, { shortcut: MOD + 'Z' }), button('redo', 'redo', 'Redo', redo, { shortcut: mac ? '⌘⇧Z' : 'Ctrl+Y' }));
    const tools = $('#g-tools');
    for (const [id, label, key] of TOOLS) {
      const b = button('tool-' + id, id, label, () => setTool(id), { shortcut: key });
      b.setAttribute('aria-pressed', 'false');
      tools.append(b);
    }
    $('#g-extras').append(
      button('pii', 'pii', 'Hide personal data (PII)', () => hidePII(), { shortcut: MOD + SHIFT + 'H' }),
      button('ocr', 'ocr', 'Read text (OCR)', runOcr, { shortcut: SHIFT + 'T' }),
      button('backdrop', 'backdrop', 'Backdrop', toggleBackdropPanel, { shortcut: 'K' }),
      button('license', 'key', 'License', () => api.openLicense()),
    );
    const zoomval = Object.assign(document.createElement('button'), { className: 'zoomval', id: 'zoomval', type: 'button', title: t('Actual size (100%)') });
    zoomval.addEventListener('mousedown', e => e.preventDefault());
    zoomval.addEventListener('click', () => setZoom(1));
    $('#g-zoom').append(
      button('zoomOut', 'zoomOut', 'Zoom out', () => setZoom(S.zoom / 1.25), { shortcut: '−' }),
      zoomval,
      button('zoomIn', 'zoomIn', 'Zoom in', () => setZoom(S.zoom * 1.25), { shortcut: '+' }),
      button('fit', 'fit', 'Fit to window', () => setZoom(fitZoom(), true), { shortcut: '0' }),
    );
    $('#g-share').append(
      button('upload', 'upload', 'Upload and copy the link', () => uploadImage()),
      button('pin', 'pin', 'Pin to the screen', () => pinImage()),
      button('save', 'save', 'Save', () => saveImage(), { shortcut: MOD + 'S', text: 'Save' }),
      button('copy', 'copy', 'Copy picture', copyImage, { shortcut: MOD + 'C', text: 'Copy', primary: true }),
      button('more', 'more', 'More', e => showMoreMenu(e.currentTarget)),
    );
    buttons.more.setAttribute('aria-haspopup', 'menu');
  }
  function refreshChrome() {
    buttons.undo.disabled = !S.undo.length; buttons.redo.disabled = !S.redo.length;
    for (const [id] of TOOLS) buttons['tool-' + id].setAttribute('aria-pressed', String(S.tool === id));
    buttons.backdrop.setAttribute('aria-pressed', String(!$('#backdrop').hidden));
    $('#zoomval').textContent = `${Math.round(S.zoom * 100)}%`;
  }

  // ---------------------------------------------------------------- narrow windows: fold low-priority groups into the ⋯ menu
  // Order matters: the first entries fold first. Tools fold last, from the end of the row.
  const folded = new Set();
  function foldSteps() {
    return [
      ['readout', [$('#readout')]], ['brand', [$('.brand')]], ['extras', [$('#g-extras'), $('#sep-extras')]], ['zoom', [$('#g-zoom'), $('#sep-zoom')]],
      ['shareExtras', [buttons.upload, buttons.pin]],
      ['saveLabel', null], ['copyLabel', null],
      ...TOOLS.slice(1).reverse().map(([id]) => ['tool-' + id, [buttons['tool-' + id]]]),
    ];
  }
  function setFolded(name, els, on) {
    if (on) folded.add(name); else folded.delete(name);
    if (name === 'saveLabel') buttons.save.classList.toggle('icon-only', on);
    else if (name === 'copyLabel') buttons.copy.classList.toggle('icon-only', on);
    else for (const el of els) if (el) el.classList.toggle('folded', on);
  }
  function fitBar() {
    const bar = $('#bar');
    const steps = foldSteps();
    for (const [name, els] of steps) setFolded(name, els, false);
    for (const [name, els] of steps) {
      if (bar.scrollWidth <= bar.clientWidth + 1) break;
      setFolded(name, els, true);
    }
  }
  function moreMenuItems() {
    const items = [];
    const toolItems = TOOLS.filter(([id]) => folded.has('tool-' + id)).map(([id, label, key]) => ({ id: 'tool:' + id, label: t(label), checked: S.tool === id, accelerator: key }));
    if (toolItems.length) items.push({ label: t('Tools'), submenu: toolItems });
    if (folded.has('extras')) {
      items.push({ id: 'pii', label: t('Hide personal data (PII)'), accelerator: 'CommandOrControl+Shift+H' }, { id: 'ocr', label: t('Read text (OCR)'), accelerator: 'Shift+T' },
        { id: 'backdrop', label: t('Backdrop'), checked: !$('#backdrop').hidden, accelerator: 'K' });
    }
    if (folded.has('zoom')) {
      items.push({ type: 'separator' }, { id: 'zoomIn', label: t('Zoom in'), accelerator: '=' }, { id: 'zoomOut', label: t('Zoom out'), accelerator: '-' },
        { id: 'fit', label: t('Fit to window'), accelerator: '0' }, { id: 'actual', label: t('Actual size (100%)') });
    }
    items.push({ type: 'separator' }, { id: 'saveAs', label: t('Save as…'), accelerator: 'CommandOrControl+Shift+S' }, { id: 'copy', label: t('Copy picture'), accelerator: 'CommandOrControl+C' });
    if (folded.has('shareExtras')) items.push({ id: 'upload', label: t('Upload and copy the link') }, { id: 'pin', label: t('Pin to the screen') });
    items.push({ id: 'print', label: t('Print…'), accelerator: 'CommandOrControl+P' }, { id: 'gif', label: t('Before / after GIF') });
    return items.filter((it, i, a) => !(it.type === 'separator' && (i === 0 || a[i - 1].type === 'separator')));
  }
  function showMoreMenu(anchor) {
    const r = anchor.getBoundingClientRect();
    api.showMenu({ x: r.left, y: r.bottom + 4, items: moreMenuItems() });
  }
  const COMMANDS = {
    pii: () => hidePII(), ocr: () => runOcr(), backdrop: () => toggleBackdropPanel(), zoomIn: () => setZoom(S.zoom * 1.25), zoomOut: () => setZoom(S.zoom / 1.25),
    fit: () => setZoom(fitZoom(), true), actual: () => setZoom(1), saveAs: () => saveImage({ saveAs: true }), copy: () => copyImage(),
    upload: () => uploadImage(), pin: () => pinImage(), print: () => printImage(), gif: () => exportGif(),
  };
  function runCommand(id) {
    if (id.startsWith('tool:')) { setTool(id.slice(5)); return; }
    if (COMMANDS[id]) COMMANDS[id]();
  }

  /** Language switched elsewhere: relabel everything in place. */
  function relabel(next) {
    lang = next; document.documentElement.lang = lang;
    buildBar(); renderStrip(); if (!$('#backdrop').hidden) renderBackdropPanel();
    refreshChrome(); fitBar();
  }

  function setTool(id) {
    if (S.editing) closeEditor(true);
    if (S.tool === 'crop' && id !== 'crop') S.cropRect = null;
    if (id !== 'select' && id !== S.tool && S.sel != null) S.sel = null;      // a new tool starts fresh; click a mark to edit it
    S.tool = id;
    S.probe = null; S.pick = null; S.measureAxis = 'both';
    if (id === 'measure' || id === 'eyedropper') S.sel = null;     // the strip explains the tool, not a mark
    cv.className = id === 'select' ? 'cur-default' : id === 'text' ? 'cur-text' : 'cur-cross';
    if (id === 'editText') ensureOcr();
    renderStrip(); refreshChrome(); draw();
  }

  // ---------------------------------------------------------------- context strip
  function swatchRow(opts) {
    const wrap = document.createElement('div'); wrap.className = 'swatches'; wrap.setAttribute('role', 'radiogroup'); wrap.setAttribute('aria-label', t(opts.label));
    const choose = value => opts.onPick(value);
    const mk = (cls, text, value) => {
      const b = document.createElement('button'); b.type = 'button'; b.className = cls; b.textContent = text || '';
      b.setAttribute('role', 'radio'); b.setAttribute('aria-checked', String(opts.value === value));
      b.addEventListener('mousedown', e => e.preventDefault()); b.addEventListener('click', () => choose(value));
      wrap.append(b); return b;
    };
    if (opts.auto) mk('sw auto', t('Auto'), 'auto');
    if (opts.none) mk('sw none', t('None'), null);
    for (const c of PALETTE) { const b = mk('sw', '', c); b.style.background = c; b.title = c; b.setAttribute('aria-label', c); }
    const custom = document.createElement('span'); custom.className = 'sw custom'; custom.title = t('Custom colour');
    const input = document.createElement('input'); input.type = 'color'; input.value = /^#[0-9a-f]{6}$/i.test(opts.value || '') ? opts.value : '#ff3b30';
    input.setAttribute('aria-label', t('Custom colour'));
    input.addEventListener('input', () => choose(input.value));   // live while the colour dialog is dragged
    custom.append(input); wrap.append(custom);
    return wrap;
  }
  function field(label, node) {
    const f = document.createElement('div'); f.className = 'field';
    const l = document.createElement('label'); l.textContent = t(label);
    f.append(l, node); return f;
  }
  function slider(min, max, value, onInput, suffix = '') {
    const wrap = document.createElement('div'); wrap.className = 'field';
    const r = document.createElement('input'); r.type = 'range'; r.min = min; r.max = max; r.value = value;
    const n = document.createElement('span'); n.className = 'num'; n.textContent = value + suffix;
    r.addEventListener('input', () => { n.textContent = r.value + suffix; onInput(Number(r.value)); });
    wrap.append(r, n); return wrap;
  }
  function seg(label, options, value, onPick) {
    const wrap = document.createElement('div'); wrap.className = 'seg'; wrap.setAttribute('role', 'radiogroup'); wrap.setAttribute('aria-label', t(label));
    for (const [v, text] of options) {
      const b = document.createElement('button'); b.type = 'button'; b.textContent = t(text); b.setAttribute('role', 'radio');
      b.setAttribute('aria-checked', String(value === v));
      b.addEventListener('mousedown', e => e.preventDefault()); b.addEventListener('click', () => onPick(v));
      wrap.append(b);
    }
    return wrap;
  }

  /** The value a control should show: the selected mark's own, else the default for the next mark. */
  function val(key, shapeKey) {
    const sh = selected();
    if (sh && shapeKey in sh) return sh[shapeKey];
    return S.style[key];
  }
  function context() {
    const sh = selected();
    if (sh) return sh.type;
    return S.tool;
  }

  function renderStrip() {
    const strip = $('#strip');
    strip.textContent = '';
    const kind = context();
    const colour = (label, key = 'color', shapeKey = 'color') =>
      field(label, swatchRow({ label, value: val(key, shapeKey), onPick: v => applyStyle({ color: v }, 'color') }));
    switch (kind) {
      case 'rect': case 'ellipse':
        strip.append(colour('Colour'), field('Width', slider(1, 20, val('width', 'width'), v => applyStyle({ width: v }, 'width'), ' px')),
          field('Style', seg('Style', [[false, 'Outline'], [true, 'Tinted']], !!val('fill', 'fill'), v => applyStyle({ fill: v }, 'fill'))));
        break;
      case 'arrow': case 'line': case 'pen':
        strip.append(colour('Colour'), field('Width', slider(1, 24, val('width', 'width'), v => applyStyle({ width: v }, 'width'), ' px')));
        break;
      case 'highlight': strip.append(colour('Colour')); break;
      case 'blur':
        strip.append(field('Block size', slider(4, 48, val('blur', 'strength'), v => applyStyle({ blur: v }, 'blur'), ' px')),
          hint(t('Drag over what you want to hide. Pixelation cannot be undone by anyone who only has the saved picture.')));
        break;
      case 'text': {
        const sh2 = selected();
        strip.append(
          field('Text colour', swatchRow({ label: 'Text colour', value: val('color', 'color'), onPick: v => applyStyle({ color: v }, 'color') })),
          field('Background', swatchRow({ label: 'Background', none: true, value: sh2 ? sh2.bg : S.style.bg, onPick: v => applyStyle({ bg: v }, 'bg') })),
          field('Size', slider(8, 160, val('textSize', 'size'), v => applyStyle({ textSize: v }, 'size'), ' px')),
          field('Font', fontSelect()),
          field('Weight', seg('Weight', [[false, 'Regular'], [true, 'Bold']], !!val('bold', 'bold'), v => applyStyle({ bold: v }, 'bold'))));
        break;
      }
      case 'counter': {
        const sh2 = selected();
        strip.append(
          field('Colour', swatchRow({ label: 'Colour', value: val('color', 'color'), onPick: v => applyStyle({ color: v }, 'color') })),
          field('Number colour', swatchRow({ label: 'Number colour', auto: true, value: sh2 ? sh2.textColor : S.style.textColor, onPick: v => applyStyle({ textColor: v }, 'textColor') })),
          field('Size', slider(16, 120, val('counterSize', 'size'), v => applyStyle({ counterSize: v }, 'size'), ' px')),
          counterValue());
        if (sh2) strip.append(hint(t('Drag the round handle to turn the pointer.')));
        break;
      }
      case 'spotlight':
        strip.append(field('Darkness', slider(1, 9, val('level', 'level'), v => applyStyle({ level: v }, 'level'))),
          field('Shape', seg('Shape', [[false, 'Rectangle'], [true, 'Oval']], !!val('oval', 'oval'), v => applyStyle({ oval: v }, 'oval'))),
          colour('Outline'), hint(t('Keys 1–9 set the darkness.')));
        break;
      case 'magnifier':
        strip.append(field('Zoom', seg('Zoom', [[2, '2×'], [3, '3×'], [4, '4×']], val('zoom', 'zoom'), v => applyStyle({ zoom: v }, 'zoom'))),
          colour('Colour'), field('Width', slider(1, 12, val('width', 'width'), v => applyStyle({ width: v }, 'width'), ' px')),
          hint(t('Drag from the centre of what to enlarge. Drag the bubble to move it.')));
        break;
      case 'measure':
        strip.append(hint(t('Point at something: it measures itself. Hold 1 for height only, 2 for width only. Click to keep it on the picture; drag to measure a line.')));
        break;
      case 'eyedropper':
        strip.append(hint(t('Click to copy the colour under the pointer. It also becomes the colour for new marks.')));
        break;
      case 'editText':
        strip.append(hint(S.ocr && S.ocr.base === S.base ? t('Click a word, or drag a frame over the part to change, to retype it in the same font, size and colour. Shift-click takes the whole line.') : t('Reading the text in the picture…')));
        break;
      case 'crop': {
        const apply = Object.assign(document.createElement('button'), { className: 'btn primary', textContent: t('Apply crop') });
        const cancel = Object.assign(document.createElement('button'), { className: 'btn', textContent: t('Cancel') });
        apply.disabled = !S.cropRect;
        apply.addEventListener('click', applyCrop); cancel.addEventListener('click', () => { S.cropRect = null; renderStrip(); draw(); });
        strip.append(hint(t('Drag the area to keep, then press Enter.')), apply, cancel);
        break;
      }
      default:
        strip.append(hint(S.tool === 'select' ? t('Choose a tool above, or click a mark to change its colour and size. Everything applies as you click.') : ''));
    }
    const sh = selected();
    if (sh) {
      const del = button('delete', 'trash', 'Delete', deleteSelected, { shortcut: '⌫' });
      del.style.marginLeft = 'auto';
      strip.append(del);
    }
  }
  function hint(text) { const s = document.createElement('span'); s.className = 'hint'; s.textContent = text; return s; }
  function fontSelect() {
    const sel = document.createElement('select'); sel.className = 'fld'; sel.setAttribute('aria-label', t('Font'));
    const current = val('font', 'font');
    const list = FONTS.slice();
    if (!list.some(([v]) => v === current)) list.push([current, String(current).replace(/"/g, '').split(',')[0]]);
    for (const [v, label] of list) { const o = document.createElement('option'); o.value = v; o.textContent = v === 'system' ? t('System') : label; if (v === current) o.selected = true; sel.append(o); }
    sel.addEventListener('change', () => applyStyle({ font: sel.value }, 'font'));
    return sel;
  }
  function counterValue() {
    const wrap = document.createElement('div'); wrap.className = 'field';
    const sh = selected();
    const input = document.createElement('input'); input.className = 'fld'; input.setAttribute('aria-label', t('Number'));
    // With a counter selected this edits it; with none, it sets what the next counter will say (native: setCounterText).
    input.value = sh ? sh.label : shapeCounterLabel(); input.title = t('Type any text: 1.1, 3.6, A2'); input.id = 'counter-value';
    const set = text => { if (sh) setCounterLabel(sh, text); else { S.counterNext = text; renderStrip(); } };
    const commit = () => { const v = input.value.trim(); if (v && v !== (sh ? sh.label : shapeCounterLabel())) set(v); };
    input.addEventListener('change', commit);
    input.addEventListener('keydown', e => { e.stopPropagation(); if (e.key === 'Enter') { commit(); input.blur(); } });
    const mk = (icon, delta, label) => button('c' + delta, icon, label, () => set(CounterText.step(sh ? sh.label : shapeCounterLabel(), delta)));
    wrap.append(input, mk('minus', -1, 'Previous number'), mk('plus', 1, 'Next number'));
    const lab = document.createElement('label'); lab.textContent = t(sh ? 'Number' : 'Next number'); lab.style.cssText = 'color:var(--text-muted);font-size:11.5px;font-weight:500';
    const f = document.createElement('div'); f.className = 'field'; f.append(lab, wrap);
    if (!sh) f.append(hint(t('double-click a number to edit')));
    return f;
  }
  /** A counter given new text becomes the one the next counter continues from (native: its serial is renewed). */
  function setCounterLabel(sh, label) {
    pushUndo(); sh.label = label; sh.serial = nextSerial(); S.counterNext = null; draw(); renderStrip();
  }

  /** Change colour/size/etc. now: on the selected mark and as the default for the next one. */
  function applyStyle(patch, group) {
    Object.assign(S.style, patch);
    const sh = selected();
    if (sh) {
      coalesce(group);
      const map = { color: 'color', width: 'width', fill: 'fill', bg: 'bg', bold: 'bold', font: 'font', textColor: 'textColor', blur: 'strength', level: 'level', oval: 'oval', zoom: 'zoom' };
      for (const [k, v] of Object.entries(patch)) {
        if (k in map && (map[k] in sh || (k === 'blur' && sh.type === 'blur'))) sh[map[k]] = v;
        if (k === 'textSize' && sh.type === 'text') sh.size = v;
        if (k === 'counterSize' && sh.type === 'counter') sh.size = v;
      }
    }
    if (S.editing) styleEditor();
    draw();
    if (!['width', 'textSize', 'counterSize', 'blur', 'level'].some(k => k in patch)) renderStrip();     // sliders keep their focus
  }

  // ---------------------------------------------------------------- in-place editors (text and counter numbers)
  function openEditor(shape, opts = {}) {
    closeEditor(true);
    S.editing = { id: shape.id, kind: shape.type, isNew: !!opts.isNew, original: shape.type === 'text' ? shape.text : shape.label, undoDepth: S.undo.length };
    const box = $('#editbox'); box.hidden = false; box.textContent = '';
    const el = shape.type === 'text' ? document.createElement('textarea') : document.createElement('input');
    el.spellcheck = false; el.setAttribute('aria-label', shape.type === 'text' ? t('Text') : t('Number'));
    el.value = shape.type === 'text' ? shape.text : shape.label;
    box.append(el);
    S.editing.el = el;
    el.addEventListener('input', () => {
      if (shape.type === 'text') shape.text = el.value; else shape.label = el.value || ' ';
      positionEditor(); draw();
    });
    el.addEventListener('keydown', e => {
      e.stopPropagation();
      if (e.key === 'Escape') { closeEditor(false); }
      else if (e.key === 'Enter' && (shape.type === 'counter' || e.metaKey || e.ctrlKey)) { e.preventDefault(); closeEditor(true); }
    });
    el.addEventListener('blur', () => { if (S.editing && S.editing.el === el) closeEditor(true); });
    styleEditor(); positionEditor();
    el.focus();
    if (opts.selectAll) el.select(); else el.setSelectionRange(el.value.length, el.value.length);   // caret at the end, never replacing the text
    draw();
  }
  function editedShape() { return S.editing ? S.shapes.find(s => s.id === S.editing.id) : null; }
  function styleEditor() {
    const sh = editedShape(); if (!sh) return;
    const el = S.editing.el, k = scale();
    if (sh.type === 'text') {
      Object.assign(el.style, { font: fontCss(sh.size * k, sh.bold, sh.font), lineHeight: `${sh.size * 1.25 * k}px`, color: sh.color });
    } else {
      Object.assign(el.style, { font: fontCss(sh.size * 0.54 * k, true, 'system'), color: ink(sh), textAlign: 'center', lineHeight: `${sh.size * k}px` });
    }
  }
  function positionEditor() {
    const sh = editedShape(); if (!sh) return;
    const el = S.editing.el, k = scale();
    const stage = $('#stage').getBoundingClientRect(), r = cv.getBoundingClientRect();
    const origin = { x: r.left - stage.left + pad() * k, y: r.top - stage.top + pad() * k };
    const box = $('#editbox');
    if (sh.type === 'text') {
      const tm = textMetrics(sh, meas);
      Object.assign(el.style, { left: `${origin.x + sh.x * k}px`, top: `${origin.y + sh.y * k}px`, width: `${Math.max(40, tm.w * k + 8)}px`, height: `${tm.h * k + 2}px` });
    } else {
      const g = counterGeometry(sh, meas);
      Object.assign(el.style, { left: `${origin.x + g.x * k}px`, top: `${origin.y + g.y * k}px`, width: `${g.w * k}px`, height: `${g.h * k}px`, outlineOffset: '2px' });
    }
    box.style.left = '0'; box.style.top = '0';
  }
  /** Finish editing. keep=false puts the old text back. */
  function closeEditor(keep) {
    if (!S.editing) return;
    const ed = S.editing, sh = editedShape();
    S.editing = null;
    $('#editbox').hidden = true; $('#editbox').textContent = '';
    if (sh) {
      if (sh.type === 'text') {
        if (!keep) sh.text = ed.original;
        if (!sh.text.trim()) { S.shapes = S.shapes.filter(s => s !== sh); if (S.sel === sh.id) S.sel = null; }
      } else {
        if (!keep || !String(sh.label).trim()) sh.label = ed.original;
        sh.label = String(sh.label).trim() || ed.original;
        // As in the native app, a counter given new text is the one the next counter continues from.
        if (sh.label !== ed.original) { sh.serial = nextSerial(); S.counterNext = null; }
      }
      if (!keep && ed.isNew) { S.shapes = S.shapes.filter(s => s !== sh); S.sel = null; }
    }
    renderStrip(); draw(); refreshChrome();
  }

  // ---------------------------------------------------------------- creating, selecting and dragging marks
  const newShape = (type, props) => ({ id: S.nextId++, type, ...props });
  function hitTest(p) {
    const tol = 5 / scale();
    for (let i = S.shapes.length - 1; i >= 0; i--) if (hit(S.shapes[i], p.x, p.y, tol, meas)) return S.shapes[i];
    return null;
  }
  /** Grab points of the selected mark (round ones a little more forgiving, as they are small targets on a moving mark). */
  function hitHandle(p) {
    const sh = selected(); if (!sh) return null;
    const r = 8 / scale();
    return handlePoints(sh, meas).find(h => (h.round ? Math.hypot(h.x - p.x, h.y - p.y) <= r * 1.2 : Math.abs(h.x - p.x) <= r && Math.abs(h.y - p.y) <= r)) || null;
  }
  function select(id) { if (S.sel !== id) { S.sel = id; renderStrip(); } draw(); }
  /** Native behaviour: the mark you take comes to the front; ⌥ / Alt while pressing takes a copy instead. */
  function takeMark(over, e) {
    pushUndo();
    let mark = over;
    if (e.altKey) {
      mark = JSON.parse(JSON.stringify(over)); mark.id = S.nextId++;
      if (mark.type === 'counter') mark.serial = nextSerial();
      S.shapes.push(mark);
    } else if (S.shapes[S.shapes.length - 1] !== over) {
      S.shapes = S.shapes.filter(s => s !== over); S.shapes.push(over);
    }
    select(mark.id);
    S.drag = { mode: 'move', shape: mark, last: null };
    cv.className = 'cur-move';
    return mark;
  }

  function onDown(e) {
    if (!S.base || e.button !== 0) return;
    if (S.editing) closeEditor(true);
    const p = eventPoint(e);
    try { cv.setPointerCapture(e.pointerId); } catch { /* synthetic events */ }

    // Grab points of the selected mark win over starting something new, whatever the tool (except crop) — native order.
    const handle = S.tool !== 'crop' && hitHandle(p);
    if (handle) { pushUndo(); S.drag = { mode: 'handle', handle: handle.name, shape: selected() }; return; }

    if (e.detail === 2) { const h = hitTest(p); if (h && (h.type === 'text' || h.type === 'counter')) { select(h.id); openEditor(h, { selectAll: false }); return; } }

    const t0 = S.tool;
    const over = hitTest(p);
    // Pressing an existing mark with ANY drawing tool selects and moves that mark instead of starting another one (hold Ctrl to draw a new
    // one right on top of it). Enter, or clicking empty space, lets the next press start a new mark.
    // Big area marks (spotlight, highlight, pixelate, tinted shapes) only take the press when selected or when their own tool is active, or they
    // would block drawing anything on top of them.
    const area = over && (['spotlight', 'highlight', 'blur'].includes(over.type) || over.fill) && over.id !== S.sel && over.type !== t0;
    const moveIt = over && !area && !(e.ctrlKey || e.metaKey) && !['crop', 'editText', 'measure', 'eyedropper'].includes(t0);
    if (t0 === 'select' || moveIt) {
      if (over) { takeMark(over, e); S.drag.last = p; }
      else { select(null); S.drag = null; }
      return;
    }
    if (t0 === 'editText') { S.drag = { mode: 'textRegion', start: p, end: p, whole: e.shiftKey }; return; }
    if (t0 === 'eyedropper') { pickColour(p); return; }
    if (t0 === 'measure') { S.drag = { mode: 'measure', start: p, end: p }; return; }    // a click keeps the live measurement, a drag draws a line
    if (t0 === 'crop') { S.cropRect = { x: clampX(p.x), y: clampY(p.y), w: 0, h: 0 }; S.drag = { mode: 'crop' }; renderStrip(); return; }
    if (t0 === 'text') {
      pushUndo();
      const sh = newShape('text', { x: p.x, y: p.y, text: '', size: S.style.textSize, font: S.style.font, bold: S.style.bold, color: S.style.color, bg: S.style.bg });
      S.shapes.push(sh); S.sel = sh.id; renderStrip(); openEditor(sh, { isNew: true }); return;
    }
    if (t0 === 'counter') {
      pushUndo();
      // Every new counter points down-left (native default); its own handle turns it.
      const sh = newShape('counter', { x: p.x, y: p.y, size: S.style.counterSize, label: shapeCounterLabel(), color: S.style.color, textColor: S.style.textColor, serial: nextSerial() });
      S.counterNext = null;
      S.shapes.push(sh); S.sel = sh.id; renderStrip(); draw(); return;
    }
    // Drawing tools
    pushUndo();
    let sh;
    switch (t0) {
      case 'rect': case 'ellipse': sh = newShape(t0, { x: p.x, y: p.y, w: 0, h: 0, color: S.style.color, width: S.style.width, fill: S.style.fill }); break;
      case 'highlight': sh = newShape('highlight', { x: p.x, y: p.y, w: 0, h: 0, color: S.style.color === '#FFFFFF' ? '#FFCC00' : S.style.color }); break;
      case 'blur': sh = newShape('blur', { x: p.x, y: p.y, w: 0, h: 0, strength: S.style.blur }); break;
      case 'spotlight': sh = newShape('spotlight', { x: p.x, y: p.y, w: 0, h: 0, level: S.style.level, oval: S.style.oval, color: S.style.color, width: S.style.width }); break;
      case 'magnifier': sh = newShape('magnifier', { x: p.x, y: p.y, r: 0, zoom: S.style.zoom, color: S.style.color, width: Math.min(6, S.style.width) }); break;
      case 'arrow': case 'line': sh = newShape(t0, { x1: p.x, y1: p.y, x2: p.x, y2: p.y, color: S.style.color, width: S.style.width }); break;
      case 'pen': sh = newShape('pen', { pts: [[p.x, p.y]], color: S.style.color, width: S.style.width }); break;
      default: S.undo.pop(); return;
    }
    S.shapes.push(sh); S.sel = sh.id; S.drag = { mode: 'draw', shape: sh, start: p };
    draw();
  }
  const clampX = x => Math.max(0, Math.min(S.w, x)), clampY = y => Math.max(0, Math.min(S.h, y));

  function onMove(e) {
    if (!S.base) return;
    const p = eventPoint(e), d = S.drag;
    if (!d) { hoverCursor(p); return; }
    if (d.mode === 'move') { moveShape(d.shape, p.x - d.last.x, p.y - d.last.y); d.last = p; draw(); return; }
    if (d.mode === 'handle') {
      const sh = d.shape;
      let x = p.x, y = p.y;
      if (LINE_TYPES.includes(sh.type) && e.shiftKey) { const ox = d.handle === 'p1' ? sh.x2 : sh.x1, oy = d.handle === 'p1' ? sh.y2 : sh.y1; [x, y] = snap45(ox, oy, x, y); }
      dragHandle(sh, d.handle, x, y);      // a counter's pointer turns freely towards the mouse, as in the native app
      draw(); return;
    }
    if (d.mode === 'textRegion') { d.end = p; draw(); return; }
    if (d.mode === 'measure') {
      d.end = e.shiftKey ? (() => { const [x, y] = snap45(d.start.x, d.start.y, p.x, p.y); return { x, y }; })() : p;
      draw(); return;
    }
    if (d.mode === 'crop') { S.cropRect.w = clampX(p.x) - S.cropRect.x; S.cropRect.h = clampY(p.y) - S.cropRect.y; draw(); return; }
    if (d.mode === 'draw') {
      const sh = d.shape;
      switch (sh.type) {
        case 'rect': case 'ellipse': case 'highlight': case 'blur': case 'spotlight': {
          let w = p.x - d.start.x, h = p.y - d.start.y;
          if (e.shiftKey && sh.type !== 'blur') { const s = Math.max(Math.abs(w), Math.abs(h)); w = Math.sign(w || 1) * s; h = Math.sign(h || 1) * s; }
          sh.w = w; sh.h = h; break;
        }
        case 'magnifier': sh.r = Math.hypot(p.x - d.start.x, p.y - d.start.y); break;
        case 'arrow': case 'line': { let [x, y] = e.shiftKey ? snap45(sh.x1, sh.y1, p.x, p.y) : [p.x, p.y]; sh.x2 = x; sh.y2 = y; break; }
        case 'pen': { const last = sh.pts[sh.pts.length - 1]; if (Math.hypot(p.x - last[0], p.y - last[1]) > 1.2 / scale()) sh.pts.push([p.x, p.y]); break; }
      }
      draw();
    }
  }
  function snap45(ox, oy, x, y) {
    const dx = x - ox, dy = y - oy, len = Math.hypot(dx, dy), a = Math.round(Math.atan2(dy, dx) / (Math.PI / 4)) * (Math.PI / 4);
    return [ox + len * Math.cos(a), oy + len * Math.sin(a)];
  }
  function onUp(e) {
    const d = S.drag; S.drag = null;
    try { cv.releasePointerCapture(e.pointerId); } catch { /* ignore */ }
    if (!d) return;
    if (d.mode === 'draw') {
      const sh = d.shape;
      if (BOX_TYPES.includes(sh.type)) {
        const b = normBox(sh);
        if (b.w < 3 && b.h < 3) { discardLast(sh); return; }
        sh.x = b.x; sh.y = b.y; sh.w = b.w; sh.h = b.h;
      } else if (sh.type === 'magnifier' && sh.r < 4) { discardLast(sh); return; }
      else if ((sh.type === 'arrow' || sh.type === 'line') && Math.hypot(sh.x2 - sh.x1, sh.y2 - sh.y1) < 4) { discardLast(sh); return; }
      renderStrip();
    }
    if (d.mode === 'measure') keepMeasurement(d);
    if (d.mode === 'textRegion') { editTextAt(d); S.drag = null; draw(); return; }
    if (d.mode === 'crop') { const b = normBox(S.cropRect); if (b.w < 4 || b.h < 4) S.cropRect = null; else S.cropRect = b; renderStrip(); }
    if (d.mode === 'move') cv.className = S.tool === 'select' ? 'cur-default' : S.tool === 'text' ? 'cur-text' : 'cur-cross';
    draw();
  }
  function discardLast(sh) { S.shapes = S.shapes.filter(s => s !== sh); S.sel = null; S.undo.pop(); renderStrip(); refreshChrome(); draw(); }
  function hoverCursor(p) {
    if (S.tool === 'editText' && S.ocr && S.ocr.base === S.base) {
      const w = wordAt(p), key = w ? w.word.bbox.x0 + ',' + w.word.bbox.y0 : null;
      if (key !== S.hover) { S.hover = key; S.hoverWord = w; draw(); }
      cv.className = w ? 'cur-text' : 'cur-default'; return;
    }
    if (S.tool === 'measure') { S.probe = inPicture(p) ? { x: Math.floor(p.x), y: Math.floor(p.y) } : null; cv.className = 'cur-cross'; draw(); return; }
    if (S.tool === 'eyedropper') { S.pick = inPicture(p) ? pixelAt(p.x, p.y) : null; cv.className = 'cur-cross'; draw(); return; }
    const handle = hitHandle(p);
    if (handle) { cv.className = 'cur-move'; return; }
    const over = hitTest(p);
    if (S.tool === 'select') cv.className = over ? 'cur-move' : 'cur-default';
    else if ((S.tool === 'text' || S.tool === 'counter') && over && over.type === S.tool) cv.className = 'cur-move';
    else cv.className = S.tool === 'text' ? 'cur-text' : 'cur-cross';
  }

  // ---------------------------------------------------------------- ruler and colour picker
  const inPicture = p => p.x >= 0 && p.y >= 0 && p.x < S.w && p.y < S.h;
  let pixels = null;     // RGBA of the current picture, read once per version of it
  function pixelData() {
    if (!pixels || pixels.base !== S.base) pixels = { base: S.base, data: S.base.getContext('2d', { willReadFrequently: true }).getImageData(0, 0, S.w, S.h).data };
    return pixels.data;
  }
  const rgbAt = (x, y) => { const d = pixelData(), i = (y * S.w + x) * 4; return [d[i], d[i + 1], d[i + 2]]; };
  function pixelAt(x, y) {
    const c = rgbAt(Math.max(0, Math.min(S.w - 1, Math.floor(x))), Math.max(0, Math.min(S.h - 1, Math.floor(y))));
    return { rgb: c, hex: hexOf(c) };
  }
  /** The live measurement at the pointer: dimension lines across the flat-coloured element it is on. */
  function probeMarks() {
    const p = S.probe; if (!p) return [];
    const marks = [];
    if (S.measureAxis !== 'v') { const [a, b] = flatRun(rgbAt, S.w, S.h, p.x, p.y, true); marks.push({ x1: a, y1: p.y + 0.5, x2: b + 1, y2: p.y + 0.5 }); }
    if (S.measureAxis !== 'h') { const [a, b] = flatRun(rgbAt, S.w, S.h, p.x, p.y, false); marks.push({ x1: p.x + 0.5, y1: a, x2: p.x + 0.5, y2: b + 1 }); }
    if (marks.length === 2) marks[0].labelT = crossingLabelT(marks[0], marks[1]);
    return marks;
  }
  /** Mouse up with the ruler: a click keeps what is shown, a drag keeps the line drawn. One undo step. */
  function keepMeasurement(d) {
    const dragged = Math.hypot(d.end.x - d.start.x, d.end.y - d.start.y) >= 3;
    const marks = dragged ? [{ x1: d.start.x, y1: d.start.y, x2: d.end.x, y2: d.end.y }] : (S.probe = { x: Math.floor(d.start.x), y: Math.floor(d.start.y) }, probeMarks());
    if (!marks.length || !inPicture(d.start)) return;
    pushUndo();
    for (const m of marks) S.shapes.push(newShape('measure', { ...m, color: '#FF2D92' }));
    S.sel = null; renderStrip();
  }
  async function pickColour(p) {
    if (!inPicture(p)) return;
    S.pick = pixelAt(p.x, p.y);
    S.style.color = S.pick.hex;
    await api.copyText(S.pick.hex);
    toast(t('Copied %@').replace('%@', S.pick.hex));
    renderReadout();
  }

  function deleteSelected() {
    const sh = selected(); if (!sh) return;
    pushUndo(); S.shapes = S.shapes.filter(s => s !== sh); S.sel = null; renderStrip(); draw();
  }
  function duplicateSelected() {
    const sh = selected(); if (!sh) return;
    pushUndo();
    const copy = JSON.parse(JSON.stringify(sh)); copy.id = S.nextId++;
    moveShape(copy, 16, 16);
    if (copy.type === 'counter') { copy.label = shapeCounterLabel(); copy.serial = nextSerial(); S.counterNext = null; }
    S.shapes.push(copy); S.sel = copy.id; renderStrip(); draw();
  }

  // ---------------------------------------------------------------- crop
  function applyCrop() {
    if (!S.cropRect) return;
    const b = normBox(S.cropRect), x = Math.round(b.x), y = Math.round(b.y), w = Math.round(b.w), h = Math.round(b.h);
    if (w < 4 || h < 4) return;
    pushUndo();
    const out = document.createElement('canvas'); out.width = w; out.height = h;
    out.getContext('2d').drawImage(S.base, x, y, w, h, 0, 0, w, h);
    S.base = out; S.w = w; S.h = h; S.ocr = null; S.cropRect = null;
    for (const s of S.shapes) moveShape(s, -x, -y);
    layout(); renderStrip(); draw();
    toast(t('Cropped'));
  }

  // ---------------------------------------------------------------- edit text in the picture (OCR + font matching)
  /** Reads the picture once per version of it; callers share the same pending request. */
  function ensureOcr() {
    if (S.ocr && S.ocr.base === S.base) return Promise.resolve(S.ocr.lines);
    if (S.ocr && S.ocr.pending === S.base) return S.ocr.promise;
    const base = S.base;
    const promise = (async () => {
      try {
        const res = await api.ocr(base.toDataURL('image/png'));
        if (base !== S.base) return [];
        if (res.error) { toast(t('Could not read the text: ') + res.error, true); S.ocr = null; return []; }
        S.ocr = { base, lines: res.lines };
        if (!res.lines.length) toast(t('No text found in the picture'), true);
      } catch (error) { toast(t('Could not read the text: ') + error.message, true); S.ocr = null; }
      renderStrip(); draw();
      return S.ocr ? S.ocr.lines : [];
    })();
    S.ocr = { base: null, pending: base, lines: [], promise };
    renderStrip();
    return promise;
  }
  const THAI = /[฀-๿]/;
  const hasWords = () => S.ocr && S.ocr.base === S.base;
  const inBox = (b, p, m = 2) => p.x >= b.x0 - m && p.x <= b.x1 + m && p.y >= b.y0 - m && p.y <= b.y1 + m;
  /** The recognised word under the point (with the line it belongs to). */
  function wordAt(p) {
    if (!hasWords()) return null;
    for (const line of S.ocr.lines) for (const word of line.words || []) if (inBox(word.bbox, p)) return { line, word };
    return null;
  }
  /**
   * What the user chose to retype: a drag selects the words inside the frame, a click selects the word under the pointer, Shift-click the
   * whole line. Returns { text, bbox, parts: [{ line, words }] } or null.
   */
  function pickText(d) {
    const frame = normBox({ x: d.start.x, y: d.start.y, w: d.end.x - d.start.x, h: d.end.y - d.start.y });
    const dragged = frame.w >= 4 || frame.h >= 4, parts = [];
    for (const line of S.ocr.lines) {
      let words = line.words || [];
      if (d.whole && !dragged) words = inBox(line.bbox, d.start) ? words : [];
      else if (dragged) words = words.filter(w => { const cx = (w.bbox.x0 + w.bbox.x1) / 2, cy = (w.bbox.y0 + w.bbox.y1) / 2; return cx >= frame.x && cx <= frame.x + frame.w && cy >= frame.y && cy <= frame.y + frame.h; });
      else {
        words = words.filter(w => inBox(w.bbox, d.start));
        // Thai has no spaces and the recogniser splits it into fragments: a click takes the whole run of touching fragments.
        if (words.length && THAI.test(words[0].text)) {
          const row = (line.words || []).slice().sort((p, q) => p.bbox.x0 - q.bbox.x0), at = row.indexOf(words[0]);
          const gap = (line.bbox.y1 - line.bbox.y0) * 0.45;
          let lo = at, hi = at;
          while (lo > 0 && row[lo].bbox.x0 - row[lo - 1].bbox.x1 < gap) lo--;
          while (hi < row.length - 1 && row[hi + 1].bbox.x0 - row[hi].bbox.x1 < gap) hi++;
          words = row.slice(lo, hi + 1);
        }
      }
      if (words.length) parts.push({ line, words });
    }
    if (!parts.length) return null;
    // One text mark per drag: the words of the first line hit (a frame over several lines edits the first, so each keeps its own style).
    const { words } = parts[0];
    const bbox = { x0: Math.min(...words.map(w => w.bbox.x0)), y0: Math.min(...words.map(w => w.bbox.y0)), x1: Math.max(...words.map(w => w.bbox.x1)), y1: Math.max(...words.map(w => w.bbox.y1)) };
    // Thai fragments rejoin (no spaces inside Thai words); everything else keeps single spaces.
    const text = words.map(w => w.text).join(' ').replace(/([฀-๿])\s+(?=[฀-๿])/g, '$1').replace(/ํา/g, 'ำ');
    return { text, bbox, part: { line: parts[0].line, words } };
  }
  async function editTextAt(d) {
    if (!hasWords()) { toast(t('Reading the text in the picture…')); await ensureOcr(); return; }
    const picked = pickText(d);
    if (!picked) { toast(t('Click a word, or drag a frame over the text to change')); return; }
    const line = { text: picked.text, bbox: picked.bbox };
    const guess = window.FontMatch.guess(S.base, line.bbox, line.text);
    S.lastMatch = guess;
    pushUndo();
    const bbox = line.bbox;
    S.base = window.FontMatch.erase(S.base, bbox);
    // The words just retyped are gone from the picture; the rest of their line stays available.
    const used = new Set(picked.part.words), L = picked.part.line;
    L.words = L.words.filter(w => !used.has(w));
    S.ocr = { base: S.base, lines: S.ocr.lines.filter(l => l !== L || L.words.length) };
    const sh = newShape('text', guess
      ? { x: guess.x, y: guess.y, text: line.text, size: guess.size, font: guess.font, bold: guess.bold, color: guess.ink, bg: null }
      : { x: bbox.x0, y: bbox.y0, text: line.text, size: Math.round((bbox.y1 - bbox.y0) * 0.85), font: 'system', bold: false, color: '#000000', bg: null });
    S.shapes.push(sh); S.sel = sh.id; S.hover = null;
    S.style.color = sh.color;
    renderStrip(); draw();
    openEditor(sh, { selectAll: true });
    toast(guess ? `${t('Matched font')}: ${guess.fontLabel}${guess.bold ? ' Bold' : ''} · ${Math.round(guess.size)} px` : t('Font not recognised — using a close match'));
  }

  // ---------------------------------------------------------------- backdrop panel
  function toggleBackdropPanel() {
    const panel = $('#backdrop');
    panel.hidden = !panel.hidden;
    if (!panel.hidden) { if (!S.bd.on) { S.bd.on = true; } renderBackdropPanel(); }
    relayout();
  }
  function relayout() { layout(); draw(); refreshChrome(); }
  function renderBackdropPanel() {
    const panel = $('#backdrop'); panel.textContent = '';
    const h = Object.assign(document.createElement('h3'), { textContent: t('Backdrop') });
    const presets = document.createElement('div'); presets.className = 'presets'; presets.setAttribute('role', 'radiogroup'); presets.setAttribute('aria-label', t('Backdrop presets'));
    BACKDROPS.forEach(([a, b], i) => {
      const btn = document.createElement('button'); btn.type = 'button'; btn.setAttribute('role', 'radio');
      btn.style.background = `linear-gradient(135deg, ${a}, ${b})`; btn.setAttribute('aria-label', `${a} → ${b}`);
      btn.setAttribute('aria-checked', String(S.bd.preset === i && S.bd.c1 === a && S.bd.c2 === b));
      btn.addEventListener('click', () => { S.bd.preset = i; S.bd.c1 = a; S.bd.c2 = b; saveBackdrop(); renderBackdropPanel(); draw(); });
      presets.append(btn);
    });
    const colorInput = (label, key) => {
      const row = document.createElement('div'); row.className = 'row';
      const l = Object.assign(document.createElement('label'), { textContent: t(label) });
      const i = Object.assign(document.createElement('input'), { type: 'color', value: S.bd[key] });
      i.addEventListener('input', () => { S.bd[key] = i.value; saveBackdrop(); draw(); });
      row.append(l, i); return row;
    };
    const range = (label, key, min, max) => {
      const row = document.createElement('div'); row.className = 'row';
      const l = Object.assign(document.createElement('label'), { textContent: t(label) });
      const r = Object.assign(document.createElement('input'), { type: 'range', min, max, value: S.bd[key] });
      const n = Object.assign(document.createElement('span'), { className: 'num', textContent: S.bd[key] });
      r.addEventListener('input', () => { S.bd[key] = Number(r.value); n.textContent = r.value; saveBackdrop(); relayout(); });
      row.append(l, r, n); return row;
    };
    const swap = Object.assign(document.createElement('button'), { className: 'btn', textContent: t('Swap colours') });
    swap.addEventListener('click', () => { [S.bd.c1, S.bd.c2] = [S.bd.c2, S.bd.c1]; saveBackdrop(); renderBackdropPanel(); draw(); });
    const random = Object.assign(document.createElement('button'), { className: 'btn', textContent: t('Random') });
    random.addEventListener('click', () => { const r = () => '#' + Math.floor(Math.random() * 0xffffff).toString(16).padStart(6, '0'); S.bd.c1 = r(); S.bd.c2 = r(); saveBackdrop(); renderBackdropPanel(); draw(); });
    const remove = Object.assign(document.createElement('button'), { className: 'btn', textContent: t('Remove backdrop') });
    remove.addEventListener('click', () => { S.bd.on = false; $('#backdrop').hidden = true; relayout(); });
    const done = Object.assign(document.createElement('button'), { className: 'btn primary', textContent: t('Done') });
    done.addEventListener('click', () => { $('#backdrop').hidden = true; relayout(); });
    const actions = document.createElement('div'); actions.style.cssText = 'display:flex;gap:8px;flex-wrap:wrap';
    actions.append(swap, random);
    const footer = document.createElement('div'); footer.style.cssText = 'display:flex;gap:8px;margin-top:auto';
    footer.append(remove, done);
    panel.append(h, presets, colorInput('Colour 1', 'c1'), colorInput('Colour 2', 'c2'), actions, range('Padding', 'pad', 0, 220), range('Corner radius', 'radius', 0, 60), range('Shadow', 'shadow', 0, 80), footer);
  }
  function saveBackdrop() { try { localStorage.setItem('bd', JSON.stringify(S.bd)); } catch { /* storage unavailable */ } }

  // ---------------------------------------------------------------- actions
  // The main process writes the clipboard: it does not need this window to have the focus (the web Clipboard API does), and
  // it puts a plain bitmap there that Word, Paint, Teams and LINE all accept.
  async function copyImage() {
    try {
      const res = await api.copyImage(exportDataURL());
      if (res.error === 'license') toast(t('Copying needs a license'), true);
      else if (res.ok) toast(t('Copied to clipboard'));
      else toast(t('Could not copy: ') + (res.message || res.error), true);
    } catch (error) { toast(t('Could not copy: ') + error.message, true); }
  }
  async function saveImage(opts = {}) {
    try {
      const res = await api.saveImage(exportDataURL(), opts);
      if (res.error === 'license') toast(t('Saving needs a license'), true);
      else if (res.ok) toast(t('Saved') + ': ' + res.path);
      else if (res.error) toast(t('Could not save: ') + (res.message || res.error), true);
      return res;
    } catch (error) { toast(t('Could not save: ') + error.message, true); return { error: error.message }; }
  }
  /** Shared reply handling for the main-process actions: license refusal, not set up, errors. */
  function report(res, okText) {
    if (!res) return res;
    if (res.error === 'license') toast(t('This needs a license'), true);
    else if (res.error === 'notConfigured') { toast(res.message || t('Upload is not set up yet. Choose S3 or HTTP in Settings ▸ Upload.'), true); api.openSettings(); }
    else if (res.error) toast((res.message || res.error), true);
    else if (res.ok && okText) toast(okText);
    return res;
  }
  async function uploadImage() {
    toast(t('Uploading…'));
    const res = await api.uploadImage(exportDataURL());
    return report(res, res && res.ok ? t('Uploaded — link copied') + ': ' + res.url : null);
  }
  async function pinImage() { return report(await api.pinImage(exportDataURL(), S.pixelScale)); }
  async function printImage() { return report(await api.printImage(exportDataURL())); }
  /** Before / after GIF (native GIFExport): the picture as it was opened, then as edited, 1.2 s each, looping. */
  async function exportGif() {
    const after = exportCanvas(), before = S.original;
    const w = Math.max(after.width, before.width), h = Math.max(after.height, before.height);
    const frame = src => {
      const c = document.createElement('canvas'); c.width = w; c.height = h;
      const x = c.getContext('2d', { willReadFrequently: true });
      if (src.width !== w || src.height !== h) {        // a smaller frame sits centred on its own edge colour
        const p = src.getContext('2d').getImageData(0, 0, 1, 1).data;
        x.fillStyle = `rgb(${p[0]},${p[1]},${p[2]})`; x.fillRect(0, 0, w, h);
      }
      x.drawImage(src, Math.floor((w - src.width) / 2), Math.floor((h - src.height) / 2));
      return { data: x.getImageData(0, 0, w, h).data, width: w, height: h };
    };
    toast(t('Making the GIF…'));
    await new Promise(r => setTimeout(r, 30));      // let the message paint before the encoder takes the thread
    const bytes = window.GIF.encode([frame(before), frame(after)], { delayCs: 120 });
    const res = await api.saveGif(bytes);
    return report(res, res && res.ok ? (res.copied ? t('GIF saved and copied') : t('GIF saved')) + ': ' + res.path : null);
  }

  function showModal(title, text) {
    const modal = $('#modal'); modal.hidden = false; modal.textContent = '';
    const card = document.createElement('div'); card.className = 'card'; card.setAttribute('role', 'dialog'); card.setAttribute('aria-label', title);
    const h = Object.assign(document.createElement('h2'), { textContent: title });
    const ta = Object.assign(document.createElement('textarea'), { value: text, readOnly: true });
    const actions = document.createElement('div'); actions.className = 'actions';
    const copy = Object.assign(document.createElement('button'), { className: 'btn primary', textContent: t('Copy text') });
    copy.addEventListener('click', async () => { await api.copyText(ta.value); toast(t('Copied to clipboard')); });
    const close = Object.assign(document.createElement('button'), { className: 'btn', textContent: t('Close') });
    close.addEventListener('click', () => { modal.hidden = true; });
    actions.append(close, copy); card.append(h, ta, actions); modal.append(card);
    ta.focus(); ta.select();
  }
  /** Hide PII (native hidePII): read the picture, find emails, IDs, phones, cards, keys…, pixelate each one — all as one undo step. */
  async function hidePII() {
    toast(t('Checking the picture for personal data…'));
    const lines = await ensureOcr();
    let cfg = {};
    try { cfg = (await api.settings.get()).pii || {}; } catch { /* defaults */ }
    const rects = window.PII.regions(lines, window.PII.patterns(cfg.enabled, cfg.custom), { width: S.w, height: S.h });
    if (!rects.length) { toast(t('Nothing to hide')); return 0; }
    pushUndo();
    for (const r of rects) S.shapes.push(newShape('blur', { x: r.x, y: r.y, w: r.w, h: r.h, strength: Math.max(8, Math.min(S.style.blur, Math.round(r.h / 2))) }));
    S.sel = null; renderStrip(); draw();
    toast(t('Hid %d item(s)').replace('%d', rects.length));
    return rects.length;
  }

  async function runOcr() {
    toast(t('Reading the text in the picture…'));
    const res = await api.ocr(S.base.toDataURL('image/png'));
    if (res.error) { toast(t('Could not read the text: ') + res.error, true); return; }
    if (!res.text) { toast(t('No text found in the picture'), true); return; }
    showModal(t('Recognised text'), res.text);
  }

  // ---------------------------------------------------------------- keyboard
  /**
   * The key that was pressed, independent of the keyboard layout: with the Thai layout active `e.key` is a Thai letter ("พ" for R,
   * "ผ" for Z), so letters, digits, − and + are read from the physical key (`e.code`).
   */
  function keyName(e) {
    const c = e.code || '';
    if (/^Key[A-Z]$/.test(c)) return c.slice(3).toLowerCase();
    if (/^(Digit|Numpad)[0-9]$/.test(c)) return c.slice(-1);
    if (c === 'Minus' || c === 'NumpadSubtract') return '-';
    if (c === 'Equal' || c === 'NumpadAdd') return '+';
    return (e.key || '').toLowerCase();
  }
  /** Typing into a text field, a number box or a list keeps its keys; sliders and colour wells do not need the letters. */
  function typingTarget(el) {
    const tag = (el.tagName || '').toLowerCase();
    if (tag === 'textarea' || tag === 'select' || el.isContentEditable) return true;
    return tag === 'input' && !['range', 'color', 'checkbox', 'radio', 'button'].includes(el.type);
  }
  window.addEventListener('keydown', e => {
    if (typingTarget(e.target)) return;
    if (!$('#modal').hidden) { if (e.key === 'Escape') $('#modal').hidden = true; return; }
    const mod = mac ? e.metaKey : e.ctrlKey, key = keyName(e);
    if (mod && key === 'z') { e.preventDefault(); e.shiftKey ? redo() : undo(); return; }
    if (mod && key === 'y') { e.preventDefault(); redo(); return; }
    if (mod && key === 's') { e.preventDefault(); saveImage({ saveAs: e.shiftKey }); return; }
    if (mod && key === 'c') { e.preventDefault(); copyImage(); return; }
    if (mod && key === 'd') { e.preventDefault(); duplicateSelected(); return; }
    if (mod && e.shiftKey && key === 'h') { e.preventDefault(); hidePII(); return; }
    if (mod && key === 'p') { e.preventDefault(); printImage(); return; }
    if (mod && e.shiftKey && key === 'u') { e.preventDefault(); api.openUploads(); return; }
    if (mod || e.altKey || e.metaKey || e.ctrlKey) return;
    // Ruler: hold 1 for the height only, 2 for the width only (native). Spotlight: 1–9 is the darkness.
    if (S.tool === 'measure' && (key === '1' || key === '2')) { S.measureAxis = key === '1' ? 'v' : 'h'; draw(); return; }
    const spot = selected() && selected().type === 'spotlight' ? selected() : null;
    if ((spot || S.tool === 'spotlight') && /^[1-9]$/.test(key)) { applyStyle({ level: Number(key) }, 'level'); renderStrip(); return; }
    if (e.key.startsWith('Arrow') && e.target.type === 'range') return;     // a focused slider uses the arrows
    if (e.shiftKey && key === 't') { runOcr(); return; }
    if (e.key === 'Delete' || e.key === 'Backspace') { e.preventDefault(); deleteSelected(); return; }
    if (e.key === 'Escape') { if (S.cropRect) { S.cropRect = null; renderStrip(); draw(); } else { S.sel = null; renderStrip(); draw(); } return; }
    if (e.key === 'Enter' && S.cropRect) { applyCrop(); return; }
    if (e.key === 'Enter' && S.sel != null) { S.sel = null; renderStrip(); draw(); return; }     // done with this mark: the next press makes a new one
    if (key === '+' || key === '=') { setZoom(S.zoom * 1.25); return; }
    if (key === '-') { setZoom(S.zoom / 1.25); return; }
    if (key === '0') { setZoom(fitZoom(), true); return; }
    if (e.key.startsWith('Arrow') && selected()) {
      e.preventDefault(); const step = e.shiftKey ? 10 : 1;
      pushUndo(); moveShape(selected(), e.key === 'ArrowLeft' ? -step : e.key === 'ArrowRight' ? step : 0, e.key === 'ArrowUp' ? -step : e.key === 'ArrowDown' ? step : 0); draw(); return;
    }
    if (e.shiftKey) return;
    if (key === 'k') { toggleBackdropPanel(); return; }
    const tool = TOOLS.find(([, , k]) => k.toLowerCase() === key);
    if (tool) setTool(tool[0]);
  });

  window.addEventListener('keyup', e => {
    const key = keyName(e);
    if (S.tool === 'measure' && (key === '1' || key === '2')) { S.measureAxis = 'both'; draw(); }
  });
  cv.addEventListener('pointerleave', () => { if (S.probe || S.pick) { S.probe = null; S.pick = null; draw(); } });
  cv.addEventListener('pointerdown', onDown);
  cv.addEventListener('pointermove', onMove);
  cv.addEventListener('pointerup', onUp);
  cv.addEventListener('pointercancel', onUp);
  $('#scroller').addEventListener('wheel', e => {
    if (!(e.ctrlKey || e.metaKey)) return;
    e.preventDefault(); setZoom(S.zoom * (e.deltaY < 0 ? 1.1 : 1 / 1.1));
  }, { passive: false });
  window.addEventListener('resize', () => { fitBar(); if (S.fitMode) { layout(); draw(); refreshChrome(); } else if (S.editing) positionEditor(); });
  // Windows: the caption buttons' area changes with the window and the display scale.
  if (navigator.windowControlsOverlay) navigator.windowControlsOverlay.addEventListener('geometrychange', fitBar);
  api.onLanguage(relabel);
  api.onCommand(runCommand);
  $('#scroller').addEventListener('scroll', () => { if (S.editing) positionEditor(); });

  // ---------------------------------------------------------------- start
  function loadBase(img, pixelScale) {
    const c = document.createElement('canvas'); c.width = img.naturalWidth || img.width; c.height = img.naturalHeight || img.height;
    c.getContext('2d').drawImage(img, 0, 0);
    S.base = c; S.w = c.width; S.h = c.height; S.pixelScale = pixelScale || 1;
    S.original = c;         // the "before" of the before/after GIF (edits replace S.base with new canvases)
  }
  async function start() {
    buildBar();
    const init = await api.getInitial();
    document.title = 'Tenix-ChaeDiew';
    const img = new Image();
    img.src = init.dataURL;
    await img.decode();
    loadBase(img, init.pixelScale);
    S.fitMode = true;
    renderStrip(); layout(); draw(); refreshChrome(); fitBar();
    if (document.fonts) document.fonts.ready.then(fitBar);     // label widths change once the UI font has loaded
    if (api.testMode) window.__test = makeTestApi();
  }

  // Hooks used only by the automated smoke run (`electron . --smoke`).
  function makeTestApi() {
    const toClient = (x, y) => { const r = cv.getBoundingClientRect(), k = scale(); return { clientX: r.left + (x + pad()) * k, clientY: r.top + (y + pad()) * k }; };
    const fire = (type, x, y, extra = {}) => cv.dispatchEvent(new PointerEvent(type, { bubbles: true, pointerId: 1, button: 0, ...toClient(x, y), ...extra }));
    return {
      S, setTool, applyStyle, undo, redo, drawNow, exportDataURL, toggleBackdropPanel, setCounterLabel, runOcr, exportSize: () => [S.w + 2 * pad(), S.h + 2 * pad()],
      drag(x1, y1, x2, y2, extra) { fire('pointerdown', x1, y1, extra); fire('pointermove', (x1 + x2) / 2, (y1 + y2) / 2, extra); fire('pointermove', x2, y2, extra); fire('pointerup', x2, y2, extra); },
      click(x, y, detail = 1, extra = {}) { fire('pointerdown', x, y, { detail, ...extra }); fire('pointerup', x, y, { detail, ...extra }); },
      type(text) { const el = S.editing && S.editing.el; if (!el) return false; el.value = text; el.dispatchEvent(new Event('input')); return true; },
      commitEdit() { closeEditor(true); },
      ensureOcr, editTextAt, openEditor, shapes: () => S.shapes, selected, select, scale, strip: () => $('#strip').innerText,
      openModalText: () => ($('#modal textarea') || {}).value || '',
      fitBar, folded: () => [...folded], moreMenuItems, runCommand, lang: () => lang, saveImage, copyImage,
      hidePII, probeMarks, pixelAt, uploadImage, pinImage, printImage, exportGif, nextLabel: shapeCounterLabel, hover: (x, y) => fire('pointermove', x, y, { buttons: 0 }),
      counterGeometry: id => { const s = S.shapes.find(x => x.id === id); return s && counterGeometry(s, meas); },
      handles: () => (selected() ? handlePoints(selected(), meas) : []),
      pixelOfCanvas(x, y) { drawNow(); const k = cv.width / (S.w + 2 * pad()), d = ctx.getImageData(Math.round((x + pad()) * k), Math.round((y + pad()) * k), 1, 1).data; return [d[0], d[1], d[2]]; },
      exportPixel(x, y) { const c = exportCanvas(), d = c.getContext('2d').getImageData(Math.round(x + pad()), Math.round(y + pad()), 1, 1).data; return [d[0], d[1], d[2]]; },
      key(init) { window.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, cancelable: true, ...init })); },
      barText: () => $('#bar').innerText + ' ' + [...document.querySelectorAll('#bar [aria-label]')].map(b => b.getAttribute('aria-label')).join(' '),
    };
  }
  start().catch(error => { document.body.textContent = String(error && error.stack || error); });
})();
