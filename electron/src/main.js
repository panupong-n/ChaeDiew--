'use strict';
// Tenix-ChaeDiew (Electron) — main process: capture, windows, menus, clipboard/save/OCR services and license enforcement.
// Powered by Panupong Nijjaboon.
const path = require('path');
const fs = require('fs');
const os = require('os');
const {
  app, BrowserWindow, Tray, Menu, globalShortcut, ipcMain, desktopCapturer, screen, clipboard, ClipboardItem, nativeImage, nativeTheme, dialog, shell, systemPreferences,
} = require('electron');

const store = require('./store');
const ocr = require('./ocr');
const { LicenseManager } = require('./license');
const { rawMachineId } = require('./machine-id');
const PUBLIC_KEY = require('./public-key');
const { th } = require('./strings');
const hotkeys = require('./hotkeys');
const files = require('./files');
const { cropRect, editorBounds } = require('./capture-geom');
const { taskbarUsesLightTheme, trayIconFile } = require('./tray-icon');

const INK = '#15171C', TEXT = '#F5F7FA';
const ROOT = path.join(__dirname, '..');
const smoke = process.argv.includes('--smoke');
const startHidden = process.argv.includes('--hidden');      // started at login: stay in the tray
const win32 = process.platform === 'win32', mac = process.platform === 'darwin';
app.setName('Tenix-ChaeDiew');
if (win32) app.setAppUserModelId('com.tenix.chaediew.electron');   // same id as the installer's shortcuts: one taskbar group, named notifications
// The automated smoke run uses a throw-away profile so it never touches the real trial / license data.
if (smoke) app.setPath('userData', path.join(os.tmpdir(), `tenix-chaediew-smoke-${process.pid}`));

let settings, license, extras, tray = null, homeWindow = null, licenseWindow = null, settingsWindow = null;
const editors = new Map();        // webContents.id → { dataURL, pixelScale }
const captureJobs = new Map();    // webContents.id → { shot (dataURL), finish }
let hotkeyStatus = {};            // { area: { accel, ok }, full: { accel, ok } }
let hotkeysPaused = false;

// ---------------------------------------------------------------- language
const systemLang = () => (app.getLocale().toLowerCase().startsWith('th') ? 'th' : 'en');
const lang = () => settings.get('lang', systemLang());
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
  homeWindow = baseWindow({ width: 440, height: 708, useContentSize: true, resizable: false, maximizable: false, fullscreenable: false, title: 'Tenix-ChaeDiew' });
  const win = homeWindow;
  win.loadFile(path.join(ROOT, 'renderer', 'home.html'));
  win.on('closed', () => { if (homeWindow === win) homeWindow = null; });
  return win;
}

function showLicense(reason) {
  if (licenseWindow && !licenseWindow.isDestroyed()) licenseWindow.close();
  const win = baseWindow({ width: 540, height: 640, resizable: false, maximizable: false, minimizable: false, fullscreenable: false, title: 'Tenix-ChaeDiew — ' + t('License') });
  licenseWindow = win;
  win.loadFile(path.join(ROOT, 'renderer', 'license.html'), reason ? { query: { reason } } : undefined);
  // The window being replaced closes after this one exists: only forget the reference if it is still this window.
  win.on('closed', () => { if (licenseWindow === win) licenseWindow = null; });
  return win;
}

function showSettings() {
  if (settingsWindow && !settingsWindow.isDestroyed()) { settingsWindow.show(); settingsWindow.focus(); return settingsWindow; }
  const win = baseWindow({ width: 600, height: 700, minWidth: 520, minHeight: 480, maximizable: false, fullscreenable: false, title: 'Tenix-ChaeDiew — ' + t('Settings') });
  settingsWindow = win;
  win.loadFile(path.join(ROOT, 'renderer', 'settings.html'));
  win.on('closed', () => { if (settingsWindow === win) settingsWindow = null; if (hotkeysPaused) { hotkeysPaused = false; registerShortcuts(); } });
  return win;
}

