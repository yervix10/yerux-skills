'use strict';

const { formatCountdown, usageColor } = window.metrics;
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
  admin: 'Admin', idle: 'En espera', working: 'Trabajando', limited: 'Limitado',
  stuck: 'Atascado', off: 'Apagado', unknown: 'Desconocido',
};
const scale = { green: 'normal', amber: 'alto', red: 'crítico' };
const periods = [['five_hour', '5 h'], ['weekly', 'Semana'], ['monthly', 'Mes']];
const timeFormat = new Intl.DateTimeFormat('es', { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
const percentFormat = new Intl.NumberFormat('es', { style: 'percent', maximumFractionDigits: 2 });

let snapshot = { data: null, disconnected: false };
let collapsed = false;

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function metric(label, used, resetAt = null) {
  const row = element('div', 'metric');
  const color = usageColor(used);
  row.append(element('span', 'metric-label', label));
  const value = used === null ? 'Sin dato' : percentFormat.format(used / 100);
  if (used === null) {
    const track = element('span', 'unknown-track');
    track.setAttribute('aria-hidden', 'true');
    row.append(track);
  } else {
    const bar = element('progress', color);
    bar.max = 100;
    bar.value = used;
    bar.setAttribute('aria-label', label);
    bar.setAttribute('aria-valuetext', `${value}, uso ${scale[color]}`);
    row.append(bar);
  }
  row.append(element('span', 'percent', value));
  const countdown = element('span', 'countdown');
  if (resetAt !== null) {
    countdown.dataset.reset = resetAt;
    countdown.title = new Date(resetAt * 1000).toLocaleString('es');
  }
  row.append(countdown);
  return row;
}

function agentCard(agent) {
  const card = element('article', 'agent');
  const identity = element('div', 'identity');
  const name = element('h2', 'agent-name', agent.name);
  name.title = agent.name;
  identity.append(name, element('span', `badge badge-${agent.role}`, agent.role),
    element('span', 'badge', agent.kind));

  const state = element('span', `state state-${agent.state}`, states[agent.state]);
  identity.append(state);
  card.append(identity);

  const metadata = element('div', 'metadata');
  const model = agent.model || agent.set_model || 'Modelo sin datos';
  const effort = agent.effort || agent.set_effort;
  const modelLine = element('span', 'truncate', effort ? `${model} · ${effort}` : model);
  modelLine.title = modelLine.textContent;
  metadata.append(modelLine);
  if (agent.tier) {
    const tier = element('span', `tier tier-${agent.tier}`, agent.tier);
    tier.setAttribute('aria-label', `Capacidad ${agent.tier}`);
    metadata.append(tier);
  }
  card.append(metadata);

  const project = [agent.project, agent.branch].filter(Boolean).join(' / ');
  if (project) {
    const line = element('p', 'project truncate', project);
    line.title = project;
    card.append(line);
  }

  const metrics = element('div', 'metrics');
  metrics.append(metric('Contexto', agent.context));
  for (const [key, label] of periods) {
    const usage = agent[key];
    if (usage.used !== null) metrics.append(metric(label, usage.used, usage.resets_at));
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
  const agents = data?.agents ?? [];
  const working = agents.filter(({ state }) => state === 'working').length;
  const limited = agents.filter(({ state }) => state === 'limited').length;
  const total = `${agents.length} ${agents.length === 1 ? 'agente' : 'agentes'}`;
  const limits = `${limited} ${limited === 1 ? 'limitado' : 'limitados'}`;
  const counts = data ? `${total} · ${working} trabajando · ${limits}` : 'Conectando…';
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
  list.replaceChildren(...agents.map(agentCard));
  if (data && !agents.length) list.append(element('p', 'empty', 'No hay agentes conectados'));
  content.scrollTop = scroll;
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
  applyCollapsed();
});
