'use strict';
// Shared by the small windows (home, license, capture): translate helper and platform class.
window.t = key => (window.tenix.lang === 'th' && window.tenix.strings[key]) || key;
document.documentElement.lang = window.tenix.lang;
document.body.classList.add(window.tenix.platform === 'darwin' ? 'mac' : window.tenix.platform === 'win32' ? 'win' : 'other');
document.querySelectorAll('[data-t]').forEach(el => { el.textContent = window.t(el.dataset.t); });
document.querySelectorAll('[data-t-title]').forEach(el => { el.title = window.t(el.dataset.tTitle); });
document.querySelectorAll('[data-t-placeholder]').forEach(el => { el.placeholder = window.t(el.dataset.tPlaceholder); });
