'use strict';
// Text recognition (English + Thai) with the language data bundled in tessdata/, so it works offline. The engine runs in a child
// process so a crash or a slow page never freezes the app.
const path = require('path');
const { fork } = require('child_process');
const { app } = require('electron');

let child = null;
let nextId = 1;
const pending = new Map();

function start() {
  child = fork(path.join(__dirname, 'ocr-worker.js'), [], { env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' }, execArgv: [], silent: true });
  child.on('message', msg => {
    const job = pending.get(msg.id);
    if (!job) return;
    pending.delete(msg.id);
    if (msg.error) job.reject(new Error(msg.error)); else job.resolve({ text: msg.text, lines: msg.lines });
  });
  const fail = reason => {
    for (const job of pending.values()) job.reject(new Error(reason));
    pending.clear();
    child = null;
  };
  let errText = '';
  child.stderr.on('data', d => { errText += d; });
  child.on('exit', code => fail('OCR stopped (' + code + ') ' + errText.slice(0, 900)));
  child.on('error', error => fail(error.message));
}

/** `png` is a Buffer. Returns { text, lines: [{ text, bbox: {x0,y0,x1,y1}, confidence }] } in image pixels. */
function recognize(png) {
  if (!child) start();
  const id = nextId++;
  return new Promise((resolve, reject) => {
    pending.set(id, { resolve, reject });
    child.send({
      id, png: png.toString('base64'),
      langPath: path.join(__dirname, '..', 'tessdata'),
      cachePath: path.join(app.getPath('userData'), 'ocr-cache'),
    });
  });
}

function shutdown() { if (child) { try { child.kill(); } catch { /* gone */ } child = null; } }

module.exports = { recognize, shutdown };
