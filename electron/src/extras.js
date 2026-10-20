'use strict';
// Pin to screen, print, before/after GIF, capture history, uploads and scrolling capture — the native app's PinWindow, print,
// GIFExport, Library, Uploader / UploadHistory and ScrollCaptureSession. Installed by main.js, which passes what these need.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFile } = require('child_process');
const { app, BrowserWindow, Menu, ipcMain, nativeImage, clipboard, ClipboardItem, shell, screen, globalShortcut } = require('electron');
const files = require('./files');
const { LibraryStore, UploadHistory } = require('./library');
const uploader = require('./uploader');
const { cropRect } = require('./capture-geom');
const { Stitcher } = require('../renderer/stitch');

function install(ctx) {
  const { t, gate, settings, secrets, openEditor, baseWindow, ROOT, smoke, saveDir, ocr, preload } = ctx;
  const LICENSE_REASON = 'Copying, saving, uploading and printing need a license';
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const win32 = process.platform === 'win32';

  // ================================================================ pin to screen (native PinWindow)
  // A borderless always-on-top picture: drag to move, scroll to resize, right-click for copy / opacity / close, Esc to close.
  const pins = new Map();       // webContents.id → { dataURL, aspect, win }
  function pinImage(dataURL, pixelScale = 1) {
    const image = nativeImage.createFromDataURL(dataURL);
    if (image.isEmpty()) return null;
    const { width, height } = image.getSize();
    const wa = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea;
    let w = width / pixelScale, h = height / pixelScale;
    const k = Math.min(1, (wa.width * 0.8) / w, (wa.height * 0.8) / h);
    w = Math.max(40, Math.round(w * k)); h = Math.max(20, Math.round(h * k));
    const win = new BrowserWindow({
      x: Math.round(wa.x + (wa.width - w) / 2), y: Math.round(wa.y + (wa.height - h) / 2), width: w, height: h, useContentSize: true,
      frame: false, thickFrame: false, resizable: true, minimizable: false, maximizable: false, fullscreenable: false, hasShadow: true,
      alwaysOnTop: true, skipTaskbar: false, show: false, title: 'Tenix-ChaeDiew — ' + t('Pinned picture'), backgroundColor: '#FFFFFF',
      webPreferences: { preload, contextIsolation: true, sandbox: true },
    });
    win.setAlwaysOnTop(true, 'floating');
    win.setAspectRatio(w / h);
    const id = win.webContents.id;
    pins.set(id, { dataURL, aspect: w / h, win });
    win.on('closed', () => pins.delete(id));
    win.once('ready-to-show', () => win.show());
    win.loadFile(path.join(ROOT, 'renderer', 'pin.html'));
    return win;
  }
  const pinOf = e => pins.get(e.sender.id);
  ipcMain.handle('pin:init', e => (pinOf(e) || {}).dataURL || '');
  ipcMain.on('pin:move', (e, dx, dy) => {
    const p = pinOf(e); if (!p) return;
    const b = p.win.getBounds(); p.win.setBounds({ ...b, x: Math.round(b.x + dx), y: Math.round(b.y + dy) });
  });
  ipcMain.on('pin:zoom', (e, factor) => {
    const p = pinOf(e); if (!p) return;
    const b = p.win.getContentBounds();
    const w = Math.max(80, Math.min(8000, b.width * factor)), h = w / p.aspect;
    p.win.setContentBounds({ x: Math.round(b.x + b.width / 2 - w / 2), y: Math.round(b.y + b.height / 2 - h / 2), width: Math.round(w), height: Math.round(h) });
  });
  ipcMain.on('pin:close', e => { const p = pinOf(e); if (p) p.win.close(); });
  function pinMenuTemplate(p) {
    return [
      { label: t('Copy'), click: () => copyPNG(nativeImage.createFromDataURL(p.dataURL).toPNG()) },
      { type: 'separator' },
      ...[100, 70, 40].map(v => ({ label: t('Opacity %d%').replace('%d', v), type: 'radio', checked: Math.round(p.win.getOpacity() * 100) === v, click: () => p.win.setOpacity(v / 100) })),
      { type: 'separator' },
      { label: t('Close'), accelerator: 'Esc', registerAccelerator: false, click: () => p.win.close() },
    ];
  }
  ipcMain.on('pin:menu', e => { const p = pinOf(e); if (p) Menu.buildFromTemplate(pinMenuTemplate(p)).popup({ window: p.win }); });

  async function copyPNG(png) {
    await clipboard.write([new ClipboardItem({ 'image/png': new Blob([png], { type: 'image/png' }) })]);
  }

  // ================================================================ print
  /** The picture alone on the page, as large as fits, landscape when it is wider than tall. `toPDF` is used by the smoke run. */
  async function printImage(dataURL, { toPDF = null } = {}) {
    const image = nativeImage.createFromDataURL(dataURL);
    if (image.isEmpty()) return { error: 'empty' };
    const { width, height } = image.getSize();
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tenix-print-'));
    fs.writeFileSync(path.join(dir, 'picture.png'), image.toPNG());
    fs.writeFileSync(path.join(dir, 'print.html'), `<!doctype html><meta charset="utf-8"><title>Tenix-ChaeDiew</title>
<style>@page { margin: 10mm } html, body { margin: 0; height: 100% } body { display: flex; align-items: center; justify-content: center }
img { max-width: 100%; max-height: 100%; object-fit: contain }</style><img src="picture.png" alt="">`);
    const win = new BrowserWindow({ show: false, webPreferences: { sandbox: true, contextIsolation: true } });
    try {
      await win.loadFile(path.join(dir, 'print.html'));
      const landscape = width > height;
      if (toPDF) {
        const pdf = await win.webContents.printToPDF({ landscape, printBackground: false, pageSize: 'A4' });
        fs.writeFileSync(toPDF, pdf);
        return { ok: true, path: toPDF, landscape };
      }
      // The system print dialog (printer, copies, pages) — it blocks only this hidden window.
      const result = await new Promise(resolve => win.webContents.print({ landscape, printBackground: false }, (success, reason) => resolve({ success, reason })));
      return result.success ? { ok: true } : { canceled: result.reason === 'cancelled', error: result.reason === 'cancelled' ? undefined : result.reason };
    } finally {
      if (!win.isDestroyed()) win.destroy();
      fs.rm(dir, { recursive: true, force: true }, () => {});
    }
  }

  // ================================================================ before / after GIF (native GIFExport)
  /** Copies a file (not its contents) to the clipboard, so pasting into Teams, LINE or Explorer attaches it. */
  function copyFileToClipboard(file) {
    if (!win32) return Promise.resolve(false);
    return new Promise(resolve => {
      execFile((process.env.SystemRoot || 'C:\\Windows') + '\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
        ['-NoProfile', '-NonInteractive', '-Command', `Set-Clipboard -LiteralPath '${file.replace(/'/g, "''")}'`],
        { windowsHide: true, timeout: 15000 }, err => resolve(!err));
    });
  }
  async function saveGif(bytes) {
    const dir = saveDir();
    const name = files.defaultName().replace('Tenix-ChaeDiew', 'Tenix-ChaeDiew before-after');
    let file = path.join(dir, `${files.sanitizeName(name)}.gif`);
    for (let i = 2; fs.existsSync(file) && i < 1000; i++) file = path.join(dir, `${files.sanitizeName(name)} ${i}.gif`);
    try {
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(file, Buffer.from(bytes));
    } catch (error) { return { error: 'write', message: error.message }; }
    const copied = await copyFileToClipboard(file);
    return { ok: true, path: file, copied };
  }

  // ================================================================ capture history (native Library: on, kept 30 days, searchable)
  const library = new LibraryStore(path.join(app.getPath('userData'), 'library'), {
    makeThumb: png => {
      const img = nativeImage.createFromBuffer(png), s = img.getSize(), k = Math.min(1, 360 / s.width, 240 / s.height);
      return img.resize({ width: Math.max(1, Math.round(s.width * k)), height: Math.max(1, Math.round(s.height * k)), quality: 'good' }).toPNG();
    },
  });
  const indexQueue = [];
  let indexing = false;
  async function indexNext() {
    if (indexing || !indexQueue.length) return;
    indexing = true;
    const item = indexQueue.shift();
    try {
      const res = await ocr.recognize(fs.readFileSync(library.file(item)));
      library.setOCRText(item.id, res.text);
      broadcast('library:changed');
    } catch { /* not searchable by text; still listed */ }
    indexing = false;
    indexNext();
  }
  /** Keeps a new capture in the history (unless turned off) and reads its text in the background for search. */
  function remember(image, pixelScale) {
    if (!settings.get('libraryEnabled', true)) return null;
    try {
      const { width, height } = image.getSize();
      const item = library.add(image.toPNG(), { width, height, pixelScale });
      indexQueue.push(item);
      setTimeout(indexNext, 1500);        // after the editor's own first OCR, if any
      broadcast('library:changed');
      return item;
    } catch { return null; }
  }
  const broadcast = channel => { for (const w of BrowserWindow.getAllWindows()) if (!w.isDestroyed()) w.webContents.send(channel); };

  let libraryWindow = null;
  function showLibrary() {
    if (libraryWindow && !libraryWindow.isDestroyed()) { libraryWindow.show(); libraryWindow.focus(); return libraryWindow; }
    const win = baseWindow({ width: 900, height: 640, minWidth: 560, minHeight: 400, title: 'Tenix-ChaeDiew — ' + t('History') });
    libraryWindow = win;
    win.loadFile(path.join(ROOT, 'renderer', 'library.html'));
    win.on('closed', () => { if (libraryWindow === win) libraryWindow = null; });
    return win;
  }
  ipcMain.handle('library:list', (e, query) => library.search(query).slice(0, 300).map(i => {
    let thumb = '';
    try { thumb = 'data:image/png;base64,' + fs.readFileSync(library.thumb(i)).toString('base64'); } catch { /* missing file */ }
    return { id: i.id, date: i.date, width: i.width, height: i.height, ocrText: i.ocrText.slice(0, 300), thumb };
  }));
  ipcMain.handle('library:open', (e, id) => {
    const i = library.get(id); if (!i) return false;
    const image = nativeImage.createFromPath(library.file(i));
    if (image.isEmpty()) return false;
    openEditor(image, i.pixelScale || 1); return true;
  });
  ipcMain.handle('library:copy', async (e, id) => {
    const i = library.get(id); if (!i) return { error: 'missing' };
    if (!gate(LICENSE_REASON)) return { error: 'license' };
    await copyPNG(fs.readFileSync(library.file(i))); return { ok: true };
  });
  ipcMain.handle('library:reveal', (e, id) => { const i = library.get(id); if (i) shell.showItemInFolder(library.file(i)); return !!i; });
  ipcMain.handle('library:remove', (e, id) => { const ok = library.remove(id); broadcast('library:changed'); return ok; });
  ipcMain.handle('library:clear', () => { library.removeAll(); broadcast('library:changed'); return true; });
  ipcMain.handle('library:open-window', () => { showLibrary(); });

  // ================================================================ uploads (native Uploader + UploadHistory)
  const uploads = new UploadHistory(path.join(app.getPath('userData'), 'uploads.json'));
  const uploadConfig = () => ({
    mode: settings.get('uploadMode', 'none'),
    s3: {
      endpoint: settings.get('s3Endpoint', ''), region: settings.get('s3Region', 'us-east-1'), bucket: settings.get('s3Bucket', ''),
      prefix: settings.get('s3Prefix', ''), accessKey: settings.get('s3AccessKey', ''), secretKey: secrets.get('s3-secret') || '',
      publicBase: settings.get('s3PublicBase', ''), expirySeconds: settings.get('s3ExpirySeconds', 3600),
    },
    http: { url: settings.get('httpURL', ''), token: secrets.get('http-token') || '' },
  });
  async function uploadImage(dataURL, { name } = {}) {
    const cfg = uploadConfig();
    if (cfg.mode !== 's3' && cfg.mode !== 'http') return { error: 'notConfigured', message: t('Upload is not set up yet. Choose S3 or HTTP in Settings ▸ Upload.') };
    const png = nativeImage.createFromDataURL(dataURL).toPNG();
    const fileName = (name || files.defaultName()) + '.png';
    try {
      const url = cfg.mode === 's3'
        ? await uploader.uploadS3(png, { fileName, contentType: 'image/png', cfg: cfg.s3 })
        : await uploader.uploadHTTP(png, { fileName, contentType: 'image/png', url: cfg.http.url, token: cfg.http.token });
      uploads.add(url, fileName);
      await clipboard.writeText(url);
      broadcast('uploads:changed');
      return { ok: true, url };
    } catch (error) {
      return { error: error.code || 'upload', message: error.code === 'notConfigured' ? t('Upload settings are incomplete: ') + error.message : error.message };
    }
  }
  let uploadsWindow = null;
  function showUploads() {
    if (uploadsWindow && !uploadsWindow.isDestroyed()) { uploadsWindow.show(); uploadsWindow.focus(); return uploadsWindow; }
    const win = baseWindow({ width: 640, height: 520, minWidth: 420, minHeight: 300, title: 'Tenix-ChaeDiew — ' + t('Uploaded links') });
    uploadsWindow = win;
    win.loadFile(path.join(ROOT, 'renderer', 'uploads.html'));
    win.on('closed', () => { if (uploadsWindow === win) uploadsWindow = null; });
    return win;
  }
  ipcMain.handle('uploads:list', () => uploads.load());
  ipcMain.handle('uploads:copy', async (e, id) => { const r = uploads.load().find(x => x.id === id); if (r) await clipboard.writeText(r.url); return !!r; });
  ipcMain.handle('uploads:open', (e, id) => { const r = uploads.load().find(x => x.id === id); if (r && /^https?:\/\//.test(r.url)) shell.openExternal(r.url); return !!r; });
  ipcMain.handle('uploads:remove', (e, id) => { uploads.remove(id); broadcast('uploads:changed'); return true; });
  ipcMain.handle('uploads:clear', () => { uploads.removeAll(); broadcast('uploads:changed'); return true; });
  ipcMain.handle('uploads:open-window', () => { showUploads(); });
  // Settings ▸ Upload: plain values in settings.json, the secret and the token encrypted (DPAPI / Keychain via safeStorage).
  function uploadSettings() {
    const c = uploadConfig();
    return { mode: c.mode, s3: { ...c.s3, secretKey: undefined, hasSecret: !!c.s3.secretKey }, http: { url: c.http.url, hasToken: !!c.http.token } };
  }
  function applyUpload(patch) {
    if (!patch) return uploadSettings();
    if ('mode' in patch) settings.set('uploadMode', ['s3', 'http'].includes(patch.mode) ? patch.mode : 'none');
    const map = { endpoint: 's3Endpoint', region: 's3Region', bucket: 's3Bucket', prefix: 's3Prefix', accessKey: 's3AccessKey', publicBase: 's3PublicBase', expirySeconds: 's3ExpirySeconds' };
    for (const [k, key] of Object.entries(map)) if (patch.s3 && k in patch.s3) settings.set(key, k === 'expirySeconds' ? Math.max(60, Math.min(604800, Number(patch.s3[k]) || 3600)) : String(patch.s3[k]).trim());
    if (patch.s3 && typeof patch.s3.secretKey === 'string') secrets.set('s3-secret', patch.s3.secretKey);
    if (patch.http && 'url' in patch.http) settings.set('httpURL', String(patch.http.url).trim());
    if (patch.http && typeof patch.http.token === 'string') secrets.set('http-token', patch.http.token);
    return uploadSettings();
  }
  ipcMain.handle('upload:settings', (e, patch) => applyUpload(patch));
  ipcMain.handle('upload:test', async () => {
    // A 1 × 1 picture through the real settings, so the user knows the setup works before relying on it.
    const dot = nativeImage.createFromBuffer(Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==', 'base64'));
    return uploadImage(dot.toDataURL(), { name: 'Tenix-ChaeDiew upload test' });
  });

  // ================================================================ editor actions
  ipcMain.handle('image:pin', (e, dataURL, pixelScale) => {
    if (!gate(LICENSE_REASON)) return { error: 'license' };
    return pinImage(dataURL, pixelScale) ? { ok: true } : { error: 'empty' };
  });
  ipcMain.handle('image:print', (e, dataURL) => {
    if (!gate(LICENSE_REASON)) return { error: 'license' };
    return printImage(dataURL);
  });
  ipcMain.handle('image:gif', (e, bytes) => {
    if (!gate(LICENSE_REASON)) return { error: 'license' };
    return saveGif(bytes);
  });
  ipcMain.handle('image:upload', (e, dataURL) => {
    if (!gate(LICENSE_REASON)) return { error: 'license' };
    return uploadImage(dataURL);
  });

  // ================================================================ scrolling capture (native ScrollCaptureSession, manual scrolling)
  // Choose an area, then scroll it yourself (wheel, keys or scroll bar): frames are taken a few times a second and joined where they
  // overlap. A frame around the area and a small bar with Done / Cancel stay out of the pictures (content protection).
  let session = null;
  function hudHtml() { return path.join(ROOT, 'renderer', 'scroll-hud.html'); }
  async function scrollSession(display, rect, shotSize, { interval = 280, grab = ctx.grabDisplay } = {}) {
    if (session) return null;
    const sf = display.scaleFactor || 1, b = display.bounds;
    const crop = cropRect(rect, shotSize);
    const area = { x: b.x + crop.x / sf, y: b.y + crop.y / sf, width: crop.width / sf, height: crop.height / sf };
    const stitcher = new Stitcher(settings.get('scrollMaxHeight', 30000));
    const common = { frame: false, resizable: false, movable: false, minimizable: false, maximizable: false, fullscreenable: false, skipTaskbar: true, alwaysOnTop: true, show: false, hasShadow: false };
    // The outline: click-through, so the content underneath can be scrolled.
    const border = new BrowserWindow({ ...common, transparent: true, focusable: false, x: Math.round(area.x - 3), y: Math.round(area.y - 3), width: Math.round(area.width + 6), height: Math.round(area.height + 6), webPreferences: { sandbox: true } });
    border.setIgnoreMouseEvents(true);
    border.setContentProtection(true);
    border.setAlwaysOnTop(true, 'screen-saver');
    border.loadURL('data:text/html,' + encodeURIComponent('<style>html,body{margin:0;height:100%;background:transparent}div{position:fixed;inset:0;border:3px solid #1FA0FF;border-radius:4px}</style><div></div>'));
    border.once('ready-to-show', () => border.showInactive());
    // The bar: below the area, or above it when there is no room.
    const hw = 460, hh = 52, wa = display.workArea;
    const below = area.y + area.height + 10 + hh <= wa.y + wa.height;
    const hud = new BrowserWindow({ ...common, x: Math.round(Math.min(Math.max(area.x + area.width / 2 - hw / 2, wa.x + 8), wa.x + wa.width - hw - 8)), y: Math.round(below ? area.y + area.height + 10 : Math.max(wa.y + 8, area.y - hh - 10)), width: hw, height: hh, backgroundColor: '#15171C', webPreferences: { preload, contextIsolation: true, sandbox: true } });
    hud.setContentProtection(true);
    hud.setAlwaysOnTop(true, 'screen-saver');
    hud.loadFile(hudHtml());
    hud.once('ready-to-show', () => hud.showInactive());
    let resolveDone;
    const done = new Promise(r => { resolveDone = r; });
    session = { hud, border, stitcher, finish: keep => resolveDone(keep), state: { frames: 0, height: 0, note: '' } };
    let escape = false;
    try { escape = globalShortcut.register('Escape', () => session && session.finish(false)); } catch { escape = false; }
    hud.on('closed', () => session && session.finish(false));
    let running = true;
    const loop = (async () => {
      while (running) {
        try {
          const shot = await grab(display);
          if (!running) break;
          const part = shot.crop(crop), size = part.getSize();
          const res = stitcher.add({ data: part.toBitmap(), width: size.width, height: size.height });
          session.state = { frames: session.state.frames + 1, height: stitcher.totalHeight, note: res };
          if (!hud.isDestroyed()) hud.webContents.send('scroll:progress', { height: Math.round(stitcher.totalHeight / sf), result: res });
          if (res === 'limitReached') { session.finish(true); break; }
        } catch { /* a missed frame: try again */ }
        await sleep(interval);
      }
    })();
    const keep = await done;
    running = false;
    await loop;
    if (escape) globalShortcut.unregister('Escape');
    for (const w of [hud, border]) if (!w.isDestroyed()) w.destroy();
    session = null;
    if (!keep) return null;
    const joined = stitcher.finish();
    if (!joined) return null;
    const image = nativeImage.createFromBitmap(Buffer.from(joined.data.buffer, joined.data.byteOffset, joined.data.byteLength), { width: joined.width, height: joined.height, scaleFactor: 1 });
    remember(image, sf);
    return openEditor(image, sf, display);
  }
  ipcMain.on('scroll:done', () => session && session.finish(true));
  ipcMain.on('scroll:cancel', () => session && session.finish(false));
  const scrolling = () => !!session;

  return { pinImage, printImage, saveGif, remember, library, uploads, uploadImage, applyUpload, showLibrary, showUploads, scrollSession, scrolling, pins, finishScroll: keep => session && session.finish(keep), copyFileToClipboard };
}

module.exports = { install };
