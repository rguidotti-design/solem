// SOLEM Dashboard — client logic.
// Vanilla JS, zero dependencies, polling 5s.

const API = '';  // same-origin
const REFRESH_MS = 5000;

let state = {
  manifest: null,
  capabilities: [],
  identity: null,
  devices: [],
  capFilter: 'all',
};

// ── Helpers ──────────────────────────────────────────────────────────
const $ = (sel) => document.querySelector(sel);
const $$ = (sel) => document.querySelectorAll(sel);

async function api(path, opts) {
  try {
    const r = await fetch(API + path, opts);
    if (!r.ok) throw new Error(`${r.status} ${r.statusText}`);
    return await r.json();
  } catch (e) {
    console.error(`[solem] ${path}:`, e);
    return null;
  }
}

function fmt(v) { return v == null ? '—' : String(v); }

function fmtUptime(seconds) {
  if (!seconds) return '—';
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (d > 0) return `${d}d ${h}h ${m}m`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m ${seconds % 60}s`;
}

function fmtDate(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('it-IT', { hour12: false });
}

function tagFor(status) {
  return `<span class="tag-${status}">${status}</span>`;
}

// ── Data loaders ─────────────────────────────────────────────────────
async function loadManifest() {
  state.manifest = await api('/solem/manifest');
  renderOverview();
  renderLayers();
  renderServices();
}

async function loadCapabilities() {
  const r = await api('/solem/capabilities');
  state.capabilities = r ? r.capabilities : [];
  renderCapabilities();
}

async function loadIdentity() {
  state.identity = await api('/solem/identity/me');
  renderIdentity();
}

async function loadDevices() {
  const r = await api('/solem/pairing/devices');
  state.devices = r ? r.devices : [];
  renderDevices();
}

// ── Renderers ────────────────────────────────────────────────────────
function renderOverview() {
  const m = state.manifest;
  if (!m) return;

  $('#ov-name').textContent = m.name;
  $('#ov-version').textContent = m.version;
  $('#ov-step').textContent = m.step;
  $('#ov-primary-ai').textContent = m.primary_ai;
  $('#footer-version').textContent = m.version;

  const rt = m.runtime || {};
  $('#ov-uptime').textContent = fmtUptime(rt.uptime_seconds);
  $('#ov-memory').textContent = rt.memory_mb ? `${rt.memory_mb} MB` : '—';
  $('#ov-disk').textContent = rt.disk_free_gb != null ? `${rt.disk_free_gb} GB liberi` : '—';
  $('#ov-services-count').textContent = (rt.active_services || []).length;

  const eps = $('#ov-endpoints');
  eps.innerHTML = '';
  Object.entries(m.services || {}).forEach(([name, url]) => {
    const li = document.createElement('li');
    li.innerHTML = `<span class="ep-name">${name}</span><span class="ep-url">${url}</span>`;
    eps.appendChild(li);
  });

  // Layer bar (compact overview)
  const bar = $('#ov-layer-bar');
  bar.innerHTML = '';
  (m.layers || []).forEach(l => {
    const cell = document.createElement('div');
    cell.className = 'layer-cell';
    cell.innerHTML = `
      <span class="lb-l">${l.layer}</span>
      <div class="lb-name">${l.name}</div>
      <div class="lb-status">${tagFor(l.status)}</div>
    `;
    bar.appendChild(cell);
  });

  // Top status
  $('#topStatus').querySelector('.dot').className = 'dot dot-ok';
  $('#topStatusText').textContent = `up · ${m.name} ${m.version} · ${m.profile || 'minimal'}`;

  // Aggiorna anche Settings tab che dipende dal manifest
  renderSettings();
}

function renderLayers() {
  const m = state.manifest;
  if (!m) return;
  const tb = $('#layers-table');
  tb.innerHTML = '';
  (m.layers || []).forEach(l => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${l.layer}</td>
      <td>${l.name}</td>
      <td>${tagFor(l.status)}</td>
      <td style="font-family:var(--sans); font-size:12px;">${l.description}</td>
    `;
    tb.appendChild(tr);
  });
}

function renderServices() {
  const m = state.manifest;
  if (!m) return;
  const tb = $('#services-table');
  tb.innerHTML = '';
  const active = new Set(m.runtime?.active_services || []);
  ['gavio', 'solem-api', 'ollama', 'docker', 'caddy', 'systemd-resolved'].forEach(svc => {
    const isUp = active.has(svc);
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${svc}</td>
      <td>${isUp ? '<span class="tag-ok">active</span>' : '<span class="tag-down">down</span>'}</td>
    `;
    tb.appendChild(tr);
  });
}

function renderCapabilities() {
  const caps = state.capabilities;
  // Update counts
  $('#cap-count-all').textContent = caps.length;
  $('#cap-count-solem').textContent = caps.filter(c => c.source === 'solem').length;
  $('#cap-count-gavio').textContent = caps.filter(c => c.source === 'gavio').length;
  $('#cap-count-extension').textContent = caps.filter(c => c.source === 'extension').length;

  const tb = $('#capabilities-table');
  tb.innerHTML = '';
  const filtered = state.capFilter === 'all'
    ? caps
    : caps.filter(c => c.source === state.capFilter);

  filtered.forEach(c => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${c.id}</td>
      <td style="font-family:var(--sans);">${c.name}</td>
      <td><span class="tag-${c.source === 'solem' ? 'active' : 'partial'}">${c.source}</span></td>
      <td>${c.permission_required}</td>
    `;
    tb.appendChild(tr);
  });
}