function openEditor(image, pixelScale = 1, display) {
  const d = display || screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
  const bounds = editorBounds(d.workArea);
  const win = baseWindow({
    ...bounds, minWidth: Math.min(960, bounds.width), minHeight: Math.min(560, bounds.height), title: 'Tenix-ChaeDiew',
    ...(mac
      ? { titleBarStyle: 'hiddenInset', trafficLightPosition: { x: 16, y: 16 } }
      : { titleBarStyle: 'hidden', titleBarOverlay: { color: INK, symbolColor: TEXT, height: 48 } }),
  });
  const id = win.webContents.id;      // read now: webContents is already destroyed when 'closed' fires
  editors.set(id, { dataURL: image.toDataURL(), pixelScale });
  win.on('closed', () => { editors.delete(id); trace('editor closed', id); });
  win.webContents.on('render-process-gone', (e, details) => trace('editor renderer gone', id, details));
  win.loadFile(path.join(ROOT, 'renderer', 'editor.html'));
  return win;
}

// ---------------------------------------------------------------- capture
const sleep = ms => new Promise(r => setTimeout(r, ms));

async function grabDisplay(display) {
  const sf = display.scaleFactor || 1;
  const sources = await desktopCapturer.getSources({
    types: ['screen'], thumbnailSize: { width: Math.round(display.size.width * sf), height: Math.round(display.size.height * sf) },
  });
  const source = sources.find(s => s.display_id === String(display.id)) || (sources.length === 1 ? sources[0] : null);
  if (!source || source.thumbnail.isEmpty()) throw new Error('empty-capture');
  return source.thumbnail;
}

