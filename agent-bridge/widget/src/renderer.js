'use strict';

const { formatCountdown, usageColor, sortAgents, normalizeSettings } = window.metrics;
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

const states = {
  admin: 'Admin', idle: 'Libre', working: 'Trabajando', limited: 'Limitado',
  stuck: 'Atascado', off: 'Apagado', unknown: 'Desconocido',
};
const scale = { green: 'normal', amber: 'alto', red: 'crítico' };
const periods = [['five_hour', '5 h'], ['weekly', 'Semana'], ['monthly', 'Mes']];
const timeFormat = new Intl.DateTimeFormat('es', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
const percentFormat = new Intl.NumberFormat('es', { style: 'percent', maximumFractionDigits: 2 });

let snapshot = { data: null, disconnected: false };
let collapsed = false;
let settings = { compact: false, sort: 'urgency', opacity: 100, fontSize: 12 };
let lastAgents = '';

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function metric(label, used, resetAt = null, context = false) {
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
  if (resetAt !== null) {
    countdown.dataset.reset = resetAt;
    countdown.title = new Date(resetAt * 1000).toLocaleString('es');
    countdown.setAttribute('aria-label', `Se reinicia en ${formatCountdown(resetAt)}`);
  }
  row.append(countdown);
  return row;
}

function highest(agent) {
  return Math.max(agent.context ?? 0, agent.five_hour.used ?? 0, agent.weekly.used ?? 0, agent.monthly.used ?? 0);
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
    card.append(identity, element('span', 'compact-percent', `${highest(agent)}%`), element('span', 'compact-tier', agent.tier || '—'));
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

  const metrics = element('div', 'metrics');
  metrics.append(metric('Contexto', agent.context, null, true));
  const availableLimits = periods.map(([key]) => ({ key, usage: agent[key] })).filter(({ usage }) => usage.used !== null);
  const highestLimit = availableLimits.sort((a, b) => b.usage.used - a.usage.used)[0];
  const tightest = highestLimit?.usage.used >= 60 ? highestLimit.key : undefined;
  for (const [key, label] of periods) {
    const usage = agent[key];
    const row = metric(label, usage.used, usage.resets_at);
    if (key === tightest) row.classList.add('tightest-limit');
    metrics.append(row);
  }
  card.append(metrics);

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
  const fingerprint = JSON.stringify(agents.map((agent) => ({
    ...agent,
    data_age_s: null,
    detail: agent.detail.replace(/\b\d+s\b/g, 'N s').replace(/\[N s ago\]/g, '[age]'),
  })));
  if (fingerprint !== lastAgents) {
    const scroll = content.scrollTop;
    list.replaceChildren(...agents.map(agentCard));
    if (data && !agents.length) list.append(element('p', 'empty', 'No hay agentes conectados'));
    content.scrollTop = scroll;
    lastAgents = fingerprint;
  }
  updateClock();
  reportLayout(!!data);
}

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
});
window.bridgeWidget.initial().then((initial) => {
  if (snapshot.data === null && !snapshot.disconnected) snapshot = initial.snapshot;
  collapsed = initial.collapsed;
  settings = normalizeSettings(initial.settings || settings);
  applySettings();
  applyCollapsed();
});

function applySettings() {
  document.documentElement.style.setProperty('--font-size', `${settings.fontSize || 12}px`);
  document.documentElement.style.setProperty('--opacity', `${(settings.opacity || 100) / 100}`);
  lastAgents = '';
  render();
}
window.bridgeWidget.onSettings((next) => { settings = normalizeSettings(next); applySettings(); });
document.addEventListener('visibilitychange', () => window.bridgeWidget.visibility(!document.hidden));
