'use strict';

const { execFile } = require('node:child_process');
const { homedir } = require('node:os');
const path = require('node:path');
const { promisify } = require('node:util');
const { parseDashboard } = require('./dashboard.cjs');

const run = promisify(execFile);

async function fetchDashboard(signal) {
  const bridgeRoot = path.resolve(process.env.BRIDGE_DIR || path.join(homedir(), '.claude-bridge'));
  const command = process.env.BRIDGE_WIDGET_CMD ||
    (process.platform === 'win32' ? '' : path.join(bridgeRoot, 'bin', 'agent'));
  if (!command) throw new Error('Configura BRIDGE_WIDGET_CMD');

  if (process.platform !== 'win32') {
    const relative = path.relative(bridgeRoot, path.resolve(command));
    if (!relative || relative === '..' || relative.startsWith(`..${path.sep}`) || path.isAbsolute(relative)) {
      throw new Error('BRIDGE_WIDGET_CMD debe apuntar dentro de ~/.claude-bridge');
    }
  }

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
