'use strict';
// Tenix-ChaeDiew (Electron) — main process: capture, windows, menus, clipboard/save/OCR services and license enforcement.
// Powered by Panupong Nijjaboon.
const path = require('path');
const fs = require('fs');
const {
  app, BrowserWindow, Tray, Menu, globalShortcut, ipcMain, desktopCapturer, screen, clipboard, nativeImage, dialog, shell, systemPreferences,
} = require('electron');

const store = require('./store');
const ocr = require('./ocr');
const { LicenseManager } = require('./license');
const { rawMachineId } = require('./machine-id');
const PUBLIC_KEY = require('./public-key');
const { th } = require('./strings');

const INK = '#15171C', TEXT = '#F5F7FA';
const ROOT = path.join(__dirname, '..');
const smoke = process.argv.includes('--smoke');
app.setName('Tenix-ChaeDiew');
// The automated smoke run uses a throw-away profile so it never touches the real trial / license data.
if (smoke) app.setPath('userData', path.join(require('os').tmpdir(), `tenix-chaediew-smoke-${process.pid}`));

let settings, license, tray = null, homeWindow = null, licenseWindow = null;
const editors = new Map();        // webContents.id → { dataURL, pixelScale }
const captureJobs = new Map();    // webContents.id → { shot (dataURL), resolve }

// ---------------------------------------------------------------- language
const lang = () => settings.get('lang', app.getLocale().toLowerCase().startsWith('th') ? 'th' : 'en');
const t = key => (lang() === 'th' && th[key]) || key;

// ---------------------------------------------------------------- license
function licenseStatus() {
  const s = license.status();
  const info = s.info && { licensee: s.info.licensee, seats: s.info.seats, issued: s.info.issued.toISOString(), expires: s.info.expires ? s.info.expires.toISOString() : null, keyID: s.info.keyID };
  return { state: s.state, daysLeft: s.daysLeft, trialDaysLeft: s.trialDaysLeft, error: s.error, info, allowsUse: s.allowsUse, machineCode: license.machineCode, hasKey: !!license.storedKey };
}
function broadcastLicense() { for (const w of BrowserWindow.getAllWindows()) w.webContents.send('license:changed'); }
/** Copy, save, upload and print need a license (or the trial). Opens the license window when they are not allowed. */
function gate(reason) {
  if (license.allowsUse) return true;
  showLicense(reason);
  return false;
}

// ---------------------------------------------------------------- windows
function baseWindow(options) {
  const win = new BrowserWindow({
    backgroundColor: INK, show: false, autoHideMenuBar: true,
    webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: true, nodeIntegration: false },
    ...options,
  });
  win.once('ready-to-show', () => win.show());
  win.webContents.setWindowOpenHandler(({ url }) => { if (/^https?:/.test(url)) shell.openExternal(url); return { action: 'deny' }; });
  win.webContents.on('will-navigate', e => e.preventDefault());
  return win;
}

function showHome() {
  if (homeWindow && !homeWindow.isDestroyed()) { homeWindow.show(); homeWindow.focus(); return homeWindow; }
  homeWindow = baseWindow({ width: 440, height: 600, resizable: false, maximizable: false, fullscreenable: false, title: 'Tenix-ChaeDiew' });
  homeWindow.loadFile(path.join(ROOT, 'renderer', 'home.html'));
  homeWindow.on('closed', () => { homeWindow = null; });
  return homeWindow;
}

function showLicense(reason) {
  if (licenseWindow && !licenseWindow.isDestroyed()) licenseWindow.close();
  licenseWindow = baseWindow({ width: 540, height: 640, resizable: false, maximizable: false, minimizable: false, fullscreenable: false, title: 'Tenix-ChaeDiew — ' + t('License') });
  licenseWindow.loadFile(path.join(ROOT, 'renderer', 'license.html'), reason ? { query: { reason } } : undefined);
  licenseWindow.on('closed', () => { licenseWindow = null; });
  return licenseWindow;
}

function openEditor(image, pixelScale = 1) {
  const area = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea;
  const width = Math.min(1380, area.width - 60), height = Math.min(900, area.height - 60);
  const win = baseWindow({
    width, height, minWidth: 960, minHeight: 560, title: 'Tenix-ChaeDiew',
    ...(process.platform === 'darwin'
      ? { titleBarStyle: 'hiddenInset', trafficLightPosition: { x: 16, y: 16 } }
      : { titleBarStyle: 'hidden', titleBarOverlay: { color: INK, symbolColor: TEXT, height: 48 } }),
  });
  const id = win.webContents.id;      // read now: webContents is already destroyed when 'closed' fires
  editors.set(id, { dataURL: image.toDataURL(), pixelScale });
  win.on('closed', () => editors.delete(id));
  win.loadFile(path.join(ROOT, 'renderer', 'editor.html'));
  return win;
}

// ---------------------------------------------------------------- capture
async function grabDisplay(display) {
  const sf = display.scaleFactor || 1;
  const sources = await desktopCapturer.getSources({
    types: ['screen'], thumbnailSize: { width: Math.round(display.size.width * sf), height: Math.round(display.size.height * sf) },
  });
  const source = sources.find(s => s.display_id === String(display.id)) || sources[0];
  if (!source || source.thumbnail.isEmpty()) throw new Error('empty-capture');
  return source.thumbnail;
}

