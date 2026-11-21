'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { fetchDashboard } = require('../src/poll.cjs');

test('acepta BRIDGE_WIDGET_CMD dentro del bridge y bloquea rutas fuera', async (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'bridge-widget-source-'));
  const previous = { command: process.env.BRIDGE_WIDGET_CMD, bridge: process.env.BRIDGE_DIR };
  t.after(() => {
    fs.rmSync(root, { recursive: true, force: true });
    if (previous.command === undefined) delete process.env.BRIDGE_WIDGET_CMD; else process.env.BRIDGE_WIDGET_CMD = previous.command;
    if (previous.bridge === undefined) delete process.env.BRIDGE_DIR; else process.env.BRIDGE_DIR = previous.bridge;
  });
  const bin = path.join(root, 'bin');
  fs.mkdirSync(bin);
  const inside = path.join(bin, 'agent.cjs');
  fs.writeFileSync(inside, "process.stdout.write('{\\\"time\\\":1,\\\"agents\\\":[]}');\n");
  process.env.BRIDGE_DIR = root;
  process.env.BRIDGE_WIDGET_CMD = inside;
  assert.deepEqual(await fetchDashboard(), { time: 1, agents: [] });

  const outside = path.join(os.tmpdir(), `bridge-widget-outside-${process.pid}.cjs`);
  fs.writeFileSync(outside, "process.stdout.write('{\\\"time\\\":1,\\\"agents\\\":[]}');\n");
  try {
    process.env.BRIDGE_WIDGET_CMD = outside;
    await assert.rejects(fetchDashboard(), /debe apuntar dentro de ~\/\.claude-bridge/);
    process.env.BRIDGE_WIDGET_CMD = path.join(bin, '..', '..', 'outside.cjs');
    await assert.rejects(fetchDashboard(), /debe apuntar dentro de ~\/\.claude-bridge/);
  } finally { fs.rmSync(outside, { force: true }); }
});
