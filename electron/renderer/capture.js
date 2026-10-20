'use strict';
(async () => {
  const api = window.tenix.capture;
  const shot = await api.getShot();
  const img = document.getElementById('shot'), dim = document.getElementById('dim'), sel = document.getElementById('sel'), size = document.getElementById('size');
  document.getElementById('help').textContent = (await api.getHelp()) || t('Drag to choose an area · Enter or double-click = whole screen · Esc or right-click = cancel');
  img.src = shot; await img.decode();
  let a = null, last = null;
  const whole = () => ({ x: 0, y: 0, w: innerWidth, h: innerHeight, vw: innerWidth, vh: innerHeight, dpr: devicePixelRatio });
  const rect = (p, q) => ({ x: Math.min(p.x, q.x), y: Math.min(p.y, q.y), w: Math.abs(p.x - q.x), h: Math.abs(p.y - q.y) });
  const reset = () => { a = null; sel.style.display = 'none'; size.style.display = 'none'; dim.style.display = ''; };

  function show(r) {
    Object.assign(sel.style, { display: 'block', left: r.x + 'px', top: r.y + 'px', width: r.w + 'px', height: r.h + 'px' });
    Object.assign(size.style, { display: 'block', left: r.x + 'px', top: Math.max(4, r.y - 28) + 'px' });
    const k = devicePixelRatio || 1;
    size.textContent = Math.round(r.w * k) + ' × ' + Math.round(r.h * k);
  }
  function release(p) {
    if (!a) return;
    const r = rect(a, p);
    // A click (no real drag) is not a choice: keep the overlay so a double-click can still take the whole screen.
    if (r.w < 4 || r.h < 4) { reset(); return; }
    a = null;
    api.done({ ...r, vw: innerWidth, vh: innerHeight, dpr: devicePixelRatio });
  }

  // Pointer events with pointer capture: the release is delivered even if the button comes up during a system hiccup. If it is lost
  // anyway (Windows can drop it when another program grabs the mouse), the first move with no button held ends the drag there.
  addEventListener('pointerdown', e => {
    if (e.button === 2) { api.done(null); return; }
    if (e.button !== 0) return;
    try { document.body.setPointerCapture(e.pointerId); } catch { /* synthetic */ }
    a = { x: e.clientX, y: e.clientY }; last = a; dim.style.display = 'none';
  });
  addEventListener('pointermove', e => {
    if (!a) return;
    if (e.buttons === 0) { release(last); return; }
    last = { x: e.clientX, y: e.clientY };
    show(rect(a, last));
  });
  addEventListener('pointerup', e => { if (e.button === 0) release({ x: e.clientX, y: e.clientY }); });
  addEventListener('dblclick', () => api.done(whole()));
  addEventListener('contextmenu', e => e.preventDefault());
  addEventListener('dragstart', e => e.preventDefault());      // never an HTML drag-and-drop (see capture.html #shot)
  addEventListener('keydown', e => {
    if (e.key === 'Escape') api.done(null);
    if (e.key === 'Enter') api.done(whole());
  });
  window.__ready = true;    // for the smoke run
})();