async function ensureScreenPermission() {
  if (process.platform !== 'darwin') return true;
  const status = systemPreferences.getMediaAccessStatus('screen');
  if (status === 'granted') return true;
  const { response } = await dialog.showMessageBox({
    type: 'info', buttons: [t('Open System Settings'), t('Cancel')], defaultId: 0, cancelId: 1,
    message: t('Allow Tenix-ChaeDiew to record the screen'),
    detail: t('Turn on Tenix-ChaeDiew under Privacy & Security ▸ Screen Recording, then quit and reopen the app.'),
  });
  if (response === 0) shell.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture');
  return false;
}

async function capture(mode) {
  try {
    if (!(await ensureScreenPermission())) return;
    const display = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
    const shot = await grabDisplay(display);
    const sf = display.scaleFactor || 1;
    if (mode === 'full') { openEditor(shot, sf); return; }
    const rect = await chooseArea(display, shot);
    if (!rect) return;
    const k = shot.getSize().width / rect.vw;      // image pixels per overlay CSS pixel
    const crop = shot.crop({ x: Math.round(rect.x * k), y: Math.round(rect.y * k), width: Math.max(1, Math.round(rect.w * k)), height: Math.max(1, Math.round(rect.h * k)) });
    openEditor(crop, sf);
  } catch (error) {
    dialog.showErrorBox('Tenix-ChaeDiew', t('Could not capture the screen: ') + error.message);
  }
}

function chooseArea(display, shot) {
  return new Promise(resolve => {
    const b = display.bounds;
    const win = new BrowserWindow({
      x: b.x, y: b.y, width: b.width, height: b.height, frame: false, resizable: false, movable: false, hasShadow: false, show: false,
      alwaysOnTop: true, skipTaskbar: true, fullscreenable: false, enableLargerThanScreen: true, backgroundColor: '#000000',
      webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: true },
    });
    win.setAlwaysOnTop(true, 'screen-saver');
    const id = win.webContents.id;      // read now: webContents is already destroyed when 'closed' fires
    let finished = false;
    const finish = rect => { if (finished) return; finished = true; captureJobs.delete(id); if (!win.isDestroyed()) win.close(); resolve(rect); };
    captureJobs.set(id, { shot: shot.toDataURL(), finish });
    win.on('closed', () => finish(null));
    win.once('ready-to-show', () => { win.show(); win.focus(); });
    win.loadFile(path.join(ROOT, 'renderer', 'capture.html'));
  });
}

