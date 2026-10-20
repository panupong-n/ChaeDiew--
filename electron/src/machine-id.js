'use strict';
// The operating system's own identifier for this computer. macOS reads the same IOPlatformUUID as the native app, so one
// activation covers both builds on a Mac.
const { execFileSync } = require('child_process');
const fs = require('fs');
const os = require('os');

function rawMachineId() {
  try {
    if (process.platform === 'darwin') {
      const out = execFileSync('/usr/sbin/ioreg', ['-rd1', '-c', 'IOPlatformExpertDevice'], { encoding: 'utf8', timeout: 5000 });
      const m = /"IOPlatformUUID"\s*=\s*"([^"]+)"/.exec(out);
      if (m) return m[1];
    } else if (process.platform === 'win32') {
      const reg = (process.env.SystemRoot || 'C:\\Windows') + '\\System32\\reg.exe';
      const out = execFileSync(reg, ['query', 'HKLM\\SOFTWARE\\Microsoft\\Cryptography', '/v', 'MachineGuid'],
        { encoding: 'utf8', timeout: 5000, windowsHide: true });
      const m = /MachineGuid\s+REG_SZ\s+([^\s]+)/i.exec(out);
      if (m) return m[1];
    } else {
      for (const file of ['/etc/machine-id', '/var/lib/dbus/machine-id']) {
        try { const v = fs.readFileSync(file, 'utf8').trim(); if (v) return v; } catch { /* next */ }
      }
    }
  } catch { /* fall through */ }
  return os.hostname();
}

let cached;
module.exports = { rawMachineId: () => (cached ??= rawMachineId()) };
