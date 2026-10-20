'use strict';
// Licensing for Tenix-ChaeDiew (Electron). A faithful port of Sources/ChaeDiewLicense (LicenseKey.swift, MachineBinding.swift) and
// LicenseManager.swift, so the same key and the same activation code work on macOS (native or Electron) and Windows.
//   key         TXCD1-…  Ed25519-signed payload (licensee, seats, dates, key id)
//   machine     MC-XXXX-XXXX-XXXX-XXXX  hash of the OS machine id
//   activation  TXAC1-…  Ed25519 signature over (key id ‖ machine) — one key = one computer
const crypto = require('crypto');

const KEY_PREFIX = 'TXCD1';
const ACTIVATION_PREFIX = 'TXAC1';
const KEY_DOMAIN = Buffer.from('Tenix-ChaeDiew license v1');
const MACHINE_DOMAIN = Buffer.from('Tenix-ChaeDiew machine v1\n');
const ACTIVATION_DOMAIN = Buffer.from('Tenix-ChaeDiew activation v1');
const EPOCH_MS = Date.UTC(2024, 0, 1);
const DAY_MS = 86400000;
const TRIAL_DAYS = 14;

class LicenseError extends Error {
  constructor(code, message) { super(message || code); this.code = code; }
}

// ---- Base32 (RFC 4648 alphabet, no padding) ----
const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
function base32Encode(buf) {
  let out = '', bits = 0, value = 0;
  for (const byte of buf) {
    value = (value << 8) | byte; bits += 8;
    while (bits >= 5) { out += ALPHABET[(value >>> (bits - 5)) & 31]; bits -= 5; }
    value &= (1 << bits) - 1;
  }
  if (bits > 0) out += ALPHABET[(value << (5 - bits)) & 31];
  return out;
}
function base32Decode(text) {
  const out = []; let bits = 0, value = 0;
  for (const c of text) {
    const v = ALPHABET.indexOf(c);
    if (v < 0) return null;
    value = (value << 5) | v; bits += 5;
    if (bits >= 8) { out.push((value >>> (bits - 8)) & 0xff); bits -= 8; }
    value &= (1 << bits) - 1;
  }
  return Buffer.from(out);
}

/** Removes spaces, line breaks and dashes, upper-cases, and fixes the look-alikes 0→O, 1→I, 8→B. */
function normalise(text) {
  return String(text).toUpperCase().replace(/[\s-]/g, '').replace(/0/g, 'O').replace(/1/g, 'I').replace(/8/g, 'B');
}

function publicKeyObject(base64) {
  const raw = Buffer.from(base64, 'base64');
  const spkiPrefix = Buffer.from('302a300506032b6570032100', 'hex');
  return crypto.createPublicKey({ key: Buffer.concat([spkiPrefix, raw]), format: 'der', type: 'spki' });
}
function isValidSignature(publicKeyB64, message, signature) {
  try { return crypto.verify(null, message, publicKeyObject(publicKeyB64), signature); } catch { return false; }
}

function isoDay(date) { return date.toISOString().slice(0, 10); }

/** Checks a license key; returns its details or throws a LicenseError (malformed, unsupportedVersion, badSignature, expired). */
function verifyKey(text, publicKeyB64, now = new Date()) {
  let s = normalise(text);
  const marker = normalise(KEY_PREFIX);
  if (!s.startsWith(marker)) throw new LicenseError('malformed');
  s = s.slice(marker.length);
  const bytes = base32Decode(s);
  if (!bytes || bytes.length <= 9 + 6 + 64) throw new LicenseError('malformed');
  const payload = bytes.subarray(0, bytes.length - 64), signature = bytes.subarray(bytes.length - 64);
  if (payload.length < 9) throw new LicenseError('malformed');
  if (payload[0] !== 1) throw new LicenseError('unsupportedVersion');
  const nameLength = payload[8];
  if (payload.length !== 9 + nameLength + 6) throw new LicenseError('malformed');
  if (!isValidSignature(publicKeyB64, Buffer.concat([KEY_DOMAIN, payload]), signature)) throw new LicenseError('badSignature');
  const seats = (payload[2] << 8) | payload[3];
  const issued = (payload[4] << 8) | payload[5];
  const exp = (payload[6] << 8) | payload[7];
  const licensee = payload.subarray(9, 9 + nameLength).toString('utf8');
  const keyID = payload.subarray(payload.length - 6).toString('hex').toUpperCase();
  const expires = exp === 0 ? null : new Date(EPOCH_MS + exp * DAY_MS);
  if (expires && now.getTime() > expires.getTime() + DAY_MS) { const e = new LicenseError('expired'); e.expires = expires; throw e; }
  return { licensee, seats, issued: new Date(EPOCH_MS + issued * DAY_MS), expires, keyID };
}

