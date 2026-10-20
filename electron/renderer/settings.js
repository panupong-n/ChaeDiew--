'use strict';
(() => {
  const api = window.tenix, S = api.settings;
  const $ = id => document.getElementById(id);
  const OK = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l5 5 9-10.5"/></svg>';
  const WARN = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 4l9 16H3z"/><path d="M12 10v4.5M12 17.5v.01"/></svg>';
  $('lang').setAttribute('aria-label', t('Language'));
  $('format').setAttribute('aria-label', t('Format'));
  if (api.platform !== 'win32') $('prtscn-note').hidden = true;
  let current = null, recording = null;
  const MODES = ['area', 'full', 'scroll'];
  const days = { 7: t('7 days'), 30: t('30 days'), 90: t('90 days'), 0: t('Never') };
  document.querySelectorAll('#lib-days button').forEach(b => { b.textContent = days[b.dataset.v]; });
  $('lib-days').setAttribute('aria-label', t('Delete captures after'));
  $('up-mode').setAttribute('aria-label', t('Upload to'));

  function seg(el, value) { el.querySelectorAll('button').forEach(b => b.setAttribute('aria-checked', String(b.dataset.v === value))); }
  function render(s) {
    current = s;
    seg($('lang'), s.lang); seg($('format'), s.format);
    $('login').setAttribute('aria-checked', String(!!s.openAtLogin));
    $('ask').setAttribute('aria-checked', String(!!s.askWhere));
    $('ask-note').textContent = s.askWhere ? '' : t('Save puts the file straight into the folder above.');
    $('dir').textContent = s.saveDir; $('dir').title = s.saveDir;
    for (const mode of MODES) {
      if (recording === mode) continue;
      const h = s.hotkeys[mode] || {}, key = $('key-' + mode), st = $('st-' + mode), set = !!h.accel;
      key.textContent = set ? h.label : t('None'); key.classList.remove('recording'); key.classList.toggle('off', set && !h.ok);
      st.className = 'state ' + (!set ? '' : h.ok ? 'ok' : 'bad');
      st.innerHTML = !set ? '' : h.ok ? OK : WARN;
      if (set) st.append(h.ok ? t('Ready') : t('Used by another program'));
    }
    // History
    $('lib-on').setAttribute('aria-checked', String(!!s.library.enabled));
    seg($('lib-days'), String(s.library.retentionDays));
    $('lib-count').textContent = t('%d captures kept').replace('%d', s.library.count);
    // Upload
    const u = s.upload;
    seg($('up-mode'), u.mode);
    $('up-s3').hidden = u.mode !== 's3'; $('up-http').hidden = u.mode !== 'http'; $('up-test-row').hidden = u.mode === 'none';
    for (const input of document.querySelectorAll('#up-s3 [data-k]')) if (document.activeElement !== input) input.value = u.s3[input.dataset.k] == null ? '' : u.s3[input.dataset.k];
    $('s3-secret').placeholder = u.s3.hasSecret ? t('Saved — type to replace') : '';
    if (document.activeElement !== $('http-url')) $('http-url').value = u.http.url || '';
    $('http-token').placeholder = u.http.hasToken ? t('Saved — type to replace') : '';
    // Hide PII kinds: a switch each, all on unless turned off.
    const on = new Set(s.pii.enabled || window.PII.BUILTINS.map(p => p.id)), kinds = $('pii-kinds');
    kinds.textContent = '';
    for (const p of window.PII.BUILTINS) {
      const row = Object.assign(document.createElement('div'), { className: 'check' });
      const sw = Object.assign(document.createElement('button'), { className: 'switch', type: 'button', id: 'pii-' + p.id });
      sw.setAttribute('role', 'switch'); sw.setAttribute('aria-checked', String(on.has(p.id)));
      const label = Object.assign(document.createElement('span'), { id: 'pii-l-' + p.id, textContent: t(p.name) });
      sw.setAttribute('aria-labelledby', label.id);
      sw.addEventListener('click', async () => {
        on.has(p.id) ? on.delete(p.id) : on.add(p.id);
        render(await S.set({ piiEnabled: window.PII.BUILTINS.map(b => b.id).filter(id => on.has(id)) }));
      });
      row.append(sw, label); kinds.append(row);
    }
    if (document.activeElement !== $('pii-custom')) $('pii-custom').value = (s.pii.custom || []).join('\n');
    const presets = $('presets'); presets.textContent = '';
    for (const p of s.presets) {
      const b = Object.assign(document.createElement('button'), { className: 'btn', textContent: p.label, type: 'button' });
      b.addEventListener('click', async () => { $('key-msg').textContent = ''; render(await S.set({ hotkeys: { area: p.area, full: p.full } })); });
      presets.append(b);
    }
  }

  // ---- shortcut recording: press the new combination; Esc or clicking away cancels
  async function startRecording(mode) {
    if (recording) await stopRecording();
    recording = mode;
    await S.pauseHotkeys();
    const key = $('key-' + mode);
    key.textContent = t('Press the new shortcut…'); key.classList.add('recording'); key.classList.remove('off');
    $('key-msg').textContent = '';
    key.focus();
  }
  async function stopRecording() {
    if (!recording) return;
    recording = null;
    await S.resumeHotkeys();
    render(await S.get());
  }
  document.querySelectorAll('[data-record]').forEach(b => b.addEventListener('click', () => startRecording(b.dataset.record)));
  for (const mode of MODES) {
    const key = $('key-' + mode);
    key.addEventListener('blur', () => { if (recording === mode) stopRecording(); });
    key.addEventListener('keydown', async e => {
      if (recording !== mode) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); startRecording(mode); } return; }
      e.preventDefault(); e.stopPropagation();
      const plain = !e.ctrlKey && !e.altKey && !e.shiftKey && !e.metaKey;
      if (e.key === 'Escape' && plain) { stopRecording(); return; }
      if ((e.key === 'Backspace' || e.key === 'Delete') && plain) {      // no shortcut for this capture
        recording = null; await S.set({ hotkeys: { [mode]: '' } }); await S.resumeHotkeys(); render(await S.get()); return;
      }
      const res = await S.keyToAccelerator({ code: e.code, ctrlKey: e.ctrlKey, altKey: e.altKey, shiftKey: e.shiftKey, metaKey: e.metaKey });
      if (!res) return;     // only modifiers so far, or not allowed (a plain letter)
      recording = null;
      const s = await S.set({ hotkeys: { [mode]: res.accel } });
      if (s.errors && s.errors.hotkeys === 'duplicate') $('key-msg').textContent = t('Two captures cannot use the same shortcut.');
      await S.resumeHotkeys();
      render(await S.get());
    });
    // Print Screen only sends keyup on Windows.
    key.addEventListener('keyup', async e => {
      if (recording !== mode || e.code !== 'PrintScreen') return;
      const res = await S.keyToAccelerator({ code: e.code, ctrlKey: e.ctrlKey, altKey: e.altKey, shiftKey: e.shiftKey, metaKey: e.metaKey });
      if (!res) return;
      recording = null;
      await S.set({ hotkeys: { [mode]: res.accel } });
      await S.resumeHotkeys();
      render(await S.get());
    });
  }

  // ---- the rest apply on click
  $('lang').addEventListener('click', async e => { const v = e.target.dataset && e.target.dataset.v; if (v && v !== current.lang) await S.set({ lang: v }); });
  $('format').addEventListener('click', async e => { const v = e.target.dataset && e.target.dataset.v; if (v) render(await S.set({ format: v })); });
  $('login').addEventListener('click', async () => render(await S.set({ openAtLogin: !current.openAtLogin })));
  $('ask').addEventListener('click', async () => render(await S.set({ askWhere: !current.askWhere })));
  $('choose').addEventListener('click', async () => render(await S.chooseFolder()));
  $('open-dir').addEventListener('click', () => S.openFolder());
  // Own patterns are saved when the field is left; a line that is not a valid regular expression is named and not used.
  $('pii-custom').addEventListener('change', async () => {
    const lines = $('pii-custom').value.split('\n').map(l => l.trim()).filter(Boolean);
    const bad = lines.filter(l => { try { new RegExp(l); return false; } catch { return true; } });
    $('pii-msg').textContent = bad.length ? t('Not a valid pattern, so it is skipped: %@').replace('%@', bad.join(', ')) : '';
    render(await S.set({ piiCustom: lines }));
  });
  // History
  $('lib-on').addEventListener('click', async () => render(await S.set({ libraryEnabled: !current.library.enabled })));
  $('lib-days').addEventListener('click', async e => { const v = e.target.dataset && e.target.dataset.v; if (v != null) render(await S.set({ libraryRetentionDays: Number(v) })); });
  $('lib-open').addEventListener('click', () => api.openLibrary());
  // Upload: values save when a field is left; the secret and the token only when something is typed (they are never shown again).
  $('up-mode').addEventListener('click', async e => { const v = e.target.dataset && e.target.dataset.v; if (v) render(await S.set({ upload: { mode: v } })); });
  for (const input of document.querySelectorAll('#up-s3 [data-k]')) input.addEventListener('change', async () => render(await S.set({ upload: { s3: { [input.dataset.k]: input.value } } })));
  $('s3-secret').addEventListener('change', async () => { if ($('s3-secret').value) { await S.set({ upload: { s3: { secretKey: $('s3-secret').value } } }); $('s3-secret').value = ''; render(await S.get()); } });
  $('http-url').addEventListener('change', async () => render(await S.set({ upload: { http: { url: $('http-url').value } } })));
  $('http-token').addEventListener('change', async () => { if ($('http-token').value) { await S.set({ upload: { http: { token: $('http-token').value } } }); $('http-token').value = ''; render(await S.get()); } });
  $('up-test').addEventListener('click', async () => {
    $('up-msg').textContent = t('Uploading…');
    const r = await api.upload.test();
    $('up-msg').textContent = r.ok ? t('Works — link copied') + ': ' + r.url : (r.error === 'license' ? t('This needs a license') : r.message || r.error);
  });
  api.onSettingsChanged(async () => { if (!recording) render(await S.get()); });

  S.get().then(render);
  window.__settingsTest = { startRecording, render: () => S.get().then(render) };
})();
