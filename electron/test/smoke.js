'use strict';
// Automated end-to-end run inside real Electron windows:  npx electron . --smoke <output-dir>
// Drives the editor with real pointer events, checks results, and writes screenshots for review. Never touches the real profile.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { BrowserWindow, nativeImage } = require('electron');

const outDir = process.argv[process.argv.indexOf('--smoke') + 1] && !process.argv[process.argv.indexOf('--smoke') + 1].startsWith('-')
  ? process.argv[process.argv.indexOf('--smoke') + 1] : fs.mkdtempSync(path.join(os.tmpdir(), 'tenix-smoke-'));
fs.mkdirSync(outDir, { recursive: true });

let failures = 0, passes = 0;
function check(name, ok, detail) {
  if (ok) { passes++; console.log('PASS  ' + name); } else { failures++; console.log('FAIL  ' + name + (detail ? '  —  ' + detail : '')); }
}
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function shot(win, name) {
  await sleep(250);
  const img = await win.webContents.capturePage();
  fs.writeFileSync(path.join(outDir, name + '.png'), img.toPNG());
}

async function mockImage() {
  const win = new BrowserWindow({ show: false, width: 1200, height: 700, webPreferences: { offscreen: false } });
  await win.loadURL('about:blank');
  const dataURL = await win.webContents.executeJavaScript(`(() => {
    const c = document.createElement('canvas'); c.width = 1100; c.height = 640; const x = c.getContext('2d');
    x.fillStyle = '#EEF1F6'; x.fillRect(0, 0, c.width, c.height);
    x.fillStyle = '#1E293B'; x.fillRect(0, 0, c.width, 84);
    x.fillStyle = '#fff'; x.textBaseline = 'top'; x.font = 'bold 34px Arial'; x.fillText('Dashboard Overview', 36, 22);
    const g = x.createLinearGradient(0, 120, 0, 250); g.addColorStop(0, '#DCE7FF'); g.addColorStop(1, '#B9CCF5');
    x.fillStyle = g; x.fillRect(36, 110, 1028, 150);
    x.fillStyle = '#B3261E'; x.font = 'bold 44px Georgia'; x.fillText('Total revenue 482,150', 70, 150);
    x.fillStyle = '#1B5E20'; x.font = '28px Menlo'; x.fillText('Server status: online', 70, 215);
    x.fillStyle = '#222'; x.font = '30px Arial'; x.fillText('Customer name: John Smith', 70, 300);
    x.fillStyle = '#16365C'; x.font = '34px Thonburi, Tahoma'; x.fillText('รายงานสรุปยอดขายประจำเดือน', 70, 370);
    x.fillStyle = '#fff'; x.fillRect(36, 450, 1028, 150); x.strokeStyle = '#C9D1DE'; x.strokeRect(36.5, 450.5, 1027, 149);
    x.fillStyle = '#444'; x.font = '24px Arial'; x.fillText('Card number 4111 1111 1111 1111', 70, 490); x.fillText('Email: person@example.com', 70, 540);
    return c.toDataURL('image/png');
  })()`);
  win.destroy();
  return nativeImage.createFromDataURL(dataURL);
}