// ---- Machine binding ----
function machineBytes(rawID) {
  const id = String(rawID).trim().toUpperCase();
  return crypto.createHash('sha256').update(Buffer.concat([MACHINE_DOMAIN, Buffer.from(id)])).digest().subarray(0, 10);
}
function machineCodeFromBytes(bytes) {
  const text = base32Encode(bytes);
  return ['MC', ...text.match(/.{1,4}/g)].join('-');
}
function machineCode(rawID) { return machineCodeFromBytes(machineBytes(rawID)); }
function parseMachineCode(text) {
  let s = normalise(text);
  if (s.length === 18 && s.startsWith('MC')) s = s.slice(2);
  if (s.length !== 16) return null;
  const bytes = base32Decode(s);
  return bytes && bytes.length === 10 ? bytes : null;
}
function looksLikeActivation(text) { return normalise(text).startsWith(normalise(ACTIVATION_PREFIX)); }
function verifyActivation(code, keyID, machine, publicKeyB64) {
  let s = normalise(code);
  const marker = normalise(ACTIVATION_PREFIX);
  if (!s.startsWith(marker)) return false;
  s = s.slice(marker.length);
  if (!/^[0-9A-Fa-f]{12}$/.test(keyID) || machine.length !== 10) return false;
  const sig = base32Decode(s);
  if (!sig || sig.length !== 64) return false;
  return isValidSignature(publicKeyB64, Buffer.concat([ACTIVATION_DOMAIN, Buffer.from(keyID, 'hex'), machine]), sig);
}

// ---- Manager: trial, key, activation ----
const KEY_ACCOUNT = 'license-key', ACTIVATION_ACCOUNT = 'activation-code', TRIAL_ACCOUNT = 'trial-start';

class LicenseManager {
  /**
   * secrets: { get(account) → string|null, set(account, value) }  (value '' deletes).
   * requireActivation=false (default): a genuine, unexpired key is 'licensed' at once. true: also needs a TXAC1 activation code for this computer.
   */
  constructor({ secrets, publicKey, machineId, now = () => new Date(), requireActivation = false }) {
    this.secrets = secrets; this.publicKey = publicKey; this.machineId = machineId; this.now = now; this.requireActivation = requireActivation;
  }
  get storedKey() { return this.secrets.get(KEY_ACCOUNT) || null; }
  get storedActivation() { return this.secrets.get(ACTIVATION_ACCOUNT) || null; }
  get machineCode() { return machineCode(this.machineId()); }

  trialStart() {
    const saved = this.secrets.get(TRIAL_ACCOUNT);
    const parsed = saved ? new Date(saved) : null;
    if (parsed && !isNaN(parsed)) return parsed;
    const start = this.now();
    this.secrets.set(TRIAL_ACCOUNT, start.toISOString());
    return start;
  }
  trialStatus() {
    const elapsed = Math.floor((this.now() - this.trialStart()) / DAY_MS);
    const left = TRIAL_DAYS - elapsed;
    return left > 0 ? { state: 'trial', daysLeft: left } : { state: 'trialEnded' };
  }

  /** state: licensed | needsActivation | trial | trialEnded | keyProblem; allowsUse says whether copy/save/upload are open. */
  status() {
    const key = this.storedKey;
    if (key) {
      try {
        const info = verifyKey(key, this.publicKey, this.now());
        if (!this.requireActivation) return { state: 'licensed', info, allowsUse: true };
        const code = this.storedActivation;
        if (code && verifyActivation(code, info.keyID, machineBytes(this.machineId()), this.publicKey)) {
          return { state: 'licensed', info, allowsUse: true };
        }
        const trial = this.trialStatus();
        const left = trial.state === 'trial' ? trial.daysLeft : 0;
        return { state: 'needsActivation', info, trialDaysLeft: left, allowsUse: left > 0 };
      } catch (error) {
        const trial = this.trialStatus();
        if (trial.state === 'trial') return { ...trial, allowsUse: true };
        return { state: 'keyProblem', error: error.code || 'malformed', allowsUse: false };
      }
    }
    const trial = this.trialStatus();
    return { ...trial, allowsUse: trial.state === 'trial' };
  }
  get allowsUse() { return this.status().allowsUse; }

  /** Takes a license key or the activation code for this computer. Throws LicenseError. */
  activate(text) {
    if (looksLikeActivation(text)) {
      const key = this.storedKey;
      if (!key) throw new LicenseError('activationNeedsKey');
      const info = verifyKey(key, this.publicKey, this.now());
      if (!verifyActivation(text, info.keyID, machineBytes(this.machineId()), this.publicKey)) throw new LicenseError('wrongActivation');
      this.secrets.set(ACTIVATION_ACCOUNT, normalise(text));
      return info;
    }
    const info = verifyKey(text, this.publicKey, this.now());
    const normalised = normalise(text);
    if (normalised !== this.storedKey) this.secrets.set(ACTIVATION_ACCOUNT, '');
    this.secrets.set(KEY_ACCOUNT, normalised);
    return info;
  }
  remove() { this.secrets.set(KEY_ACCOUNT, ''); this.secrets.set(ACTIVATION_ACCOUNT, ''); }
}

class MemorySecrets {
  constructor() { this.values = new Map(); }
  get(account) { return this.values.get(account) || null; }
  set(account, value) { if (value) this.values.set(account, value); else this.values.delete(account); }
}

module.exports = {
  LicenseError, LicenseManager, MemorySecrets, TRIAL_DAYS,
  normalise, verifyKey, base32Encode, base32Decode, isoDay,
  machineBytes, machineCode, machineCodeFromBytes, parseMachineCode, looksLikeActivation, verifyActivation,
};
