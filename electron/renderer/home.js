'use strict';
const api = window.tenix, mac = api.platform === 'darwin';
document.getElementById('k-open').textContent = mac ? '⌘O' : 'Ctrl+O';
document.getElementById('area').onclick = () => api.home.capture('area');
document.getElementById('full').onclick = () => api.home.capture('full');
document.getElementById('scroll').onclick = () => api.home.capture('scroll');
document.getElementById('history').onclick = () => api.openLibrary();
document.getElementById('open').onclick = () => api.home.openFile();
document.getElementById('license').onclick = () => api.openLicense();
document.getElementById('settings').onclick = () => api.openSettings();
document.getElementById('hk-fix').onclick = () => api.openSettings();
document.querySelector('.ver').textContent = 'v' + api.version;
document.querySelectorAll('[data-lang]').forEach(b => {
  b.setAttribute('aria-checked', String(b.dataset.lang === api.lang));
  b.onclick = () => api.home.setLanguage(b.dataset.lang);
});

/** Shows the shortcuts that are really active; one another program already owns is struck through and explained. */
async function shortcuts() {
  const hk = await api.home.hotkeys();
  const failed = [];
  for (const mode of ['area', 'full', 'scroll']) {
    const k = document.getElementById('k-' + mode), s = hk[mode];
    const set = !!(s && s.accel);         // scrolling capture has no shortcut unless one is chosen
    k.textContent = set ? s.label : '';
    k.classList.toggle('off', set && !s.ok);
    k.title = set && !s.ok ? t('Not available: another program uses this shortcut') : '';
    if (set && !s.ok) failed.push(s.label);
  }
  document.getElementById('hk-warn').hidden = !failed.length;
  document.getElementById('hk-warn-text').textContent = (failed.length > 1 ? t('Shortcuts %@ are used by another program, so they do nothing.')
    : t('Shortcut %@ is used by another program, so it does nothing.')).replace('%@', failed.join(', '));
}

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
api.onSettingsChanged(shortcuts); shortcuts();
