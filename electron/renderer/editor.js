'use strict';
// Tenix-ChaeDiew editor (Electron). Canvas-based annotation: shapes live in image pixels; the bar, the context strip and the
// backdrop panel apply every change to the selected mark immediately.
(() => {
  const { CounterText, BOX_TYPES, normBox, counterGeometry, textMetrics, boundsOf, hit, moveShape, handlePoints, resizeBox, readableOn } = window.Model;
  const api = window.tenix;
  const lang = api.lang;
  const t = key => (lang === 'th' && api.strings[key]) || key;
  const $ = (sel, el = document) => el.querySelector(sel);

  document.body.classList.add(api.platform === 'darwin' ? 'mac' : api.platform === 'win32' ? 'win' : 'other');
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
  };
  const svg = name => `<svg viewBox="0 0 24 24" aria-hidden="true">${ICON[name]}</svg>`;

  // ---------------------------------------------------------------- state
  const PALETTE = ['#FF3B30', '#FF9500', '#FFCC00', '#34C759', '#1FA0FF', '#5856D6', '#FF2D92', '#FFFFFF', '#15171C'];
  const FONTS = [['system', 'System'], ['Helvetica Neue', 'Helvetica Neue'], ['Arial', 'Arial'], ['Georgia', 'Georgia'], ['Menlo', 'Menlo / Consolas'], ['Tahoma', 'Tahoma']];
  const BACKDROPS = [
    ['#6EE7F9', '#6366F1'], ['#F9A8D4', '#C084FC'], ['#FDE68A', '#FB923C'], ['#86EFAC', '#0EA5E9'], ['#FDA4AF', '#F43F5E'], ['#A5B4FC', '#312E81'],
    ['#E2E8F0', '#94A3B8'], ['#1E293B', '#0F172A'], ['#FFFFFF', '#E5E7EB'], ['#FEF3C7', '#FCA5A5'], ['#BBF7D0', '#14B8A6'], ['#15171C', '#1FA0FF'],
  ];
  const S = {
    base: null, w: 0, h: 0, pixelScale: 1,
    shapes: [], sel: null, tool: 'select',
    style: { color: '#FF3B30', textColor: 'auto', bg: null, width: 4, fill: false, textSize: 28, counterSize: 34, blur: 12, font: 'system', bold: true },
    zoom: 1, fitMode: true,
    undo: [], redo: [], nextId: 1,
    bd: { on: false, preset: 0, c1: BACKDROPS[0][0], c2: BACKDROPS[0][1], pad: 64, radius: 14, shadow: 32 },
    cropRect: null, ocr: null, editing: null, drag: null, hover: null, lastStyleGroup: null, lastStyleAt: 0, busy: false,
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
  const shapeCounterLabel = () => {
    const counters = S.shapes.filter(s => s.type === 'counter');
    return counters.length ? CounterText.next(counters[counters.length - 1].label) : '1';
  };
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

  function drawCounter(c, s) {
    const g = counterGeometry(s, meas);
    c.fillStyle = s.color; roundRectPath(c, g.x, g.y, g.w, g.h, g.h / 2); c.fill();
    c.strokeStyle = 'rgba(255,255,255,0.9)'; c.lineWidth = Math.max(1.5, s.size * 0.06); roundRectPath(c, g.x, g.y, g.w, g.h, g.h / 2); c.stroke();
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
    }
    c.restore();
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
    // Spotlight-free: marks are clipped to the picture when a backdrop is on, as in the native app.
    for (const s of S.shapes) drawShape(c, s);
    if (ui) drawUi(c);
    c.restore();
  }

  function drawUi(c) {
    const k = scale();
    const sh = selected();
    if (S.tool === 'editText' && S.ocr && S.ocr.base === S.base) {
      for (const [i, line] of S.ocr.lines.entries()) {
        const b = line.bbox;
        c.strokeStyle = S.hover === i ? 'rgba(31,160,255,0.95)' : 'rgba(31,160,255,0.45)';
        c.lineWidth = (S.hover === i ? 2 : 1) / k;
        c.fillStyle = S.hover === i ? 'rgba(31,160,255,0.12)' : 'rgba(31,160,255,0.04)';
        c.fillRect(b.x0 - 2, b.y0 - 2, b.x1 - b.x0 + 4, b.y1 - b.y0 + 4);
        c.strokeRect(b.x0 - 2, b.y0 - 2, b.x1 - b.x0 + 4, b.y1 - b.y0 + 4);
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
        c.beginPath(); c.rect(hp.x - r, hp.y - r, 2 * r, 2 * r); c.fill(); c.stroke();
      }
    }
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
      $('#readout').textContent = `${S.w} × ${S.h}`;
    });
  }
  function drawNow() {   // for tests and exports: draw synchronously
    const W = S.w + 2 * pad(), H = S.h + 2 * pad();
    ctx.setTransform(cv.width / W, 0, 0, cv.height / H, 0, 0);
    ctx.clearRect(0, 0, W, H);
    paint(ctx, W, H, true);
  }

  function exportDataURL() {
    const p = pad(), W = S.w + 2 * p, H = S.h + 2 * p;
    const out = document.createElement('canvas'); out.width = W; out.height = H;
    const c = out.getContext('2d');
    const keep = S.editing; S.editing = null;
    paint(c, W, H, false);
    S.editing = keep;
    return out.toDataURL('image/png');
  }

  // ---------------------------------------------------------------- bar
  const TOOLS = [
    ['select', 'Select', 'V'], ['rect', 'Rectangle', 'R'], ['ellipse', 'Ellipse', 'O'], ['arrow', 'Arrow', 'A'], ['line', 'Line', 'L'],
    ['pen', 'Pen', 'P'], ['highlight', 'Highlight', 'H'], ['text', 'Text', 'T'], ['counter', 'Counter', 'N'], ['blur', 'Hide (pixelate)', 'B'],
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
  function buildBar() {
    const mod = api.platform === 'darwin' ? '⌘' : 'Ctrl+';
    $('#g-history').append(button('undo', 'undo', 'Undo', undo, { shortcut: mod + 'Z' }), button('redo', 'redo', 'Redo', redo, { shortcut: mod + '⇧Z' }));
    const tools = $('#g-tools');
    for (const [id, label, key] of TOOLS) {
      const b = button('tool-' + id, id, label, () => setTool(id), { shortcut: key });
      b.setAttribute('aria-pressed', 'false');
      tools.append(b);
    }
    $('#g-extras').append(
      button('ocr', 'ocr', 'Read text (OCR)', runOcr, { shortcut: '⇧T' }),
      button('backdrop', 'backdrop', 'Backdrop', toggleBackdropPanel, { shortcut: 'K' }),
      button('license', 'key', 'License', () => api.openLicense()),
    );
    $('#g-zoom').append(
      button('zoomOut', 'zoomOut', 'Zoom out', () => setZoom(S.zoom / 1.25), { shortcut: '−' }),
      Object.assign(document.createElement('span'), { className: 'zoomval', id: 'zoomval' }),
      button('zoomIn', 'zoomIn', 'Zoom in', () => setZoom(S.zoom * 1.25), { shortcut: '+' }),
      button('fit', 'fit', 'Fit to window', () => setZoom(fitZoom(), true), { shortcut: '0' }),
    );
    $('#g-share').append(
      button('save', 'save', 'Save as…', saveImage, { shortcut: mod + 'S', text: 'Save' }),
      button('copy', 'copy', 'Copy picture', copyImage, { shortcut: mod + 'C', text: 'Copy', primary: true }),
    );
  }
  function refreshChrome() {
    buttons.undo.disabled = !S.undo.length; buttons.redo.disabled = !S.redo.length;
    for (const [id] of TOOLS) buttons['tool-' + id].setAttribute('aria-pressed', String(S.tool === id));
    buttons.backdrop.setAttribute('aria-pressed', String(!$('#backdrop').hidden));
    $('#zoomval').textContent = `${Math.round(S.zoom * 100)}%`;
  }

  function setTool(id) {
    if (S.editing) closeEditor(true);
    if (S.tool === 'crop' && id !== 'crop') S.cropRect = null;
    S.tool = id;
    if (id !== 'select' && id !== 'text' && id !== 'counter') { /* keep selection so colour changes still reach it */ }
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
        break;
      }
      case 'editText':
        strip.append(hint(S.ocr && S.ocr.base === S.base ? t('Click a highlighted line of text in the picture to retype it in the same font, size and colour.') : t('Reading the text in the picture…')));
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
    input.value = sh ? sh.label : shapeCounterLabel(); input.disabled = !sh; input.title = t('Type any text: 1.1, 3.6, A2');
    const commit = () => { if (sh && input.value.trim()) setCounterLabel(sh, input.value.trim()); };
    input.addEventListener('change', commit);
    input.addEventListener('keydown', e => { e.stopPropagation(); if (e.key === 'Enter') { commit(); input.blur(); } });
    const mk = (icon, delta, label) => { const b = button('c' + delta, icon, label, () => sh && setCounterLabel(sh, CounterText.step(sh.label, delta))); b.disabled = !sh; return b; };
    wrap.append(input, mk('minus', -1, 'Previous number'), mk('plus', 1, 'Next number'));
    const lab = document.createElement('label'); lab.textContent = t('Number'); lab.style.cssText = 'color:var(--text-muted);font-size:11.5px;font-weight:500';
    const f = document.createElement('div'); f.className = 'field'; f.append(lab, wrap);
    if (!sh) f.append(hint(t('Next: ') + shapeCounterLabel() + ' · ' + t('double-click a number to edit')));
    return f;
  }
  function setCounterLabel(sh, label) {
    pushUndo(); sh.label = label; draw(); renderStrip();
  }

  /** Change colour/size/etc. now: on the selected mark and as the default for the next one. */
  function applyStyle(patch, group) {
    Object.assign(S.style, patch);
    const sh = selected();
    if (sh) {
      coalesce(group);
      const map = { color: 'color', width: 'width', fill: 'fill', bg: 'bg', bold: 'bold', font: 'font', textColor: 'textColor', blur: 'strength' };
      for (const [k, v] of Object.entries(patch)) {
        if (k in map && (map[k] in sh || (k === 'blur' && sh.type === 'blur'))) sh[map[k]] = v;
        if (k === 'textSize' && sh.type === 'text') sh.size = v;
        if (k === 'counterSize' && sh.type === 'counter') sh.size = v;
      }
    }
    if (S.editing) styleEditor();
    draw();
    if (!patch.hasOwnProperty('width') && !patch.hasOwnProperty('textSize') && !patch.hasOwnProperty('counterSize') && !patch.hasOwnProperty('blur')) renderStrip();
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
  function hitHandle(p) {
    const sh = selected(); if (!sh) return null;
    const r = 8 / scale();
    return handlePoints(sh, meas).find(h => Math.abs(h.x - p.x) <= r && Math.abs(h.y - p.y) <= r) || null;
  }
  function select(id) { if (S.sel !== id) { S.sel = id; renderStrip(); } draw(); }

  function onDown(e) {
    if (!S.base || e.button !== 0) return;
    if (S.editing) closeEditor(true);
    const p = eventPoint(e);
    try { cv.setPointerCapture(e.pointerId); } catch { /* synthetic events */ }

    if (e.detail === 2) { const h = hitTest(p); if (h && (h.type === 'text' || h.type === 'counter')) { select(h.id); openEditor(h, { selectAll: false }); return; } }

    const handle = hitHandle(p);
    if (handle) { pushUndo(); S.drag = { mode: 'handle', handle: handle.name, shape: selected() }; return; }

    const t0 = S.tool;
    const over = hitTest(p);
    // Text and counters: pressing one moves it (so old numbers can be dragged), otherwise a new one is placed.
    if (t0 === 'select' || ((t0 === 'text' || t0 === 'counter') && over && over.type === t0)) {
      if (over) { select(over.id); pushUndo(); S.drag = { mode: 'move', shape: over, last: p }; cv.className = 'cur-move'; }
      else { select(null); S.drag = null; }
      return;
    }
    if (t0 === 'editText') { editTextAt(p); return; }
    if (t0 === 'crop') { S.cropRect = { x: clampX(p.x), y: clampY(p.y), w: 0, h: 0 }; S.drag = { mode: 'crop' }; renderStrip(); return; }
    if (t0 === 'text') {
      pushUndo();
      const sh = newShape('text', { x: p.x, y: p.y, text: '', size: S.style.textSize, font: S.style.font, bold: S.style.bold, color: S.style.color, bg: S.style.bg });
      S.shapes.push(sh); S.sel = sh.id; renderStrip(); openEditor(sh, { isNew: true }); return;
    }
    if (t0 === 'counter') {
      pushUndo();
      const sh = newShape('counter', { x: p.x, y: p.y, size: S.style.counterSize, label: shapeCounterLabel(), color: S.style.color, textColor: S.style.textColor });
      S.shapes.push(sh); S.sel = sh.id; renderStrip(); draw(); return;
    }
    // Drawing tools
    pushUndo();
    let sh;
    switch (t0) {
      case 'rect': case 'ellipse': sh = newShape(t0, { x: p.x, y: p.y, w: 0, h: 0, color: S.style.color, width: S.style.width, fill: S.style.fill }); break;
      case 'highlight': sh = newShape('highlight', { x: p.x, y: p.y, w: 0, h: 0, color: S.style.color === '#FFFFFF' ? '#FFCC00' : S.style.color }); break;
      case 'blur': sh = newShape('blur', { x: p.x, y: p.y, w: 0, h: 0, strength: S.style.blur }); break;
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
      if (sh.type === 'line' || sh.type === 'arrow') {
        let x = p.x, y = p.y;
        if (e.shiftKey) { const ox = d.handle === 'p1' ? sh.x2 : sh.x1, oy = d.handle === 'p1' ? sh.y2 : sh.y1; [x, y] = snap45(ox, oy, x, y); }
        if (d.handle === 'p1') { sh.x1 = x; sh.y1 = y; } else { sh.x2 = x; sh.y2 = y; }
      } else resizeBox(sh, d.handle, p.x, p.y);
      draw(); return;
    }
    if (d.mode === 'crop') { S.cropRect.w = clampX(p.x) - S.cropRect.x; S.cropRect.h = clampY(p.y) - S.cropRect.y; draw(); return; }
    if (d.mode === 'draw') {
      const sh = d.shape;
      switch (sh.type) {
        case 'rect': case 'ellipse': case 'highlight': case 'blur': {
          let w = p.x - d.start.x, h = p.y - d.start.y;
          if (e.shiftKey && sh.type !== 'blur') { const s = Math.max(Math.abs(w), Math.abs(h)); w = Math.sign(w || 1) * s; h = Math.sign(h || 1) * s; }
          sh.w = w; sh.h = h; break;
        }
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
      } else if ((sh.type === 'arrow' || sh.type === 'line') && Math.hypot(sh.x2 - sh.x1, sh.y2 - sh.y1) < 4) { discardLast(sh); return; }
      renderStrip();
    }
    if (d.mode === 'crop') { const b = normBox(S.cropRect); if (b.w < 4 || b.h < 4) S.cropRect = null; else S.cropRect = b; renderStrip(); }
    if (d.mode === 'move') cv.className = S.tool === 'select' ? 'cur-default' : S.tool === 'text' ? 'cur-text' : 'cur-cross';
    draw();
  }
  function discardLast(sh) { S.shapes = S.shapes.filter(s => s !== sh); S.sel = null; S.undo.pop(); renderStrip(); refreshChrome(); draw(); }
  function hoverCursor(p) {
    if (S.tool === 'editText' && S.ocr && S.ocr.base === S.base) {
      const i = S.ocr.lines.findIndex(l => p.x >= l.bbox.x0 - 2 && p.x <= l.bbox.x1 + 2 && p.y >= l.bbox.y0 - 2 && p.y <= l.bbox.y1 + 2);
      if (i !== S.hover) { S.hover = i < 0 ? null : i; draw(); }
      cv.className = i >= 0 ? 'cur-text' : 'cur-default'; return;
    }
    const handle = hitHandle(p);
    if (handle) { cv.className = 'cur-move'; return; }
    const over = hitTest(p);
    if (S.tool === 'select') cv.className = over ? 'cur-move' : 'cur-default';
    else if ((S.tool === 'text' || S.tool === 'counter') && over && over.type === S.tool) cv.className = 'cur-move';
    else cv.className = S.tool === 'text' ? 'cur-text' : 'cur-cross';
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
    if (copy.type === 'counter') copy.label = shapeCounterLabel();
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
  async function editTextAt(p) {
    if (!S.ocr || S.ocr.base !== S.base) { toast(t('Reading the text in the picture…')); await ensureOcr(); return; }
    const line = S.ocr.lines.find(l => p.x >= l.bbox.x0 - 2 && p.x <= l.bbox.x1 + 2 && p.y >= l.bbox.y0 - 2 && p.y <= l.bbox.y1 + 2);
    if (!line) { toast(t('Click on a highlighted line of text')); return; }
    const guess = window.FontMatch.guess(S.base, line.bbox, line.text);
    pushUndo();
    const bbox = line.bbox;
    S.base = window.FontMatch.erase(S.base, bbox);
    S.ocr = { base: S.base, lines: S.ocr.lines.filter(l => l !== line) };
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
  function exportBlob() {
    const p = pad(), W = S.w + 2 * p, H = S.h + 2 * p;
    const out = document.createElement('canvas'); out.width = W; out.height = H;
    const keep = S.editing; S.editing = null;
    paint(out.getContext('2d'), W, H, false);
    S.editing = keep;
    return new Promise(resolve => out.toBlob(resolve, 'image/png'));
  }
  async function copyImage() {
    const gate = await api.gate();
    if (gate.error === 'license') { toast(t('Copying needs a license'), true); return; }
    try {
      await navigator.clipboard.write([new ClipboardItem({ 'image/png': await exportBlob() })]);
      toast(t('Copied to clipboard'));
    } catch (error) { toast(t('Could not copy: ') + error.message, true); }
  }
  async function saveImage() {
    const res = await api.saveImage(exportDataURL());
    if (res.error === 'license') toast(t('Saving needs a license'), true); else if (res.ok) toast(t('Saved') + ': ' + res.path);
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
  async function runOcr() {
    toast(t('Reading the text in the picture…'));
    const res = await api.ocr(S.base.toDataURL('image/png'));
    if (res.error) { toast(t('Could not read the text: ') + res.error, true); return; }
    if (!res.text) { toast(t('No text found in the picture'), true); return; }
    showModal(t('Recognised text'), res.text);
  }

  // ---------------------------------------------------------------- keyboard
  window.addEventListener('keydown', e => {
    const tag = (e.target.tagName || '').toLowerCase();
    if (tag === 'input' || tag === 'textarea' || tag === 'select') return;
    if (!$('#modal').hidden) { if (e.key === 'Escape') $('#modal').hidden = true; return; }
    const mod = e.metaKey || e.ctrlKey, key = e.key.toLowerCase();
    if (mod && key === 'z') { e.preventDefault(); e.shiftKey ? redo() : undo(); return; }
    if (mod && key === 'y') { e.preventDefault(); redo(); return; }
    if (mod && key === 's') { e.preventDefault(); saveImage(); return; }
    if (mod && key === 'c') { e.preventDefault(); copyImage(); return; }
    if (mod && key === 'd') { e.preventDefault(); duplicateSelected(); return; }
    if (mod) return;
    if (e.shiftKey && key === 't') { runOcr(); return; }
    if (e.key === 'Delete' || e.key === 'Backspace') { e.preventDefault(); deleteSelected(); return; }
    if (e.key === 'Escape') { if (S.cropRect) { S.cropRect = null; renderStrip(); draw(); } else { S.sel = null; renderStrip(); draw(); } return; }
    if (e.key === 'Enter' && S.cropRect) { applyCrop(); return; }
    if (e.key === '+' || e.key === '=') { setZoom(S.zoom * 1.25); return; }
    if (e.key === '-') { setZoom(S.zoom / 1.25); return; }
    if (e.key === '0') { setZoom(fitZoom(), true); return; }
    if (e.key.startsWith('Arrow') && selected()) {
      e.preventDefault(); const step = e.shiftKey ? 10 : 1;
      pushUndo(); moveShape(selected(), e.key === 'ArrowLeft' ? -step : e.key === 'ArrowRight' ? step : 0, e.key === 'ArrowUp' ? -step : e.key === 'ArrowDown' ? step : 0); draw(); return;
    }
    if (key === 'k') { toggleBackdropPanel(); return; }
    const tool = TOOLS.find(([, , k]) => k.toLowerCase() === key);
    if (tool) setTool(tool[0]);
  });

  cv.addEventListener('pointerdown', onDown);
  cv.addEventListener('pointermove', onMove);
  cv.addEventListener('pointerup', onUp);
  cv.addEventListener('pointercancel', onUp);
  $('#scroller').addEventListener('wheel', e => {
    if (!(e.ctrlKey || e.metaKey)) return;
    e.preventDefault(); setZoom(S.zoom * (e.deltaY < 0 ? 1.1 : 1 / 1.1));
  }, { passive: false });
  window.addEventListener('resize', () => { if (S.fitMode) { layout(); draw(); refreshChrome(); } else if (S.editing) positionEditor(); });
  $('#scroller').addEventListener('scroll', () => { if (S.editing) positionEditor(); });

  // ---------------------------------------------------------------- start
  function loadBase(img, pixelScale) {
    const c = document.createElement('canvas'); c.width = img.naturalWidth || img.width; c.height = img.naturalHeight || img.height;
    c.getContext('2d').drawImage(img, 0, 0);
    S.base = c; S.w = c.width; S.h = c.height; S.pixelScale = pixelScale || 1;
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
    renderStrip(); layout(); draw(); refreshChrome();
    if (api.testMode) window.__test = makeTestApi();
  }

  // Hooks used only by the automated smoke run (`electron . --smoke`).
  function makeTestApi() {
    const toClient = (x, y) => { const r = cv.getBoundingClientRect(), k = scale(); return { clientX: r.left + (x + pad()) * k, clientY: r.top + (y + pad()) * k }; };
    const fire = (type, x, y, extra = {}) => cv.dispatchEvent(new PointerEvent(type, { bubbles: true, pointerId: 1, button: 0, ...toClient(x, y), ...extra }));
    return {
      S, setTool, applyStyle, undo, redo, drawNow, exportDataURL, toggleBackdropPanel, setCounterLabel, runOcr, exportSize: () => [S.w + 2 * pad(), S.h + 2 * pad()],
      drag(x1, y1, x2, y2, extra) { fire('pointerdown', x1, y1, extra); fire('pointermove', (x1 + x2) / 2, (y1 + y2) / 2, extra); fire('pointermove', x2, y2, extra); fire('pointerup', x2, y2, extra); },
      click(x, y, detail = 1) { fire('pointerdown', x, y, { detail }); fire('pointerup', x, y, { detail }); },
      type(text) { const el = S.editing && S.editing.el; if (!el) return false; el.value = text; el.dispatchEvent(new Event('input')); return true; },
      commitEdit() { closeEditor(true); },
      ensureOcr, editTextAt, openEditor, shapes: () => S.shapes, selected, select, scale, strip: () => $('#strip').innerText,
      openModalText: () => ($('#modal textarea') || {}).value || '',
    };
  }
  start().catch(error => { document.body.textContent = String(error && error.stack || error); });
})();
