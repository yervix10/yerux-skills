'use strict';

const choices = {
  role: ['admin', 'worker'],
  kind: ['claude', 'codex', 'kiro', 'antigravity', 'cursor', 'qwen'],
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
    if (agent.credit_used !== undefined) {
      if (!(agent.credit_used === null || (Number.isFinite(agent.credit_used) && agent.credit_used >= 0))) throw new TypeError(`Créditos inválidos en la posición ${index}`);
      normalized.credit_used = agent.credit_used;
    }
    if (agent.model_note !== undefined) {
      if (typeof agent.model_note !== 'string') throw new TypeError(`Nota de modelo inválida en la posición ${index}`);
      normalized.model_note = agent.model_note;
    }
    for (const key of periods) {
      const { used, resets_at } = agent[key];
      normalized[key] = { used: used === null ? null : Math.min(used, 100), resets_at };
      if (key === 'monthly') {
        for (const field of ['credits_used', 'credits_total']) {
          if (usageFieldPresent(agent[key], field)) {
            const value = agent[key][field];
            if (!(value === null || (Number.isFinite(value) && value >= 0))) throw new TypeError(`Créditos mensuales inválidos en la posición ${index}`);
            normalized[key][field] = value;
          }
        }
        if (usageFieldPresent(agent[key], 'plan')) {
          if (!(agent[key].plan === null || typeof agent[key].plan === 'string')) throw new TypeError(`Plan mensual inválido en la posición ${index}`);
          normalized[key].plan = agent[key].plan;
        }
      }
    }
    if (normalized.context !== null) normalized.context = Math.min(normalized.context, 100);
    return normalized;
  });
  return { time: data.time, agents };
}

function usageFieldPresent(usage, key) {
  return Object.hasOwn(usage, key);
}

module.exports = { parseDashboard };
