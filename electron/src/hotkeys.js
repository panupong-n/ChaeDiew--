'use strict';
// Global shortcut helpers shared by the main process and the Settings window: defaults, recording a key press as an Electron
// accelerator (by physical key, so a Thai keyboard layout records the same thing as an English one) and display labels.

// Scrolling capture has no default: every extra global shortcut takes a key combination away from other programs.
const DEFAULTS = { area: 'CommandOrControl+Shift+2', full: 'CommandOrControl+Shift+1', scroll: '' };
const PRESETS = [
  { area: 'CommandOrControl+Shift+2', full: 'CommandOrControl+Shift+1' },
  { area: 'Control+Alt+2', full: 'Control+Alt+1' },
  { area: 'PrintScreen', full: 'Control+PrintScreen' },
];

const NAMED = {
  Space: 'Space', Tab: 'Tab', Enter: 'Enter', Backspace: 'Backspace', Delete: 'Delete', Insert: 'Insert', Home: 'Home', End: 'End',
  PageUp: 'PageUp', PageDown: 'PageDown', ArrowUp: 'Up', ArrowDown: 'Down', ArrowLeft: 'Left', ArrowRight: 'Right', PrintScreen: 'PrintScreen',
  Minus: '-', Equal: '=', BracketLeft: '[', BracketRight: ']', Backslash: '\\', Semicolon: ';', Quote: "'", Comma: ',', Period: '.', Slash: '/',
  Backquote: '`', NumpadAdd: 'numadd', NumpadSubtract: 'numsub', NumpadMultiply: 'nummult', NumpadDivide: 'numdiv', NumpadDecimal: 'numdec',
};

/** Accelerator key for a KeyboardEvent.code, or null for modifiers and keys a global shortcut cannot use. */
function keyFromCode(code) {
  if (/^Key[A-Z]$/.test(code)) return code.slice(3);
  if (/^Digit[0-9]$/.test(code)) return code.slice(5);
  if (/^Numpad[0-9]$/.test(code)) return 'num' + code.slice(6);
  if (/^F([1-9]|1[0-9]|2[0-4])$/.test(code)) return code;
  return NAMED[code] || null;
}

/**
 * A key press → accelerator ("Control+Shift+2"). Needs a modifier, except for F-keys and PrintScreen, so ordinary typing can never become
 * a global shortcut. Returns null while only modifiers are held or the combination is not allowed.
 */
function fromKeyEvent(e, platform) {
  const key = keyFromCode(e.code || '');
  if (!key) return null;
  const mods = [];
  if (e.ctrlKey) mods.push('Control');
  if (e.metaKey) mods.push(platform === 'darwin' ? 'Command' : 'Super');
  if (e.altKey) mods.push('Alt');
  if (e.shiftKey) mods.push('Shift');
  const standalone = /^F\d+$/.test(key) || key === 'PrintScreen';
  if (!mods.length && !standalone) return null;
  if (mods.length === 1 && mods[0] === 'Shift' && !standalone) return null;   // Shift+letter is just typing
  return [...mods, key].join('+');
}

/** How an accelerator is shown to the user on this platform. */
function label(accel, platform) {
  if (!accel) return '';
  const mac = platform === 'darwin';
  const parts = accel.split('+').map(p => {
    switch (p) {
      case 'CommandOrControl': case 'CmdOrCtrl': return mac ? '⌘' : 'Ctrl';
      case 'Command': case 'Cmd': return mac ? '⌘' : 'Win';
      case 'Control': case 'Ctrl': return mac ? '⌃' : 'Ctrl';
      case 'Alt': case 'Option': return mac ? '⌥' : 'Alt';
      case 'Shift': return mac ? '⇧' : 'Shift';
      case 'Super': return 'Win';
      case 'PrintScreen': return mac ? 'Print Screen' : 'PrtScn';
      default: return p.replace(/^num/, 'Num ');
    }
  });
  return mac ? parts.join('') : parts.join('+');
}

/** Same physical shortcut? ("CommandOrControl+Shift+2" equals "Control+Shift+2" on Windows.) */
function same(a, b, platform) {
  const norm = s => String(s || '').split('+').map(p => (/^(CommandOrControl|CmdOrCtrl)$/.test(p) ? (platform === 'darwin' ? 'Command' : 'Control') : p === 'Ctrl' ? 'Control' : p)).sort().join('+');
  return norm(a) === norm(b);
}

module.exports = { DEFAULTS, PRESETS, keyFromCode, fromKeyEvent, label, same };
