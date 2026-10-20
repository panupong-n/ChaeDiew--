'use strict';
// Run: node test/pii.test.js — Hide PII patterns (the same cases as the native app's ChaeDiewChecks) and mapping matches to pixels.
const P = require('../renderer/pii');

let passed = 0;
function check(name, ok, detail) {
  if (ok) { passed++; console.log('PASS  ' + name); } else { console.log('FAIL  ' + name + (detail !== undefined ? '  —  ' + JSON.stringify(detail) : '')); process.exitCode = 1; }
}
const ids = (text, only) => P.matches(text, P.patterns([only], [])).length;

check('finds an email', ids('mail john.doe@example.com now', 'email') === 1);
check('Thai ID: valid checksum is found', ids('ID 1234567890121 ok', 'thai_id') === 1);
check('Thai ID: wrong checksum is ignored', ids('ID 1234567890122 ok', 'thai_id') === 0);
check('Thai ID: dashed format is found', ids('1-2345-67890-12-1', 'thai_id') === 1);
check('card: Luhn-valid number is found', ids('card 4111 1111 1111 1111', 'card') === 1);
check('card: Luhn-invalid number is ignored', ids('card 4111 1111 1111 1112', 'card') === 0);
check('phone: mobile', ids('tel 081-234-5678', 'phone_th') === 1);
check('phone: landline and +66', ids('02-123-4567 / +66 81 234 5678', 'phone_th') === 2);
check('ip: valid found, invalid ignored', ids('host 192.168.1.10', 'ip') === 1 && ids('host 999.1.1.1', 'ip') === 0);
check('secret: AWS key', ids('key AKIAIOSFODNN7EXAMPLE end', 'secret') === 1);
check('password assignment', ids('password: hunter2', 'password') === 1);
const custom = P.patterns([], ['EMP-\\d{5}', '([']);
check('custom regex works and a broken one is skipped', custom.length === 1 && P.matches('id EMP-12345', custom).length === 1);
check('every built-in is on by default', P.patterns(undefined, []).length === P.BUILTINS.length);
check('Thai text around the data does not get in the way', ids('อีเมล somchai@corp.co.th โทร 089-123-4567', 'email') === 1 && ids('อีเมล somchai@corp.co.th โทร 089-123-4567', 'phone_th') === 1);

// ---- matches → pixel boxes, using OCR word boxes
const word = (text, x0, x1, y0 = 100, y1 = 120) => ({ text, bbox: { x0, y0, x1, y1 } });
const lines = [
  { words: [word('Card', 10, 60), word('number', 70, 150), word('4111', 170, 220), word('1111', 230, 280), word('1111', 290, 340), word('1111', 350, 400)] },
  { words: [word('Email:', 10, 80, 150, 170), word('person@example.com', 90, 300, 150, 170)] },
  { words: [word('id:somchai@corp.com', 10, 200, 200, 220)] },
  { words: [word('Nothing', 10, 80, 250, 270), word('here', 90, 130, 250, 270)] },
];
const r = P.regions(lines, P.patterns(undefined, []), { padding: 3, width: 1000, height: 600 });
const card = r.find(x => x.id === 'card'), mail = r.filter(x => x.id === 'email');
check('a card number split over four OCR words becomes one box over the digits only', card && card.x === 167 && card.x + card.w === 403 && card.y === 97, card);
check('the label before an email is left readable', mail[0] && mail[0].x >= 87 && mail[0].x + mail[0].w <= 303, mail[0]);
check('an email glued to a label inside one word is cut out in proportion', (() => {
  const m = mail.find(x => x.y === 197); return m && m.x > 10 + 190 * (3 / 19) - 4 && m.x < 10 + 190 * (3 / 19) + 2 && m.x + m.w >= 200;
})(), mail);
check('lines without personal data give nothing', !r.some(x => x.y >= 247));
check('one place matched by two patterns is hidden once', P.regions([{ words: [word('4111111111111111', 0, 160)] }], P.patterns(undefined, []), {}).length === 1);
check('boxes stay inside the picture', P.regions([{ words: [word('a@b.co', 0, 50, 0, 10)] }], P.patterns(['email'], []), { width: 40, height: 8 }).every(b => b.x >= 0 && b.y >= 0 && b.x + b.w <= 40 && b.y + b.h <= 8));

console.log(`\n${process.exitCode ? 'SOME CHECKS FAILED' : 'All checks passed.'} (${passed} passed)`);
