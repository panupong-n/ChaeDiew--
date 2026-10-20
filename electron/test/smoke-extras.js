'use strict';
// Smoke checks for pin, print, before/after GIF, upload, history and scrolling capture, in real windows (called from test/smoke.js).
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const { execFileSync } = require('child_process');
const { BrowserWindow, clipboard, nativeImage } = require('electron');

async function waitFor(fn, ms = 8000, step = 150) {
  const end = Date.now() + ms;
  for (;;) {
    let v; try { v = await fn(); } catch { v = null; }
    if (v || Date.now() > end) return v;
    await new Promise(r => setTimeout(r, step));
  }
}

async function run(h, { check, shot, sleep, outDir, editor }) {
  const win = await editor();
  const ev = code => win.webContents.executeJavaScript(code, true);
  const win32 = process.platform === 'win32';

  // ------------------------------------------------ one secret store: an upload secret must not erase the license key (and back)
  h.secrets.set('license-test-entry', 'keep-me');
  h.applySettings({ upload: { s3: { secretKey: 'upload-secret' } } });
  const fresh = require('../src/store').secrets();
  check('saving an upload secret keeps the license data in the same encrypted file', fresh.get('license-test-entry') === 'keep-me' && fresh.get('s3-secret') === 'upload-secret');
  h.secrets.set('license-test-entry', null); h.applySettings({ upload: { s3: { secretKey: '' } } });

  // ------------------------------------------------ pin to the screen (native PinWindow)
  await ev('__test.pinImage()');
  const pinWin = await waitFor(() => [...h.extras.pins.values()][0] && [...h.extras.pins.values()][0].win);
  check('Pin opens a picture window that stays on top', !!pinWin && pinWin.isAlwaysOnTop());
  if (pinWin) {
    await waitFor(() => pinWin.webContents.executeJavaScript('!!window.__ready'));
    await sleep(300);
    const b0 = pinWin.getContentBounds(), [iw, ih] = await ev('__test.exportSize()');
    check('…at the picture size (or 80 % of the screen), same proportions', Math.abs(b0.width / b0.height - iw / ih) < 0.02, { b0, iw, ih });
    const wc = pinWin.webContents;
    wc.sendInputEvent({ type: 'mouseWheel', x: 50, y: 50, deltaX: 0, deltaY: 120, wheelTicksY: 1, canScroll: true });
    await sleep(300);
    const b1 = pinWin.getContentBounds();
    check('the mouse wheel resizes it and keeps its proportions', b1.width !== b0.width && Math.abs(b1.width / b1.height - b0.width / b0.height) < 0.03, { b0, b1 });
    // Screen coordinates too (globalX/Y): the pin moves by how far the pointer moved on the screen, as with a real mouse.
    const at = (x, y) => ({ x, y, globalX: b1.x + x, globalY: b1.y + y });
    wc.sendInputEvent({ type: 'mouseMove', ...at(60, 60) }); wc.sendInputEvent({ type: 'mouseDown', ...at(60, 60), button: 'left', clickCount: 1 });
    wc.sendInputEvent({ type: 'mouseMove', ...at(140, 100), modifiers: ['leftButtonDown'] }); wc.sendInputEvent({ type: 'mouseUp', ...at(140, 100), button: 'left', clickCount: 1 });
    await sleep(300);
    const b2 = pinWin.getContentBounds();
    check('dragging moves it by the distance dragged', Math.abs(b2.x - b1.x - 80) <= 2 && Math.abs(b2.y - b1.y - 40) <= 2, { b1, b2 });
    await shot(pinWin, '40-pin');
    wc.sendInputEvent({ type: 'keyDown', keyCode: 'Escape' });
    await sleep(400);
    check('Esc closes it', pinWin.isDestroyed() && h.extras.pins.size === 0);
  }

  // ------------------------------------------------ print: the picture alone, landscape when wide (checked as a PDF)
  const pdf = path.join(outDir, '41-print.pdf');
  const pr = await h.extras.printImage(await ev('__test.exportDataURL()'), { toPDF: pdf });
  const pdfBytes = fs.existsSync(pdf) ? fs.readFileSync(pdf) : Buffer.alloc(0);
  check('Print lays the picture out on a page (PDF of the print page)', pr.ok && pdfBytes.slice(0, 4).toString() === '%PDF' && pdfBytes.length > 20000 && pr.landscape === true, { pr, size: pdfBytes.length });
  check('…on one page', (pdfBytes.toString('latin1').match(/\/Type\s*\/Page[^s]/g) || []).length === 1);

  // ------------------------------------------------ before / after GIF (native GIFExport), saved and the file put on the clipboard
  const gifDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tenix-gif ทดสอบ '));
  h.applySettings({ saveDir: gifDir });
  await ev(`__test.setTool('rect'); __test.drag(80, 120, 420, 260)`);
  const g = await ev('__test.exportGif()');
  const gifBytes = g && g.ok ? fs.readFileSync(g.path) : Buffer.alloc(0);
  check('Before / after GIF is saved as a GIF in the save folder', g && g.ok && gifBytes.slice(0, 6).toString() === 'GIF89a' && path.dirname(g.path) === gifDir, g);
  const decoded = await ev(`new Promise(r => { const i = new Image(); i.onload = () => r([i.naturalWidth, i.naturalHeight]); i.onerror = () => r(null); i.src = 'data:image/gif;base64,${gifBytes.toString('base64')}'; })`);
  const [ew, eh] = await ev('__test.exportSize()');
  check('…Chromium decodes it, at the picture size', decoded && decoded[0] === ew && decoded[1] === eh, { decoded, ew, eh });
  if (win32) {
    let drop = '';
    try { drop = execFileSync('powershell.exe', ['-NoProfile', '-Command', '[Console]::OutputEncoding = [Text.Encoding]::UTF8; (Get-Clipboard -Format FileDropList | Select-Object -First 1).FullName'], { encoding: 'utf8', windowsHide: true }).trim(); } catch { /* none */ }
    // The same file whether written with the short (8.3) or the long folder name.
    const real = p => { try { return fs.realpathSync.native(p).toLowerCase(); } catch { return String(p).toLowerCase(); } };
    check('…and the file is on the clipboard, ready to paste into Teams / LINE / Explorer (Thai folder name too)', g.copied && real(drop) === real(g.path), { drop, path: g && g.path });
  }

  // ------------------------------------------------ Settings: the new sections are there and the window scrolls to them
  h.applySettings({ upload: { mode: 's3' } });
  h.showSettings(); await sleep(1000);
  const sw = h.windows().settingsWindow;
  if (sw) {
    await sw.webContents.executeJavaScript(`document.getElementById('h-upload').scrollIntoView()`); await sleep(200);
    check('Settings has History and Upload (S3 fields shown for S3)', await sw.webContents.executeJavaScript(`!!document.getElementById('lib-on') && !document.getElementById('up-s3').hidden && document.getElementById('up-http').hidden`));
    await shot(sw, '45-settings-upload');
    sw.close();
  }
  h.applySettings({ upload: { mode: 'none' } });

  // ------------------------------------------------ upload (native Uploader): not set up → explained; HTTP endpoint → link copied
  h.applySettings({ upload: { mode: 'none' } });
  let up = await ev('__test.uploadImage()');
  check('Upload without settings says how to set it up (and opens Settings)', up && up.error === 'notConfigured' && /Settings/.test(up.message));
  await sleep(500);
  if (h.windows().settingsWindow) h.windows().settingsWindow.close();
  let received = null;
  const server = http.createServer((req, res) => {
    const chunks = []; req.on('data', c => chunks.push(c)); req.on('end', () => {
      received = { auth: req.headers.authorization, bytes: Buffer.concat(chunks) };
      res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ url: 'https://files.example.com/shot-123.png' }));
    });
  });
  await new Promise(r => server.listen(0, '127.0.0.1', r));
  h.applySettings({ upload: { mode: 'http', http: { url: `http://127.0.0.1:${server.address().port}/up`, token: 'smoke-token' } } });
  up = await ev('__test.uploadImage()');
  const png = received && received.bytes.indexOf(Buffer.from([0x89, 0x50, 0x4e, 0x47]));
  check('Upload sends the picture (PNG, bearer token) and copies the link', up && up.ok && up.url === 'https://files.example.com/shot-123.png' && received.auth === 'Bearer smoke-token' && png > 0 && (await clipboard.readText()) === up.url, up);
  check('…and lists it under Uploaded links', h.extras.uploads.load()[0].url === up.url);
  h.extras.showUploads(); await sleep(900);
  const uw = BrowserWindow.getAllWindows().find(w => /Uploaded links|ลิงก์ที่อัปโหลด/.test(w.getTitle()));
  if (uw) { check('the Uploaded links window shows it', (await uw.webContents.executeJavaScript(`document.querySelector('.link .url') && document.querySelector('.link .url').textContent`)) === up.url); await shot(uw, '42-uploaded-links'); uw.close(); }
  server.close();
  h.applySettings({ upload: { mode: 'none', http: { url: '' } } });
  h.applySettings({ upload: { http: { token: '' } } });

  // ------------------------------------------------ history (native Library): kept, read by OCR, searchable, opens again
  const mock = nativeImage.createFromDataURL(await ev('__test.S.original.toDataURL()'));
  const item = h.extras.remember(mock, 1);
  const indexed = await waitFor(() => (h.extras.library.get(item.id) || {}).ocrText, 60000, 500);
  check('a capture is kept in the history and its text is read for search', !!item && /Dashboard/i.test(indexed || ''), (indexed || '').slice(0, 60));
  h.extras.showLibrary(); await sleep(1000);
  const lw = BrowserWindow.getAllWindows().find(w => /History|ประวัติ/.test(w.getTitle()));
  if (lw) {
    await lw.webContents.executeJavaScript(`__libraryTest.search('revenue dashboard')`);
    await sleep(300);
    const found = await lw.webContents.executeJavaScript(`[...document.querySelectorAll('.card')].map(c => c.dataset.id)`);
    check('History search finds it by words in the picture', found.length === 1 && found[0] === item.id, found);
    await lw.webContents.executeJavaScript(`__libraryTest.search('')`); await sleep(300);
    const tallest = await lw.webContents.executeJavaScript(`Math.max(...[...document.querySelectorAll('.acts button')].map(b => b.scrollHeight))`);
    check('History card buttons stay on one line', tallest <= 30, tallest);
    await shot(lw, '43-history');
    const before = BrowserWindow.getAllWindows().length;
    await lw.webContents.executeJavaScript(`document.querySelector('.card[data-id="${item.id}"] .thumb').click()`);
    await sleep(1200);
    check('clicking it opens it in the editor', BrowserWindow.getAllWindows().length === before + 1);
    const opened = BrowserWindow.getAllWindows().find(w => w !== win && w !== lw && /Tenix-ChaeDiew$/.test(w.getTitle()) && w.getSize()[0] > 700);
    if (opened) opened.destroy();
    await lw.webContents.executeJavaScript(`document.querySelector('.card[data-id="${item.id}"] .danger').click()`);
    await sleep(400);
    check('Delete removes it and its files', !h.extras.library.get(item.id) && !fs.existsSync(path.join(h.extras.library.folder, item.fileName)));
    lw.close();
  }

  // ------------------------------------------------ scrolling capture: a real window scrolled while frames are taken
  // Not under --force-device-scale-factor: the desktop picture is then resampled from the real (100 %) screen and content moves by
  // fractions of a pixel, so no two frames share identical rows. On a real 125 / 150 % display the picture is at native resolution.
  if (process.argv.some(a => a.startsWith('--force-device-scale-factor'))) {
    console.log('      (scrolling capture not checked under an emulated display scale — needs a real 125/150 % display)');
    win.destroy();
    return;
  }
  const display = h.screen.getPrimaryDisplay(), sf = display.scaleFactor;
  const page = new BrowserWindow({ x: display.workArea.x + 80, y: display.workArea.y + 60, width: 520, height: 420, frame: false, alwaysOnTop: true, show: false, webPreferences: { sandbox: true } });
  // A long page: numbered rows with their own colours and text, like a document or a list.
  const rows = Array.from({ length: 120 }, (_, i) => `<div style="height:${28 + (i * 7) % 23}px;background:hsl(${(i * 47) % 360} 55% ${86 - (i % 5) * 4}%);font:15px Segoe UI, sans-serif;padding:4px 12px">Row ${i + 1} — ${'lorem ipsum '.repeat(1 + i % 4)}</div>`).join('');
  await page.loadURL('data:text/html;charset=utf-8,' + encodeURIComponent(`<body style="margin:0;overflow-y:scroll;scrollbar-width:none">${rows}</body>`));
  page.showInactive(); page.setAlwaysOnTop(true, 'screen-saver'); await sleep(700);
  const cb = page.getContentBounds();
  const rect = { x: cb.x - display.bounds.x + 20, y: cb.y - display.bounds.y + 20, w: 400, h: 300, vw: display.bounds.width, vh: display.bounds.height, dpr: sf };
  const size = (await h.grabDisplay(display)).getSize();
  const pending = h.extras.scrollSession(display, rect, size, { interval: 200 });
  await sleep(700);
  let scrolled = 0;
  for (let i = 0; i < 8; i++) { scrolled += 110; await page.webContents.executeJavaScript(`scrollBy({ top: 110, behavior: 'instant' }); 0`); await sleep(550); }
  await sleep(500);
  h.extras.finishScroll(true);
  const ed = await pending;
  const got = ed && (await waitFor(() => ed.webContents.executeJavaScript('window.__test ? [__test.S.w, __test.S.h] : null'), 8000));
  const wantH = Math.round((300 + scrolled) * sf);
  check(`scrolling capture joins the frames into one tall picture (${got && got[1]} of ${wantH} px)`, got && got[0] === Math.round(400 * sf) && Math.abs(got[1] - wantH) <= 3 * sf, { got, wantH });
  if (ed) {
    // The frame and the bar are kept out of the pictures: no accent-blue outline rows inside the result.
    const blueRows = await ed.webContents.executeJavaScript(`(() => { const c = __test.S.base, d = c.getContext('2d').getImageData(0, 0, c.width, c.height).data; let n = 0;
      for (let y = 0; y < c.height; y++) { let blue = 0; for (let x = 0; x < c.width; x++) { const i = (y * c.width + x) * 4; if (Math.abs(d[i] - 31) < 12 && Math.abs(d[i + 1] - 160) < 12 && Math.abs(d[i + 2] - 255) < 12) blue++; } if (blue > c.width * 0.8) n++; } return n; })()`);
    check('…without the outline or the bar in the picture', blueRows === 0, blueRows);
    await shot(ed, '44-scrolling-capture');
    ed.destroy();
  }
  page.destroy();
  win.destroy();
}

module.exports = { run };
