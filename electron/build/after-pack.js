'use strict';
// Windows: stamp our icon and version details into the .exe. electron-builder normally does this with rcedit, which needs Wine on a Mac;
// resedit does the same in pure JavaScript, so the Windows build can be produced from macOS.
const fs = require('fs');
const path = require('path');

exports.default = async function afterPack(context) {
  if (context.electronPlatformName !== 'win32') return;
  const ResEdit = require('resedit');
  const { NtExecutable, NtExecutableResource } = require('pe-library');
  const exePath = path.join(context.appOutDir, `${context.packager.appInfo.productFilename}.exe`);
  const exe = NtExecutable.from(fs.readFileSync(exePath));
  const res = NtExecutableResource.from(exe);

  const icon = ResEdit.Data.IconFile.from(fs.readFileSync(path.join(__dirname, '..', 'assets', 'icon.ico')));
  const groups = ResEdit.Resource.IconGroupEntry.fromEntries(res.entries);
  const group = groups[0] || { id: 1, lang: 1033 };
  ResEdit.Resource.IconGroupEntry.replaceIconsForResource(res.entries, group.id, group.lang, icon.icons.map(i => i.data));

  const version = context.packager.appInfo.version;
  const vi = ResEdit.Resource.VersionInfo.fromEntries(res.entries)[0];
  if (vi) {
    vi.setFileVersion(...version.split('.').map(Number), 0);
    vi.setProductVersion(...version.split('.').map(Number), 0);
    vi.setStringValues({ lang: 1033, codepage: 1200 }, {
      ProductName: 'Tenix-ChaeDiew', FileDescription: 'Tenix-ChaeDiew', InternalName: 'Tenix-ChaeDiew', OriginalFilename: 'Tenix-ChaeDiew.exe',
      LegalCopyright: 'Powered by Panupong Nijjaboon', CompanyName: 'Panupong Nijjaboon',
    });
    vi.outputToResourceEntries(res.entries);
  }
  res.outputResource(exe);
  fs.writeFileSync(exePath, Buffer.from(exe.generate()));
  console.log('  • Windows icon and version details written to ' + path.basename(exePath));
};
