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

console.log(`\n${process.exitCode ? 'SOME CHECKS FAILED' : 'All checks passed.'} (${passed} passed)`);
