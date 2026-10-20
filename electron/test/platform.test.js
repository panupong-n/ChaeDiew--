'use strict';
// Run: node test/platform.test.js — capture geometry, global-shortcut recording, file names and the tray icon choice (no Electron needed).
const path = require('path');
const { cropRect, editorBounds } = require('../src/capture-geom');
const H = require('../src/hotkeys');
const F = require('../src/files');
const { trayIconFile } = require('../src/tray-icon');

let passed = 0;
function check(name, ok, detail) {
  if (ok) { passed++; console.log('PASS  ' + name); } else { console.log('FAIL  ' + name + (detail ? '  —  ' + JSON.stringify(detail) : '')); process.exitCode = 1; }
}
const eq = (a, b) => JSON.stringify(a) === JSON.stringify(b);

// ---- capture: overlay CSS pixels → screenshot pixels
check('100 %: a drag maps 1:1', eq(cropRect({ x: 10, y: 20, w: 300, h: 200, vw: 1920, vh: 1080 }, { width: 1920, height: 1080 }), { x: 10, y: 20, width: 300, height: 200 }));
check('150 %: CSS pixels scale to device pixels', eq(cropRect({ x: 100, y: 100, w: 200, h: 100, vw: 1280, vh: 720 }, { width: 1920, height: 1080 }), { x: 150, y: 150, width: 300, height: 150 }));
check('125 %: fractional scale rounds to whole pixels and keeps the far edge', (() => {
  const r = cropRect({ x: 1, y: 1, w: 1535, h: 863, vw: 1536, vh: 864 }, { width: 1920, height: 1080 });
  return r.x === 1 && r.y === 1 && r.x + r.width === 1920 && r.y + r.height === 1080;
})());
// The bug this replaces: an overlay shrunk to the work area (1032 of 1080 high) used the width ratio for y too.
const squeezed = cropRect({ x: 0, y: 1000, w: 100, h: 32, vw: 1920, vh: 1032 }, { width: 1920, height: 1080 });
check('an overlay of another aspect still maps y by its own height', squeezed.y === 1047 && squeezed.y + squeezed.height === 1080, squeezed);
// 1366 × 768 at 125 %: the display is 1092.8 × 614.4 CSS px, the window 1093 × 614; dpr gives exact device pixels where the ratio is off by one.
const frac = cropRect({ x: 100, y: 100, w: 200, h: 200, vw: 1093, vh: 614, dpr: 1.25 }, { width: 1366, height: 768 });
check('fractional display size: CSS × devicePixelRatio is used (200 CSS px = 250 px)', frac.width === 250 && frac.height === 250 && frac.x === 125, frac);
check('…but not when the screenshot is not viewport × dpr', cropRect({ x: 0, y: 0, w: 100, h: 100, vw: 1000, vh: 1000, dpr: 2 }, { width: 1000, height: 1000 }).width === 100);
check('a selection is clamped to the picture', eq(cropRect({ x: -20, y: -5, w: 3000, h: 3000, vw: 1920, vh: 1080 }, { width: 1920, height: 1080 }), { x: 0, y: 0, width: 1920, height: 1080 }));
check('a tiny selection is still at least 1 × 1', (() => { const r = cropRect({ x: 5, y: 5, w: 0.2, h: 0.2, vw: 100, vh: 100 }, { width: 100, height: 100 }); return r.width === 1 && r.height === 1; })());
const eb = editorBounds({ x: -1920, y: 0, width: 1920, height: 1040 });     // a monitor on the left (negative x)
check('the editor opens centred on the capture\'s own display, also at negative coordinates', eb.x === -1920 + 270 && eb.width === 1380 && eb.x + eb.width <= 0);
check('the editor fits a small display', (() => { const b = editorBounds({ x: 0, y: 0, width: 1024, height: 728 }); return b.width === 964 && b.height === 668 && b.x === 30; })());

