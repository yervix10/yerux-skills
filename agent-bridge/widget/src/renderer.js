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
let activeAgent = null; let newestEventKey = ''; let newEventCount = 0; let pendingControl = null;
const controlOptionsCache = new Map();
let captureFeed = false;
let adminFeedFilter = 'all';
const toolGroupsOpen = new Set(JSON.parse(localStorage.getItem('bridge-tool-groups-open') || '[]'));
const toolDetailsOpen = new Set(JSON.parse(localStorage.getItem('bridge-tool-details-open') || '[]'));

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
  const card = element('article', `agent${settings.compact ? ' compact' : ''} agent-${agent.kind}${agent.role === 'admin' ? ' agent-admin' : ''}`);
  const identity = element('div', 'identity');
  const identityMain = element('div', 'identity-main');
  const name = element('h2', 'agent-name', agent.name);
  name.title = agent.name;
  identityMain.append(name, element('span', `state state-${agent.state}`, states[agent.state]));
  identity.append(identityMain);
  const labels = element('div', 'identity-labels');
  if (agent.role === 'admin') labels.append(element('span', 'badge badge-admin', 'Admin'));
  labels.append(element('span', `badge badge-${agent.kind}`, agent.kind === 'kiro' ? '✦ Kiro' : agent.kind));
  if (agent.context !== null && agent.context > 40) labels.append(element('span', 'badge badge-warning', 'Compactará'));
  if (agent.tier === 'skip') labels.append(element('span', 'badge badge-critical', 'Skip'));
  identity.append(labels);
  if (settings.compact) {
    const usage = highestUsage(agent);
    card.append(identity, element('span', 'compact-percent', usage === null ? '—' : `${usage}%`), element('span', 'compact-tier', Number.isFinite(agent.credit_used) ? `${agent.credit_used.toFixed(2)} cr` : agent.tier || '—'));
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
  if (Number.isFinite(agent.credit_used)) metadata.append(element('span', 'effort-badge', `${agent.credit_used.toFixed(2)} créditos`));
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
  const agent = snapshot.data?.agents?.find((item) => item.name === detailName);
  if (!agent) return;
  activeAgent = agent;
  document.querySelector('#detail-title').textContent = agent.name;
  detailView.classList.toggle('detail-admin', agent.role === 'admin');
  configureControls(agent);
  const status = document.querySelector('#detail-status');
  const age = data.state.since ? Math.max(0, Math.floor(Date.now()/1000-data.state.since)) : 0;
  status.textContent = data.state.status === 'working' ? `Trabajando hace ${age >= 60 ? `${Math.floor(age/60)} min` : `${age} s`} · ahora: ${data.state.activity || '…'}` : `Estado: ${data.state.status}`;
  const box = document.querySelector('#detail-events'); const wasRecent = box.scrollTop < 30;
  const oldHeight = box.scrollHeight; const oldTop = box.scrollTop;
  const events = [...data.events].sort((a, b) => Date.parse(b.ts) - Date.parse(a.ts));
  const newest = events[0]; const nextKey = newest ? `${newest.ts}|${newest.role}|${newest.text}` : '';
  if (newestEventKey && nextKey && newestEventKey !== nextKey && !wasRecent) newEventCount += Math.max(1, events.filter(e => Date.parse(e.ts) > Date.parse(newestEventKey.split('|')[0])).length);
  if (!newestEventKey) { newEventCount = 0; }
  newestEventKey = nextKey;
  const filters = document.querySelector('#feed-filters');
  filters.hidden = agent.role !== 'admin';
  if (agent.role === 'admin') {
    const groups = [
      ['all', 'Todos', events.length],
      ['orders', 'Órdenes enviadas', events.filter(item => item.role === 'order').length],
      ['reports', 'Reportes recibidos', events.filter(item => item.role === 'report').length],
      ['conversation', 'Conversación con el usuario', events.filter(item => ['admin', 'user'].includes(item.role)).length],
    ];
    filters.replaceChildren(...groups.map(([key, label, count]) => {
      const button = element('button', 'feed-filter', `${label} · ${count}`); button.type = 'button';
      button.setAttribute('aria-pressed', String(adminFeedFilter === key));
      button.addEventListener('click', () => { adminFeedFilter = key; refreshDetail(); });
      return button;
    }));
  }
  const displayedEvents = agent.role !== 'admin' || adminFeedFilter === 'all' ? events : events.filter(item =>
    adminFeedFilter === 'orders' ? item.role === 'order' :
      adminFeedFilter === 'reports' ? item.role === 'report' : ['admin', 'user'].includes(item.role));
  box.replaceChildren();
  let previousDay = '';
  for (let i = 0; i < displayedEvents.length;) {
    const event = displayedEvents[i];
    const day = new Date(event.ts).toLocaleDateString('es', { weekday: 'long', day: 'numeric', month: 'long' });
    if (day !== previousDay) { box.append(element('div', 'feed-day', day)); previousDay = day; }
    const timestamp = new Date(event.ts).toLocaleTimeString('es', { hour: '2-digit', minute: '2-digit' });
    if (event.role === 'tool' || event.role === 'tool_result') {
      const groupStart = i; const groupEvents = [];
      while (i < displayedEvents.length && ['tool', 'tool_result'].includes(displayedEvents[i].role)) groupEvents.push(displayedEvents[i++]);
      const key = groupEvents.map(toolEventKey).join('~');
      const rowsId = `feed-tool-rows-${groupStart}`;
      const group = element('section', 'feed-tool-group');
      const head = element('button', 'feed-tool-group-head'); head.type = 'button'; head.setAttribute('aria-controls', rowsId); head.setAttribute('aria-expanded', String(toolGroupsOpen.has(key)));
      const calls = groupEvents.filter(item => item.role === 'tool');
      const results = groupEvents.filter(item => item.role === 'tool_result');
      if (!calls.length) continue;
      const label = element('span', '', `Herramientas (${calls.length})`);
      const counts = new Map(); for (const item of calls) counts.set(item.tool || 'Herramienta', (counts.get(item.tool || 'Herramienta') || 0) + 1);
      const names = [...counts].map(([name, count]) => `${name}${count > 1 ? ` ×${count}` : ''}`).join(', ');
      head.append(label, element('span', 'feed-tool-group-summary', names));
      const inProgress = groupStart === 0 && snapshot.data?.state?.status === 'working';
      if (inProgress) head.append(element('span', 'feed-tool-running', 'en curso…'));
      head.append(element('span', 'feed-tool-chevron', '⌄'));
      head.addEventListener('click', () => { if (toolGroupsOpen.has(key)) toolGroupsOpen.delete(key); else toolGroupsOpen.add(key); localStorage.setItem('bridge-tool-groups-open', JSON.stringify([...toolGroupsOpen])); refreshDetail(); });
      const rows = element('div', 'feed-tool-rows'); rows.id = rowsId; rows.hidden = !toolGroupsOpen.has(key);
      for (let toolIndex = 0; toolIndex < calls.length; toolIndex++) {
        const item = calls[toolIndex]; const result = results[toolIndex];
        const itemKey = toolEventKey(item); const detailId = `feed-tool-detail-${groupStart}-${toolIndex}`; const details = element('div', 'feed-tool-detail');
        const row = element('button', 'feed-tool-row'); row.type = 'button'; row.setAttribute('aria-controls', detailId); row.setAttribute('aria-expanded', String(toolDetailsOpen.has(itemKey)));
        row.append(element('strong', 'feed-tool-name', item.tool || 'Herramienta'));
        row.append(element('span', 'feed-tool-summary', safeToolSummary(item.text || '')));
        const running = inProgress && toolIndex === 0;
        const failed = result && /error|fail|denied|timeout/i.test(result.text);
        row.append(element('span', `feed-tool-status ${running ? 'is-running' : failed ? 'is-error' : 'is-ok'}`, running ? '…' : failed ? 'Error' : 'OK'));
        row.addEventListener('click', () => { if (toolDetailsOpen.has(itemKey)) toolDetailsOpen.delete(itemKey); else toolDetailsOpen.add(itemKey); localStorage.setItem('bridge-tool-details-open', JSON.stringify([...toolDetailsOpen])); refreshDetail(); });
        const full = element('pre', 'feed-tool-full', `${safeToolSummary(item.text || '')}${result ? `\n\nResultado:\n${result.text}` : ''}`); full.id = detailId; full.hidden = !toolDetailsOpen.has(itemKey); details.append(row, full); rows.append(details);
      }
      group.append(head, rows); box.append(group); continue;
    }
    i++;
    const role = event.role === 'order' ? 'admin' : event.role === 'assistant' ? 'assistant' : event.role;
    const row = element('article', `feed-message feed-${role}`);
    row.dataset.eventKey = `${event.ts}|${event.role}|${event.text}`;
    const byline = element('div', 'feed-byline');
    const speaker = event.role === 'order' ? `Admin → ${event.to || agent.name}` : event.role === 'report' ? `${event.from || agent.name} → Admin` : event.role === 'admin' ? 'Admin' : event.role === 'user' ? 'Usuario' : agent.name;
    byline.append(element('strong', '', speaker));
    byline.append(element('time', '', timestamp));
    if (event.role === 'result') byline.append(element('span', `feed-result-chip ${/error|fail|timeout|limit/i.test(event.text) ? 'is-error' : 'is-ok'}`, /error|fail|timeout|limit/i.test(event.text) ? 'Error' : 'OK'));
    row.append(byline);
    const body = element('div', 'feed-body'); renderMarkdown(body, event.text || ''); row.append(body); box.append(row);
  }
  const newButton = document.querySelector('#new-events');
  newButton.hidden = newEventCount === 0;
  newButton.textContent = `${newEventCount} nuevos · Ir a lo más reciente`;
  if (wasRecent) { box.scrollTop = 0; detailPinned = true; newEventCount = 0; newButton.hidden = true; }
  else if (oldHeight) box.scrollTop = oldTop + (box.scrollHeight - oldHeight);
  reportLayout(captureFeed);
}
function toolEventKey(event) { return `${event.ts}|${event.tool || ''}|${event.text || ''}`; }
function safeToolSummary(text) {
  try { const value = JSON.parse(text); if (value && typeof value === 'object') return Object.entries(value).slice(0, 3).map(([k,v]) => `${k}: ${typeof v === 'string' ? v : JSON.stringify(v)}`).join(' · '); } catch {}
  return text;
}
function renderInline(parent, value) {
  const pattern = /(`[^`]+`|\*\*[^*]+\*\*|(?:\.{0,2}\/)?[\w.-]+(?:\/[\w.-]+)+|\b(?:npm|git|agent|codex|claude)\s+[\w.-]+(?:\s+[\w./-]+)?|\b[0-9a-f]{7,40}\b)/gi;
  let at = 0; let match;
  while ((match = pattern.exec(value))) {
    if (match.index > at) parent.append(document.createTextNode(value.slice(at, match.index)));
    const token = match[0];
    if (token.startsWith('`')) parent.append(element('code', 'feed-inline-code', token.slice(1, -1)));
    else if (token.startsWith('**')) parent.append(element('strong', '', token.slice(2, -2)));
    else parent.append(element('code', 'feed-inline-code feed-code-badge', token));
    at = match.index + token.length;
  }
  if (at < value.length) parent.append(document.createTextNode(value.slice(at)));
}
function renderMarkdown(parent, value) {
  const lines = String(value).split('\n'); let inCode = false; let code = []; let language = ''; let listNode = null;
  const flushList = () => { listNode = null; };
  for (const line of lines) {
    const fence = line.match(/^\s*```\s*([\w+-]*)/);
    if (fence && !inCode) { flushList(); inCode = true; language = fence[1] || 'code'; code = []; continue; }
    if (inCode && /^\s*```/.test(line)) {
      const block = element('section', 'feed-code-block'); const head = element('div', 'feed-code-head');
      head.append(element('span', '', language)); const copy = element('button', '', 'Copiar'); copy.type = 'button';
      const text = code.join('\n'); copy.addEventListener('click', async () => { await window.bridgeWidget.copyText(text); copy.textContent = 'Copiado'; setTimeout(() => { copy.textContent = 'Copiar'; }, 1200); });
      head.append(copy); block.append(head); block.append(element('pre', '', text)); parent.append(block); inCode = false; continue;
    }
    if (inCode) { code.push(line); continue; }
    if (!line.trim()) { flushList(); continue; }
    const heading = line.match(/^(#{1,3})\s+(.+)$/);
    if (heading) { flushList(); const h=element(`h${heading[1].length + 2}`, 'feed-heading'); renderInline(h, heading[2]); parent.append(h); continue; }
    const item = line.match(/^\s*(?:[-*]|\d+\.)\s+(.+)$/);
    if (item) { if (!listNode) { listNode=element('ul','feed-list'); parent.append(listNode); } const li=element('li'); renderInline(li,item[1]); listNode.append(li); continue; }
    flushList(); const p=element('p'); renderInline(p,line); parent.append(p);
  }
  if (inCode) { const block=element('pre','feed-code-block feed-code-incomplete',code.join('\n')); parent.append(block); }
}
async function configureControls(agent) {
  const worker = agent.role !== 'admin';
  document.querySelector('#worker-controls').hidden = !worker;
  document.querySelector('#admin-controls-note').hidden = worker;
  document.querySelector('#copy-compact').hidden = worker;
  if (!worker) return;
  let options = controlOptionsCache.get(agent.name);
  if (!options) { options = window.bridgeWidget.controlOptions(agent.name); controlOptionsCache.set(agent.name, options); }
  options = await options;
  if (options) controlOptionsCache.set(agent.name, options);
  if (!options || detailName !== agent.name) return;
  document.querySelector('#next-order-note').textContent = `Activo: ${agent.model || 'predeterminado'} · esfuerzo ${agent.effort || 'predeterminado'}. Cambios desde la próxima orden.`;
  document.querySelector('#control-security-note').hidden = options.authorized;
  for (const control of document.querySelectorAll('#worker-controls select, #worker-controls button')) control.disabled = !options.authorized;
  const fill = (id, values, current) => { const select=document.querySelector(id); if(select.options.length && select.dataset.agent===agent.name) return; select.replaceChildren(); for(const value of values){const option=element('option','',value);option.value=value;select.append(option);} select.value=current;select.dataset.agent=agent.name; };
  fill('#model-select',options.model,options.configuredModel); fill('#effort-select',options.effort,options.configuredEffort);
}
async function executeControl(action,value,confirmed=false) {
  if (!activeAgent) return;
  const feedback=document.querySelector('#control-feedback'); feedback.textContent='Aplicando…';
  const result=await window.bridgeWidget.control({action,name:activeAgent.name,value,confirmed});
  feedback.textContent=result?.message || (result?.ok ? 'Hecho' : 'No se pudo completar');
  if (result?.ok) { newestEventKey=''; controlOptionsCache.delete(activeAgent.name); if(action==='compact') refreshDetail(); else configureControls(activeAgent); }
}
function askConfirmation(message, request) { pendingControl=request; document.querySelector('#confirm-message').textContent=message; document.querySelector('#confirm-action').showModal(); }
document.querySelector('#apply-model').addEventListener('click',()=>{const value=document.querySelector('#model-select').value; if(value==='opus') askConfirmation('Opus tiene mayor costo. ¿Confirmas usarlo para las próximas órdenes?',()=>executeControl('model',value,true)); else executeControl('model',value);});
document.querySelector('#apply-effort').addEventListener('click',()=>executeControl('effort',document.querySelector('#effort-select').value));
document.querySelector('#compact-worker').addEventListener('click',()=>askConfirmation('Solicitar compactación ahora. Si el agente trabaja, se ejecutará antes de su próxima orden.',()=>executeControl('compact')));
document.querySelector('#confirm-cancel').addEventListener('click',()=>{document.querySelector('#confirm-action').close();pendingControl=null;});
document.querySelector('#confirm-accept').addEventListener('click',()=>{document.querySelector('#confirm-action').close();const run=pendingControl;pendingControl=null;run?.();});
document.querySelector('#copy-compact').addEventListener('click',async()=>{const ok=await window.bridgeWidget.copyCompact();document.querySelector('#control-feedback').textContent=ok?'Copiado /compact':'No se pudo copiar';});
document.querySelector('#new-events').addEventListener('click',()=>{document.querySelector('#detail-events').scrollTop=0;detailPinned=true;newEventCount=0;document.querySelector('#new-events').hidden=true;});
function openDetail(name) { detailName = name; newestEventKey=''; newEventCount=0; document.querySelector('#detail-events').scrollTop=0; detailView.hidden = false; document.querySelector('#agents').hidden = true; detailPinned = true; refreshDetail(); clearInterval(detailTimer); detailTimer = setInterval(refreshDetail, 3000); reportLayout(); }
function closeDetail() { detailName = null; activeAgent=null; clearInterval(detailTimer); detailView.hidden = true; document.querySelector('#agents').hidden = false; reportLayout(); }
document.querySelector('#detail-back').addEventListener('click', closeDetail);
document.querySelector('#detail-events').addEventListener('scroll', (event) => { const b=event.currentTarget; detailPinned=b.scrollTop<30; if(detailPinned){newEventCount=0;document.querySelector('#new-events').hidden=true;} });
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