async function ensureScreenPermission() {
  if (!mac) return true;
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

/** Our own launcher windows must not end up in the picture: hide them for the shot and return them to show again on cancel. */
function hideOwnWindows() {
  const hidden = [];
  for (const w of [homeWindow, settingsWindow, licenseWindow]) if (w && !w.isDestroyed() && w.isVisible()) { w.hide(); hidden.push(w); }
  return hidden;
}

const trace = process.env.TENIX_TRACE ? (...a) => console.log(`      [trace ${(performance.now() / 1000).toFixed(2)}s]`, ...a) : () => {};
let capturing = false;
async function capture(mode) {
  if (extras.scrolling()) { extras.finishScroll(true); return null; }     // the shortcut again ends a scrolling capture
  if (capturing) return null;
  capturing = true;
  const hidden = hideOwnWindows();
  let opened = null;
  try {
    if (!(await ensureScreenPermission())) return null;
    if (hidden.length) await sleep(win32 ? 260 : 180);    // let the compositor remove them before the shot
    const display = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
    trace('capture: grabbing');
    const shot = await grabDisplay(display);
    trace('capture: grabbed', shot.getSize());
    const sf = display.scaleFactor || 1;
    if (mode === 'full') { extras.remember(shot, sf); opened = openEditor(shot, sf, display); }
    else if (mode === 'scroll') {
      const rect = await chooseArea(display, shot, t('Drag over the part that scrolls · Esc = cancel'));
      if (rect) { capturing = false; opened = await extras.scrollSession(display, rect, shot.getSize()); }
    } else {
      const rect = await chooseArea(display, shot);
      trace('capture: area', rect);
      if (rect) { const part = shot.crop(cropRect(rect, shot.getSize())); extras.remember(part, sf); opened = openEditor(part, sf, display); }
      trace('capture: editor opened');
    }
  } catch (error) {
    dialog.showErrorBox('Tenix-ChaeDiew', t('Could not capture the screen: ') + error.message);
  } finally {
    capturing = false;
    if (!opened) for (const w of hidden) if (!w.isDestroyed()) w.show();
  }
  return opened;
}

function chooseArea(display, shot, help) {
  return new Promise(resolve => {
    const b = display.bounds;
    const win = new BrowserWindow({
      x: b.x, y: b.y, width: b.width, height: b.height, frame: false, resizable: false, movable: false, hasShadow: false, show: false,
      alwaysOnTop: true, skipTaskbar: true, fullscreenable: false, enableLargerThanScreen: true, thickFrame: false, backgroundColor: '#000000',
      webPreferences: { preload: path.join(__dirname, 'preload.js'), contextIsolation: true, sandbox: true },
    });
    // Windows shrinks a new frameless window to the work area (the taskbar stayed visible and the picture was squeezed) and can size it
    // with the wrong scale on a second monitor; setting the bounds again after creation gives exactly the display.
    win.setBounds(b);
    win.setAlwaysOnTop(true, 'screen-saver');
    const id = win.webContents.id;      // read now: webContents is already destroyed when 'closed' fires
    let finished = false, escape = false;
    const finish = rect => {
      if (finished) return;
      finished = true; captureJobs.delete(id);
      if (escape) globalShortcut.unregister('Escape');
      if (!win.isDestroyed()) win.close();
      resolve(rect);
    };
    trace('overlay: encoding shot');
    captureJobs.set(id, { shot: shot.toDataURL(), help, finish, window: win });
    trace('overlay: loading');
    win.on('closed', () => finish(null));
    win.once('ready-to-show', () => {
      trace('overlay: ready');
      win.setBounds(b); win.show(); win.focus();
      // Esc must cancel even when Windows refuses to give the overlay the keyboard focus.
      try { escape = globalShortcut.register('Escape', () => finish(null)); } catch { escape = false; }
      trace('overlay: shown, Escape registered =', escape);
    });
    win.loadFile(path.join(ROOT, 'renderer', 'capture.html'));
  });
}

async function openFileDialog() {
  const { filePaths } = await dialog.showOpenDialog({ title: t('Open a picture…'), properties: ['openFile'], filters: [{ name: t('Pictures'), extensions: ['png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'] }] });
  if (!filePaths || !filePaths[0]) return;
  openPictureFile(filePaths[0]);
}
function openPictureFile(file) {
  const image = nativeImage.createFromPath(file);
  if (image.isEmpty()) { dialog.showErrorBox('Tenix-ChaeDiew', t('Could not open that picture.')); return null; }
  return openEditor(image, 1);
}

// ---------------------------------------------------------------- saving and copying
const saveDir = () => settings.get('saveDir', app.getPath('pictures'));

/** Writes a PNG or JPEG (by extension). Never throws: a failure comes back as { error, message } for the editor to show. */
function writeImageFile(filePath, dataURL) {
  try {
    const image = nativeImage.createFromDataURL(dataURL);
    if (image.isEmpty()) throw new Error(t('The picture is empty.'));
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    fs.writeFileSync(filePath, files.formatOf(filePath) === 'jpg' ? image.toJPEG(92) : image.toPNG());
    return { ok: true, path: filePath };
  } catch (error) {
    return { error: 'write', message: error.message, path: filePath };
  }
}

async function saveImage(win, dataURL, { saveAs = false } = {}) {
  const format = settings.get('format', 'png') === 'jpg' ? 'jpg' : 'png';
  const dir = saveDir();
  let filePath;
  if (!saveAs && !settings.get('askWhere', true)) {
    filePath = files.uniquePath(dir, files.defaultName(), format, fs.existsSync);
  } else {
    const png = { name: 'PNG', extensions: ['png'] }, jpg = { name: 'JPEG', extensions: ['jpg', 'jpeg'] };
    const result = await dialog.showSaveDialog(win, {
      title: t('Save as…'), defaultPath: path.join(settings.get('lastSaveDir', dir), `${files.defaultName()}.${format}`),
      filters: format === 'jpg' ? [jpg, png] : [png, jpg],
    });
    if (result.canceled || !result.filePath) return { canceled: true };
    filePath = files.withExtension(result.filePath, format);
  }
  const res = writeImageFile(filePath, dataURL);
  if (res.ok) settings.set('lastSaveDir', path.dirname(filePath));
  return res;
}

/**
 * Electron 44's clipboard is the W3C-style async one (writeImage is gone). Writing image/png puts PNG, DIB, DIBV5 and Bitmap on the
 * Windows clipboard, so Word, Paint, Teams and LINE all paste it; it does not need the editor window to have the focus.
 */
async function copyImage(dataURL) {
  const image = nativeImage.createFromDataURL(dataURL);
  if (image.isEmpty()) return { error: 'empty' };
  try {
    await clipboard.write([new ClipboardItem({ 'image/png': new Blob([image.toPNG()], { type: 'image/png' }) })]);
    return { ok: true };
  } catch (error) { return { error: 'clipboard', message: error.message }; }
}

// ---------------------------------------------------------------- settings
function publicSettings() {
  return {
    lang: lang(), saveDir: saveDir(), format: settings.get('format', 'png'), askWhere: settings.get('askWhere', true),
    openAtLogin: settings.get('openAtLogin', false), platform: process.platform,
    // Hide PII: which built-in kinds are on (all by default, as in the native app) and the user's own regular expressions.
    pii: { enabled: settings.get('piiEnabled', null), custom: settings.get('piiCustom', []) },
    library: { enabled: settings.get('libraryEnabled', true), retentionDays: settings.get('libraryRetentionDays', 30), count: extras.library.load().length },
    upload: extras.applyUpload(null),
    hotkeys: Object.fromEntries(Object.entries(hotkeyStatus).map(([k, v]) => [k, { ...v, label: hotkeys.label(v.accel, process.platform) }])),
    presets: hotkeys.PRESETS.map(p => ({ ...p, label: `${hotkeys.label(p.area, process.platform)} / ${hotkeys.label(p.full, process.platform)}` })),
  };
}

function setLoginItem(on) {
  if (smoke) return;      // never touch the real login items from a test run
  const args = app.isPackaged ? ['--hidden'] : [app.getAppPath(), '--hidden'];
  app.setLoginItemSettings({ openAtLogin: !!on, path: process.execPath, args });
}

function setLanguage(value) {
  settings.set('lang', value === 'en' ? 'en' : 'th');
  buildMenus();
  for (const w of BrowserWindow.getAllWindows()) {
    if (editors.has(w.webContents.id)) w.webContents.send('app:lang', lang());   // editors relabel in place: reloading would lose the marks
    else if (!captureJobs.has(w.webContents.id)) w.webContents.reload();
  }
  if (licenseWindow && !licenseWindow.isDestroyed()) licenseWindow.setTitle('Tenix-ChaeDiew — ' + t('License'));
  if (settingsWindow && !settingsWindow.isDestroyed()) settingsWindow.setTitle('Tenix-ChaeDiew — ' + t('Settings'));
}

function applySettings(patch) {
  const errors = {};
  if ('format' in patch) settings.set('format', patch.format === 'jpg' ? 'jpg' : 'png');
  if ('askWhere' in patch) settings.set('askWhere', !!patch.askWhere);
  if ('saveDir' in patch && typeof patch.saveDir === 'string' && patch.saveDir) settings.set('saveDir', patch.saveDir);
  if ('piiEnabled' in patch && Array.isArray(patch.piiEnabled)) settings.set('piiEnabled', patch.piiEnabled.map(String));
  if ('piiCustom' in patch && Array.isArray(patch.piiCustom)) settings.set('piiCustom', patch.piiCustom.map(String).filter(s => s.trim()).slice(0, 50));
  if ('libraryEnabled' in patch) settings.set('libraryEnabled', !!patch.libraryEnabled);
  if ('libraryRetentionDays' in patch) {
    const days = [0, 7, 30, 90, 365].includes(Number(patch.libraryRetentionDays)) ? Number(patch.libraryRetentionDays) : 30;
    settings.set('libraryRetentionDays', days);
    extras.library.purge(days);
  }
  if ('upload' in patch) extras.applyUpload(patch.upload);
  if ('openAtLogin' in patch) { settings.set('openAtLogin', !!patch.openAtLogin); setLoginItem(patch.openAtLogin); }
  if ('hotkeys' in patch) {
    const next = { ...currentHotkeys(), ...patch.hotkeys };
    const set = Object.values(next).filter(Boolean);
    if (set.some((a, i) => set.slice(i + 1).some(b => hotkeys.same(a, b, process.platform)))) errors.hotkeys = 'duplicate';
    else { settings.set('hotkeys', next); registerShortcuts(); }
  }
  if ('lang' in patch) setLanguage(patch.lang);
  buildMenus();
  for (const w of BrowserWindow.getAllWindows()) w.webContents.send('settings:changed');
  return { ...publicSettings(), errors };
}

// ---------------------------------------------------------------- IPC
function registerIpc() {
  ipcMain.on('app:boot', e => { e.returnValue = { lang: lang(), strings: th, platform: process.platform, testMode: smoke, version: app.getVersion() }; });
  ipcMain.handle('editor:init', e => editors.get(e.sender.id) || { dataURL: '', pixelScale: 1 });

  ipcMain.handle('license:gate', (e, reason) => (gate(reason || 'Copying, saving, uploading and printing need a license') ? { ok: true } : { error: 'license' }));
  ipcMain.handle('image:copy', (e, dataURL) => {
    if (!gate('Copying, saving, uploading and printing need a license')) return { error: 'license' };
    return copyImage(dataURL);
  });
  ipcMain.handle('image:save', (e, dataURL, opts) => {
    if (!gate('Copying, saving, uploading and printing need a license')) return { error: 'license' };
    return saveImage(BrowserWindow.fromWebContents(e.sender), dataURL, opts || {});
  });
  ipcMain.handle('text:copy', async (e, text) => { await clipboard.writeText(String(text)); return true; });
  ipcMain.handle('ocr:run', async (e, dataURL) => {
    try { return await ocr.recognize(nativeImage.createFromDataURL(dataURL).toPNG()); }
    catch (error) {
      const message = String(error && error.message || error);
      return { error: message === 'timeout' ? t('Reading took too long. Try again, or with a smaller area.') : message };
    }
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

  ipcMain.handle('capture:start', (e, mode) => { setTimeout(() => capture(mode), 60); return true; });
  ipcMain.handle('file:open', () => openFileDialog());
  ipcMain.handle('app:set-language', (e, value) => { setLanguage(value); return true; });
  ipcMain.handle('app:hotkeys', () => publicSettings().hotkeys);
  ipcMain.handle('settings:open', () => { showSettings(); });
  ipcMain.handle('home:open', () => { showHome(); });
  ipcMain.handle('settings:get', () => publicSettings());
  ipcMain.handle('settings:set', (e, patch) => applySettings(patch || {}));
  ipcMain.handle('settings:choose-folder', async e => {
    const { canceled, filePaths } = await dialog.showOpenDialog(BrowserWindow.fromWebContents(e.sender), { title: t('Choose a folder'), defaultPath: saveDir(), properties: ['openDirectory', 'createDirectory'] });
    return canceled || !filePaths[0] ? applySettings({}) : applySettings({ saveDir: filePaths[0] });
  });
  ipcMain.handle('settings:open-folder', () => shell.openPath(saveDir()));
  ipcMain.handle('hotkeys:from-event', (e, ev) => { const accel = hotkeys.fromKeyEvent(ev || {}, process.platform); return accel ? { accel, label: hotkeys.label(accel, process.platform) } : null; });
  // While a shortcut is being recorded the current ones must not fire (pressing the old one would start a capture).
  ipcMain.handle('hotkeys:pause', () => { hotkeysPaused = true; unregisterCaptureShortcuts(); return true; });
  ipcMain.handle('hotkeys:resume', () => { hotkeysPaused = false; registerShortcuts(); return publicSettings().hotkeys; });

  ipcMain.handle('editor:menu', (e, spec) => { popupEditorMenu(e.sender, spec || {}); return true; });

  ipcMain.handle('capture:shot', e => (captureJobs.get(e.sender.id) || {}).shot || '');
  ipcMain.handle('capture:help', e => (captureJobs.get(e.sender.id) || {}).help || '');
  ipcMain.on('capture:done', (e, rect) => { trace('capture:done', rect); const job = captureJobs.get(e.sender.id); if (job) job.finish(rect); });
}

// ---------------------------------------------------------------- menus, tray, shortcuts
const currentHotkeys = () => ({ ...hotkeys.DEFAULTS, ...settings.get('hotkeys', {}) });

function captureItems() {
  const hk = currentHotkeys();
  return [
    { label: t('Capture an area'), accelerator: hk.area, registerAccelerator: false, click: () => capture('area') },
    { label: t('Capture the whole screen'), accelerator: hk.full, registerAccelerator: false, click: () => capture('full') },
    { label: t('Scrolling capture'), accelerator: hk.scroll || undefined, registerAccelerator: false, click: () => capture('scroll') },
    { label: t('Open a picture…'), accelerator: 'CommandOrControl+O', click: openFileDialog },
  ];
}
function listItems() {
  return [
    { label: t('History…'), click: () => extras.showLibrary() },
    { label: t('Uploaded links…'), accelerator: 'CommandOrControl+Shift+U', registerAccelerator: false, click: () => extras.showUploads() },
  ];
}

/** The editor's ⋯ menu: what the bar folded away on a narrow window, then the app commands that have no button there. */
function editorMenuTemplate(sender, spec) {
  const send = id => () => { if (!sender.isDestroyed()) sender.send('editor:command', id); };
  const fromSpec = item => (item.type === 'separator' ? { type: 'separator' } : {
    label: item.label, enabled: item.enabled !== false, accelerator: item.accelerator, registerAccelerator: false,
    ...(item.checked !== undefined ? { type: 'checkbox', checked: !!item.checked } : {}),
    ...(item.submenu ? { submenu: item.submenu.map(fromSpec) } : { click: send(item.id) }),
  });
  const own = (spec.items || []).map(fromSpec);
  return [
    ...own, ...(own.length ? [{ type: 'separator' }] : []),
    ...captureItems().map(i => ({ ...i, accelerator: i.accelerator, registerAccelerator: false })),
    { type: 'separator' },
    ...listItems(),
    { type: 'separator' },
    { label: t('Settings…'), click: showSettings },
    { label: t('License…'), click: () => showLicense() },
    { label: t('Open Tenix-ChaeDiew'), click: showHome },
  ];
}
function popupEditorMenu(sender, spec) {
  const win = BrowserWindow.fromWebContents(sender);
  if (!win) return;
  Menu.buildFromTemplate(editorMenuTemplate(sender, spec)).popup({ window: win, x: Math.round(spec.x || 0), y: Math.round(spec.y || 0) });
}

function buildMenus() {
  const items = captureItems();
  const template = [
    ...(mac ? [{ label: 'Tenix-ChaeDiew', submenu: [
      { label: t('About Tenix-ChaeDiew'), click: showHome }, { label: t('Settings…'), accelerator: 'Command+,', click: showSettings }, { label: t('License…'), click: () => showLicense() }, { type: 'separator' },
      { role: 'hide' }, { role: 'hideOthers' }, { role: 'unhide' }, { type: 'separator' }, { role: 'quit' }] }] : []),
    { label: t('File'), submenu: [...items, { type: 'separator' }, ...listItems(), { type: 'separator' }, ...(mac ? [] : [{ label: t('Settings…'), accelerator: 'Control+,', click: showSettings }, { type: 'separator' }]), mac ? { role: 'close' } : { role: 'quit', label: t('Quit') }] },
    { label: t('Edit'), submenu: [{ role: 'undo' }, { role: 'redo' }, { type: 'separator' }, { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }] },
    { label: t('Window'), submenu: [{ role: 'minimize' }, { role: 'zoom' }, ...(mac ? [{ type: 'separator' }, { role: 'front' }] : [])] },
    { label: t('Help'), submenu: [{ label: t('License…'), click: () => showLicense() }, { label: t('About Tenix-ChaeDiew'), click: showHome }] },
  ];
  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
  if (tray) {
    tray.setContextMenu(Menu.buildFromTemplate([
      ...items,
      { type: 'separator' },
      ...listItems(),
      { type: 'separator' },
      { label: t('Open Tenix-ChaeDiew'), click: showHome },
      { label: t('Settings…'), click: showSettings },
      { label: t('License…'), click: () => showLicense() },
      { type: 'separator' },
      { label: t('Quit'), click: () => app.quit() },
    ]));
    tray.setToolTip(trayTooltip());
  }
}
function trayTooltip() {
  const hk = hotkeyStatus.area;
  return hk && hk.ok ? `Tenix-ChaeDiew — ${t('Capture an area')}: ${hotkeys.label(hk.accel, process.platform)}` : 'Tenix-ChaeDiew';
}

function trayImage() {
  const file = path.join(ROOT, 'assets', trayIconFile(process.platform, taskbarUsesLightTheme()));
  const src = nativeImage.createFromPath(file);
  if (mac) { const icon = src.resize({ width: 18, height: 18 }); icon.setTemplateImage(true); return icon; }
  // One image with a bitmap per display scale, so the icon is sharp at 100 / 125 / 150 / 200 %.
  const icon = nativeImage.createEmpty();
  for (const scaleFactor of [1, 1.25, 1.5, 2]) icon.addRepresentation({ scaleFactor, buffer: src.resize({ width: Math.round(16 * scaleFactor), height: Math.round(16 * scaleFactor), quality: 'best' }).toPNG() });
  return icon;
}
function createTray() {
  tray = new Tray(trayImage());
  tray.setToolTip('Tenix-ChaeDiew');
  tray.on('click', () => { if (!mac) showHome(); });
  // Windows mode (light/dark taskbar) can change while the app runs.
  nativeTheme.on('updated', () => { if (tray && !tray.isDestroyed()) tray.setImage(trayImage()); });
}

function unregisterCaptureShortcuts() {
  for (const v of Object.values(hotkeyStatus)) if (v.ok) { try { globalShortcut.unregister(v.accel); } catch { /* not ours */ } }
}
/** (Re)registers the capture shortcuts and remembers which ones worked: another app may already own a combination. */
function registerShortcuts() {
  unregisterCaptureShortcuts();
  const hk = currentHotkeys();
  hotkeyStatus = {};
  for (const [mode, accel] of Object.entries(hk)) {
    let ok = false;
    if (accel && !hotkeysPaused) { try { ok = globalShortcut.register(accel, () => capture(mode)); } catch { ok = false; } }
    hotkeyStatus[mode] = { accel, ok };
  }
  if (tray) tray.setToolTip(trayTooltip());
  return hotkeyStatus;
}

// ---------------------------------------------------------------- lifecycle
const gotLock = smoke || app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();          // the running copy shows its window (second-instance below)
} else {
  app.on('second-instance', (event, argv) => {
    const file = argv.slice(1).find(a => /\.(png|jpe?g|gif|bmp|webp)$/i.test(a) && fs.existsSync(a));
    if (file && app.isReady()) openPictureFile(file); else showHome();
  });
  app.on('window-all-closed', () => {
    // Stay in the tray / menu bar. On Windows say so once, or closing the last window looks like quitting.
    if (win32 && tray && !smoke && !settings.get('trayHintShown', false)) {
      settings.set('trayHintShown', true);
      tray.displayBalloon({ iconType: 'info', title: 'Tenix-ChaeDiew', content: t('Tenix-ChaeDiew keeps running in the notification area. Right-click its icon for captures, settings, or Quit.') });
    }
  });
  app.on('activate', () => { if (!BrowserWindow.getAllWindows().length) showHome(); });
  app.on('will-quit', () => { globalShortcut.unregisterAll(); ocr.shutdown(); });

  app.whenReady().then(async () => {
    settings = store.settings();
    // One secret store for everything: two instances on the same file would each save their own copy and erase the other's entries.
    const secrets = store.secrets();
    license = new LicenseManager({ secrets, publicKey: PUBLIC_KEY, machineId: rawMachineId });
    extras = require('./extras').install({ t, gate, settings, secrets, openEditor, baseWindow, ROOT, smoke, saveDir, ocr, grabDisplay, preload: path.join(__dirname, 'preload.js') });
    extras.library.purge(settings.get('libraryRetentionDays', 30));
    if (mac && app.dock) app.dock.setIcon(nativeImage.createFromPath(path.join(ROOT, 'assets', 'icon.png')));
    registerIpc();
    createTray();
    registerShortcuts();
    buildMenus();
    if (smoke) {
      try {
        await require('../test/smoke').run({
          openEditor, showLicense, showHome, showSettings, license, licenseStatus, capture, grabDisplay, screen, nativeImage, settings,
          applySettings, publicSettings, registerShortcuts, setLanguage, saveImage, writeImageFile, editorMenuTemplate, captureJobs,
          windows: () => ({ homeWindow, settingsWindow, licenseWindow }), tray: () => tray, ocr, extras, secrets, chooseArea,
        });
      } catch (error) { console.error('SMOKE ERROR', error); process.exitCode = 1; }
      app.exit(process.exitCode || 0);
      return;
    }
    const file = process.argv.slice(1).find(a => /\.(png|jpe?g|gif|bmp|webp)$/i.test(a) && fs.existsSync(a));
    if (file) openPictureFile(file);
    else if (!startHidden) showHome();
  });
}

module.exports = { openEditor };
