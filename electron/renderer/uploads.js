'use strict';
// Uploaded links (native UploadHistory): newest first; copy, open or remove each.
(() => {
  const api = window.tenix.uploads, $ = id => document.getElementById(id);
  const locale = window.tenix.lang === 'th' ? 'th-TH' : 'en-GB';
  const el = (tag, props = {}, ...kids) => { const e = Object.assign(document.createElement(tag), props); e.append(...kids); return e; };
  document.title = t('Uploaded links');
  async function render() {
    const list = await api.list(), rows = $('rows');
    rows.textContent = '';
    $('empty').hidden = list.length > 0;
    for (const r of list) {
      const btn = (label, fn) => { const b = el('button', { textContent: t(label), type: 'button' }); b.onclick = fn; return b; };
      const copy = btn('Copy link', async () => { await api.copy(r.id); copy.textContent = t('Copied'); setTimeout(() => (copy.textContent = t('Copy link')), 1200); });
      rows.append(el('div', { className: 'link' },
        el('span', { className: 'url', textContent: r.url, title: r.url }),
        el('span', { className: 'when', textContent: `${new Date(r.date).toLocaleString(locale, { dateStyle: 'medium', timeStyle: 'short' })} · ${r.name}` }),
        el('div', { className: 'acts' }, copy, btn('Open', () => api.open(r.id)), btn('Remove', () => api.remove(r.id)))));
    }
  }
  $('clear').onclick = async () => { if (confirm(t('Clear the list of uploaded links?'))) await api.clear(); };
  window.tenix.onUploadsChanged(render);
  render();
})();
