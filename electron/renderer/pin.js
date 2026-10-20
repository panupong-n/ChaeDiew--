'use strict';
// Pinned picture (native PinWindow): drag to move, wheel to resize, right-click for copy / opacity / close, Esc to close.
(async () => {
  const pin = window.tenix.pin;
  document.getElementById('pic').src = await pin.init();
  document.title = t('Pinned picture');
  let last = null;
  addEventListener('pointerdown', e => {
    if (e.button !== 0) return;
    last = { x: e.screenX, y: e.screenY };
    try { document.body.setPointerCapture(e.pointerId); } catch { /* synthetic */ }
  });
  addEventListener('pointermove', e => {
    if (!last) return;
    if (e.buttons === 0) { last = null; return; }
    const dx = e.screenX - last.x, dy = e.screenY - last.y;
    if (dx || dy) { pin.move(dx, dy); last = { x: e.screenX, y: e.screenY }; }
  });
  addEventListener('pointerup', () => { last = null; });
  addEventListener('wheel', e => { e.preventDefault(); pin.zoom(e.deltaY < 0 ? 1.08 : 1 / 1.08); }, { passive: false });
  addEventListener('contextmenu', e => { e.preventDefault(); pin.menu(); });
  addEventListener('keydown', e => { if (e.key === 'Escape') pin.close(); });
  addEventListener('dragstart', e => e.preventDefault());
  window.__ready = true;
})();
