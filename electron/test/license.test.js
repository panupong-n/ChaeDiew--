'use strict';
// Run: node test/license.test.js   (no test framework needed)
const assert = require('assert');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const L = require('../src/license');
const realPublicKey = require('../src/public-key');

let passed = 0;
function check(name, fn) {
  try { const ok = typeof fn === 'function' ? fn() : fn; if (!ok) throw new Error('false'); passed++; console.log('PASS  ' + name); }
  catch (e) { console.log('FAIL  ' + name + '  —  ' + e.message); process.exitCode = 1; }
}
const throwsCode = (fn, code) => { try { fn(); return false; } catch (e) { return e.code === code; } };

// A throw-away issuer, written independently of src/license.js's verifying half, mirroring ChaeDiewKeygen.
const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
const signerPublic = publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
const otherPublic = crypto.generateKeyPairSync('ed25519').publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
const EPOCH = Date.UTC(2024, 0, 1), DAY = 86400000;
function group(text, n, prefix) { return [prefix, ...text.match(new RegExp('.{1,' + n + '}', 'g'))].join('-'); }
function issueKey({ licensee, seats = 1, now, expires = null }) {
  const name = Buffer.from(licensee);
  const day = d => Math.floor((d.getTime() - EPOCH) / DAY);
  const head = Buffer.from([1, 1, seats >> 8, seats & 255, day(now) >> 8, day(now) & 255, expires ? day(expires) >> 8 : 0, expires ? day(expires) & 255 : 0, name.length]);
  const payload = Buffer.concat([head, name, crypto.randomBytes(6)]);
  const signature = crypto.sign(null, Buffer.concat([Buffer.from('Tenix-ChaeDiew license v1'), payload]), privateKey);
  return group(L.base32Encode(Buffer.concat([payload, signature])), 8, 'TXCD1');
}
function issueActivation(keyID, machine) {
  const sig = crypto.sign(null, Buffer.concat([Buffer.from('Tenix-ChaeDiew activation v1'), Buffer.from(keyID, 'hex'), machine]), privateKey);
  return group(L.base32Encode(sig), 8, 'TXAC1');
}

const today = new Date(Date.UTC(2026, 9, 19, 12));
const yearOn = new Date(today.getTime() + 365 * DAY);

// ---- keys ----
const key = issueKey({ licensee: 'Panupong Nijjaboon', seats: 25, now: today, expires: yearOn });
check('a key starts with TXCD1 and is grouped', key.startsWith('TXCD1-') && key.split('-').length > 10);
const info = L.verifyKey(key, signerPublic, today);
check('a genuine key verifies and carries its details', info.licensee === 'Panupong Nijjaboon' && info.seats === 25 && info.keyID.length === 12 && info.expires);
check('the expiry is a year ahead', Math.abs(info.expires - today - 365 * DAY) < 2 * DAY);
check('a key does not verify under another public key', throwsCode(() => L.verifyKey(key, otherPublic, today), 'badSignature'));
check('changing a single character breaks the signature', (() => { const i = key.length - 30; const t = key.slice(0, i) + (key[i] === 'B' ? 'C' : 'B') + key.slice(i + 1); return throwsCode(() => L.verifyKey(t, signerPublic, today), 'badSignature'); })());
check('a truncated key is malformed', throwsCode(() => L.verifyKey(key.slice(0, -12), signerPublic, today), 'malformed'));
check('text that is not a key is malformed', throwsCode(() => L.verifyKey('hello world', signerPublic), 'malformed'));
check('pasting with spaces, line breaks and lower case still works', !!L.verifyKey(' ' + key.toLowerCase().replace(/-/g, '\n') + '\n', signerPublic, today));
check('an expired key is refused after its last day', throwsCode(() => L.verifyKey(key, signerPublic, new Date(yearOn.getTime() + 3 * DAY)), 'expired'));
const forever = issueKey({ licensee: 'Everyone', now: today });
check('a perpetual key never expires', L.verifyKey(forever, signerPublic, new Date(today.getTime() + 20 * 365 * DAY)).expires === null);
check('a Thai licensee name round-trips', L.verifyKey(issueKey({ licensee: 'เท็นนิค', now: today }), signerPublic, today).licensee === 'เท็นนิค');

// ---- keys made by the real Swift keygen (only if present on this machine) ----
const issuedDir = path.join(os.homedir(), 'Library/Application Support/Tenix-ChaeDiew-Keygen/issued');
const csv = path.join(issuedDir, 'Tenix-licenses-50.csv');
if (fs.existsSync(csv)) {
  const rows = fs.readFileSync(csv, 'utf8').trim().split('\n').slice(1).map(l => l.split(','));
  check('all 50 issued keys verify with the shipped public key', rows.length === 50 && rows.every(r => L.verifyKey(r[5], realPublicKey).seats === 1));
  check('…and every key id is unique', new Set(rows.map(r => L.verifyKey(r[5], realPublicKey).keyID)).size === 50);
} else console.log('      (skipped: issued key list not on this machine)');

