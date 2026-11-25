(function exposeMetrics() {
  'use strict';

  function formatCountdown(resetAt, now = Date.now() / 1000) {
    if (resetAt === null) return '';
    const seconds = Math.max(0, Math.ceil(resetAt - now));
    const days = Math.floor(seconds / 86400);
    const hours = Math.floor(seconds / 3600) % 24;
    const minutes = Math.floor(seconds / 60) % 60;
    if (days) return `↻ ${days}d${hours}h`;
    if (hours) return `↻ ${hours}h${minutes}m`;
    if (minutes) return `↻ ${minutes}m${seconds % 60}s`;
    return `↻ ${seconds}s`;
  }

  function usageColor(used) {
    if (used === null) return 'unknown';
    if (used >= 85) return 'red';
    if (used >= 60) return 'amber';
    return 'green';
  }

  function sortAgents(agents, mode = 'urgency') {
    if (mode === 'manual') return [...agents];
    const rank = { auth: -1, limited: 0, stuck: 1, working: 2, idle: 3, admin: 4, unknown: 5, off: 6, disabled: 7 };
    return [...agents].sort((a, b) => (a.role === 'admin' ? -1 : b.role === 'admin' ? 1 :
      (rank[a.state] ?? 5) - (rank[b.state] ?? 5)) || a.name.localeCompare(b.name));
  }

  function normalizeSettings(value = {}) {
    return {
      compact: value.compact === true,
      sort: value.sort === 'manual' ? 'manual' : 'urgency',
      opacity: [80, 90, 100].includes(value.opacity) ? value.opacity : 100,
      fontSize: [11, 12, 14].includes(value.fontSize) ? value.fontSize : 12,
      groupOpen: normalizeGroupOpen(value.groupOpen),
    };
  }

  function normalizeGroupOpen(value = {}) {
    return {
      working: value.working !== false,
      free: value.free === true,
    };
  }

  function partitionAgents(agents, mode = 'urgency') {
    const groups = { admins: [], attention: [], working: [], free: [] };
    for (const agent of agents) {
      if (agent.role === 'admin') groups.admins.push(agent);
      else if (agent.state === 'auth') groups.attention.push(agent);
      else if (agent.state === 'working') groups.working.push(agent);
      else groups.free.push(agent);
    }
    return Object.fromEntries(Object.entries(groups).map(([key, values]) => [key, sortAgents(values, mode)]));
  }

  function visibleMetrics(agent) {
    const rows = [];
    if (agent.context !== null) rows.push({ key: 'context', label: 'Contexto', used: agent.context, resetsAt: null, context: true });
    for (const [key, label] of [['five_hour', '5 h'], ['weekly', 'Semana'], ['monthly', 'Mes']]) {
      const usage = agent[key];
      if (usage.used !== null || usage.resets_at !== null) {
        const details = key === 'monthly' && Number.isFinite(usage.credits_used) && Number.isFinite(usage.credits_total)
          ? `${usage.credits_used.toFixed(2)} / ${usage.credits_total.toFixed(0)} créditos${usage.plan ? ` · ${usage.plan}` : ''}` : '';
        rows.push({ key, label, used: usage.used, resetsAt: usage.resets_at, context: false, detail: details });
      }
    }
    return rows;
  }

  function highestUsage(agent) {
    const values = [agent.context, agent.five_hour.used, agent.weekly.used, agent.monthly.used]
      .filter((value) => value !== null);
    return values.length ? Math.max(...values) : null;
  }

  const metrics = { formatCountdown, usageColor, sortAgents, normalizeSettings, normalizeGroupOpen, partitionAgents, visibleMetrics, highestUsage };
  if (typeof module === 'object' && module.exports) module.exports = metrics;
  else window.metrics = Object.freeze(metrics);
})();
