'use strict';
// Where license data and settings live: the OS keychain-backed safeStorage (Keychain on macOS, DPAPI on Windows) when available.
const fs = require('fs');
const path = require('path');
const { app, safeStorage } = require('electron');

class SecretStore {
  constructor(file) { this.file = file; this.data = null; }
  load() {
    if (this.data) return this.data;
    try { this.data = JSON.parse(fs.readFileSync(this.file, 'utf8')); } catch { this.data = {}; }
    return this.data;
  }
  save() {
    try {
      fs.mkdirSync(path.dirname(this.file), { recursive: true });
      fs.writeFileSync(this.file, JSON.stringify(this.data), { mode: 0o600 });
    } catch { /* read-only profile: the trial simply restarts per launch */ }
  }
  get(account) {
    const v = this.load()[account];
    if (!v) return null;
    try {
      if (v.startsWith('enc:')) return safeStorage.decryptString(Buffer.from(v.slice(4), 'base64'));
      if (v.startsWith('raw:')) return Buffer.from(v.slice(4), 'base64').toString('utf8');
    } catch { /* unreadable (moved profile): treat as missing */ }
    return null;
  }
  set(account, value) {
    const d = this.load();
    if (!value) delete d[account];
    else if (safeStorage.isEncryptionAvailable()) d[account] = 'enc:' + safeStorage.encryptString(value).toString('base64');
    else d[account] = 'raw:' + Buffer.from(value, 'utf8').toString('base64');
    this.save();
  }
}

class Settings {
  constructor(file) { this.file = file; this.data = null; }
  load() {
    if (this.data) return this.data;
    try { this.data = JSON.parse(fs.readFileSync(this.file, 'utf8')); } catch { this.data = {}; }
    return this.data;
  }
  get(key, fallback) { const v = this.load()[key]; return v === undefined ? fallback : v; }
  set(key, value) {
    this.load()[key] = value;
    try { fs.mkdirSync(path.dirname(this.file), { recursive: true }); fs.writeFileSync(this.file, JSON.stringify(this.data)); } catch { /* ignore */ }
  }
}

module.exports = {
  secrets: () => new SecretStore(path.join(app.getPath('userData'), 'license.dat')),
  settings: () => new Settings(path.join(app.getPath('userData'), 'settings.json')),
};
