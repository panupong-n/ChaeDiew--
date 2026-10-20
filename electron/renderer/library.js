'use strict';
// History (native Library): every capture, newest first, searchable by the text OCR found in it, its date or its name.
(() => {
  const api = window.tenix.library, $ = id => document.getElementById(id);
  const locale = window.tenix.lang === 'th' ? 'th-TH' : 'en-GB';     // Buddhist year in Thai, as the native app
  const when = iso => new Date(iso).toLocaleString(locale, { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
  const el = (tag, props = {}, ...kids) => { const e = Object.assign(document.createElement(tag), props); e.append(...kids); return e; };
  document.title = t('History');
  $('q').placeholder = t('Search the text in your captures, or a date (2026-10-20)');
  $('q').setAttribute('aria-label', t('Search'));

  async function render() {
    const items = await api.list($('q').value);
    const grid = $('grid'); grid.textContent = '';
    $('sub').textContent = t('%d captures · kept on this computer only').replace('%d', items.length);
    $('empty').hidden = items.length > 0;
    $('empty').textContent = $('q').value.trim() ? t('Nothing matches. Text in a capture becomes searchable a few seconds after it is taken.') : t('Captures you take appear here.');
    for (const it of items) {
      const img = el('img', { src: it.thumb, alt: '' });
      const open = el('button', { className: 'thumb', title: t('Open in the editor') }, img);
      open.setAttribute('aria-label', t('Open in the editor') + ' — ' + when(it.date));
      open.onclick = () => api.open(it.id);
      const btn = (label, fn, cls = '') => { const b = el('button', { textContent: t(label), className: cls, type: 'button' }); b.onclick = fn; return b; };
      const card = el('article', { className: 'card' }, open,
        el('div', { className: 'meta' }, el('span', { textContent: when(it.date) }), el('span', { textContent: `${it.width} × ${it.height}` })),
        el('div', { className: 'snippet', textContent: it.ocrText }),
        el('div', { className: 'acts' },
          btn('Open', () => api.open(it.id)), btn('Copy', async () => { const r = await api.copy(it.id); if (r.ok) flash(t('Copied to clipboard')); }),
          btn('Show file', () => api.reveal(it.id)), btn('Delete', async () => { await api.remove(it.id); }, 'danger')));
      card.dataset.id = it.id;
      grid.append(card);
    }
  }
  function flash(text) { $('sub').textContent = text; setTimeout(render, 1400); }
  let timer = null;
  $('q').addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(render, 150); });
  $('clear').onclick = async () => { if (confirm(t('Delete every capture in the history? This cannot be undone.'))) await api.clear(); };
  window.tenix.onLibraryChanged(render);
  render();
  window.__libraryTest = { render, search: q => { $('q').value = q; return render(); } };
})();
