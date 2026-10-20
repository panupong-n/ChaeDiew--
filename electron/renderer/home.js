'use strict';
const api = window.tenix, mac = api.platform === 'darwin', mod = mac ? '⌘⇧' : 'Ctrl+Shift+';
document.getElementById('k-area').textContent = mod + '2';
document.getElementById('k-full').textContent = mod + '1';
document.getElementById('k-open').textContent = mac ? '⌘O' : 'Ctrl+O';
document.getElementById('area').onclick = () => api.home.capture('area');
document.getElementById('full').onclick = () => api.home.capture('full');
document.getElementById('open').onclick = () => api.home.openFile();
document.getElementById('license').onclick = () => api.openLicense();
document.querySelectorAll('[data-lang]').forEach(b => {
  b.setAttribute('aria-checked', String(b.dataset.lang === api.lang));
  b.onclick = () => api.home.setLanguage(b.dataset.lang);
});
async function status() {
  const s = await api.license.status(), el = document.getElementById('status');
  let text, cls = '';
  if (s.state === 'licensed') { text = t('Licensed to') + ': <b></b>'; cls = 'ok'; }
  else if (s.state === 'needsActivation') { text = '<b></b>'; }
  else if (s.state === 'trial') { text = '<b></b>'; }
  else { text = '<b></b>'; cls = 'warn'; }
  el.className = 'status ' + cls; el.innerHTML = text;
  el.querySelector('b').textContent = s.state === 'licensed' ? s.info.licensee : s.state === 'needsActivation' ? t('Activation needed')
    : s.state === 'trial' ? t('Free trial — %d days left').replace('%d', s.daysLeft) : s.state === 'trialEnded' ? t('Trial ended') : t('Key not usable');
}
api.onLicenseChanged(status); status();
