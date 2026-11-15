const byId = (id) => document.getElementById(id);
const cards = new Map();

async function request(path, options = {}) {
  const response = await fetch(path, { ...options, signal: AbortSignal.timeout(60000) });
  const result = await response.json();
  if (!response.ok) {
    const error = new Error(result.error || 'The service could not complete this request.');
    error.result = result;
    throw error;
  }
  return result;
}

function post(path, body) {
  return request(path, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
}

function makeCard(router) {
  const element = byId('router-template').content.firstElementChild.cloneNode(true);
  element.dataset.router = router.id;
  const find = (role) => element.querySelector(`[data-role="${role}"]`);
  const card = { element, find, router, busy: false, locked: router.locked };
  find('name').textContent = router.name;
  find('id').textContent = router.id;
  find('type').textContent = router.type === 'openwrt-ubus' ? 'OpenWrt API' : 'ZTE web API';
  find('refresh').setAttribute('aria-label', `Refresh ${router.name}`);
  find('on').setAttribute('aria-label', `Turn ${router.name} Wi-Fi on`);
  find('off').setAttribute('aria-label', `Turn ${router.name} Wi-Fi off`);
  find('on').addEventListener('click', () => update(card, 'wifi', true));
  find('off').addEventListener('click', () => update(card, 'wifi', false));
  find('refresh').addEventListener('click', () => update(card));
  find('lock').addEventListener('click', () => update(card, 'lock', !card.locked));
  renderLock(card, router.locked);
  byId('routers').append(element);
  cards.set(router.id, card);
  return card;
}

function renderLock(card, locked) {
  card.locked = locked;
  card.find('lock').setAttribute('aria-pressed', String(locked));
  card.find('lock').setAttribute('aria-label', `${locked ? 'Resume' : 'Pause'} scheduled changes for ${card.router.name}`);
  card.find('lock-label').textContent = locked ? 'Scheduled changes paused' : 'Scheduled changes active';
  card.find('lock-action').textContent = locked ? 'Resume' : 'Pause';
  card.find('lock-note').textContent = locked
    ? 'This router skips the timers. Manual buttons still work.'
    : 'Daily timers apply. Manual buttons always work.';
}

function feedback(card, text, error = false) {
  card.find('feedback').textContent = text;
  card.find('feedback').classList.toggle('error', error);
}

function renderRadios(card, radios) {
  const managed = radios.filter((radio) => !radio.configuredDisabled);
  const enabled = managed.filter((radio) => radio.enabled).length;
  const pending = radios.some((radio) => radio.pending);
  const state = pending ? 'pending' : enabled === 0 ? 'off' : enabled === managed.length ? 'on' : 'mixed';
  card.element.dataset.state = state;
  card.find('status').textContent = pending ? 'Wi-Fi is changing.' : state === 'mixed' ? 'Some bands are on.' : `Wi-Fi is ${state}.`;
  card.find('radios').replaceChildren();
  for (const radio of radios) {
    const row = document.createElement('div');
    const band = document.createElement('dt');
    const status = document.createElement('dd');
    band.textContent = radio.band;
    band.title = radio.id;
    status.textContent = radio.pending ? 'Updating…' : radio.enabled ? 'Enabled' : radio.configuredDisabled ? 'Configured off' : 'Disabled';
    row.append(band, status);
    card.find('radios').append(row);
  }
  card.find('checked').textContent = `Last confirmed ${new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' })}`;
}

async function update(card, action = 'status', value) {
  if (card.busy) return;
  card.busy = true;
  const buttons = [...card.element.querySelectorAll('button')];
  buttons.forEach((button) => { button.disabled = true; });
  const path = `/api/routers/${encodeURIComponent(card.router.id)}/${action}`;
  feedback(card, action === 'wifi' ? `Turning Wi-Fi ${value ? 'on' : 'off'}…` : action === 'lock' ? 'Saving schedule lock…' : 'Reading radio status…');
  try {
    const result = action === 'status' ? await request(path)
      : await post(path, action === 'lock' ? { locked: value } : { enabled: value });
    renderLock(card, result.locked);
    if (result.radios) renderRadios(card, result.radios);
    if (action === 'lock') {
      feedback(card, value ? 'Scheduled changes paused. The current Wi-Fi state is unchanged.' : 'Schedule resumed. The next daily event will apply; Wi-Fi stays as it is for now.');
    } else if (result.radios.some((radio) => radio.pending)) {
      feedback(card, 'The router is updating its radios. Refresh to check when they are ready.');
    } else if (action === 'status') {
      feedback(card, 'Radio states confirmed.');
    } else if (!result.changed) {
      feedback(card, `Already ${value ? 'on' : 'off'}. No router settings changed.`);
    } else {
      feedback(card, value ? 'Wi-Fi enabled. Networks may take a little time to appear.' : 'Wi-Fi disabled. The daily timers are unchanged.');
    }
  } catch (error) {
    if (typeof error.result?.locked === 'boolean') renderLock(card, error.result.locked);
    if (action !== 'lock') {
      card.element.dataset.state = 'unknown';
      card.find('status').textContent = 'State unconfirmed.';
      card.find('radios').replaceChildren();
    }
    feedback(card, error.name === 'TimeoutError'
      ? 'The connection timed out. Use Ethernet or mobile data with Tailscale if Wi-Fi was switched off.'
      : error.message, true);
  } finally {
    card.busy = false;
    buttons.forEach((button) => { button.disabled = false; });
  }
}

function renderSchedule({ schedule, next }) {
  byId('timezone').textContent = schedule.timezone;
  byId('on-time').textContent = schedule.on;
  byId('off-time').textContent = schedule.off;
  const formatter = new Intl.DateTimeFormat('en-GB', {
    timeZone: schedule.timezone, weekday: 'short', hour: '2-digit', minute: '2-digit', timeZoneName: 'short',
  });
  byId('next-event').textContent = `Next: Wi-Fi ${next.enabled ? 'on' : 'off'} · ${formatter.format(new Date(next.at))} · unlocked routers`;
}

async function initialize() {
  try {
    const config = await request('/api/config');
    renderSchedule(config);
    for (const router of config.routers) update(makeCard(router));
  } catch {
    byId('page-error').textContent = 'Could not load the controller configuration. Reload this page to retry.';
    byId('page-error').hidden = false;
  }
}

initialize();
setInterval(() => {
  if (document.hidden) return;
  for (const card of cards.values()) if (!card.busy) update(card);
  request('/api/config').then(renderSchedule).catch(() => {
    byId('next-event').textContent = 'Schedule display unavailable. Refresh this page to retry.';
  });
}, 60000);
