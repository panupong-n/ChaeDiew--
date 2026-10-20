'use strict';
// Text recognition (English + Thai) with the language data bundled in tessdata/, so it works offline. The engine runs in a child
// process so a crash or a slow page never freezes the app. A job that takes longer than the timeout restarts the engine and fails
// with a message, instead of leaving the user waiting forever (antivirus scanning the language data on first use can stall it).
const path = require('path');
const { fork } = require('child_process');
const { app } = require('electron');

let child = null;
let nextId = 1;
const pending = new Map();
let timeoutMs = 90000;      // the first job also loads ~4 MB of language data

function start() {
  const proc = fork(path.join(__dirname, 'ocr-worker.js'), [], { env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' }, execArgv: [], silent: true, windowsHide: true });
  child = proc;
  proc.on('message', msg => {
    const job = pending.get(msg.id);
    if (!job) return;
    pending.delete(msg.id); clearTimeout(job.timer);
    if (msg.error) job.reject(new Error(msg.error)); else job.resolve({ text: msg.text, lines: msg.lines });
  });
  const fail = reason => {
    if (child !== proc) return;      // an engine that was already replaced
    for (const job of pending.values()) { clearTimeout(job.timer); job.reject(new Error(reason)); }
    pending.clear();
    child = null;
  };
  let errText = '';
  proc.stderr.on('data', d => { errText += d; });
  proc.on('exit', code => fail('OCR stopped (' + code + ') ' + errText.slice(0, 900)));
  proc.on('error', error => fail(error.message));
}

/** `png` is a Buffer. Returns { text, lines: [{ text, bbox: {x0,y0,x1,y1}, confidence }] } in image pixels. */
function recognize(png) {
  if (!child) start();
  const id = nextId++;
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      if (!pending.has(id)) return;
      pending.delete(id);
      reject(new Error('timeout'));
      shutdown();     // a stuck engine is replaced on the next request
    }, timeoutMs);
    pending.set(id, { resolve, reject, timer });
    child.send({
      id, png: png.toString('base64'),
      langPath: path.join(__dirname, '..', 'tessdata'),
      cachePath: path.join(app.getPath('userData'), 'ocr-cache'),
    });
  });
}

/** Starts the engine and loads the language data in the background, so the first real request is fast. */
function warmUp(png) { recognize(png).catch(() => { /* a failure here shows up again, with a message, on the real request */ }); }

function shutdown() {
  if (!child) return;
  const proc = child; child = null;
  for (const job of pending.values()) { clearTimeout(job.timer); job.reject(new Error('OCR stopped')); }
  pending.clear();
  try { proc.kill(); } catch { /* gone */ }
}

module.exports = { recognize, warmUp, shutdown, setTimeoutMs: ms => { timeoutMs = ms; } };
