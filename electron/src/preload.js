'use strict';
const { contextBridge, ipcRenderer } = require('electron');

const boot = ipcRenderer.sendSync('app:boot');   // { lang, strings, platform, testMode }
const call = (channel, ...args) => ipcRenderer.invoke(channel, ...args);

contextBridge.exposeInMainWorld('tenix', {
  lang: boot.lang, strings: boot.strings, platform: boot.platform, testMode: boot.testMode,
  // editor
  getInitial: () => call('editor:init'),
  gate: reason => call('license:gate', reason),
  saveImage: dataURL => call('image:save', dataURL),
  copyText: text => call('text:copy', text),
  ocr: dataURL => call('ocr:run', dataURL),
  openLicense: () => call('license:open'),
  // license window
  license: {
    status: () => call('license:status'),
    activate: text => call('license:activate', text),
    remove: () => call('license:remove'),
  },
  onLicenseChanged: callback => ipcRenderer.on('license:changed', () => callback()),
  // home window
  home: {
    capture: mode => call('capture:start', mode),
    openFile: () => call('file:open'),
    setLanguage: lang => call('app:set-language', lang),
  },
  // capture overlay
  capture: {
    getShot: () => call('capture:shot'),
    done: rect => ipcRenderer.send('capture:done', rect),
  },
});
