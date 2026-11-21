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

  const metrics = { formatCountdown, usageColor };
  if (typeof module === 'object' && module.exports) module.exports = metrics;
  else window.metrics = Object.freeze(metrics);
})();
