'use strict';

const { execFile } = require('node:child_process');
const { homedir } = require('node:os');
const path = require('node:path');
const { promisify } = require('node:util');
const { parseDashboard } = require('./dashboard.cjs');

const run = promisify(execFile);

async function fetchDashboard(signal) {
  const command = process.env.BRIDGE_WIDGET_CMD ||
    (process.platform === 'win32' ? '' : path.join(homedir(), '.claude-bridge', 'bin', 'agent'));
  if (!command) throw new Error('Configura BRIDGE_WIDGET_CMD');

  const javascript = /\.[cm]?js$/i.test(command);
  const args = ['dashboard', '--json'];
  const { stdout } = await run(
    javascript ? process.execPath : command,
    javascript ? [path.resolve(command), ...args] : args,
    {
      encoding: 'utf8',
      maxBuffer: 512 * 1024,
      timeout: 10_000,
      windowsHide: true,
      shell: false,
      signal,
      env: javascript ? { ...process.env, ELECTRON_RUN_AS_NODE: '1' } : process.env,
    },
  );
  return parseDashboard(stdout);
}

module.exports = { fetchDashboard };
