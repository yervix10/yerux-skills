'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const { parseDashboard } = require('../src/dashboard.cjs');
const { formatCountdown, usageColor, sortAgents, normalizeSettings, partitionAgents, visibleMetrics, highestUsage } = require('../src/metrics.js');

const usage = { used: null, resets_at: null };

test('define acento violeta admin coherente y variantes de vista compacta/detalle', () => {
  const css = fs.readFileSync(path.join(__dirname, '../src/style.css'), 'utf8');
  const renderer = fs.readFileSync(path.join(__dirname, '../src/renderer.js'), 'utf8');
  assert.doesNotMatch(css, /inset \d+px 0 0/, 'no left accent bar on cards');
  assert.doesNotMatch(css, /border-left/);
  assert.match(css, /\.compact\.agent-admin \.identity-labels \{ display: flex; \}/);
  assert.match(css, /--admin-accent: #5b3db5/);
  assert.doesNotMatch(css, /prefers-color-scheme: dark|color-scheme: dark/, 'light theme only');
  assert.match(css, /\.detail-admin \.feed-admin[\s\S]*?--admin-accent/);
  assert.match(renderer, /agent\.role === 'admin' \? ' agent-admin'/);
  assert.match(renderer, /detailView\.classList\.toggle\('detail-admin', agent\.role === 'admin'\)/);
});

const agent = {
  name: 'codex-1', role: 'worker', kind: 'codex', state: 'working',
  detail: '', model: 'gpt', effort: '', set_model: '', set_effort: 'medium',
  project: 'agent-bridge', branch: 'main', tier: 'normal', context: 0,
  data_age_s: 601, five_hour: { used: 85, resets_at: 1234 },
  weekly: { used: 0, resets_at: null }, monthly: usage,
};

test('acepta datos reales del esquema y copia solo campos conocidos', () => {
  const input = { time: 1000, agents: [{ ...agent, extra: 'ignorado' }], extra: true };
  assert.deepEqual(parseDashboard(JSON.stringify(input)), { time: 1000, agents: [agent] });
  assert.deepEqual(parseDashboard('{"time":0,"agents":[]}'), { time: 0, agents: [] });
  assert.equal(parseDashboard(JSON.stringify({ time: 0, agents: [{ ...agent, context: null, data_age_s: null }] })).agents[0].context, null);
});
test('acepta Kiro como worker y créditos de sesión opcionales', () => {
  const kiro = { ...agent, name: 'kiro-1', kind: 'kiro', credit_used: 0.15 };
  assert.equal(parseDashboard(JSON.stringify({ time: 1000, agents: [kiro] })).agents[0].credit_used, 0.15);
  assert.throws(() => parseDashboard(JSON.stringify({ time: 1000, agents: [{ ...kiro, credit_used: -1 }] })));
});
test('muestra cuota mensual Kiro, créditos del plan y tooltip para auto', () => {
  const renderer = fs.readFileSync(path.join(__dirname, '../src/renderer.js'), 'utf8');
  const kiro = { ...agent, name: 'kiro-1', kind: 'kiro', model: 'auto', model_note: 'Kiro elige modelo por tarea',
    monthly: { used: 14.5, resets_at: 1900000000, credits_used: 7.25, credits_total: 50, plan: 'KIRO FREE' } };
  const parsed = parseDashboard(JSON.stringify({ time: 1000, agents: [kiro] })).agents[0];
  assert.equal(parsed.monthly.plan, 'KIRO FREE');
  assert.equal(parsed.model_note, 'Kiro elige modelo por tarea');
  assert.equal(visibleMetrics(parsed).find(({ key }) => key === 'monthly').detail, '7.25 / 50 créditos · KIRO FREE');
  assert.match(renderer, /compact-monthly/);
  assert.match(renderer, /formatCountdown\(Number\(countdown\.dataset\.reset\), now\)/);
});
test('marca explícitamente el contexto guardado cuando se muestra un dato viejo', () => {
  const renderer = fs.readFileSync(path.join(__dirname, '../src/renderer.js'), 'utf8');
  assert.match(renderer, /Dato de contexto de hace/);
  assert.match(renderer, /ctx hace/);
});

test('rechaza JSON, esquema, duplicados y métricas inválidas', () => {
  for (const input of ['{', 'null', '{"time":0,"agents":null}', '{"time":-1,"agents":[]}']) {
    assert.throws(() => parseDashboard(input));
  }
  for (const change of [
    { name: ' ' }, { role: 'root' }, { kind: 'other' }, { state: 'busy' }, { tier: 'max' },
    { context: -1 }, { data_age_s: '601' }, { model: null }, { branch: undefined },
    { five_hour: null }, { weekly: { used: -1, resets_at: null } },
    { monthly: { used: 1, resets_at: -1 } },
    { monthly: { used: 1, resets_at: null, credits_used: -1 } },
  ]) {
    assert.throws(() => parseDashboard(JSON.stringify({ time: 0, agents: [{ ...agent, ...change }] })));
  }
  assert.throws(() => parseDashboard(JSON.stringify({ time: 0, agents: [agent, agent] })));
});

test('limita al 100 % el uso que supera el límite', () => {
  const over = { ...agent, five_hour: { used: 101, resets_at: null }, context: 130 };
  const [parsed] = parseDashboard(JSON.stringify({ time: 0, agents: [over] })).agents;
  assert.equal(parsed.five_hour.used, 100);
  assert.equal(parsed.context, 100);
});

test('formatea el reinicio desde días hasta segundos y trunca al vencer', () => {
  assert.equal(formatCountdown(null, 10), '');
  assert.equal(formatCountdown(10 + 9660, 10), '↻ 2h41m');
  assert.equal(formatCountdown(10 + 338400, 10), '↻ 3d22h');
  assert.equal(formatCountdown(110, 10), '↻ 1m40s');
  assert.equal(formatCountdown(70, 69.1), '↻ 1s');
  assert.equal(formatCountdown(70, 71), '↻ 0s');
});

test('asigna los colores en ambos límites y distingue datos ausentes', () => {
  assert.deepEqual([null, 0, 59.99, 60, 84.99, 85, 100].map(usageColor),
    ['unknown', 'green', 'green', 'amber', 'amber', 'red', 'red']);
});

test('ordena primero admin y después agentes urgentes, y conserva orden manual', () => {
  const agents = [
    { name: 'idle', state: 'idle', role: 'worker' },
    { name: 'working', state: 'working', role: 'worker' },
    { name: 'admin', state: 'admin', role: 'admin' },
    { name: 'stuck', state: 'stuck', role: 'worker' },
    { name: 'limited', state: 'limited', role: 'worker' },
  ];
  assert.deepEqual(sortAgents(agents).map(({ name }) => name), ['admin', 'limited', 'stuck', 'working', 'idle']);
  assert.deepEqual(sortAgents(agents, 'manual'), agents);
});

test('oculta métricas sin uso ni reinicio y conserva filas con solo reinicio', () => {
  const monthlyOnly = { ...agent, context: null, five_hour: usage, weekly: usage,
    monthly: { used: 42, resets_at: 4567 } };
  assert.deepEqual(visibleMetrics(monthlyOnly).map(({ key }) => key), ['monthly']);
  const shortAndWeekly = { ...agent, context: 24, five_hour: { used: 4, resets_at: 1234 },
    weekly: { used: 70, resets_at: 5678 }, monthly: usage };
  assert.deepEqual(visibleMetrics(shortAndWeekly).map(({ key }) => key), ['context', 'five_hour', 'weekly']);
  const resetOnly = { ...agent, context: null, five_hour: { used: null, resets_at: 1234 }, weekly: usage, monthly: usage };
  assert.deepEqual(visibleMetrics(resetOnly).map(({ key, used, resetsAt }) => ({ key, used, resetsAt })),
    [{ key: 'five_hour', used: null, resetsAt: 1234 }]);
  assert.deepEqual(visibleMetrics({ ...agent, context: null, five_hour: usage, weekly: usage, monthly: usage }), []);
  assert.equal(highestUsage({ ...agent, context: null, five_hour: usage, weekly: usage, monthly: usage }), null);
  assert.equal(highestUsage({ ...agent, context: 0, five_hour: usage, weekly: usage, monthly: usage }), 0);
});

test('separa admin fijo, sesión caída, trabajando y libres, y ordena urgencia dentro de los grupos', () => {
  const agents = [
    { name: 'idle', role: 'worker', state: 'idle' },
    { name: 'working-b', role: 'worker', state: 'working' },
    { name: 'admin', role: 'admin', state: 'admin' },
    { name: 'stuck', role: 'worker', state: 'stuck' },
    { name: 'limited', role: 'worker', state: 'limited' },
    { name: 'working-a', role: 'worker', state: 'working' },
    { name: 'off', role: 'worker', state: 'off' },
    { name: 'no-login', role: 'worker', state: 'auth' },
  ];
  const groups = partitionAgents(agents);
  assert.deepEqual(Object.fromEntries(Object.entries(groups).map(([key, values]) => [key, values.map(({ name }) => name)])), {
    admins: ['admin'], attention: ['no-login'], working: ['working-a', 'working-b'], free: ['limited', 'stuck', 'idle', 'off'],
  });
});

test('valida ajustes persistentes con valores permitidos y valores por defecto', () => {
  assert.deepEqual(normalizeSettings({ compact: true, sort: 'manual', opacity: 80, fontSize: 14 }),
    { compact: true, sort: 'manual', opacity: 80, fontSize: 14, groupOpen: { working: true, free: false } });
  assert.deepEqual(normalizeSettings({ compact: 1, sort: 'random', opacity: 1, fontSize: 99 }),
    { compact: false, sort: 'urgency', opacity: 100, fontSize: 12, groupOpen: { working: true, free: false } });
  assert.deepEqual(normalizeSettings({ groupOpen: { working: 0, free: 1 } }).groupOpen,
    { working: true, free: false });
});

test('conserva abierto/cerrado de los acordeones en los ajustes JSON', () => {
  const saved = JSON.parse(JSON.stringify({ groupOpen: { working: false, free: true } }));
  assert.deepEqual(normalizeSettings(saved).groupOpen, { working: false, free: true });
});
