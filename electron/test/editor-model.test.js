'use strict';
// Run: node test/editor-model.test.js
const M = require('../renderer/model');

let passed = 0;
function check(name, ok) { if (ok) { passed++; console.log('PASS  ' + name); } else { console.log('FAIL  ' + name); process.exitCode = 1; } }
const measure = (text, px) => String(text).length * px * 0.6;

const { CounterText: C } = M;
check('counter: 1 → 2', C.next('1') === '2');
check('counter: 1.1 → 1.2 (the last number steps)', C.next('1.1') === '1.2');
check('counter: 3.6 → 3.7', C.next('3.6') === '3.7');
check('counter: multi-dot 2.4.9 → 2.4.10', C.next('2.4.9') === '2.4.10');
check('counter: A2 → A3', C.next('A2') === 'A3');
check('counter: keeps leading zeros 007 → 008', C.next('007') === '008');
check('counter: no digits starts at 1', C.next('abc') === '1');
check('counter: step down never below 0', C.step('1', -5) === '0');
check('counter: step down 1.2 → 1.1', C.step('1.2', -1) === '1.1');

const rect = { type: 'rect', x: 10, y: 10, w: 100, h: 50, width: 4, fill: false };
check('rect outline: border hits, centre does not', M.hit(rect, 10, 30, 4, measure) && !M.hit(rect, 60, 35, 4, measure));
check('rect filled: centre hits', M.hit({ ...rect, fill: true }, 60, 35, 4, measure));
check('rect with negative size normalises', M.normBox({ x: 50, y: 50, w: -20, h: -10 }).x === 30);
const line = { type: 'line', x1: 0, y1: 0, x2: 100, y2: 0, width: 4 };
check('line hit within slack, miss far away', M.hit(line, 50, 5, 4, measure) && !M.hit(line, 50, 20, 4, measure));
const ellipse = { type: 'ellipse', x: 0, y: 0, w: 100, h: 60, width: 4, fill: false };
check('ellipse outline: edge hits, centre does not', M.hit(ellipse, 50, 0, 4, measure) && !M.hit(ellipse, 50, 30, 4, measure));
const counter = { type: 'counter', x: 100, y: 100, size: 40, label: '1.1.3' };
const g = M.counterGeometry(counter, measure);
check('long counter label stretches into a capsule', g.w > g.d && g.h === 40);
check('short counter label stays a circle', M.counterGeometry({ ...counter, label: '1' }, measure).w === 40);
check('counter hit', M.hit(counter, 100, 100, 2, measure) && !M.hit(counter, 300, 300, 2, measure));
const pen = { type: 'pen', pts: [[0, 0], [50, 50], [100, 0]], width: 6 };
check('pen hit on the stroke', M.hit(pen, 25, 25, 3, measure) && !M.hit(pen, 50, 0, 3, measure));
const moved = { type: 'arrow', x1: 0, y1: 0, x2: 10, y2: 10, width: 4 };
M.moveShape(moved, 5, 7);
check('moving an arrow moves both ends', moved.x1 === 5 && moved.y2 === 17);
const box = { type: 'rect', x: 10, y: 10, w: 100, h: 50 };
M.resizeBox(box, 'se', 200, 100);
check('dragging the se handle resizes', box.x === 10 && box.w === 190 && box.h === 90);
M.resizeBox(box, 'w', 250, 0);
check('dragging a handle past the other side flips cleanly', box.x === 200 && box.w === 50);
check('box has 8 handles, line has 2', M.handlePoints(box, measure).length === 8 && M.handlePoints(moved, measure).length === 2);
check('auto text colour: black on yellow, white on navy', M.readableOn('#ffcc00') === '#000000' && M.readableOn('#102a6b') === '#ffffff');
const txt = { type: 'text', x: 5, y: 5, text: 'ab\ncdef', size: 20, bold: false, font: 'x' };
const tb = M.boundsOf(txt, measure);
check('multi-line text bounds use the widest line and line height', tb.w === 4 * 20 * 0.6 && tb.h === 20 * 1.25 * 2);

