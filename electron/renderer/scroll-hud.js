'use strict';
// The bar shown during a scrolling capture: how tall the picture is so far, Cancel and Done. Kept out of the screenshots.
const msg = document.getElementById('msg');
const show = h => { msg.textContent = ''; const b = document.createElement('b'); b.textContent = h + ' px'; msg.append(t('Scroll the content now') + ' · ', b); };
show(0);
window.tenix.onScrollProgress(p => show(p.height));
document.getElementById('done').onclick = () => window.tenix.scroll.done();
document.getElementById('cancel').onclick = () => window.tenix.scroll.cancel();
