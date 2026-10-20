'use strict';
// History of captures with full-text search (the native app's Library.swift) and the list of uploaded links (UploadHistory.swift).
// Kept in the app's own data folder, not in the user's visible folders; captures older than the retention period are deleted.
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const pad = n => String(n).padStart(2, '0');
const day = d => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

class LibraryStore {
  /** `folder` holds index.json, <id>.png and <id>.thumb.png. `writeThumb(pngBuffer) → pngBuffer` is injected (nativeImage in the app). */
  constructor(folder, { makeThumb } = {}) { this.folder = folder; this.makeThumb = makeThumb; this.items = null; }
  get indexFile() { return path.join(this.folder, 'index.json'); }
  load() {
    if (this.items) return this.items;
    try { this.items = JSON.parse(fs.readFileSync(this.indexFile, 'utf8')).filter(i => i && i.id && i.fileName); } catch { this.items = []; }
    return this.items;
  }
  persist() {
    fs.mkdirSync(this.folder, { recursive: true });
    const tmp = this.indexFile + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(this.items));
    fs.renameSync(tmp, this.indexFile);          // never a half-written index
  }
  file(item) { return path.join(this.folder, item.fileName); }
  thumb(item) { return path.join(this.folder, item.thumbName || item.fileName); }

  /** Adds a capture (PNG bytes). Newest first. */
  add(png, { width, height, pixelScale = 1, date = new Date() }) {
    this.load();
    const id = crypto.randomUUID();
    const item = { id, fileName: `${id}.png`, thumbName: null, date: date.toISOString(), width, height, pixelScale, ocrText: '' };
    fs.mkdirSync(this.folder, { recursive: true });
    fs.writeFileSync(this.file(item), png);
    if (this.makeThumb) {
      try { const t = this.makeThumb(png); if (t) { item.thumbName = `${id}.thumb.png`; fs.writeFileSync(this.thumb(item), t); } } catch { /* the full picture serves */ }
    }
    this.items.unshift(item);
    this.persist();
    return item;
  }
  get(id) { return this.load().find(i => i.id === id) || null; }
  setOCRText(id, text) { const i = this.get(id); if (i) { i.ocrText = String(text || ''); this.persist(); } }
  remove(id) {
    const i = this.get(id); if (!i) return false;
    for (const f of [this.file(i), i.thumbName && this.thumb(i)]) if (f) { try { fs.unlinkSync(f); } catch { /* gone */ } }
    this.items = this.items.filter(x => x !== i); this.persist();
    return true;
  }
  removeAll() { for (const i of this.load().slice()) this.remove(i.id); }
  /** Deletes items older than `days` (0 keeps everything). Returns how many were removed. */
  purge(days, now = new Date()) {
    if (!days || days <= 0) return 0;
    const cutoff = now.getTime() - days * 86400000;
    const old = this.load().filter(i => new Date(i.date).getTime() < cutoff);
    for (const i of old) this.remove(i.id);
    return old.length;
  }
  /** Every whitespace-separated term must appear in the OCR text, the file name or the date (yyyy-mm-dd). */
  search(query) {
    const terms = String(query || '').toLowerCase().split(/\s+/).filter(Boolean);
    return this.load().filter(i => {
      const hay = `${i.ocrText} ${i.fileName} ${day(new Date(i.date))}`.toLowerCase();
      return terms.every(t => hay.includes(t));
    });
  }
}

/** Links of everything uploaded from this app, newest first, capped at 200 (native UploadHistory). */
class UploadHistory {
  constructor(file) { this.file = file; this.records = null; }
  load() {
    if (this.records) return this.records;
    try { this.records = JSON.parse(fs.readFileSync(this.file, 'utf8')); } catch { this.records = []; }
    return this.records;
  }
  persist() { fs.mkdirSync(path.dirname(this.file), { recursive: true }); fs.writeFileSync(this.file, JSON.stringify(this.records)); }
  add(url, name, date = new Date()) {
    this.load().unshift({ id: crypto.randomUUID(), url, name, date: date.toISOString() });
    this.records = this.records.slice(0, 200); this.persist();
    return this.records[0];
  }
  remove(id) { this.records = this.load().filter(r => r.id !== id); this.persist(); }
  removeAll() { this.records = []; this.persist(); }
}

module.exports = { LibraryStore, UploadHistory, day };
