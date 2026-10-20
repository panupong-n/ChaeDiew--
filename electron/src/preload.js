'use strict';
const { contextBridge, ipcRenderer } = require('electron');

const boot = ipcRenderer.sendSync('app:boot');   // { lang, strings, platform, testMode }
const call = (channel, ...args) => ipcRenderer.invoke(channel, ...args);
const listen = (channel, callback) => ipcRenderer.on(channel, (e, ...args) => callback(...args));

contextBridge.exposeInMainWorld('tenix', {
  lang: boot.lang, strings: boot.strings, platform: boot.platform, testMode: boot.testMode, version: boot.version,
  // editor
  getInitial: () => call('editor:init'),
  gate: reason => call('license:gate', reason),
  copyImage: dataURL => call('image:copy', dataURL),
  saveImage: (dataURL, opts) => call('image:save', dataURL, opts),
  copyText: text => call('text:copy', text),
  ocr: dataURL => call('ocr:run', dataURL),
  pinImage: (dataURL, pixelScale) => call('image:pin', dataURL, pixelScale),
  printImage: dataURL => call('image:print', dataURL),
  saveGif: bytes => call('image:gif', bytes),
  uploadImage: dataURL => call('image:upload', dataURL),
  openLibrary: () => call('library:open-window'),
  openUploads: () => call('uploads:open-window'),
  openLicense: () => call('license:open'),
  openSettings: () => call('settings:open'),
  showMenu: spec => call('editor:menu', spec),
  onCommand: callback => listen('editor:command', callback),
  onLanguage: callback => listen('app:lang', callback),
  // license window
  license: {
    status: () => call('license:status'),
    activate: text => call('license:activate', text),
    remove: () => call('license:remove'),
  },
  onLicenseChanged: callback => listen('license:changed', callback),
  // home window
  home: {
    capture: mode => call('capture:start', mode),
    openFile: () => call('file:open'),
    setLanguage: lang => call('app:set-language', lang),
    hotkeys: () => call('app:hotkeys'),
  },
  // settings window
  settings: {
    get: () => call('settings:get'),
    set: patch => call('settings:set', patch),
    chooseFolder: () => call('settings:choose-folder'),
    openFolder: () => call('settings:open-folder'),
    keyToAccelerator: e => call('hotkeys:from-event', e),
    pauseHotkeys: () => call('hotkeys:pause'),
    resumeHotkeys: () => call('hotkeys:resume'),
  },
  onSettingsChanged: callback => listen('settings:changed', callback),
  upload: { settings: patch => call('upload:settings', patch), test: () => call('upload:test') },
  // history and uploaded links
  library: {
    list: query => call('library:list', query), open: id => call('library:open', id), copy: id => call('library:copy', id),
    reveal: id => call('library:reveal', id), remove: id => call('library:remove', id), clear: () => call('library:clear'),
  },
  onLibraryChanged: callback => listen('library:changed', callback),
  uploads: {
    list: () => call('uploads:list'), copy: id => call('uploads:copy', id), open: id => call('uploads:open', id),
    remove: id => call('uploads:remove', id), clear: () => call('uploads:clear'),
  },
  onUploadsChanged: callback => listen('uploads:changed', callback),
  // pinned picture
  pin: {
    init: () => call('pin:init'), move: (dx, dy) => ipcRenderer.send('pin:move', dx, dy), zoom: f => ipcRenderer.send('pin:zoom', f),
    menu: () => ipcRenderer.send('pin:menu'), close: () => ipcRenderer.send('pin:close'),
  },
  // scrolling capture bar
  scroll: { done: () => ipcRenderer.send('scroll:done'), cancel: () => ipcRenderer.send('scroll:cancel') },
  onScrollProgress: callback => listen('scroll:progress', callback),
  // capture overlay
  capture: {
    getHelp: () => call('capture:help'),
    getShot: () => call('capture:shot'),
    done: rect => ipcRenderer.send('capture:done', rect),
  },
});
