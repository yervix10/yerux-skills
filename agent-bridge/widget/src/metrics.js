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
    const rank = { limited: 0, stuck: 1, working: 2, idle: 3, admin: 4, unknown: 5, off: 6 };
    return [...agents].sort((a, b) => (a.role === 'admin' ? -1 : b.role === 'admin' ? 1 :
      (rank[a.state] ?? 5) - (rank[b.state] ?? 5)) || a.name.localeCompare(b.name));
  }

  function normalizeSettings(value = {}) {
    return {
      compact: value.compact === true,
      sort: value.sort === 'manual' ? 'manual' : 'urgency',
      opacity: [80, 90, 100].includes(value.opacity) ? value.opacity : 100,
      fontSize: [11, 12, 14].includes(value.fontSize) ? value.fontSize : 12,
    };
  }

  const metrics = { formatCountdown, usageColor, sortAgents, normalizeSettings };
  if (typeof module === 'object' && module.exports) module.exports = metrics;
  else window.metrics = Object.freeze(metrics);
})();
