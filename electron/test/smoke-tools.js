'use strict';
// Smoke checks for the editor tools ported from the native macOS app, driven with real pointer events on the canvas and checked on the
// exported pixels: counters (pointer that turns, numbering), spotlight, magnifier, ruler, colour picker and Hide PII.
// Each counter check names the native behaviour it mirrors (Sources/ChaeDiewKit/CanvasView.swift, Annotation.swift).
const { clipboard } = require('electron');

async function run(h, { check, shot, sleep, win: makeWin }) {
  const win = await makeWin();
  const ev = code => win.webContents.executeJavaScript(code, true);
  const shapes = () => ev('JSON.parse(JSON.stringify(__test.shapes()))');
  const near = (a, b, tol) => Math.abs(a - b) <= tol;
  const sameRGB = (a, b, tol = 24) => a.every((v, i) => Math.abs(v - b[i]) <= tol);
  const RED = [255, 59, 48];      // #FF3B30, the default colour

  // ------------------------------------------------ counter: pointer (native Annotation.counterTail / handles() / moving(.tail))
  await ev(`__test.setTool('counter'); __test.click(250, 560)`);
  let s = await shapes();
  const c1 = s[s.length - 1];
  let g = await ev(`__test.counterGeometry(${c1.id})`);
  check('a new counter points down-left, like the native default (3π/4)', Math.abs(g.angle - Math.PI * 3 / 4) < 1e-9 && g.tip.x < 250 && g.tip.y > 560, g.angle);
  // A point inside the pointer, between the body's outline and the tip.
  const tipPoint = gg => { const ox = 250 + gg.w / 2 * Math.cos(gg.angle) * 0.92, oy = 560 + gg.h / 2 * Math.sin(gg.angle) * 0.92; return [(ox + gg.tip.x) / 2, (oy + gg.tip.y) / 2]; };
  let [tx, ty] = tipPoint(g);
  check('the pointer is drawn in the counter colour in the saved picture', sameRGB(await ev(`__test.exportPixel(${tx}, ${ty})`), RED), await ev(`__test.exportPixel(${tx}, ${ty})`));
  const handles = await ev('__test.handles()');
  check('a selected counter has one round handle, just beyond the pointer tip', handles.length === 1 && handles[0].name === 'tail' && handles[0].round && near(handles[0].x, g.handle.x, 0.01));
  await shot(win, '30-counter-default-pointer');

  // Turn it with a real drag on the handle, while the counter tool is still active: the handle wins over placing a new counter (native).
  const before = (await shapes()).filter(x => x.type === 'counter').length;
  await ev(`__test.drag(${g.handle.x}, ${g.handle.y}, 400, 560)`);
  s = await shapes();
  const turned = s.find(x => x.id === c1.id);
  check('dragging the round handle turns the pointer towards the mouse (now right, 0°)', near(turned.angle, 0, 0.02), turned.angle);
  check('…and does not place another counter', s.filter(x => x.type === 'counter').length === before);
  g = await ev(`__test.counterGeometry(${c1.id})`);
  [tx, ty] = tipPoint(g);
  const oldTip = tipPoint({ ...g, angle: Math.PI * 3 / 4, tip: { x: 250 + (g.w / 2 + g.d * 0.3) * Math.cos(Math.PI * 3 / 4), y: 560 + (g.d / 2 + g.d * 0.3) * Math.sin(Math.PI * 3 / 4) } });
  check('the saved picture shows the pointer on the right…', sameRGB(await ev(`__test.exportPixel(${tx}, ${ty})`), RED));
  check('…and no longer down-left', !sameRGB(await ev(`__test.exportPixel(${oldTip[0]}, ${oldTip[1]})`), RED));
  await ev(`__test.drag(${g.handle.x}, ${g.handle.y}, 250, 420)`);
  check('it turns all the way round (now up, −90°)', near((await shapes()).find(x => x.id === c1.id).angle, -Math.PI / 2, 0.02));
  await shot(win, '31-counter-pointer-turned');
  await ev('__test.undo()');
  check('undo puts the pointer back', near((await shapes()).find(x => x.id === c1.id).angle, 0, 0.02));
  await ev(`__test.drag(250, 560, 300, 600)`);
  const moved = (await shapes()).find(x => x.id === c1.id);
  check('moving the counter keeps where its pointer points', moved.x === 300 && near(moved.angle, 0, 0.02));
  await ev(`__test.click(600, 600)`);
  s = await shapes();
  check('the next counter starts pointing down-left again (native: new counters use the default angle)', s[s.length - 1].angle == null);

  // ------------------------------------------------ counter numbering (native nextCounterText / serial / counterOverride)
  await ev(`__test.undo(); __test.undo()`);       // back to the one counter from above, labelled 1
  await ev(`__test.click(500, 300); __test.click(560, 300)`);
  s = (await shapes()).filter(x => x.type === 'counter');
  check('counters number 1, 2, 3', s.map(x => x.label).join() === '1,2,3', s.map(x => x.label));
  const first = s[0];
  await ev(`__test.click(${first.x}, ${first.y}, 2)`);
  await ev(`__test.type('A1'); __test.commitEdit()`);
  await ev(`__test.click(620, 300)`);
  s = (await shapes()).filter(x => x.type === 'counter');
  check('after editing an older counter to A1 the next one is A2 (native: the edited counter is the latest)', s[s.length - 1].label === 'A2', s.map(x => x.label));
  const two = s.find(x => x.label === '2');
  await ev(`__test.drag(${two.x}, ${two.y}, ${two.x}, ${two.y + 40})`);
  s = await shapes();
  check('taking a mark brings it to the front (native)', s[s.length - 1].label === '2');
  await ev(`__test.click(680, 300)`);
  s = (await shapes()).filter(x => x.type === 'counter');
  check('…and numbering still follows the latest placed, not the list order (A3)', s[s.length - 1].label === 'A3', s.map(x => x.label));
  await ev(`__test.select(null); document.getElementById('counter-value').value = 'B7'; document.getElementById('counter-value').dispatchEvent(new Event('change'))`);
  await ev(`__test.click(740, 300); __test.click(800, 300)`);
  s = (await shapes()).filter(x => x.type === 'counter');
  check('with nothing selected, the number box sets what the next counter says (B7, then B8)', s.slice(-2).map(x => x.label).join() === 'B7,B8', s.map(x => x.label));
  const n = (await shapes()).length, b8 = s[s.length - 1];
  await ev(`__test.setTool('select'); __test.drag(${b8.x}, ${b8.y}, ${b8.x}, ${b8.y + 60}, { altKey: true })`);
  s = await shapes();
  check('Alt-drag takes a copy and leaves the original (native ⌥-drag)', s.length === n + 1 && s.some(x => x.id === b8.id && x.y === b8.y));
  await shot(win, '32-counters-numbering');


  // ------------------------------------------------ every mark can be moved with its own tool still active; Enter starts a new one
  await ev(`while (__test.S.undo.length) __test.undo(); __test.setTool('arrow'); __test.drag(600, 400, 800, 360)`);
  let all = await shapes();
  const arrow = all[all.length - 1];
  await ev(`__test.drag(700, 380, 700, 480)`);
  all = await shapes();
  check('arrow tool: pressing the arrow moves it (no second arrow)', all.length === 1 && Math.abs(all[0].y1 - arrow.y1 - 100) < 1.5, all.length);
  await ev(`__test.setTool('ellipse'); __test.drag(100, 200, 300, 300); __test.drag(200, 200, 260, 260)`);
  all = await shapes();
  const ell = all.find(x => x.type === 'ellipse');
  check('ellipse tool: pressing the ellipse edge area moves it instead of drawing a new one', all.filter(x => x.type === 'ellipse').length === 1);
  await ev(`__test.setTool('magnifier'); __test.drag(500, 150, 520, 150)`);
  const m0 = (await shapes()).find(x => x.type === 'magnifier');
  await ev(`__test.drag(505, 150, 560, 190)`);
  const m1 = (await shapes()).find(x => x.type === 'magnifier');
  check('magnifier tool: pressing it moves it', (await shapes()).filter(x => x.type === 'magnifier').length === 1 && m1.x > m0.x + 40);
  await ev(`__test.key({ key: 'Enter', code: 'Enter' })`);
  check('Enter finishes the mark (nothing selected)', (await ev('__test.S.sel')) === null);
  const nBefore = (await shapes()).length;
  await ev(`__test.setTool('arrow'); __test.drag(900, 500, 1000, 560)`);
  check('…and the next drag makes a new arrow', (await shapes()).length === nBefore + 1);
  const ar2 = (await shapes()).find(x => x.type === 'arrow' && x.x1 === 900);
  await ev(`__test.drag(950, 530, 950, 580)`);
  check('pressing the old arrow edits the old one again', (await shapes()).length === nBefore + 1 && (await shapes()).find(x => x.id === ar2.id).y1 > ar2.y1 + 40);
  await ev(`__test.drag(120, 380, 240, 400, { ctrlKey: true })`);
  check('Ctrl-drag draws a new arrow even over other marks', (await shapes()).length === nBefore + 2);

  // ------------------------------------------------ spotlight (native drawSpotlight: everything outside darkens by level/10)
  await ev(`while (__test.S.undo.length) __test.undo(); __test.setTool('spotlight')`);
  const base = await ev('__test.exportPixel(900, 160)'), inside0 = await ev('__test.exportPixel(200, 170)');
  await ev(`__test.drag(60, 120, 700, 270)`);
  const outside = await ev('__test.exportPixel(900, 160)'), inside = await ev('__test.exportPixel(200, 170)');
  check('spotlight: outside darkens 60 % by default (level 6)', outside.every((v, i) => near(v, base[i] * 0.4, 4)), { base, outside });
  check('spotlight: inside stays as it was', sameRGB(inside, inside0, 3));
  await ev(`__test.key({ key: '3', code: 'Digit3' })`);
  const lighter = await ev('__test.exportPixel(900, 160)');
  check('spotlight: key 3 sets 30 % darkness', lighter.every((v, i) => near(v, base[i] * 0.7, 4)), lighter);
  await shot(win, '33-spotlight');

  // ------------------------------------------------ magnifier (native: bubble = source × zoom, to the right)
  await ev(`__test.setTool('magnifier'); __test.drag(150, 160, 170, 160)`);
  s = await shapes();
  const mag = s[s.length - 1];
  check('magnifier: dragging out from a centre makes a source circle and a bubble 2× its size', mag.type === 'magnifier' && near(mag.r, 20, 0.5));
  const mg = await ev(`window.Model.magnifierGeometry(__test.shapes().find(x => x.id === ${mag.id}))`);
  const srcPx = await ev(`__test.pixelAt(150, 160).rgb`), bubblePx = await ev(`__test.exportPixel(${mg.bx}, ${mg.by})`);
  check('magnifier: the bubble centre shows the source centre', sameRGB(srcPx, bubblePx, 30), { srcPx, bubblePx });
  await ev(`__test.select(${mag.id}); __test.drag(${mg.bx}, ${mg.by}, ${mg.bx + 80}, ${mg.by + 200})`);
  const moved2 = await ev(`window.Model.magnifierGeometry(__test.shapes().find(x => x.id === ${mag.id}))`);
  check('magnifier: the bubble handle (its centre, as native) moves the bubble only', near(moved2.bx, mg.bx + 80, 0.5) && near(moved2.by, mg.by + 200, 0.5) && (await shapes()).find(x => x.id === mag.id).x === mag.x);
  await shot(win, '34-magnifier');

  // ------------------------------------------------ ruler (native PixelProbe.run, tolerance 12; hold 1 / 2)
  await ev(`while (__test.S.undo.length) __test.undo(); __test.setTool('measure'); __test.hover(500, 530)`);
  let marks = await ev('__test.probeMarks()');
  // The mock picture's white card is x 36…1063, y 450…599 (1-px border at 36.5 / 450.5 drawn in #C9D1DE).
  const hm = marks.find(m => m.y1 === m.y2), vm = marks.find(m => m.x1 === m.x2);
  check('ruler: the white card under the pointer measures itself across and down', hm && vm && near(hm.x2 - hm.x1, 1026, 3) && near(vm.y2 - vm.y1, 148, 3), marks);
  await ev(`__test.key({ key: 'ๅ', code: 'Digit1' })`);
  marks = await ev('__test.probeMarks()');
  check('ruler: holding 1 measures the height only (Thai layout too)', marks.length === 1 && marks[0].x1 === marks[0].x2);
  await ev(`window.dispatchEvent(new KeyboardEvent('keyup', { key: 'ๅ', code: 'Digit1' }))`);
  check('…and letting go measures both again', (await ev('__test.probeMarks()')).length === 2);
  await shot(win, '35-ruler-live');
  await ev(`__test.click(500, 530)`);
  s = await shapes();
  check('ruler: a click keeps both measurements on the picture, one undo step', s.filter(x => x.type === 'measure').length === 2 && (await ev('__test.S.undo.length')) === 1);
  const kh = s.find(x => x.type === 'measure' && x.y1 === x.y2), kv = s.find(x => x.type === 'measure' && x.x1 === x.x2);
  const labelX = kh && kh.x1 + (kh.x2 - kh.x1) * (kh.labelT == null ? 0.5 : kh.labelT);
  check('ruler: the width label sits clear of the height line (labels do not overlap)', kh && kv && Math.abs(labelX - kv.x1) > 120, { labelX, line: kv && kv.x1 });
  await ev(`__test.drag(100, 620, 400, 620)`);
  s = await shapes();
  const line = s[s.length - 1];
  check('ruler: a drag keeps a measured line', line.type === 'measure' && near(line.x2 - line.x1, 300, 1));
  check('the kept measurement is in the saved picture', !sameRGB(await ev('__test.exportPixel(250, 620)'), await ev('__test.pixelAt(250, 620).rgb'), 10));
  await shot(win, '36-ruler-kept');

  // ------------------------------------------------ colour picker
  await ev(`__test.setTool('eyedropper'); __test.click(900, 40)`);     // the header's plain background, right of its title
  await sleep(200);
  const hex = await clipboard.readText();
  check('colour picker: a click copies the colour under the pointer (#1E293B header)', hex === '#1E293B', hex);
  check('…and it becomes the colour for new marks', (await ev('__test.S.style.color')) === '#1E293B');


  // ------------------------------------------------ edit text: a word, or a dragged frame — never the whole row by default
  await ev(`while (__test.S.undo.length) __test.undo(); __test.setTool('editText')`);
  const lines = await ev(`__test.ensureOcr().then(l => l.map(x => ({ t: x.text, b: x.bbox, w: x.words.map(w => ({ t: w.text, b: w.bbox })) })))`);
  const cust = lines.find(l => /Customer/.test(l.t));
  const word = cust.w.find(w => /John/.test(w.t));
  await ev(`__test.click(${(word.b.x0 + word.b.x1) / 2}, ${(word.b.y0 + word.b.y1) / 2})`);
  await sleep(250);
  tx =(await shapes()).filter(x => x.type === 'text');
  check('edit text: a click takes just that word', tx.length === 1 && /^John$/.test(tx[0].text.trim()), tx.map(x => x.text));
  await ev('__test.commitEdit()');
  const smith = cust.w.find(w => /Smith/.test(w.t));
  await ev(`__test.drag(${smith.b.x0 - 3}, ${smith.b.y0 - 3}, ${smith.b.x1 + 3}, ${smith.b.y1 + 3})`);
  await sleep(250);
  tx = (await shapes()).filter(x => x.type === 'text');
  check('edit text: dragging a frame takes the words inside it', tx.length === 2 && /^Smith$/.test(tx[1].text.trim()), tx.map(x => x.text));
  await ev('__test.commitEdit()');
  const rest = await ev(`__test.S.ocr.lines.map(l => l.words.map(w => w.text).join(' '))`);
  check('the rest of the line stays selectable (Customer name:)', rest.some(r => /Customer/.test(r)) && !rest.some(r => /John|Smith/.test(r)), rest);

  // ------------------------------------------------ Hide PII (native Redactor; one undo step)
  await ev(`while (__test.S.undo.length) __test.undo(); __test.setTool('select')`);
  const undoBefore = await ev('__test.S.undo.length');
  const hidden = await ev('__test.hidePII()');
  s = await shapes();
  const blurs = s.filter(x => x.type === 'blur');
  const covers = (x, y) => blurs.some(b => x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h);
  check('Hide PII pixelates the card number and the email in the picture', hidden === 2 && blurs.length === 2, { hidden, blurs });
  check('…over the data only: the labels "Card number" and "Email:" stay readable', covers(330, 502) && covers(300, 552) && !covers(90, 502) && !covers(90, 552), blurs);
  check('…as one undo step', (await ev('__test.S.undo.length')) === undoBefore + 1);
  await shot(win, '37-hide-pii');
  win.destroy();
}

module.exports = { run };
