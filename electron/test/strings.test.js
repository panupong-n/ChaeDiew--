'use strict';
// Run: node test/strings.test.js
// Every user-visible string goes through t('…') and has a Thai entry in src/strings.js; the dictionary has no duplicate keys
// (a JavaScript object literal keeps the last duplicate silently, so a second translation would quietly win).
const fs = require('fs');
const path = require('path');
const { th } = require('../src/strings');

let passed = 0;
function check(name, ok, detail) {
  if (ok) { passed++; console.log('PASS  ' + name); } else { console.log('FAIL  ' + name + (detail ? '  —  ' + detail : '')); process.exitCode = 1; }
}
const root = path.join(__dirname, '..');
const read = f => fs.readFileSync(path.join(root, f), 'utf8');

// ---- duplicate keys in the source of the dictionary
const src = read('src/strings.js');
const keys = [];
for (const m of src.matchAll(/^\s*(['"])((?:\\.|(?!\1).)*)\1\s*:/gm)) keys.push(m[2].replace(/\\(.)/g, '$1'));
const dupes = keys.filter((k, i) => keys.indexOf(k) !== i);
check('the Thai dictionary has no duplicate keys', dupes.length === 0, dupes.join(' | '));
check('every source key made it into the dictionary', keys.length === Object.keys(th).length, `${keys.length} vs ${Object.keys(th).length}`);

// ---- every literal passed to t(…) and every data-t / data-t-title attribute has a translation
const files = [
  ...fs.readdirSync(path.join(root, 'renderer')).filter(f => /\.(js|html)$/.test(f)).map(f => 'renderer/' + f),
  ...fs.readdirSync(path.join(root, 'src')).filter(f => /\.js$/.test(f)).map(f => 'src/' + f),
];
const used = new Map();
const add = (key, file) => { if (!used.has(key)) used.set(key, file); };
for (const f of files) {
  const text = read(f);
  for (const m of text.matchAll(/\bt\(\s*(['"])((?:\\.|(?!\1).)*)\1\s*\)/g)) add(m[2].replace(/\\(.)/g, '$1'), f);
  for (const m of text.matchAll(/data-t(?:-title)?="([^"]+)"/g)) add(m[1].replace(/&amp;/g, '&'), f);
  // Labels handed to helpers that translate them (button(id, icon, 'Label', …), field('Label', …), seg('Label', …), TOOLS rows, ERRORS, reasons)
  if (f === 'renderer/editor.js') {
    for (const m of text.matchAll(/\bbutton\(\s*'[^']*',\s*'[^']*',\s*'([^']+)'/g)) add(m[1], f);
    for (const m of text.matchAll(/\b(?:field|colour|hint|range|colorInput)\(\s*'([^']+)'/g)) add(m[1], f);
    for (const m of text.matchAll(/\[\s*'[a-zA-Z]+',\s*'([^']+)',\s*'[A-Z0-9]'\s*\]/g)) add(m[1], f);
    for (const m of text.matchAll(/[{,]\s*text: '([^'<\n]+)'/g)) add(m[1], f);
    for (const m of text.matchAll(/\[(?:false|true|'[a-z]+'), '([A-Z][^']+)'\]/g)) add(m[1], f);
  }
  for (const m of text.matchAll(/\bbtn\(\s*'([^']+)'/g)) add(m[1], f);       // list windows: btn('Label', …) translates its label
  if (f === 'renderer/pii.js') for (const m of text.matchAll(/name: '([^']+)'/g)) add(m[1], f);     // shown in Settings via t(p.name)
  if (f === 'renderer/license.js') for (const m of text.matchAll(/^\s+\w+: '([^']+)',$/gm)) add(m[1], f);
  if (f === 'src/main.js') for (const m of text.matchAll(/gate\('([^']+)'\)/g)) add(m[1], f);
}
const missing = [...used].filter(([k]) => !(k in th)).map(([k, f]) => `${f}: ${k}`);
check(`every user-visible string has Thai (${used.size} checked)`, missing.length === 0, '\n        ' + missing.join('\n        '));

// ---- translations are real (not left in English) and keep their placeholders
const same = Object.entries(th).filter(([k, v]) => k === v && /[a-z]{3}/.test(k));
check('no Thai entry is just the English text again', same.length === 0, same.map(([k]) => k).join(' | '));
const placeholders = Object.entries(th).filter(([k, v]) => ['%d', '%@'].some(p => k.includes(p) !== v.includes(p)));
check('placeholders (%d, %@) survive translation', placeholders.length === 0, placeholders.map(([k]) => k).join(' | '));

console.log(`\n${process.exitCode ? 'SOME CHECKS FAILED' : 'All checks passed.'} (${passed} passed)`);
