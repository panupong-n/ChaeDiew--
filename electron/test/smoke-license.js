'use strict';
// The license window in each state, driven with a throw-away issuer (its own key pair swapped in for the run, never the real key).
// Called from test/smoke-platform.js.
const crypto = require('crypto');
const L = require('../src/license');

const EPOCH = Date.UTC(2024, 0, 1), DAY = 86400000;
const group = (text, n, prefix) => [prefix, ...text.match(new RegExp('.{1,' + n + '}', 'g'))].join('-');

async function run(h, { check, shot, sleep }) {
  const { license } = h;
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const realKey = license.publicKey;
  license.publicKey = publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
  license.remove();

  const name = Buffer.from('Test Licensee');
  const day = Math.floor((Date.now() - EPOCH) / DAY);
  const payload = Buffer.concat([Buffer.from([1, 1, 0, 1, day >> 8, day & 255, 0, 0, name.length]), name, crypto.randomBytes(6)]);
  const key = group(L.base32Encode(Buffer.concat([payload, crypto.sign(null, Buffer.concat([Buffer.from('Tenix-ChaeDiew license v1'), payload]), privateKey)])), 8, 'TXCD1');
  const keyID = L.verifyKey(key, license.publicKey).keyID;
  const act = group(L.base32Encode(crypto.sign(null, Buffer.concat([Buffer.from('Tenix-ChaeDiew activation v1'), Buffer.from(keyID, 'hex'), L.machineBytes(license.machineId())]), privateKey)), 8, 'TXAC1');

  h.showLicense(); await sleep(900);
  const lw = h.windows().licenseWindow;
  if (!lw) { check('the license window opens for the state checks', false); license.publicKey = realKey; return; }
  const view = async () => {
    lw.webContents.send('license:changed'); await sleep(600);
    return lw.webContents.executeJavaScript(`(() => {
      const shown = id => { const e = document.getElementById(id); return !!e && !e.hidden && getComputedStyle(e).display !== 'none'; };
      return { heading: (document.querySelector('#status h2') || {}).textContent || '', text: document.getElementById('status').textContent,
        entry: shown('key'), activate: shown('activate'), paste: shown('paste'), remove: shown('remove'), rule: shown('entry-rule'), label: document.getElementById('key').previousElementSibling.textContent };
    })()`);
  };

  let v = await view();
  check('no key: the trial is shown, the box is labelled "License key", no machine code, no Remove', /14/.test(v.heading) && v.entry && v.activate && !v.remove && /License key|คีย์ไลเซนส์/.test(v.label) && !/MC-/.test(v.text), v);
  await shot(lw, '25-license-trial');

  const bad = await lw.webContents.executeJavaScript(`(async () => { document.getElementById('key').value = 'TXCD1-ABCD-EFGH'; document.getElementById('activate').click(); await new Promise(r => setTimeout(r, 600)); return document.getElementById('msg').textContent; })()`);
  check('a made-up key shows a message and the app stays in the trial', bad.length > 10 && license.status().state === 'trial', bad);

  const typed = await lw.webContents.executeJavaScript(`(async () => { document.getElementById('key').value = ${JSON.stringify(key)}; document.getElementById('activate').click(); await new Promise(r => setTimeout(r, 800)); return document.getElementById('msg').textContent; })()`);
  check('typing a genuine key says it is activated for the licensee', /Test Licensee/.test(typed), typed);
  v = await view(); await shot(lw, '26-license-active');
  check('the key alone makes it Licensed, with the licensee and key ID, no trial line', !/trial|ทดลอง/i.test(v.text) && /Test Licensee/.test(v.text) && v.text.includes(keyID) && license.status().state === 'licensed', v);
  check('Licensed: no seats row, no machine code, no entry box, Activate or Paste; only Remove', !/Seats|จำนวนเครื่อง/.test(v.text) && !/MC-/.test(v.text) && !v.entry && !v.activate && !v.paste && !v.rule && v.remove, v);
  const again = new L.LicenseManager({ secrets: license.secrets, publicKey: license.publicKey, machineId: () => 'ANOTHER-COMPUTER-0001' });
  check('the stored key keeps the app licensed on a fresh start, even on another computer', again.status().state === 'licensed' && again.allowsUse);
  const home = h.windows().homeWindow;
  if (home) { await sleep(300); check('the home window says whom it is licensed to', /Test Licensee/.test(await home.webContents.executeJavaScript(`document.getElementById('status').textContent`))); }

  // the one-computer mode (kept for later) still shows its own waiting state
  license.remove(); license.requireActivation = true; license.activate(key);
  v = await view(); await shot(lw, '27-license-needs-activation');
  check('activation mode: "Activation needed", no trial line, the box stays for the code', /Activation needed|ต้องเปิดใช้งาน/i.test(v.heading) && v.entry && v.remove && !/trial|ทดลอง/i.test(v.text), v);
  license.requireActivation = false;

  license.remove();
  v = await view();
  check('removed: back to the trial with the entry box', v.entry && !v.remove, v);
  license.now = () => new Date(Date.now() + 20 * 86400000);
  const refused = await h.windows().homeWindow?.webContents.executeJavaScript(`window.tenix.gate()`);
  check('removed after the trial: copying and saving are refused and the license window opens', refused && refused.error === 'license', refused);
  license.now = () => new Date();
  license.publicKey = realKey;
  for (const w of [lw, h.windows().licenseWindow]) if (w && !w.isDestroyed()) w.close();
}
module.exports = { run };
