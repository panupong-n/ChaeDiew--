// Hide PII: finds personal or secret data in OCR text and where it sits in the picture, so it can be pixelated. A port of the native
// app's Redactor (same patterns and validators). Pure: loaded by the editor page and by test/pii.test.js.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.PII = factory();
})(this, function () {
  'use strict';

  /** Thai national ID: 13 digits, the last is a mod-11 checksum of the first 12. */
  function isValidThaiID(text) {
    const d = String(text).replace(/\D/g, '').split('').map(Number);
    if (d.length !== 13) return false;
    let sum = 0;
    for (let i = 0; i < 12; i++) sum += d[i] * (13 - i);
    return (11 - (sum % 11)) % 10 === d[12];
  }

  function isValidLuhn(text) {
    const d = String(text).replace(/\D/g, '').split('').map(Number);
    if (d.length < 13 || d.length > 19) return false;
    let sum = 0;
    d.reverse().forEach((v, i) => { if (i % 2 === 1) { v *= 2; if (v > 9) v -= 9; } sum += v; });
    return sum % 10 === 0;
  }

  const BUILTINS = [
    { id: 'email', name: 'Email addresses', regex: '[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}', flags: 'i' },
    { id: 'thai_id', name: 'Thai national ID', regex: '(?<!\\d)\\d[ -]?\\d{4}[ -]?\\d{5}[ -]?\\d{2}[ -]?\\d(?!\\d)', flags: 'i', validate: isValidThaiID },
    { id: 'phone_th', name: 'Phone numbers', regex: '(?<!\\d)(?:\\+66[ -]?|0)\\d{1,2}[ -]?\\d{3}[ -]?\\d{4}(?!\\d)', flags: 'i',
      validate: s => { const n = s.replace(/\D/g, '').length; return n >= 9 && n <= 11; } },
    { id: 'card', name: 'Payment card numbers', regex: '(?<!\\d)(?:\\d[ -]?){12,18}\\d(?!\\d)', flags: 'i', validate: isValidLuhn },
    { id: 'ip', name: 'IPv4 addresses', regex: '\\b(?:(?:25[0-5]|2[0-4]\\d|1?\\d?\\d)\\.){3}(?:25[0-5]|2[0-4]\\d|1?\\d?\\d)\\b', flags: 'i' },
    { id: 'secret', name: 'API keys and tokens', flags: '',
      regex: '\\b(?:AKIA[0-9A-Z]{16}|(?:ghp|gho|ghu|ghs|github_pat|glpat|xox[baprs]|sk|pk)[-_][A-Za-z0-9_-]{16,}|eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,})' },
    { id: 'password', name: 'Password and secret assignments', regex: '\\b(?:password|passwd|pwd|secret|token|api[_-]?key)\\b\\s*[:=]\\s*\\S+', flags: 'i' },
  ];

  /** Enabled built-ins plus the user's own regular expressions (ones that do not compile are skipped). */
  function patterns(enabledIds, custom) {
    const on = new Set(enabledIds || BUILTINS.map(p => p.id));
    const list = BUILTINS.filter(p => on.has(p.id));
    (custom || []).forEach((regex, i) => {
      if (!regex || !String(regex).trim()) return;
      try { new RegExp(regex); list.push({ id: 'custom' + i, name: regex, regex, flags: '' }); } catch { /* invalid: skipped */ }
    });
    return list;
  }

  /** [{ start, end, id }] character ranges in `text`. */
  function matches(text, pats) {
    const found = [];
    for (const p of pats) {
      const re = new RegExp(p.regex, (p.flags || '').replace('g', '') + 'g');
      for (const m of String(text).matchAll(re)) {
        if (!m[0] || (p.validate && !p.validate(m[0]))) continue;
        found.push({ start: m.index, end: m.index + m[0].length, id: p.id });
      }
    }
    return found;
  }

  /**
   * Pixel rectangles to hide. `lines`: OCR lines with `words: [{ text, bbox: {x0,y0,x1,y1} }]`. The words are joined with single spaces
   * (whatever the gap in the picture), the patterns run on that, and a match is mapped back to the words it covers; where it starts or
   * ends inside a word, the word's box is cut in proportion to the characters.
   */
  function regions(lines, pats, opts = {}) {
    const padding = opts.padding == null ? 3 : opts.padding, W = opts.width || Infinity, H = opts.height || Infinity;
    const rects = [];
    for (const line of lines || []) {
      const words = (line.words || []).filter(w => w.text && w.bbox);
      if (!words.length) continue;
      let text = '';
      const spans = words.map(w => { const start = text.length ? text.length + 1 : 0; text += (text.length ? ' ' : '') + w.text; return { start, end: start + w.text.length, w }; });
      for (const m of matches(text, pats)) {
        let box = null;
        for (const s of spans) {
          if (s.end <= m.start || s.start >= m.end) continue;
          const n = s.end - s.start, b = s.w.bbox, wpx = b.x1 - b.x0;
          const a = Math.max(0, m.start - s.start) / n, z = Math.min(n, m.end - s.start) / n;
          const part = { x0: b.x0 + wpx * a, x1: b.x0 + wpx * z, y0: b.y0, y1: b.y1 };
          box = box ? { x0: Math.min(box.x0, part.x0), y0: Math.min(box.y0, part.y0), x1: Math.max(box.x1, part.x1), y1: Math.max(box.y1, part.y1) } : part;
        }
        if (!box) continue;
        const x = Math.max(0, Math.floor(box.x0 - padding)), y = Math.max(0, Math.floor(box.y0 - padding));
        const x1 = Math.min(W, Math.ceil(box.x1 + padding)), y1 = Math.min(H, Math.ceil(box.y1 + padding));
        if (x1 - x >= 2 && y1 - y >= 2) rects.push({ x, y, w: x1 - x, h: y1 - y, id: m.id });
      }
    }
    // One number can match two patterns (a card number is also digits a phone pattern might take): keep one box per place.
    const inside = (a, b) => {
      const ix = Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)), iy = Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y));
      return ix * iy >= 0.9 * a.w * a.h;
    };
    rects.sort((a, b) => b.w * b.h - a.w * a.h);
    return rects.filter((r, i) => !rects.slice(0, i).some(o => inside(r, o)));
  }

  return { BUILTINS, patterns, matches, regions, isValidThaiID, isValidLuhn };
});
