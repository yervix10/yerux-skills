'use strict';

const choices = {
  role: ['admin', 'worker'],
  kind: ['claude', 'codex'],
  state: ['admin', 'idle', 'working', 'limited', 'stuck', 'off', 'unknown'],
  tier: ['', 'heavy', 'normal', 'light', 'skip'],
};
const textFields = ['name', 'detail', 'model', 'effort', 'set_model', 'set_effort', 'project', 'branch'];
const periods = ['five_hour', 'weekly', 'monthly'];

function record(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function nonnegative(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

function percentage(value) {
  // usage can legitimately exceed 100% once a limit is hit; it is clamped on output
  return value === null || (Number.isFinite(value) && value >= 0);
}

function parseDashboard(source) {
  const data = JSON.parse(source);
  if (!record(data) || !nonnegative(data.time) || data.time > 8_640_000_000_000 || !Array.isArray(data.agents)) {
    throw new TypeError('Dashboard inválido');
  }
  const names = new Set();
  const agents = data.agents.map((agent, index) => {
    if (!record(agent) ||
        !textFields.every((key) => typeof agent[key] === 'string') ||
        !agent.name.trim() || names.has(agent.name) ||
        !Object.entries(choices).every(([key, values]) => values.includes(agent[key])) ||
        !percentage(agent.context) ||
        !(agent.data_age_s === null || nonnegative(agent.data_age_s)) ||
        !periods.every((key) => {
          const usage = agent[key];
          return record(usage) && percentage(usage.used) &&
            (usage.resets_at === null || nonnegative(usage.resets_at));
        })) {
      throw new TypeError(`Agente inválido en la posición ${index}`);
    }
    names.add(agent.name);
    const normalized = Object.fromEntries(
      [...textFields, ...Object.keys(choices), 'context', 'data_age_s'].map((key) => [key, agent[key]]),
    );
    for (const key of periods) {
      const { used, resets_at } = agent[key];
      normalized[key] = { used: used === null ? null : Math.min(used, 100), resets_at };
    }
    if (normalized.context !== null) normalized.context = Math.min(normalized.context, 100);
    return normalized;
  });
  return { time: data.time, agents };
}

module.exports = { parseDashboard };
