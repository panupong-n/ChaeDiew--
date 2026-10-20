'use strict';
// The tray / menu-bar icon. Windows' taskbar follows "Windows mode" (SystemUsesLightTheme), not the apps' light/dark setting that
// nativeTheme reports, so it is read from the registry: a dark taskbar needs the light mark, a light one the dark mark.
const { execFileSync } = require('child_process');

function taskbarUsesLightTheme() {
  if (process.platform !== 'win32') return false;
  try {
    const reg = (process.env.SystemRoot || 'C:\\Windows') + '\\System32\\reg.exe';
    const out = execFileSync(reg, ['query', 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize', '/v', 'SystemUsesLightTheme'],
      { encoding: 'utf8', timeout: 3000, windowsHide: true });
    const m = /SystemUsesLightTheme\s+REG_DWORD\s+0x([0-9a-f]+)/i.exec(out);
    return !!(m && parseInt(m[1], 16));
  } catch { return false; }      // value missing = dark taskbar (the Windows 11 default)
}

/** File name in assets/ for the tray. macOS uses a template image (the system tints it), so the dark mark is the source there. */
function trayIconFile(platform, taskbarLight) {
  if (platform === 'darwin') return 'mark-on-light.png';
  return taskbarLight ? 'mark-on-light.png' : 'mark-on-dark.png';
}

module.exports = { taskbarUsesLightTheme, trayIconFile };