function renderSettings() {
  const m = state.manifest;
  if (!m) return;
  $('#set-profile').textContent = m.profile || 'minimal';
  const currentProfile = m.profile || 'minimal';

  // Evidenzia chip profilo corrente
  $$('.cap-filter .chip[data-profile]').forEach(c => {
    c.classList.toggle('active', c.dataset.profile === currentProfile);
  });

  const tb = $('#set-modules');
  tb.innerHTML = '';
  Object.entries(m.modules || {}).forEach(([name, active]) => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${name}</td>
      <td>${active ? '<span class="tag-ok">on</span>' : '<span class="tag-stub">off</span>'}</td>
    `;
    tb.appendChild(tr);
  });
}

async function changeProfile(profile) {
  const result = $('#profile-result');
  result.innerHTML = `<span style="color:var(--gold)">cambio a "${profile}"... (richiede rebuild)</span>`;
  const r = await api('/solem/system/profile', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({ profile, apply_now: false }),
  });
  if (!r) {
    result.innerHTML = `<span style="color:var(--err)">errore — vedi console</span>`;
    return;
  }
  if (r.profile_written) {
    result.innerHTML = `<span style="color:var(--ok)">profilo scritto: ${r.profile_written}</span><br><span class="muted">${r.next_step || ''}</span>`;
  } else {
    result.innerHTML = `<pre style="color:var(--text-mute); font-size:10px;">${JSON.stringify(r, null, 2)}</pre>`;
  }
}

function renderIdentity() {
  const id = state.identity;
  if (!id) return;
  const dl = $('#identity-dl');
  // Estrai roles dalla sezione standard se presente
  const rolesSection = (id.sections && id.sections.roles && id.sections.roles.content) || [];
  const rolesStr = Array.isArray(rolesSection) ? rolesSection.join(', ') : JSON.stringify(rolesSection);
  const sectionCount = id.sections ? Object.keys(id.sections).length : 0;
  dl.innerHTML = `
    <dt>User ID</dt><dd>${id.user_id}</dd>
    <dt>Nome</dt><dd>${id.name}</dd>
    <dt>Email</dt><dd>${id.email}</dd>
    <dt>Ruoli</dt><dd>${rolesStr || '<span style="color:var(--text-mute)">(vuoto, edita in /solem/identity/sections/roles)</span>'}</dd>
    <dt>Sezioni</dt><dd>${sectionCount} <span style="color:var(--text-mute)">(${id.sections ? Object.keys(id.sections).join(', ') : '—'})</span></dd>
    <dt>Aggiornato</dt><dd>${id.updated_at || '—'}</dd>
  `;
}

function renderDevices() {
  const devices = state.devices;
  const tb = $('#devices-table');
  const empty = $('#devices-empty');
  tb.innerHTML = '';
  if (devices.length === 0) {
    empty.hidden = false;
    return;
  }
  empty.hidden = true;
  devices.forEach(d => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${d.name}</td>
      <td>${d.assigned_ip}</td>
      <td>${fmtDate(d.paired_at)}</td>
    `;
    tb.appendChild(tr);
  });
}

// ── Pairing PIN generator ────────────────────────────────────────────
async function genPin() {
  const btn = $('#btn-gen-pin');
  btn.disabled = true;
  btn.textContent = 'Generazione…';
  const r = await api('/solem/pairing/start', { method: 'POST' });
  btn.disabled = false;
  btn.textContent = 'Genera nuovo PIN';
  if (!r) return;
  $('#pin-display').hidden = false;
  $('#pin-code').textContent = r.pin;
  $('#pin-expires').textContent = fmtDate(r.expires_at);
  $('#pin-instructions').textContent = r.instructions;
}

// ── Tabs ─────────────────────────────────────────────────────────────
function setTab(name) {
  $$('.tab').forEach(t => t.classList.remove('active'));
  $$('.nav-item').forEach(n => n.classList.remove('active'));
  $(`#tab-${name}`).classList.add('active');
  $(`.nav-item[data-tab="${name}"]`).classList.add('active');
}

function setCapFilter(source) {
  state.capFilter = source;
  $$('.cap-filter .chip').forEach(c => c.classList.remove('active'));
  $(`.cap-filter .chip[data-source="${source}"]`).classList.add('active');
  renderCapabilities();
}

// ── Bootstrap ────────────────────────────────────────────────────────
function refreshAll() {
  loadManifest();
  loadCapabilities();
  loadIdentity();
  loadDevices();
}

document.addEventListener('DOMContentLoaded', () => {
  $$('.nav-item').forEach(n => {
    n.addEventListener('click', () => setTab(n.dataset.tab));
  });

  $$('.cap-filter .chip').forEach(c => {
    c.addEventListener('click', () => setCapFilter(c.dataset.source));
  });

  $('#btn-gen-pin').addEventListener('click', genPin);

  // Settings: button profilo
  $$('.cap-filter .chip[data-profile]').forEach(b => {
    b.addEventListener('click', () => changeProfile(b.dataset.profile));
  });

  refreshAll();
  setInterval(refreshAll, REFRESH_MS);
});
