'use strict';

const { formatCountdown, usageColor, sortAgents, normalizeSettings, partitionAgents, visibleMetrics, highestUsage } = window.metrics;
const panel = document.querySelector('#panel');
const header = document.querySelector('#header');
const panelStyle = getComputedStyle(panel);
const verticalBorder = parseFloat(panelStyle.borderTopWidth) + parseFloat(panelStyle.borderBottomWidth);
const summary = document.querySelector('#summary');
const updated = document.querySelector('#updated');
const toggle = document.querySelector('#toggle');
const content = document.querySelector('#content');
const connection = document.querySelector('#connection');
const announcement = document.querySelector('#announcement');
const list = document.querySelector('#agents');
const adminList = document.querySelector('#admins');
const workingGroup = { section: document.querySelector('#group-working'), button: document.querySelector('#toggle-working'), count: document.querySelector('#count-working'), list: document.querySelector('#list-working') };
const freeGroup = { section: document.querySelector('#group-free'), button: document.querySelector('#toggle-free'), count: document.querySelector('#count-free'), list: document.querySelector('#list-free') };
const detailView = document.querySelector('#detail-view');
let detailName = null; let detailTimer = null; let detailPinned = true; let detailScroll;
let captureFeed = false;

const states = {
  admin: 'Admin', idle: 'Libre', working: 'Trabajando', limited: 'Limitado',
  stuck: 'Atascado', off: 'Apagado', unknown: 'Desconocido',
};
const scale = { green: 'normal', amber: 'alto', red: 'crítico' };
const timeFormat = new Intl.DateTimeFormat('es', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
const percentFormat = new Intl.NumberFormat('es', { style: 'percent', maximumFractionDigits: 2 });

let snapshot = { data: null, disconnected: false };
let collapsed = false;
let settings = { compact: false, sort: 'urgency', opacity: 100, fontSize: 12, groupOpen: { working: true, free: false } };
const renderedAgents = new Map();
const agentFingerprints = new Map();

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function metric({ label, used, resetsAt = null, context = false }) {
  const row = element('div', `metric${context ? ' metric-context' : ''}`);
  const color = usageColor(used);
  row.append(element('span', 'metric-label', label));
  const value = used === null ? 'Sin dato' : percentFormat.format(used / 100);
  const track = element('span', 'bar-wrap');
  if (used === null) {
    track.append(element('span', 'unknown-track'));
  } else {
    const bar = element('progress', color);
    bar.max = 100;
    bar.value = used;
    bar.setAttribute('aria-label', label);
    bar.setAttribute('aria-valuetext', `${value}, uso ${scale[color]}`);
    track.append(bar);
  }
  if (context) {
    const mark = element('span', 'context-mark');
    mark.style.left = '40%';
    mark.setAttribute('aria-hidden', 'true');
    track.append(mark);
  }
  row.append(track);
  row.append(element('span', 'percent', value));
  const countdown = element('span', 'countdown');
  if (resetsAt !== null) {
    countdown.dataset.reset = resetsAt;
    countdown.title = new Date(resetsAt * 1000).toLocaleString('es');
    countdown.setAttribute('aria-label', `Se reinicia en ${formatCountdown(resetsAt)}`);
  }
  row.append(countdown);
  return row;
}

function agentCard(agent) {
  const card = element('article', `agent${settings.compact ? ' compact' : ''}`);
  const identity = element('div', 'identity');
  const identityMain = element('div', 'identity-main');
  const name = element('h2', 'agent-name', agent.name);
  name.title = agent.name;
  identityMain.append(name, element('span', `state state-${agent.state}`, states[agent.state]));
  identity.append(identityMain);
  const labels = element('div', 'identity-labels');
  labels.append(element('span', 'badge', agent.kind));
  if (agent.context !== null && agent.context > 40) labels.append(element('span', 'badge badge-warning', 'Compactará'));
  if (agent.tier === 'skip') labels.append(element('span', 'badge badge-critical', 'Skip'));
  identity.append(labels);
  if (settings.compact) {
    const usage = highestUsage(agent);
    card.append(identity, element('span', 'compact-percent', usage === null ? '—' : `${usage}%`), element('span', 'compact-tier', agent.tier || '—'));
    card.title = agent.detail || agent.name;
    return card;
  }
  card.append(identity);

  const metadata = element('div', 'metadata');
  const model = agent.model || agent.set_model || 'Modelo sin datos';
  const effort = agent.effort || agent.set_effort;
  const modelLine = element('span', 'model-badge truncate', model);
  modelLine.title = modelLine.textContent;
  metadata.append(modelLine);
  if (effort) metadata.append(element('span', 'effort-badge', effort));
  if (agent.tier) {
    const tier = element('span', `tier tier-${agent.tier}`, agent.tier);
    tier.setAttribute('aria-label', `Capacidad ${agent.tier}`);
    metadata.append(tier);
  }
  card.append(metadata);

  if (agent.project || agent.branch) {
    const contextLine = element('p', 'project truncate');
    if (agent.project) contextLine.append(element('span', 'project-name', agent.project));
    if (agent.project && agent.branch) contextLine.append(element('span', 'project-separator', ' / '));
    if (agent.branch) contextLine.append(element('span', 'branch-name', agent.branch));
    contextLine.title = [agent.project, agent.branch].filter(Boolean).join(' / ');
    card.append(contextLine);
  }
  if (agent.detail && agent.detail !== '-') {
    const detail = element('p', 'detail truncate', agent.detail);
    detail.title = agent.detail;
    card.append(detail);
  }

  const metricRows = visibleMetrics(agent);
  if (metricRows.length) {
    const metrics = element('div', 'metrics');
    const availableLimits = metricRows.filter(({ context, used }) => !context && used !== null);
    const highestLimit = availableLimits.sort((a, b) => b.used - a.used)[0];
    const tightest = highestLimit?.used >= 60 ? highestLimit.key : undefined;
    for (const rowData of metricRows) {
      const row = metric(rowData);
      if (rowData.key === tightest) row.classList.add('tightest-limit');
      metrics.append(row);
    }
    card.append(metrics);
  }

  if (agent.data_age_s !== null) {
    const stale = element('p', 'stale');
    stale.hidden = true;
    stale.dataset.age = agent.data_age_s;
    card.append(stale);
  }
  return card;
}

function reportLayout(renderedData = false) {
  const height = Math.ceil(verticalBorder + header.getBoundingClientRect().height +
    (collapsed ? 0 : content.scrollHeight));
  window.bridgeWidget.layout(height, collapsed, renderedData);
}

function updateClock() {
  const now = Date.now() / 1000;
  for (const countdown of list.querySelectorAll('[data-reset]')) {
    const remaining = formatCountdown(Number(countdown.dataset.reset), now);
    if (countdown.textContent !== remaining) countdown.textContent = remaining;
    countdown.setAttribute('aria-label', `Se reinicia en ${remaining}`);
  }
  const elapsed = snapshot.data ? Math.max(0, now - snapshot.data.time) : 0;
  let changed = false;
  for (const stale of list.querySelectorAll('[data-age]')) {
    const age = Number(stale.dataset.age) + elapsed;
    const hidden = age <= 600;
    if (stale.hidden !== hidden) {
      stale.hidden = hidden;
      changed = true;
    }
    if (!hidden) {
      const label = `Datos de hace ${Math.floor(age / 60)} min`;
      if (stale.textContent !== label) stale.textContent = label;
    }
  }
  if (changed) reportLayout();
}

function render() {
  const { data, disconnected } = snapshot;
  const agents = sortAgents(data?.agents ?? [], settings.sort);
  const working = agents.filter(({ state }) => state === 'working').length;
  const idle = agents.filter(({ state }) => state === 'idle').length;
  const alerts = agents.filter(({ state }) => ['limited', 'stuck', 'unknown'].includes(state)).length;
  const counts = data ? `${working} trabajando · ${idle} libres · ${alerts} alertas` : 'Conectando…';
  summary.textContent = collapsed && disconnected ? 'Sin conexión con el bridge' : counts;
  summary.title = collapsed && disconnected && data ? counts : '';
  summary.classList.toggle('offline', collapsed && disconnected);
  connection.hidden = !disconnected;
  const alert = collapsed && disconnected ? 'Sin conexión con el bridge' : '';
  if (announcement.textContent !== alert) announcement.textContent = alert;
  updated.hidden = !data;
  if (data) {
    const date = new Date(data.time * 1000);
    updated.dateTime = date.toISOString();
    updated.textContent = timeFormat.format(date);
    updated.title = `Última actualización: ${date.toLocaleString('es')}`;
    updated.setAttribute('aria-label', updated.title);
  }
  const scroll = content.scrollTop;
  const groups = partitionAgents(agents, settings.sort);
  const active = new Set(agents.map(({ name }) => name));
  for (const [name, card] of renderedAgents) {
    if (!active.has(name)) {
      card.remove();
      renderedAgents.delete(name);
      agentFingerprints.delete(name);
    }
  }
  function renderCards(target, values) {
    const names = new Set(values.map(({ name }) => name));
    for (const child of target.children) {
      if (child.classList.contains('agent') && !names.has(child.dataset.agentName)) child.remove();
    }
    for (const agent of values) {
      let card = renderedAgents.get(agent.name);
      if (!card) {
        card = element('article');
        card.dataset.agentName = agent.name;
        renderedAgents.set(agent.name, card);
      }
      const fingerprint = JSON.stringify({ ...agent, data_age_s: null, compact: settings.compact,
        detail: agent.detail.replace(/\b\d+s\b/g, 'N s').replace(/\[N s ago\]/g, '[age]') });
      if (agentFingerprints.get(agent.name) !== fingerprint) {
        const fresh = agentCard(agent);
        card.className = fresh.className;
        card.title = fresh.title;
        card.replaceChildren(...fresh.childNodes);
        agentFingerprints.set(agent.name, fingerprint);
      }
      card.tabIndex = 0; card.setAttribute('role', 'button'); card.setAttribute('aria-label', `Ver actividad de ${agent.name}`);
      target.append(card);
    }
  }
  renderCards(adminList, groups.admins);
  const renderGroup = (key, group, values) => {
    const isOpen = settings.groupOpen[key];
    group.section.hidden = values.length === 0;
    group.count.textContent = String(values.length);
    group.button.setAttribute('aria-expanded', String(isOpen));
    group.list.hidden = !isOpen;
    renderCards(group.list, values);
  };
  renderGroup('working', workingGroup, groups.working);
  renderGroup('free', freeGroup, groups.free);
  let empty = list.querySelector('.empty');
  if (data && !agents.length) {
    if (!empty) { empty = element('p', 'empty', 'No hay agentes conectados'); list.append(empty); }
  } else empty?.remove();
  content.scrollTop = scroll;
  updateClock();
  reportLayout(!!data && (!captureFeed || !!detailName));
}

async function refreshDetail() {
  if (!detailName || detailView.hidden) return;
  const data = await window.bridgeWidget.readFeed(detailName);
  if (!data || detailName !== data.name) return;
  const status = document.querySelector('#detail-status');
  const age = data.state.since ? Math.max(0, Math.floor(Date.now()/1000-data.state.since)) : 0;
  status.textContent = data.state.status === 'working' ? `Trabajando hace ${age >= 60 ? `${Math.floor(age/60)} min` : `${age} s`} · ahora: ${data.state.activity || '…'}` : `Estado: ${data.state.status}`;
  const box = document.querySelector('#detail-events'); const wasBottom = box.scrollHeight - box.scrollTop - box.clientHeight < 30;
  box.replaceChildren();
  for (const event of data.events) {
    const row = element('div', `feed-${event.role}`);
    row.append(element('small', '', `${new Date(event.ts).toLocaleTimeString('es')} · ${event.role === 'order' ? 'Orden del admin' : event.role === 'tool' ? 'Herramienta' : event.role === 'result' ? 'Resultado' : event.role === 'system' ? 'Sistema' : 'Agente'}`));
    row.append(element('div', event.role === 'tool' ? 'feed-tool' : '', event.role === 'tool' ? `${event.tool || 'acción'}  ${event.text}` : event.text)); box.append(row);
  }
  if (detailPinned && wasBottom) box.scrollTop = box.scrollHeight;
  if (captureFeed) reportLayout(true);
}
function openDetail(name) { detailName = name; detailView.hidden = false; document.querySelector('#agents').hidden = true; detailPinned = true; refreshDetail(); clearInterval(detailTimer); detailTimer = setInterval(refreshDetail, 3000); reportLayout(); }
function closeDetail() { detailName = null; clearInterval(detailTimer); detailView.hidden = true; document.querySelector('#agents').hidden = false; reportLayout(); }
document.querySelector('#detail-back').addEventListener('click', closeDetail);
document.querySelector('#detail-events').addEventListener('scroll', (event) => { const b=event.currentTarget; detailPinned=b.scrollHeight-b.scrollTop-b.clientHeight<30; });
window.bridgeWidget.onCaptureFeed(() => {
  const target = snapshot.data?.agents?.find(a => a.state === 'working') || snapshot.data?.agents?.[0];
  if (target && !detailName) openDetail(target.name);
});
list.addEventListener('click', (event) => { const card=event.target.closest('[data-agent-name]'); if(card) openDetail(card.dataset.agentName); });
list.addEventListener('keydown', (event) => { const card=event.target.closest('[data-agent-name]'); if(card && (event.key==='Enter'||event.key===' ')){event.preventDefault();openDetail(card.dataset.agentName);} });

function applyCollapsed() {
  panel.classList.toggle('collapsed', collapsed);
  content.hidden = collapsed;
  toggle.setAttribute('aria-expanded', String(!collapsed));
  toggle.setAttribute('aria-label', collapsed ? 'Expandir resumen' : 'Contraer resumen');
  render();
}

function flip() {
  collapsed = !collapsed;
  applyCollapsed();
}

function toggleGroup(key) {
  settings.groupOpen[key] = !settings.groupOpen[key];
  window.bridgeWidget.setGroupOpen(key, settings.groupOpen[key]);
  render();
}

workingGroup.button.addEventListener('click', () => toggleGroup('working'));
freeGroup.button.addEventListener('click', () => toggleGroup('free'));

toggle.addEventListener('click', (event) => {
  if (event.detail <= 1) flip();
});
header.addEventListener('dblclick', (event) => {
  if (!event.target.closest('button')) flip();
});
globalThis.addEventListener('resize', () => reportLayout());
setInterval(updateClock, 1000);

window.bridgeWidget.onUpdate((next) => {
  snapshot = next;
  render();
  if (captureFeed && !detailName) {
    const target = snapshot.data?.agents?.find(a => a.state === 'working') || snapshot.data?.agents?.[0];
    if (target) openDetail(target.name);
  }
});
window.bridgeWidget.initial().then((initial) => {
  captureFeed = initial.captureFeed === true;
  if (snapshot.data === null && !snapshot.disconnected) snapshot = initial.snapshot;
  collapsed = initial.collapsed;
  settings = normalizeSettings(initial.settings || settings);
  applySettings();
  applyCollapsed();
  if (captureFeed) {
    const target = initial.snapshot.data?.agents?.find(a => a.state === 'working') || initial.snapshot.data?.agents?.[0];
    if (target) openDetail(target.name);
  }
});

function applySettings() {
  document.documentElement.style.setProperty('--font-size', `${settings.fontSize || 12}px`);
  document.documentElement.style.setProperty('--opacity', `${(settings.opacity || 100) / 100}`);
  render();
}
window.bridgeWidget.onSettings((next) => { settings = normalizeSettings(next); applySettings(); });
document.addEventListener('visibilitychange', () => window.bridgeWidget.visibility(!document.hidden));
