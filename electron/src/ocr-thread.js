'use strict';
// Entry point of tesseract.js' worker thread. Electron's binary reports process.versions.electron even when it runs as plain Node,
// which makes tesseract.js load language data like a browser (fetch). Hide it so the Node file loader is used.
try { Object.defineProperty(process.versions, 'electron', { value: undefined, configurable: true }); } catch { /* ignore */ }
require('tesseract.js/src/worker-script/node/index.js');
