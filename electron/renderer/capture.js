'use strict';
(async () => {
  const api = window.tenix.capture;
  const shot = await api.getShot();
  const img = document.getElementById('shot'), dim = document.getElementById('dim'), sel = document.getElementById('sel'), size = document.getElementById('size');
  document.getElementById('help').textContent = t('Drag to choose an area · Enter or double-click = whole screen · Esc = cancel');
  img.src = shot; await img.decode();
  let a = null;
  const rect = (p, q) => ({ x: Math.min(p.x, q.x), y: Math.min(p.y, q.y), w: Math.abs(p.x - q.x), h: Math.abs(p.y - q.y) });
  addEventListener('mousedown', e => { a = { x: e.clientX, y: e.clientY }; dim.style.display = 'none'; });
  addEventListener('mousemove', e => {
    if (!a) return;
    const r = rect(a, { x: e.clientX, y: e.clientY });
    Object.assign(sel.style, { display: 'block', left: r.x + 'px', top: r.y + 'px', width: r.w + 'px', height: r.h + 'px' });
    Object.assign(size.style, { display: 'block', left: r.x + 'px', top: Math.max(4, r.y - 28) + 'px' });
    size.textContent = Math.round(r.w) + ' × ' + Math.round(r.h);
  });
  addEventListener('mouseup', e => {
    if (!a) return;
    const r = rect(a, { x: e.clientX, y: e.clientY }); a = null;
    api.done(r.w < 4 || r.h < 4 ? null : { ...r, vw: innerWidth, vh: innerHeight });
  });
  addEventListener('dblclick', () => api.done({ x: 0, y: 0, w: innerWidth, h: innerHeight, vw: innerWidth, vh: innerHeight }));
  addEventListener('keydown', e => {
    if (e.key === 'Escape') api.done(null);
    if (e.key === 'Enter') api.done({ x: 0, y: 0, w: innerWidth, h: innerHeight, vw: innerWidth, vh: innerHeight });
  });
})();
