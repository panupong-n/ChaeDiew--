'use strict';
// File names for saved pictures. Windows refuses < > : " / \ | ? *, control characters, names ending in a dot or space, and the
// reserved device names (CON, PRN, AUX, NUL, COM1–9, LPT1–9); a name with any of these must never reach fs.writeFile.
const path = require('path');

const RESERVED = /^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\..*)?$/i;

function sanitizeName(name) {
  let s = String(name || '').replace(/[<>:"/\\|?*\u0000-\u001F]/g, '-').replace(/[. ]+$/, '').trim();
  if (!s) s = 'Tenix-ChaeDiew';
  if (RESERVED.test(s)) s = '_' + s;
  return s.slice(0, 180);
}

/** "Tenix-ChaeDiew 2026-10-19 at 14.05.09" (local time; dots, because Windows does not allow ":"). */
function defaultName(date = new Date()) {
  const p = n => String(n).padStart(2, '0');
  return `Tenix-ChaeDiew ${date.getFullYear()}-${p(date.getMonth() + 1)}-${p(date.getDate())} at ${p(date.getHours())}.${p(date.getMinutes())}.${p(date.getSeconds())}`;
}

/** Picture format from a path's extension, or null when it has none we write. */
function formatOf(filePath) {
  const ext = path.extname(String(filePath)).toLowerCase();
  return ext === '.png' ? 'png' : ext === '.jpg' || ext === '.jpeg' ? 'jpg' : null;
}

/** Makes sure the path ends in an extension we can write ("report" + png → "report.png"); the folder part is left alone. */
function withExtension(filePath, format) {
  if (formatOf(filePath)) return filePath;
  const dir = path.dirname(filePath), base = sanitizeName(path.basename(filePath));
  return path.join(dir, `${base}.${format === 'jpg' ? 'jpg' : 'png'}`);
}

/** A path inside `dir` that does not exist yet ("name.png", "name 2.png", …). `exists` is injectable for tests. */
function uniquePath(dir, base, format, exists) {
  const ext = format === 'jpg' ? 'jpg' : 'png';
  let candidate = path.join(dir, `${sanitizeName(base)}.${ext}`);
  for (let i = 2; exists(candidate) && i < 1000; i++) candidate = path.join(dir, `${sanitizeName(base)} ${i}.${ext}`);
  return candidate;
}

module.exports = { sanitizeName, defaultName, formatOf, withExtension, uniquePath };