async function openFileDialog() {
  const { filePaths } = await dialog.showOpenDialog({ title: t('Open a picture…'), properties: ['openFile'], filters: [{ name: 'Images', extensions: ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'] }] });
  if (!filePaths || !filePaths[0]) return;
  const image = nativeImage.createFromPath(filePaths[0]);
  if (image.isEmpty()) { dialog.showErrorBox('Tenix-ChaeDiew', t('Could not open that picture.')); return; }
  openEditor(image, 1);
}

// ---------------------------------------------------------------- IPC
function registerIpc() {
  ipcMain.on('app:boot', e => { e.returnValue = { lang: lang(), strings: th, platform: process.platform, testMode: smoke }; });
  ipcMain.handle('editor:init', e => editors.get(e.sender.id) || { dataURL: '', pixelScale: 1 });

  // The picture itself is put on the clipboard by the editor page (web Clipboard API); the main process only decides whether it may.
  ipcMain.handle('license:gate', (e, reason) => (gate(reason || 'Copying, saving, uploading and printing need a license') ? { ok: true } : { error: 'license' }));
  ipcMain.handle('image:save', async (e, dataURL) => {
    if (!gate('Copying, saving, uploading and printing need a license')) return { error: 'license' };
    const win = BrowserWindow.fromWebContents(e.sender);
    const now = new Date(), p = n => String(n).padStart(2, '0');
    const name = `Tenix-ChaeDiew ${now.getFullYear()}-${p(now.getMonth() + 1)}-${p(now.getDate())} at ${p(now.getHours())}.${p(now.getMinutes())}.${p(now.getSeconds())}.png`;
    const { canceled, filePath } = await dialog.showSaveDialog(win, {
      title: t('Save as…'), defaultPath: path.join(app.getPath('pictures'), name),
      filters: [{ name: 'PNG', extensions: ['png'] }, { name: 'JPEG', extensions: ['jpg', 'jpeg'] }],
    });
    if (canceled || !filePath) return { canceled: true };
    const image = nativeImage.createFromDataURL(dataURL);
    fs.writeFileSync(filePath, /\.jpe?g$/i.test(filePath) ? image.toJPEG(92) : image.toPNG());
    return { ok: true, path: filePath };
  });
  ipcMain.handle('text:copy', (e, text) => { clipboard.writeText(String(text)); return true; });
  ipcMain.handle('ocr:run', async (e, dataURL) => {
    try { return await ocr.recognize(nativeImage.createFromDataURL(dataURL).toPNG()); }
    catch (error) { return { error: String(error && error.message || error) }; }
  });

  ipcMain.handle('license:open', () => { showLicense(); });
  ipcMain.handle('license:status', () => licenseStatus());
  ipcMain.handle('license:activate', (e, text) => {
    try {
      const info = license.activate(text);
      broadcastLicense();
      return { ok: true, info: { licensee: info.licensee }, activated: licenseStatus().state === 'licensed' };
    } catch (error) { return { ok: false, code: error.code || 'malformed' }; }
  });
  ipcMain.handle('license:remove', () => { license.remove(); broadcastLicense(); return true; });

  ipcMain.handle('capture:start', (e, mode) => { setTimeout(() => capture(mode), 150); return true; });
  ipcMain.handle('file:open', () => openFileDialog());
  ipcMain.handle('app:set-language', (e, value) => {
    settings.set('lang', value === 'en' ? 'en' : 'th');
    buildMenus();
    for (const w of BrowserWindow.getAllWindows()) w.webContents.reload();
    return true;
  });

  ipcMain.handle('capture:shot', e => (captureJobs.get(e.sender.id) || {}).shot || '');
  ipcMain.on('capture:done', (e, rect) => { const job = captureJobs.get(e.sender.id); if (job) job.finish(rect); });
}

// ---------------------------------------------------------------- menus, tray, shortcuts
function buildMenus() {
  const mac = process.platform === 'darwin';
  const items = [
    { label: t('Capture an area'), accelerator: 'CommandOrControl+Shift+2', click: () => capture('area') },
    { label: t('Capture the whole screen'), accelerator: 'CommandOrControl+Shift+1', click: () => capture('full') },
    { label: t('Open a picture…'), accelerator: 'CommandOrControl+O', click: openFileDialog },
  ];
  const template = [
    ...(mac ? [{ label: 'Tenix-ChaeDiew', submenu: [
      { label: t('About Tenix-ChaeDiew'), click: showHome }, { label: t('License…'), click: () => showLicense() }, { type: 'separator' },
      { role: 'hide' }, { role: 'hideOthers' }, { role: 'unhide' }, { type: 'separator' }, { role: 'quit' }] }] : []),
    { label: t('File'), submenu: [...items, { type: 'separator' }, mac ? { role: 'close' } : { role: 'quit' }] },
    { label: t('Edit'), submenu: [{ role: 'undo' }, { role: 'redo' }, { type: 'separator' }, { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }] },
    { label: t('Window'), submenu: [{ role: 'minimize' }, { role: 'zoom' }, ...(mac ? [{ type: 'separator' }, { role: 'front' }] : [])] },
    { label: t('Help'), submenu: [{ label: t('License…'), click: () => showLicense() }, { label: t('About Tenix-ChaeDiew'), click: showHome }] },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
  if (tray) {
    tray.setContextMenu(Menu.buildFromTemplate([
      ...items.map(i => ({ ...i, accelerator: undefined })),
      { type: 'separator' },
      { label: t('Open Tenix-ChaeDiew'), click: showHome },
      { label: t('License…'), click: () => showLicense() },
      { type: 'separator' },
      { label: t('Quit'), click: () => app.quit() },
    ]));
  }
}

function createTray() {
  const icon = nativeImage.createFromPath(path.join(ROOT, 'assets', 'mark-on-light.png')).resize({ width: 18, height: 18 });
  if (process.platform === 'darwin') icon.setTemplateImage(true);
  tray = new Tray(icon);
  tray.setToolTip('Tenix-ChaeDiew');
  tray.on('click', () => { if (process.platform !== 'darwin') showHome(); });
}

function registerShortcuts() {
  for (const [accel, mode] of [['CommandOrControl+Shift+2', 'area'], ['CommandOrControl+Shift+1', 'full']]) {
    try { globalShortcut.register(accel, () => capture(mode)); } catch { /* taken by another app */ }
  }
}

// ---------------------------------------------------------------- lifecycle
if (!app.requestSingleInstanceLock() && !smoke) app.quit();
app.on('second-instance', () => showHome());
app.on('window-all-closed', () => { /* stay in the tray / menu bar */ });
app.on('activate', () => { if (!BrowserWindow.getAllWindows().length) showHome(); });
app.on('will-quit', () => { globalShortcut.unregisterAll(); ocr.shutdown(); });

app.whenReady().then(async () => {
  settings = store.settings();
  license = new LicenseManager({ secrets: store.secrets(), publicKey: PUBLIC_KEY, machineId: rawMachineId });
  if (process.platform === 'darwin' && app.dock) app.dock.setIcon(nativeImage.createFromPath(path.join(ROOT, 'assets', 'icon.png')));
  registerIpc();
  createTray();
  buildMenus();
  registerShortcuts();
  if (smoke) {
    try { await require('../test/smoke').run({ openEditor, showLicense, showHome, license, licenseStatus, capture, grabDisplay, screen, nativeImage, settings }); }
    catch (error) { console.error('SMOKE ERROR', error); process.exitCode = 1; }
    app.exit(process.exitCode || 0);
    return;
  }
  showHome();
});

module.exports = { openEditor };
