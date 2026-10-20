'use strict';
// Runs in a child process (Electron's own Node, ELECTRON_RUN_AS_NODE) because tesseract.js' worker threads do not start inside the
// Electron main process. Receives { id, png (base64), langPath, cachePath }, answers { id, text, lines } or { id, error }.
const path = require('path');
try { Object.defineProperty(process.versions, 'electron', { value: undefined, configurable: true }); } catch { /* ignore */ }
const { createWorker } = require('tesseract.js');

let workerPromise = null;
const THAI = '[\\u0E00-\\u0E7F]';

/** The Thai model puts a space between every character and splits "ำ" in two; undo both. */
function tidy(text) {
  return text
    .replace(new RegExp(`(${THAI})[ \\t]+(?=${THAI})`, 'g'), '$1')
    .replace(/ํา/g, 'ำ')
    .replace(/[ \t]+$/gm, '');
}

process.on('message', async msg => {
  try {
    workerPromise ??= createWorker(['eng', 'tha'], 1, { langPath: msg.langPath, cachePath: msg.cachePath, gzip: true, workerPath: path.join(__dirname, 'ocr-thread.js') });
    const worker = await workerPromise;
    const { data } = await worker.recognize(Buffer.from(msg.png, 'base64'));
    // Word boxes let Hide PII cover just the matching part of a line.
    const lines = (data.lines || [])
      .map(l => ({ text: tidy(l.text || '').trim(), bbox: l.bbox, confidence: l.confidence,
        words: (l.words || []).map(w => ({ text: (w.text || '').trim(), bbox: w.bbox })).filter(w => w.text) }))
      .filter(l => l.text.length > 0);
    process.send({ id: msg.id, text: tidy(data.text || '').trim(), lines });
  } catch (error) {
    workerPromise = null;
    process.send({ id: msg.id, error: String(error && error.message || error) });
  }
});
process.on('disconnect', () => process.exit(0));