// ---- machine code ----
const macA = '11111111-AAAA-BBBB-CCCC-000000000001', macB = '22222222-AAAA-BBBB-CCCC-000000000002';
check('machine code looks like MC-XXXX-XXXX-XXXX-XXXX', /^MC(-[A-Z2-7]{4}){4}$/.test(L.machineCode(macA)));
check('it is stable (any case) and differs per computer', L.machineCode(macA) === L.machineCode(macA.toLowerCase()) && L.machineCode(macA) !== L.machineCode(macB));
check('a machine code typed back parses', L.parseMachineCode(' ' + L.machineCode(macA).toLowerCase().replace(/-/g, ' ')).equals(L.machineBytes(macA)));
check('junk is not a machine code', L.parseMachineCode('MC-1234') === null);
// Fixed vector shared with the Swift check (`chaediew-keygen machine-code --raw …`): both ports must print the same.
console.log('      (vector: ' + L.machineCode('TEST-VECTOR-0001') + ')');

// ---- activation + manager ----
const bound = issueKey({ licensee: 'Bound', now: today });
const boundInfo = L.verifyKey(bound, signerPublic, today);
const actA = issueActivation(boundInfo.keyID, L.machineBytes(macA));
check('an activation code is TXAC1 plus a 64-byte signature', actA.startsWith('TXAC1-') && actA.length > 100 && actA.length < 130);
check('it verifies for its own key and computer', L.verifyActivation(actA, boundInfo.keyID, L.machineBytes(macA), signerPublic));
check('…not on another computer', !L.verifyActivation(actA, boundInfo.keyID, L.machineBytes(macB), signerPublic));
check('…not for another key', !L.verifyActivation(actA, 'AABBCCDDEEFF', L.machineBytes(macA), signerPublic));
check('…not under another issuer', !L.verifyActivation(actA, boundInfo.keyID, L.machineBytes(macA), otherPublic));
check('keys and activation codes are told apart', !L.looksLikeActivation(bound) && L.looksLikeActivation(actA));

let clock = today;
const secrets = new L.MemorySecrets();
const manager = new L.LicenseManager({ secrets, publicKey: signerPublic, machineId: () => macA, requireActivation: true, now: () => clock });
check('the first look starts a 14-day trial', manager.status().state === 'trial' && manager.status().daysLeft === 14);
clock = new Date(today.getTime() + 10 * DAY + 3600e3);
check('days count down', manager.status().daysLeft === 4);
clock = new Date(today.getTime() + 15 * DAY);
check('after the trial, use is refused', manager.status().state === 'trialEnded' && !manager.allowsUse);
check('an invalid key cannot be activated', throwsCode(() => manager.activate('TXCD1-NOPE'), 'malformed'));
check('an activation code before any key is refused', throwsCode(() => manager.activate(actA), 'activationNeedsKey'));
clock = today;
manager.activate(bound);
check('a key alone waits for activation, trial still running', manager.status().state === 'needsActivation' && manager.allowsUse);
clock = new Date(today.getTime() + 15 * DAY);
check('…and after the trial it unlocks nothing', !manager.allowsUse);
check('an activation for another computer is refused', throwsCode(() => manager.activate(issueActivation(boundInfo.keyID, L.machineBytes(macB))), 'wrongActivation'));
manager.activate(actA);
check('the right activation code switches the app on', manager.status().state === 'licensed' && manager.allowsUse);
const copied = new L.MemorySecrets();
for (const a of ['license-key', 'activation-code', 'trial-start']) copied.set(a, secrets.get(a));
check('key + activation copied to another computer do not work there', !new L.LicenseManager({ secrets: copied, publicKey: signerPublic, machineId: () => macB, requireActivation: true, now: () => clock }).allowsUse);
check('…but still work on the original', new L.LicenseManager({ secrets: copied, publicKey: signerPublic, machineId: () => macA, requireActivation: true, now: () => clock }).allowsUse);
manager.activate(issueKey({ licensee: 'Second', now: today }));
check('a different key needs its own activation', manager.storedActivation === null && !manager.allowsUse);
manager.activate(bound); manager.activate(actA);
check('re-entering the first key and its code works again', manager.status().state === 'licensed');
manager.remove();
check('removing the key clears the activation and the trial start survives', manager.storedKey === null && manager.storedActivation === null && manager.status().state === 'trialEnded');

console.log(`\n${process.exitCode ? 'SOME CHECKS FAILED' : 'All checks passed.'} (${passed} passed)`);
