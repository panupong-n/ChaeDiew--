'use strict';
(() => {
  const { t } = window;
  const api = window.tenix.license;
  const $ = id => document.getElementById(id);
  const dateText = iso => {
    if (!iso) return t('Never');
    const d = new Date(iso);
    return d.toLocaleDateString(window.tenix.lang === 'th' ? 'th-TH-u-ca-gregory' : 'en-GB', { year: 'numeric', month: 'short', day: 'numeric' });
  };
  const ERRORS = {
    malformed: 'This is not a Tenix-ChaeDiew license key (check for missing or extra characters).',
    unsupportedVersion: 'This key was made for a newer version of Tenix-ChaeDiew.',
    badSignature: 'The key is not genuine (its signature does not match).',
    expired: 'This key has expired.',
    activationNeedsKey: 'Enter the license key first, then the activation code.',
    wrongActivation: 'This activation code is not for this key on this computer.',
  };
  const el = (tag, props = {}, ...kids) => { const e = Object.assign(document.createElement(tag), props); e.append(...kids); return e; };
  const row = (dl, label, value, mono) => { dl.append(el('dt', { textContent: t(label) }), el('dd', { textContent: value, className: mono ? 'mono' : '' })); };
  const CHECK = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l5 5 9-10.5"/></svg>';
  /** Machine code with a Copy button (the text sent to the issuer: key ID, when there is one, and the machine code). */
  function machineRow(dl, s) {
    dl.append(el('dt', { textContent: t('Machine code') }));
    const copy = el('button', { className: 'btn', id: 'copy-machine', textContent: t('Copy') });
    copy.addEventListener('click', async () => {
      await window.tenix.copyText((s.info ? `Key ID: ${s.info.keyID}\n` : '') + `Machine code: ${s.machineCode}`);
      copy.innerHTML = CHECK; copy.setAttribute('aria-label', t('Copied to clipboard'));
      setTimeout(() => { copy.textContent = t('Copy'); copy.removeAttribute('aria-label'); }, 1200);
    });
    dl.append(el('dd', { className: 'copyline' }, el('span', { className: 'mono', textContent: s.machineCode }), copy));
  }

  async function render() {
    const s = await api.status();
    const box = $('status'); box.textContent = '';
    $('remove').hidden = !s.hasKey;
    // Once activated there is nothing left to enter: only Remove license stays.
    const done = s.state === 'licensed';
    // The box takes a key; the activation-code wording only appears when a key is waiting for its code.
    const waiting = s.state === 'needsActivation';
    $('key').previousElementSibling.textContent = t(waiting ? 'License key or activation code' : 'License key');
    $('key').placeholder = waiting ? 'TXCD1-…  /  TXAC1-…' : 'TXCD1-…';
    for (const n of [$('entry-rule'), $('key').previousElementSibling, $('key'), $('activate'), $('paste')]) n.hidden = done;
    if (s.state === 'licensed') {
      const h = el('h2', { className: 'ok' }); h.innerHTML = CHECK; h.append(t('Licensed'));
      box.append(h);
      const dl = el('dl'); row(dl, 'Licensed to', s.info.licensee); row(dl, 'Expires', dateText(s.info.expires));
      row(dl, 'Key ID', s.info.keyID, true); box.append(dl);
    } else if (s.state === 'needsActivation') {
      box.append(el('h2', { className: 'info', textContent: t('Activation needed') }),
        el('p', { textContent: t("One key works on one computer. Send the key ID and this computer's machine code to the issuer, then paste the activation code you get back below.") }));
      const dl = el('dl'); row(dl, 'Licensed to', s.info.licensee); row(dl, 'Key ID', s.info.keyID, true);
      machineRow(dl, s);
      box.append(dl);
    } else if (s.state === 'trial') {
      box.append(el('h2', { className: 'info', textContent: t('Free trial — %d days left').replace('%d', s.daysLeft) }));
    } else if (s.state === 'trialEnded') {
      box.append(el('h2', { className: 'warn', textContent: t('Trial ended') }),
        el('p', { textContent: t('Capturing and editing still work. Enter a license key to copy, save, upload, pin and print.') }));
    } else {
      box.append(el('h2', { className: 'warn', textContent: t('Key not usable') }), el('p', { textContent: t(ERRORS[s.error] || ERRORS.malformed) }));
    }
  }

  async function activate() {
    const text = $('key').value.trim();
    if (!text) return;
    const res = await api.activate(text);
    const msg = $('msg');
    msg.className = 'msg ' + (res.ok ? 'good' : 'bad');
    $('key').classList.toggle('bad', !res.ok);
    if (res.ok) { msg.textContent = res.activated ? t('Activated for %@').replace('%@', res.info.licensee) : t('Key accepted. Now enter the activation code for this computer.'); $('key').value = ''; }
    else msg.textContent = t(ERRORS[res.code] || ERRORS.malformed);
    render();
  }

  $('activate').addEventListener('click', activate);
  $('paste').addEventListener('click', async () => { try { $('key').value = await navigator.clipboard.readText(); } catch { $('key').focus(); } });
  $('remove').addEventListener('click', async () => { await api.remove(); $('msg').textContent = ''; render(); });
  $('key').addEventListener('keydown', e => { if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) activate(); });
  window.tenix.onLicenseChanged(render);
  const reason = new URLSearchParams(location.search).get('reason');
  if (reason) { $('reason').hidden = false; $('reason').textContent = t(reason); }
  render();
})();
