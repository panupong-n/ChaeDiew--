'use strict';
// Run: node test/library.test.js — capture history (add, search by OCR text / name / date, purge, remove) and the uploaded-links list.
const fs = require('fs');
const os = require('os');
const path = require('path');
const { LibraryStore, UploadHistory } = require('../src/library');

let passed = 0;
function check(name, ok, detail) {
  if (ok) { passed++; console.log('PASS  ' + name); } else { console.log('FAIL  ' + name + (detail !== undefined ? '  —  ' + JSON.stringify(detail) : '')); process.exitCode = 1; }
}
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'tenix-lib ทดสอบ '));
const lib = new LibraryStore(path.join(dir, 'library'), { makeThumb: png => Buffer.concat([Buffer.from('T'), png]) });
const now = new Date(2026, 9, 20, 10, 0, 0);
const a = lib.add(Buffer.from('PNG-A'), { width: 100, height: 50, date: new Date(2026, 9, 1) });
const b = lib.add(Buffer.from('PNG-B'), { width: 200, height: 80, pixelScale: 1.25, date: new Date(2026, 9, 19) });
check('captures are stored newest first, with picture and thumbnail files', lib.items[0].id === b.id && fs.readFileSync(lib.file(b)).toString() === 'PNG-B' && fs.readFileSync(lib.thumb(b)).toString() === 'TPNG-B');
lib.setOCRText(b.id, 'Invoice total 4,820 บาท ใบแจ้งหนี้');
check('search by text that OCR found (English and Thai)', lib.search('invoice').length === 1 && lib.search('ใบแจ้งหนี้').length === 1 && lib.search('INVOICE total').length === 1);
check('search by date (yyyy-mm-dd)', lib.search('2026-10-01').map(i => i.id).join() === a.id);
check('every term must match', lib.search('invoice 2026-10-01').length === 0);
check('an empty search lists everything', lib.search('').length === 2);
const reopened = new LibraryStore(path.join(dir, 'library'));
check('the index survives a restart', reopened.load().length === 2 && reopened.get(b.id).ocrText.startsWith('Invoice'));
check('purge keeps recent captures and deletes old ones with their files', lib.purge(14, now) === 1 && !fs.existsSync(lib.file(a)) && lib.items.length === 1);
check('a retention of 0 keeps everything', lib.purge(0, now) === 0 && lib.items.length === 1);
check('remove deletes picture, thumbnail and entry', lib.remove(b.id) && !fs.existsSync(lib.file(b)) && !fs.existsSync(lib.thumb(b)) && lib.items.length === 0);
fs.writeFileSync(path.join(dir, 'library', 'index.json'), '{broken');
check('a damaged index starts empty instead of crashing', new LibraryStore(path.join(dir, 'library')).load().length === 0);

const up = new UploadHistory(path.join(dir, 'uploads.json'));
for (let i = 0; i < 205; i++) up.add(`https://x/${i}`, `shot ${i}.png`);
check('upload links: newest first, capped at 200', up.records.length === 200 && up.records[0].url === 'https://x/204');
up.remove(up.records[0].id);
check('…a link can be removed and the list survives a restart', new UploadHistory(path.join(dir, 'uploads.json')).load()[0].url === 'https://x/203');

console.log(`\n${process.exitCode ? 'SOME CHECKS FAILED' : 'All checks passed.'} (${passed} passed)`);