async function run(h) {
  const { openEditor, showLicense, showHome, license, licenseStatus } = h;
  console.log('Screenshots go to ' + outDir);

  // ------------------------------------------------ editor
  const image = await mockImage();
  const win = openEditor(image, 1);
  win.setSize(1320, 860);
  const ev = code => win.webContents.executeJavaScript(code, true);
  for (let i = 0; i < 100; i++) { if (await ev('!!window.__test').catch(() => false)) break; await sleep(100); }
  check('editor loads with its test hooks', await ev('!!window.__test'));
  await shot(win, '01-editor-empty');

  await ev(`__test.setTool('rect'); __test.drag(60, 120, 420, 270);`);
  let shapes = await ev('JSON.parse(JSON.stringify(__test.shapes()))');
  check('dragging with the rectangle tool draws a rectangle', shapes.length === 1 && shapes[0].type === 'rect' && shapes[0].w > 300);
  await ev(`__test.applyStyle({ color: '#1FA0FF' }, 'color')`);
  shapes = await ev('JSON.parse(JSON.stringify(__test.shapes()))');
  check('changing colour applies at once to the selected mark (no need to click away)', shapes[0].color === '#1FA0FF');
  await ev(`__test.applyStyle({ width: 9 }, 'width'); __test.applyStyle({ fill: true }, 'fill')`);
  shapes = await ev('JSON.parse(JSON.stringify(__test.shapes()))');
  check('width and tint apply live too', shapes[0].width === 9 && shapes[0].fill === true);

  await ev(`__test.setTool('arrow'); __test.drag(600, 380, 800, 300);`);
  await ev(`__test.setTool('line'); __test.drag(600, 420, 860, 420);`);
  await ev(`__test.setTool('pen'); __test.drag(100, 330, 300, 345);`);
  await ev(`__test.setTool('highlight'); __test.drag(66, 360, 520, 410);`);
  shapes = await ev('JSON.parse(JSON.stringify(__test.shapes()))');
  check('arrow, line, pen and highlight are drawn', ['arrow', 'line', 'pen', 'highlight'].every(t => shapes.some(s => s.type === t)));

  // counters: sequence, double-click edit, 1.1 → 1.2, moving an old one
  await ev(`__test.setTool('counter'); __test.click(700, 150); __test.click(760, 150); __test.click(820, 150);`);
  shapes = await ev('JSON.parse(JSON.stringify(__test.shapes()))');
  let counters = shapes.filter(s => s.type === 'counter');
  check('counters number 1, 2, 3', counters.map(c => c.label).join() === '1,2,3', counters.map(c => c.label).join());
  await ev(`__test.click(820, 150, 2)`);
  check('double-clicking a counter opens its number for editing', await ev('!!__test.S.editing && __test.S.editing.kind === "counter"'));
  await ev(`__test.type('1.1'); __test.commitEdit();`);
  await ev(`__test.click(900, 150)`);
  shapes = await ev('JSON.parse(JSON.stringify(__test.shapes()))');
  counters = shapes.filter(s => s.type === 'counter');
  check('a counter can be set to 1.1 and the next one continues as 1.2', counters.map(c => c.label).join() === '1,2,1.1,1.2', counters.map(c => c.label).join());
  await ev(`__test.type; __test.click(900, 150, 2); __test.type('3.6.2'); __test.commitEdit();`);
  shapes = await ev('JSON.parse(JSON.stringify(__test.shapes()))');
  check('several dots are fine (3.6.2)', shapes.filter(s => s.type === 'counter').some(c => c.label === '3.6.2'));
  const before = shapes.find(s => s.type === 'counter' && s.label === '1');
  await ev(`__test.drag(700, 150, 700, 215)`);
  shapes = await ev('JSON.parse(JSON.stringify(__test.shapes()))');
  const after = shapes.find(s => s.id === before.id);
  check('an old counter can be dragged to a new place (and no new one is created)', after.y > before.y + 50 && shapes.filter(s => s.type === 'counter').length === 4);
  await ev(`__test.applyStyle({ textColor: '#FFE600' }, 'textColor'); __test.applyStyle({ color: '#6D28D9' }, 'color')`);
  shapes = await ev('JSON.parse(JSON.stringify(__test.shapes()))');
  const moved = shapes.find(s => s.id === before.id);
  check('counter number colour changes', moved.textColor === '#FFE600' && moved.color === '#6D28D9');

  // text
  await ev(`__test.setTool('text'); __test.click(560, 560);`);
  check('the text tool opens a text box', await ev('!!__test.S.editing && __test.S.editing.kind === "text"'));
  await ev(`__test.type('Note: ตรวจสอบอีกครั้ง');`);
  await ev(`__test.applyStyle({ color: '#E11D48' }, 'color')`);
  await ev(`__test.commitEdit();`);
  shapes = await ev('JSON.parse(JSON.stringify(__test.shapes()))');
  const text = shapes.find(s => s.type === 'text');
  check('typed text stays and its colour changed while typing', text && text.text.startsWith('Note') && text.color === '#E11D48');
  await ev(`__test.applyStyle({ bg: '#FFE600' }, 'bg'); __test.applyStyle({ color: '#15171C' }, 'color'); __test.applyStyle({ bold: true }, 'bold'); __test.applyStyle({ textSize: 40 }, 'size')`);
  shapes = await ev('JSON.parse(JSON.stringify(__test.shapes()))');
  const text2 = shapes.find(s => s.type === 'text');
  check('text background, colour, weight and size apply live', text2.bg === '#FFE600' && text2.color === '#15171C' && text2.size === 40);

  await ev(`__test.setTool('blur'); __test.drag(66, 520, 560, 560);`);
  await ev(`__test.drawNow()`);
  await shot(win, '02-editor-marks');
  check('the style strip follows the selection', (await ev('__test.strip()')).length > 0);

  await ev(`__test.setTool('select'); __test.undo(); __test.undo();`);
  shapes = await ev('JSON.parse(JSON.stringify(__test.shapes()))');
  const countAfterUndo = shapes.length;
  await ev(`__test.redo(); __test.redo();`);
  shapes = await ev('JSON.parse(JSON.stringify(__test.shapes()))');
  check('undo and redo step through changes', shapes.length > countAfterUndo);

  // ------------------------------------------------ edit text in the picture (OCR + font match)
  await ev(`__test.setTool('select'); for (const s of __test.shapes().slice()) { __test.select(s.id); } `);
  // start from a clean picture
  while ((await ev('__test.S.undo.length')) > 0) await ev('__test.undo()');
  await ev(`__test.setTool('editText')`);
  console.log('      (reading the picture with OCR — the first run loads the language data)');
  const lines = await ev(`__test.ensureOcr().then(l => l.map(x => ({ t: x.text, b: x.bbox })))`);
  console.log('      OCR lines: ' + lines.map(l => JSON.stringify(l.t)).join(' | '));
  check('OCR finds the lines of text in the picture', lines.length >= 4);
  await shot(win, '03-edit-text-lines');
  const target = lines.find(l => /Total/i.test(l.t)) || lines[0];
  const cx = (target.b.x0 + target.b.x1) / 2, cy = (target.b.y0 + target.b.y1) / 2;
  await ev(`__test.click(${cx}, ${cy})`);
  await sleep(300);
  shapes = await ev('JSON.parse(JSON.stringify(__test.shapes()))');
  const retyped = shapes.find(s => s.type === 'text');
  check('clicking a line of text creates an editable text mark', !!retyped && retyped.text.length > 3);
  if (retyped) {
    console.log(`      matched: font=${retyped.font} bold=${retyped.bold} size=${retyped.size} colour=${retyped.color} at (${Math.round(retyped.x)}, ${Math.round(retyped.y)}) — original line at (${target.b.x0}, ${target.b.y0})`);
    check('the match picks Georgia bold at about the original size and a red ink', /Georgia/.test(retyped.font) && retyped.bold && retyped.size > 36 && retyped.size < 52 && retyped.color.toLowerCase().startsWith('#b'), retyped.font);
    check('and puts it where the original was', Math.abs(retyped.x - target.b.x0) < 8 && Math.abs(retyped.y - target.b.y0) < 14);
  }
  await ev(`__test.type('Total revenue 999,999'); __test.commitEdit(); __test.drawNow();`);
  await shot(win, '04-edit-text-retyped');
  await ev(`__test.setTool('select'); __test.drag(${cx}, ${cy}, ${cx + 60}, ${cy + 70});`);
  shapes = await ev('JSON.parse(JSON.stringify(__test.shapes()))');
  const movedText = shapes.find(s => s.type === 'text');
  check('the retyped text can be moved', movedText && movedText.y > retyped.y + 40);
  await shot(win, '05-edit-text-moved');

  // ------------------------------------------------ backdrop
  await ev(`__test.toggleBackdropPanel(); __test.drawNow();`);
  await sleep(300);
  await shot(win, '06-backdrop-panel');
  const size = await ev('__test.exportSize()');
  check('with a backdrop the export grows by the padding on every side', size[0] === 1100 + 128 && size[1] === 640 + 128, size.join('×'));
  const exportURL = await ev('__test.exportDataURL()');
  const exported = nativeImage.createFromDataURL(exportURL);
  check('the export is a real PNG of the composite size', exported.getSize().width === size[0]);
  fs.writeFileSync(path.join(outDir, '07-export.png'), exported.toPNG());

  // ------------------------------------------------ OCR button
  await ev(`__test.runOcr()`);
  for (let i = 0; i < 60 && !(await ev(`!!document.querySelector('#modal textarea')`)); i++) await sleep(200);
  const ocrText = await ev('__test.openModalText()');
  check('Read text (OCR) lists the recognised text', /Dashboard|revenue|Server/i.test(ocrText), ocrText.slice(0, 60));
  await shot(win, '08-ocr-result');

  // ------------------------------------------------ licensing
  const stage = s => licenseStatus().state === s;
  check('a fresh profile starts a 14-day trial', stage('trial') && licenseStatus().daysLeft === 14);
  const copyRes = await ev(`window.tenix.gate()`);
  check('during the trial copying is allowed', copyRes && copyRes.ok === true);
  win.show(); win.focus(); await sleep(400);   // the Clipboard API only works in the focused window
  await ev(`document.querySelector('[aria-label="Copy picture"], [aria-label="คัดลอกภาพ"]').click()`);
  await sleep(700);
  const clipWidth = await ev(`navigator.clipboard.read().then(async items => { const blob = await items[0].getType('image/png'); return (await createImageBitmap(blob)).width; }).catch(e => 'ERR ' + e.message)`);
  check('Copy puts the picture on the clipboard', clipWidth === 1100 + 128, String(clipWidth));
  showLicense();
  await sleep(900);
  const licWin = BrowserWindow.getAllWindows().find(w => /License|ไลเซนส์/.test(w.getTitle()));
  if (licWin) await shot(licWin, '09-license-trial');
  const csv = path.join(os.homedir(), 'Library/Application Support/Tenix-ChaeDiew-Keygen/issued/Tenix-licenses-50.csv');
  if (fs.existsSync(csv)) {
    const key = fs.readFileSync(csv, 'utf8').trim().split('\n')[1].split(',')[5];
    license.activate(key);
    check('a genuine key is Licensed at once (no activation code)', stage('licensed'));
    if (licWin && !licWin.isDestroyed()) { licWin.webContents.send('license:changed'); await sleep(600); await shot(licWin, '10-license-licensed'); }
    license.now = () => new Date(Date.now() + 60 * 86400000);
    check('it keeps working after the trial would have ended', licenseStatus().allowsUse && (await ev(`window.tenix.gate()`)).ok === true);
    license.remove();
    check('after removing the key the trial has ended, so copying is refused', !licenseStatus().allowsUse && (await ev(`window.tenix.gate()`)).error === 'license');
    await sleep(600);
    license.now = () => new Date();
  }

  // Thai interface
  h.settings.set('lang', 'th');
  for (const w of BrowserWindow.getAllWindows()) w.webContents.reload();
  await sleep(2500);
  await ev(`__test && 0`).catch(() => {});
  if (!win.isDestroyed()) {
    for (let i = 0; i < 50 && !(await ev('!!window.__test').catch(() => false)); i++) await sleep(100);
    await ev(`__test.setTool('counter'); __test.click(300, 300); __test.click(360, 300);`).catch(() => {});
    await shot(win, '13-editor-thai');
    await ev(`__test.setTool('text')`).catch(() => {});
    await shot(win, '14-editor-thai-text');
  }
  showLicense();
  await sleep(900);
  const licTh = BrowserWindow.getAllWindows().find(w => /ไลเซนส์/.test(w.getTitle()));
  if (licTh) await shot(licTh, '15-license-thai');
  h.settings.set('lang', 'en');

  showHome();
  await sleep(800);
  const home = BrowserWindow.getAllWindows().find(w => /Tenix-ChaeDiew$/.test(w.getTitle()) && w.getSize()[0] < 600);
  if (home) await shot(home, '12-home');

  // ------------------------------------------------ screen capture (permission-dependent; nothing is saved)
  try {
    const display = h.screen.getPrimaryDisplay();
    const grabbed = await h.grabDisplay(display);
    check('screen capture returns an image of the display size', grabbed.getSize().width >= display.size.width);
  } catch (error) { console.log('      (screen capture not available here: ' + error.message + ')'); }

  // Closing windows must not raise errors (a destroyed webContents was once read in the 'closed' handler).
  const errors = [];
  process.on('uncaughtException', e => errors.push(String(e && e.message || e)));
  for (const w of BrowserWindow.getAllWindows()) if (!w.isDestroyed()) w.close();
  await sleep(1200);
  check('closing the editor and other windows raises no error', errors.length === 0, errors.join(' | '));

  console.log(`\n${failures ? 'SOME CHECKS FAILED' : 'All smoke checks passed.'} (${passes} passed, ${failures} failed)`);
  process.exitCode = failures ? 1 : 0;
}

module.exports = { run };