// ---- global shortcuts
check('Ctrl+Shift+2 records from the physical key (Thai layout gives e.key "/")', H.fromKeyEvent({ code: 'Digit2', key: '/', ctrlKey: true, shiftKey: true }, 'win32') === 'Control+Shift+2');
check('a letter records as a Latin letter whatever the layout', H.fromKeyEvent({ code: 'KeyA', key: 'ฟ', ctrlKey: true, altKey: true }, 'win32') === 'Control+Alt+A');
check('Print Screen alone is allowed', H.fromKeyEvent({ code: 'PrintScreen' }, 'win32') === 'PrintScreen');
check('F-keys alone are allowed', H.fromKeyEvent({ code: 'F9' }, 'win32') === 'F9');
check('a plain letter or Shift+letter is refused (that is typing)', H.fromKeyEvent({ code: 'KeyA' }, 'win32') === null && H.fromKeyEvent({ code: 'KeyA', shiftKey: true }, 'win32') === null);
check('only modifiers held: nothing yet', H.fromKeyEvent({ code: 'ControlLeft', ctrlKey: true }, 'win32') === null);
check('labels read as Windows users expect', H.label('CommandOrControl+Shift+2', 'win32') === 'Ctrl+Shift+2' && H.label('Control+PrintScreen', 'win32') === 'Ctrl+PrtScn');
check('labels on the Mac use symbols', H.label('CommandOrControl+Shift+2', 'darwin') === '⌘⇧2');
check('CommandOrControl and Control are the same shortcut on Windows', H.same('CommandOrControl+Shift+1', 'Shift+Control+1', 'win32') && !H.same('CommandOrControl+Shift+1', 'Control+Shift+1', 'darwin'));
check('defaults and presets are distinct pairs', H.PRESETS.every(p => !H.same(p.area, p.full, 'win32')) && H.same(H.DEFAULTS.area, H.PRESETS[0].area, 'win32'));

// ---- file names
check('Windows-forbidden characters are replaced', F.sanitizeName('a<b>c:d"e/f\\g|h?i*j') === 'a-b-c-d-e-f-g-h-i-j');
check('trailing dots and spaces are removed', F.sanitizeName('report. . ') === 'report');
check('reserved device names are escaped', F.sanitizeName('CON') === '_CON' && F.sanitizeName('lpt1.png') === '_lpt1.png' && F.sanitizeName('console') === 'console');
check('an empty name gets a default', F.sanitizeName('  ') === 'Tenix-ChaeDiew');
check('Thai names are kept', F.sanitizeName('รายงาน ประจำเดือน') === 'รายงาน ประจำเดือน');
check('the default name has no colon (Windows) and sorts by time', F.defaultName(new Date(2026, 9, 19, 9, 5, 7)) === 'Tenix-ChaeDiew 2026-10-19 at 09.05.07');
check('a missing extension is added for the chosen format', F.withExtension(path.join('C:', 'x', 'shot'), 'jpg') === path.join('C:', 'x', 'shot.jpg') && F.withExtension('a.PNG', 'jpg') === 'a.PNG');
check('a typed .jpeg is kept', F.formatOf('C:\\a\\b.jpeg') === 'jpg' && F.formatOf('b.webp') === null);
const taken = new Set([path.join('D', 'n.png'), path.join('D', 'n 2.png')]);
check('quick save never overwrites: name, name 2, name 3', F.uniquePath('D', 'n', 'png', p => taken.has(p)) === path.join('D', 'n 3.png'));

// ---- tray
check('dark taskbar gets the light mark, light taskbar the dark mark', trayIconFile('win32', false) === 'mark-on-dark.png' && trayIconFile('win32', true) === 'mark-on-light.png');
check('macOS uses the template (dark) mark', trayIconFile('darwin', false) === 'mark-on-light.png');

console.log(`\n${process.exitCode ? 'SOME CHECKS FAILED' : 'All checks passed.'} (${passed} passed)`);