// ---- counter pointer (rotatable, like the native app)
const c0 = { type: 'counter', x: 100, y: 100, size: 40, label: '1' };
const g0 = M.counterGeometry(c0, measure);
check('a counter points down-left by default', g0.tip.x < 100 && g0.tip.y > 100 && Math.abs(g0.angle - Math.PI * 3 / 4) < 1e-9);
const tail = M.handlePoints(c0, measure);
check('a selected counter has one handle, on its pointer', tail.length === 1 && tail[0].name === 'tail' && Math.hypot(tail[0].x - 100, tail[0].y - 100) > Math.hypot(g0.tip.x - 100, g0.tip.y - 100));
M.dragHandle(c0, 'tail', 200, 100);
const g1 = M.counterGeometry(c0, measure);
check('dragging the handle turns the pointer towards the mouse (now right)', Math.abs(c0.angle) < 1e-9 && g1.tip.x > 120 && Math.abs(g1.tip.y - 100) < 1e-9);
M.moveShape(c0, 10, 0);
check('moving a counter keeps the pointer direction', Math.abs(c0.angle) < 1e-9 && c0.x === 110);

// ---- spotlight and magnifier
const spot = { type: 'spotlight', x: 50, y: 50, w: 100, h: 60, level: 6 };
check('spotlight is a box: inside hits, 8 handles', M.hit(spot, 100, 80, 2, measure) && !M.hit(spot, 300, 300, 2, measure) && M.handlePoints(spot, measure).length === 8);
const mag = { type: 'magnifier', x: 100, y: 100, r: 20, zoom: 3 };
const mg = M.magnifierGeometry(mag);
check('magnifier bubble is r × zoom and sits to the right of the source', mg.br === 60 && mg.bx === 100 + 20 + 60 + 10 && mg.by === 100);
check('magnifier hits on the source and on the bubble, not between far away', M.hit(mag, 105, 100, 1, measure) && M.hit(mag, mg.bx, mg.by + 50, 1, measure) && !M.hit(mag, 100, 200, 1, measure));
check('the bubble handle sits at the bubble centre (as in the native app)', M.handlePoints(mag, measure).some(h => h.name === 'bubble' && h.x === mg.bx && h.y === mg.by));
M.dragHandle(mag, 'bubble', 300, 40);
check('the bubble handle moves only the bubble', mag.x === 100 && M.magnifierGeometry(mag).bx === 300 && M.magnifierGeometry(mag).by === 40);
M.dragHandle(mag, 'radius', 130, 100);
check('the radius handle resizes the source (and the bubble with it)', mag.r === 30 && M.magnifierGeometry(mag).br === 90);
M.moveShape(mag, 5, 5);
check('moving a magnifier moves source and bubble together', mag.x === 105 && M.magnifierGeometry(mag).bx === 305);
check('zoom is kept between 2× and 4×', M.magnifierGeometry({ x: 0, y: 0, r: 10, zoom: 9 }).zoom === 4 && M.magnifierGeometry({ x: 0, y: 0, r: 10 }).zoom === 2);

// ---- ruler: flat-colour runs (a 40 × 20 white card with a 10-px border of grey on a 60 × 40 picture)
const px = (x, y) => (x >= 10 && x < 50 && y >= 10 && y < 30 ? [255, 255, 255] : [200, 200, 200]);
check('ruler: width of the card under the pointer', JSON.stringify(M.flatRun(px, 60, 40, 30, 20, true)) === '[10,49]');
check('ruler: height of the card under the pointer', JSON.stringify(M.flatRun(px, 60, 40, 30, 20, false)) === '[10,29]');
check('ruler: small differences (anti-aliasing, noise) stay in the run', JSON.stringify(M.flatRun((x, y) => [100 + (x % 3) * 4, 100, 100], 50, 1, 25, 0, true)) === '[0,49]');
check('ruler: the pointer outside the picture is clamped', JSON.stringify(M.flatRun(px, 60, 40, -5, 20, true)) === '[0,9]');
const ruler = { type: 'measure', x1: 0, y1: 0, x2: 100, y2: 0 };
check('a kept measurement moves and has two end handles', (M.moveShape(ruler, 0, 5), ruler.y1 === 5 && M.handlePoints(ruler, measure).length === 2 && M.hit(ruler, 50, 8, 1, measure)));
check('hex colour', M.hexOf([31, 160, 255]) === '#1FA0FF');

console.log(`\n${process.exitCode ? 'SOME CHECKS FAILED' : 'All checks passed.'} (${passed} passed)`);
