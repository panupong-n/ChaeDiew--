'use strict';
// Smoke checks for what differs per platform (written for the first run on Windows): the one-bar title bar on a narrow window, the
// capture overlay (bounds, drag, double-click, Esc, own windows hidden), global shortcuts, keyboard shortcuts with a Thai layout,
// saving/copying, the license window, the tray, OCR time-out and live language switching. Called from test/smoke.js.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { BrowserWindow, clipboard, desktopCapturer, globalShortcut, nativeImage } = require('electron');

async function grabScreenRegion(h, rect) {
  const d = h.screen.getDisplayMatching(rect), sf = d.scaleFactor;
  const sources = await desktopCapturer.getSources({ types: ['screen'], thumbnailSize: { width: Math.round(d.size.width * sf), height: Math.round(d.size.height * sf) } });
  const src = sources.find(s => s.display_id === String(d.id)) || sources[0];
  if (!src) return null;
  const x = Math.max(0, Math.round((rect.x - d.bounds.x) * sf)), y = Math.max(0, Math.round((rect.y - d.bounds.y) * sf));
  const size = src.thumbnail.getSize();
  return src.thumbnail.crop({ x, y, width: Math.min(size.width - x, Math.round(rect.width * sf)), height: Math.min(size.height - y, Math.round(rect.height * sf)) });
}

/** Electron 44's async clipboard: the PNG on the clipboard as a NativeImage, or null. */
async function readClipboardImage() {
  for (const item of await clipboard.read()) {
    if (item.types.includes('image/png')) return nativeImage.createFromBuffer(Buffer.from(await (await item.getType('image/png')).arrayBuffer()));
  }
  return null;
}

/** A promise that gives up (null) after `ms`: executeJavaScript on a window that is closing never settles. */
const within = (promise, ms) => Promise.race([promise, new Promise(r => setTimeout(() => r(null), ms))]);

async function waitFor(fn, ms = 6000, step = 100) {
  const end = Date.now() + ms;
  for (;;) {
    let v; try { v = await within(Promise.resolve(fn()), Math.max(200, end - Date.now())); } catch { v = null; }
    if (v || Date.now() > end) return v;
    await new Promise(r => setTimeout(r, step));
  }
}

