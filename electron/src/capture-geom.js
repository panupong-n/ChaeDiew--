'use strict';
// Overlay rectangle (CSS pixels of the selection window) → crop rectangle in screenshot pixels. Pure, so test/capture.test.js can
// check it without a screen. Width and height are scaled separately: the overlay is not guaranteed to have the screenshot's aspect.

/**
 * rect: { x, y, w, h, vw, vh, dpr } from the overlay; size: { width, height } of the screenshot. When the screenshot is the overlay's
 * size times its devicePixelRatio (±2 px), CSS pixels × dpr are exact device pixels; this matters at fractional scales on displays whose
 * size does not divide evenly (1366 × 768 at 125 % is 1092.8 CSS px wide, and the window can only be 1092 or 1093).
 */
function cropRect(rect, size) {
  const dpr = rect.dpr || 0;
  const exact = dpr > 0 && Math.abs(rect.vw * dpr - size.width) <= 2 && Math.abs(rect.vh * dpr - size.height) <= 2;
  const kx = exact ? dpr : size.width / (rect.vw || size.width), ky = exact ? dpr : size.height / (rect.vh || size.height);
  const clamp = (v, max) => Math.max(0, Math.min(max, v));
  const x0 = clamp(Math.round(rect.x * kx), size.width - 1), y0 = clamp(Math.round(rect.y * ky), size.height - 1);
  const x1 = clamp(Math.round((rect.x + rect.w) * kx), size.width), y1 = clamp(Math.round((rect.y + rect.h) * ky), size.height);
  return { x: x0, y: y0, width: Math.max(1, x1 - x0), height: Math.max(1, y1 - y0) };
}

/** The editor window for a capture: as large as fits (up to 1380 × 900), centred on the display it came from. */
function editorBounds(workArea) {
  const width = Math.max(480, Math.min(1380, workArea.width - 60)), height = Math.max(360, Math.min(900, workArea.height - 60));
  return { x: Math.round(workArea.x + (workArea.width - width) / 2), y: Math.round(workArea.y + (workArea.height - height) / 2), width, height };
}

module.exports = { cropRect, editorBounds };