async function run(h, { check, shot, sleep, outDir, win }) {
  const ev = code => win.webContents.executeJavaScript(code, true);
  const win32 = process.platform === 'win32';
  const save = (name, img) => { if (img && !img.isEmpty()) fs.writeFileSync(path.join(outDir, name + '.png'), img.toPNG()); };
  await ev(`document.getElementById('modal').hidden = true`);     // the OCR result from the previous step

  // ------------------------------------------------ title bar: nothing hides under the caption buttons, even at the minimum width
  for (const width of [1320, 960]) {
    win.setSize(width, 760); await sleep(500);
    await ev('__test.fitBar()');
    const m = await ev(`(() => {
      const bar = document.getElementById('bar'), area = navigator.windowControlsOverlay && navigator.windowControlsOverlay.visible ? navigator.windowControlsOverlay.getTitlebarAreaRect() : null;
      const limit = area ? area.x + area.width : innerWidth;
      const vis = [...bar.querySelectorAll('button')].filter(b => b.offsetParent !== null);
      return { overflow: bar.scrollWidth - bar.clientWidth, limit, maxRight: Math.max(...vis.map(b => b.getBoundingClientRect().right)),
        copy: !!document.querySelector('[aria-label="Copy picture"]').offsetParent, more: !!document.querySelector('[aria-label="More"]').offsetParent };
    })()`);
    check(`title bar at ${width} px: every button is clickable, none under the window buttons`, m.overflow <= 1 && m.maxRight <= m.limit + 0.5 && m.copy && m.more, m);
    const b = win.getBounds();
    save(`20-titlebar-${width}`, await grabScreenRegion(h, { x: b.x, y: b.y, width: b.width, height: 64 }));
  }
  const folded = await ev('__test.folded()');
  check('at 960 px low-priority groups fold into the ⋯ menu', folded.includes('zoom') || folded.includes('extras'), folded);
  const menuIds = JSON.stringify(await ev('__test.moreMenuItems()'));
  check('…and the ⋯ menu offers what was folded', (!folded.includes('zoom') || menuIds.includes('"fit"')) && (!folded.includes('extras') || menuIds.includes('"ocr"')) && menuIds.includes('"saveAs"'));
  const appItems = h.editorMenuTemplate(win.webContents, { items: [] }).map(i => i.label).filter(Boolean);
  check('the ⋯ menu also reaches capture, open, settings and license from the editor', ['Capture an area', 'Capture the whole screen', 'Open a picture…', 'Settings…', 'License…'].every(l => appItems.includes(l)), appItems);
  await ev('__test.runCommand("actual")');
  check('a menu command reaches the editor (Actual size → 100 %)', Math.abs((await ev('__test.S.zoom')) - 1) < 1e-9);
  win.setSize(1320, 860); await sleep(400);
  await ev('__test.setTool("select"); __test.runCommand("fit")');

  // ------------------------------------------------ keyboard shortcuts with the Thai layout (e.key is Thai, e.code is the key)
  await ev(`__test.setTool('select'); __test.key({ key: 'พ', code: 'KeyR' })`);
  check('Thai layout: the R key (พ) picks the rectangle', (await ev('__test.S.tool')) === 'rect');
  await ev(`__test.key({ key: 'ฟ', code: 'KeyA' })`);
  check('Thai layout: the A key (ฟ) picks the arrow', (await ev('__test.S.tool')) === 'arrow');
  await ev(`__test.drag(200, 200, 320, 260)`);
  const n1 = await ev('__test.shapes().length');
  await ev(`__test.key({ key: 'ผ', code: 'KeyZ', ctrlKey: ${!(process.platform === 'darwin')}, metaKey: ${process.platform === 'darwin'} })`);
  const n2 = await ev('__test.shapes().length');
  await ev(`__test.key({ key: 'ั', code: 'KeyY', ctrlKey: ${!(process.platform === 'darwin')}, metaKey: ${process.platform === 'darwin'} })`);
  const n3 = await ev('__test.shapes().length');
  check('Thai layout: Ctrl+Z (ผ) undoes and Ctrl+Y (ั) redoes', n2 === n1 - 1 && n3 === n1, [n1, n2, n3]);
  await ev(`__test.key({ key: 'ช', code: 'Equal' })`);
  const zIn = await ev('__test.S.fitMode');
  await ev(`__test.key({ key: 'จ', code: 'Digit0' })`);
  check('Thai layout: + (ช) zooms in and 0 (จ) fits the window', zIn === false && (await ev('__test.S.fitMode')) === true);
  win.focus(); await sleep(150);
  win.webContents.sendInputEvent({ type: 'keyDown', keyCode: 'L' }); win.webContents.sendInputEvent({ type: 'char', keyCode: 'l' }); win.webContents.sendInputEvent({ type: 'keyUp', keyCode: 'L' });
  await sleep(150);
  check('a real key press (L) picks the line tool', (await ev('__test.S.tool')) === 'line');
  await ev(`__test.setTool('select')`);

  // ------------------------------------------------ text box sits exactly on its mark (display scale)
  await ev(`__test.setTool('text'); __test.click(300, 420);`);
  const pos = await ev(`(() => { const el = __test.S.editing && __test.S.editing.el; if (!el) return null; const r = el.getBoundingClientRect(), c = document.getElementById('cv').getBoundingClientRect(), k = __test.scale();
    const p = __test.S.bd.on ? __test.S.bd.pad : 0;     // a backdrop puts padding around the picture
    return { dx: r.left - (c.left + (300 + p) * k), dy: r.top - (c.top + (420 + p) * k), dpr: devicePixelRatio }; })()`);
  check(`the text box opens on the click point (devicePixelRatio ${pos && pos.dpr})`, pos && Math.abs(pos.dx) < 1.5 && Math.abs(pos.dy) < 1.5, pos);
  await ev(`__test.commitEdit(); __test.setTool('select')`);

  // ------------------------------------------------ saving: quick save into the folder, JPEG, failure is reported
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tenix-save ทดสอบ '));    // a space and Thai in the path
  h.applySettings({ saveDir: dir, askWhere: false, format: 'png' });
  const r1 = await ev('__test.saveImage()');
  check('Save puts a PNG straight into the chosen folder (path with a space and Thai)', r1 && r1.ok && fs.existsSync(r1.path) && /\.png$/.test(r1.path) && path.dirname(r1.path) === dir, r1);
  const r2 = await ev('__test.saveImage()');
  check('a second save does not overwrite the first', r2 && r2.ok && r2.path !== r1.path && fs.existsSync(r1.path));
  h.applySettings({ format: 'jpg' });
  const r3 = await ev('__test.saveImage()');
  const jpg = r3 && r3.ok && fs.readFileSync(r3.path);
  check('JPEG format writes a real JPEG', jpg && jpg[0] === 0xff && jpg[1] === 0xd8 && /\.jpg$/.test(r3.path), r3);
  if (r1 && r1.ok) {
    const saved = nativeImage.createFromPath(r1.path).getSize(), [ew, eh] = await ev('__test.exportSize()');
    check('the saved file has the full picture size', saved.width === ew && saved.height === eh, [saved, ew, eh]);
  }
  const bad = h.writeImageFile(path.join(r1 && r1.ok ? r1.path : dir, 'inside-a-file', 'x.png'), await ev('__test.exportDataURL()'));
  check('a save that cannot be written comes back as an error (no crash)', bad.error === 'write' && !!bad.message, bad);
  h.applySettings({ saveDir: path.join(os.homedir(), 'Pictures'), askWhere: true, format: 'png' });

  // ------------------------------------------------ copy through the main process
  clipboard.clear();
  const res = await ev('window.tenix.copyImage(__test.exportDataURL())');
  const clip = await readClipboardImage();
  check('Copy puts the picture on the system clipboard (no window focus needed)', res.ok && clip && clip.getSize().width === (await ev('__test.exportSize()'))[0], [res, clip && clip.getSize()]);

  // ------------------------------------------------ live language switch keeps the work
  const before = await ev('__test.shapes().length');
  h.setLanguage('th'); await sleep(700);
  const afterTh = await ev('[__test.shapes().length, __test.lang(), __test.barText()]');
  check('switching to Thai relabels the editor in place and keeps every mark', afterTh[0] === before && afterTh[1] === 'th' && /คัดลอก/.test(afterTh[2]), afterTh.slice(0, 2));
  await shot(win, '21-editor-thai-live');
  h.setLanguage('en'); await sleep(500);
  check('…and back to English', (await ev('__test.lang()')) === 'en' && (await ev('__test.shapes().length')) === before);

  // ------------------------------------------------ global shortcuts: status is known, a taken one is reported, and they can be changed
  const st = h.publicSettings().hotkeys;
  console.log(`      global shortcuts now: area ${st.area.label} ${st.area.ok ? 'OK' : 'NOT AVAILABLE'}, full ${st.full.label} ${st.full.ok ? 'OK' : 'NOT AVAILABLE'}`);
  const taken = 'Control+Alt+Shift+F9';
  globalShortcut.register(taken, () => {});      // stand-in for another program owning the combination
  let s = h.applySettings({ hotkeys: { area: taken, full: 'Control+Alt+Shift+F10' } });
  check('a shortcut another program owns is reported as not available', s.hotkeys.area.ok === false && s.hotkeys.full.ok === true, s.hotkeys);
  h.showHome(); await sleep(900);
  const home = h.windows().homeWindow;
  const warn = await home.webContents.executeJavaScript(`[!document.getElementById('hk-warn').hidden, document.getElementById('hk-warn-text').textContent, document.getElementById('k-area').className]`);
  check('the home window warns about it and strikes the shortcut through', warn[0] && /Ctrl\+Alt\+Shift\+F9/.test(warn[1]) && /off/.test(warn[2]), warn);
  const fits = await home.webContents.executeJavaScript(`[document.querySelector('.ver').getBoundingClientRect().bottom, innerHeight, document.body.scrollHeight]`);
  check('with the warning shown, the credit and version still fit in the home window', fits[0] <= fits[1] && fits[2] <= fits[1], fits);
  await shot(home, '22-home-shortcut-warning');
  s = h.applySettings({ hotkeys: { area: 'Control+Alt+Shift+F10' } });
  check('both captures cannot share a shortcut', s.errors.hotkeys === 'duplicate');
  globalShortcut.unregister(taken);
  s = h.applySettings({ hotkeys: { area: 'Control+Alt+Shift+F11', full: 'Control+Alt+Shift+F12' } });
  check('a free shortcut registers', s.hotkeys.area.ok && s.hotkeys.full.ok, s.hotkeys);
  await sleep(300);
  check('…and the warning goes away', await home.webContents.executeJavaScript(`document.getElementById('hk-warn').hidden`));

  // ------------------------------------------------ Settings window: record a shortcut with a Thai layout key event
  h.showSettings(); await sleep(1000);
  const sw = h.windows().settingsWindow;
  await sw.webContents.executeJavaScript(`__settingsTest.startRecording('area')`);
  await sleep(200);
  await sw.webContents.executeJavaScript(`document.getElementById('key-area').dispatchEvent(new KeyboardEvent('keydown', { key: 'ๅ', code: 'Digit1', ctrlKey: true, altKey: true, shiftKey: true, bubbles: true }))`);
  await sleep(600);
  s = h.publicSettings();
  check('Settings records a new shortcut from the physical key (Thai layout)', s.hotkeys.area.accel === 'Control+Alt+Shift+1' && s.hotkeys.area.ok, s.hotkeys.area);
  await shot(sw, '23-settings');
  h.applySettings({ hotkeys: { area: 'CommandOrControl+Shift+2', full: 'CommandOrControl+Shift+1' } });
  sw.close(); await sleep(300);

  // ------------------------------------------------ license window: no Remove button without a key, machine code can be copied
  h.showLicense(); await sleep(300); h.showLicense(); await sleep(900);
  const lws = BrowserWindow.getAllWindows().filter(w => !w.isDestroyed() && /License|ไลเซนส์/.test(w.getTitle()));
  const lw = h.windows().licenseWindow;
  check('opening the license window again replaces it and the app keeps track of the new one', lws.length === 1 && lw === lws[0], lws.length);
  if (!lw) return;
  const lic = await lw.webContents.executeJavaScript(`[getComputedStyle(document.getElementById('remove')).display, !!document.getElementById('copy-machine')]`);
  check('no "Remove license" button while there is no key', lic[0] === 'none', lic[0]);
  check("the trial no longer shows a machine code or a Copy button (a key alone is enough)", !lic[1]);
  await shot(lw, '24-license-copy');
  lw.close();
  await require('./smoke-license').run(h, { check, shot, sleep });

  // ------------------------------------------------ the tray
  const tray = h.tray();
  check('a tray icon exists with a tooltip', !!tray && !tray.isDestroyed());

  // ------------------------------------------------ capture overlay: real window, real mouse events
  const display = h.screen.getDisplayNearestPoint(h.screen.getCursorScreenPoint()), sf = display.scaleFactor;
  h.showHome(); await sleep(500);
  const overlay = async () => {
    const job = await waitFor(() => [...h.captureJobs.values()][0], 8000);
    if (!job) return null;
    await waitFor(() => job.window.webContents.executeJavaScript('!!window.__ready').catch(() => false), 6000);
    await sleep(200);
    return job.window;
  };
  // Like a real mouse: the pointer arrives first, and the button is held while it moves.
  const mouse = (wc, type, x, y, clickCount = 1, held = false) => wc.sendInputEvent({ type, x, y, button: 'left', clickCount, ...(held ? { modifiers: ['leftButtonDown'] } : {}) });
  const drag = (wc, x1, y1, x2, y2) => {
    mouse(wc, 'mouseMove', x1, y1); mouse(wc, 'mouseDown', x1, y1);
    mouse(wc, 'mouseMove', (x1 + x2) / 2, (y1 + y2) / 2, 1, true); mouse(wc, 'mouseMove', x2, y2, 1, true); mouse(wc, 'mouseUp', x2, y2);
  };

  let pending = h.capture('area');
  let ov = await overlay();
  check('the capture overlay opens', !!ov);
  if (ov) {
    const ob = ov.getBounds(), inner = await ov.webContents.executeJavaScript('[innerWidth, innerHeight]');
    // ±1: at fractional scales the display is a fraction of a CSS pixel larger than any window can be.
    const near = (a, b) => Math.abs(a - b) <= 1;
    check('the overlay covers the whole display including the taskbar', ob.x === display.bounds.x && ob.y === display.bounds.y && near(ob.width, display.bounds.width) && near(ob.height, display.bounds.height) && near(inner[1], display.bounds.height), { ob, inner, display: display.bounds });
    check('the home window is hidden while capturing (not in the picture)', !h.windows().homeWindow.isVisible());
    save('25-overlay-real-screen', await grabScreenRegion(h, display.bounds));
    const wc = ov.webContents;
    const shotImg = await wc.executeJavaScript(`(() => { const i = document.getElementById('shot'); return [i.draggable, getComputedStyle(i).pointerEvents, getComputedStyle(i).webkitUserDrag]; })()`);
    check('the screenshot on the overlay cannot be dragged as an image (that froze the app on Windows)', shotImg[0] === false && shotImg[1] === 'none', shotImg);
    const t0 = Date.now();
    drag(wc, 100, 120, 400, 320);
    const ed = await within(pending, 10000);
    check('the drag finishes by itself, without anyone touching the mouse', ed && Date.now() - t0 < 3000, Date.now() - t0);
    const want = { width: Math.round(400 * sf) - Math.round(100 * sf), height: Math.round(320 * sf) - Math.round(120 * sf) };
    const got = ed && (await waitFor(() => ed.webContents.executeJavaScript('window.__test ? [__test.S.w, __test.S.h, __test.S.pixelScale] : null'), 8000));
    check(`dragging 300 × 200 (scale ${sf}) opens the editor with exactly that area`, got && got[0] === want.width && got[1] === want.height && got[2] === sf, { got, want });
    if (ed) {
      const eb = ed.getBounds(), wa = display.workArea;
      check('the editor opens on the display of the capture', eb.x >= wa.x && eb.y >= wa.y && eb.x + eb.width <= wa.x + wa.width && eb.y + eb.height <= wa.y + wa.height, { eb, wa });
      ed.destroy();
    }
  }

  pending = h.capture('area');
  ov = await overlay();
  if (ov) {
    const wc = ov.webContents;
    mouse(wc, 'mouseMove', 300, 300); mouse(wc, 'mouseDown', 300, 300, 1); mouse(wc, 'mouseUp', 300, 300, 1);
    await sleep(120);
    check('a single click does not cancel the overlay', !ov.isDestroyed());
    mouse(wc, 'mouseDown', 300, 300, 2); mouse(wc, 'mouseUp', 300, 300, 2);
    const ed = await within(pending, 10000);
    const got = ed && (await waitFor(() => ed.webContents.executeJavaScript('window.__test ? [__test.S.w, __test.S.h] : null'), 8000));
    const full = (await h.grabDisplay(display)).getSize();
    check('double-click takes the whole screen', got && got[0] === full.width && got[1] === full.height, { got, full });
    if (ed) ed.destroy();
  }

  // A release that never arrives (Windows can drop it when another program grabs the mouse): the next move with no button held ends
  // the drag where the button was last held.
  pending = h.capture('area');
  ov = await overlay();
  if (ov) {
    const wc = ov.webContents;
    mouse(wc, 'mouseMove', 200, 200); mouse(wc, 'mouseDown', 200, 200); mouse(wc, 'mouseMove', 300, 260, 1, true); mouse(wc, 'mouseMove', 360, 300, 1, true);
    await sleep(150);
    mouse(wc, 'mouseMove', 380, 330);      // no mouseUp: the button is simply no longer held
    const ed = await within(pending, 10000);
    const got = ed && (await waitFor(() => ed.webContents.executeJavaScript('window.__test ? [__test.S.w, __test.S.h] : null'), 8000));
    check('a lost button release still ends the selection where the button was last held', got && got[0] === Math.round(360 * sf) - Math.round(200 * sf) && got[1] === Math.round(300 * sf) - Math.round(200 * sf), got);
    if (ed) ed.destroy();
  }

  h.showHome(); await sleep(500);
  pending = h.capture('area');
  ov = await overlay();
  if (ov) {
    ov.webContents.sendInputEvent({ type: 'keyDown', keyCode: 'Escape' });
    const ed = await within(pending, 10000);
    await sleep(300);     // closing a window finishes asynchronously
    check('Esc cancels without opening an editor', ed === null && ov.isDestroyed(), { ed: String(ed), destroyed: ov.isDestroyed() });
    await sleep(400);
    check('…and the home window comes back', h.windows().homeWindow && h.windows().homeWindow.isVisible());
  }
  pending = h.capture('area');
  ov = await overlay();
  if (ov) {
    ov.webContents.sendInputEvent({ type: 'mouseDown', x: 50, y: 50, button: 'right', clickCount: 1 });
    check('right-click cancels too', (await within(pending, 10000)) === null);
  }

  console.log('      · capture checks done');
  // ------------------------------------------------ OCR: a stuck job times out and the engine comes back
  const png = nativeImage.createFromDataURL(await ev('__test.exportDataURL()')).toPNG();
  h.ocr.setTimeoutMs(1);
  let err = null; try { await h.ocr.recognize(png); } catch (e) { err = e.message; }
  h.ocr.setTimeoutMs(90000);
  check('an OCR job that takes too long fails with a time-out instead of hanging', err === 'timeout', err);
  let again = null; try { again = await h.ocr.recognize(png); } catch (e) { again = { error: e.message }; }
  check('…and the next request starts a fresh engine and works', again && Array.isArray(again.lines) && again.lines.length > 2, again && again.error);

  console.log('      · OCR time-out checks done');
  // ------------------------------------------------ edit text: Windows faces (menus, Office, Thai UI and documents)
  const SAMPLES = [
    ['Segoe UI', 400, 15, '#1F1F1F', 'File  Edit  View  Insert  Format  Help'],
    ['Calibri', 400, 22, '#203864', 'Quarterly sales report 2026'],
    ['Consolas', 400, 18, '#0B6E0B', 'Status: connected (port 8080)'],
    ['Tahoma', 700, 18, '#222222', 'Account settings'],
    ['Leelawadee UI', 400, 20, '#16365C', 'บันทึกการเปลี่ยนแปลงทั้งหมด'],
    ['TH Sarabun New', 400, 30, '#000000', 'รายงานผลการดำเนินงานประจำปี'],
  ];
  const fontsOk = await ev(`JSON.stringify(${JSON.stringify(SAMPLES.map(s => s[0]))}.map(f => [f, window.FontMatch.installed(f)]))`);
  console.log('      installed faces: ' + fontsOk);
  const pic = await win.webContents.executeJavaScript(`(() => {
    const c = document.createElement('canvas'); c.width = 900; c.height = 60 + ${SAMPLES.length} * 64; const x = c.getContext('2d');
    x.fillStyle = '#FFFFFF'; x.fillRect(0, 0, c.width, c.height); x.textBaseline = 'top';
    ${JSON.stringify(SAMPLES)}.forEach(([f, wgt, size, col, text], i) => { x.fillStyle = col; x.font = wgt + ' ' + size + 'px "' + f + '"'; x.fillText(text, 40, 40 + i * 64); });
    return c.toDataURL('image/png');
  })()`);
  const ed2 = h.openEditor(nativeImage.createFromDataURL(pic), 1);
  await waitFor(() => ed2.webContents.executeJavaScript('!!window.__test'), 8000);
  const e2 = code => ed2.webContents.executeJavaScript(code, true);
  await e2(`__test.setTool('editText')`);
  const ocrLines = await e2(`__test.ensureOcr().then(l => l.map(x => ({ t: x.text, b: x.bbox })))`);
  const results = [];
  for (const [face, weight, size, colour, text] of SAMPLES) {
    const i = SAMPLES.findIndex(s => s[4] === text), y = 40 + i * 64 + size / 2;
    const line = ocrLines.find(l => l.b.y0 <= y && l.b.y1 >= y);
    if (!line) { results.push({ face, found: false }); continue; }
    await e2(`__test.setTool('editText'); __test.click(${(line.b.x0 + line.b.x1) / 2}, ${(line.b.y0 + line.b.y1) / 2}, 1, { shiftKey: true })`);
    await sleep(250);
    const m = await e2(`(() => { const s = __test.selected(), g = __test.S.lastMatch; __test.commitEdit();
      return s && s.type === 'text' ? { font: s.font, bold: s.bold, size: s.size, color: s.color, x: s.x, y: s.y, text: s.text, score: g && g.score, runnerUp: g && g.runnerUp } : null; })()`);
    results.push({ face, weight, size0: size, colour, ocr: line.t, ...(m || { found: false }) });
  }
  for (const r of results) {
    const ru = r.runnerUp ? `  (next: ${r.runnerUp.font}${r.runnerUp.bold ? ' bold' : ''} ${r.runnerUp.score.toFixed(3)})` : '';
    console.log(`      ${r.face.padEnd(15)} → ${r.font || '—'}${r.bold ? ' bold' : ''} ${r.size ? Math.round(r.size) + 'px' : ''} ${r.color || ''} score ${r.score ? r.score.toFixed(3) : '—'}${ru}  ocr="${r.ocr || ''}"`);
  }
  const named = (r, re) => r.font && re.test(r.font);
  if (win32) {
    const by = f => results.find(r => r.face === f) || {};
    check('Windows menu text matches Segoe UI', named(by('Segoe UI'), /Segoe UI/), by('Segoe UI'));
    check('Thai UI text matches Leelawadee UI', named(by('Leelawadee UI'), /Leelawadee/), by('Leelawadee UI'));
    check('every Windows sample is found and matched at about its size (±20 %)', results.every(r => r.font && Math.abs(r.size / r.size0 - 1) <= 0.2), results.map(r => [r.face, r.size, r.size0]));
  }
  await shot(ed2, '26-edit-text-windows-fonts');
  ed2.destroy();
}

module.exports = { run };
