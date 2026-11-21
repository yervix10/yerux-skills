'use strict';

const { spawn, spawnSync } = require('node:child_process');
const path = require('node:path');
const { setTimeout: delay } = require('node:timers/promises');

const root = path.join(__dirname, '..');
const absent = 3;

async function launch() {
  const action = process.argv[2] ?? 'start';
  if (!['start', 'stop', 'status'].includes(action) || process.argv.length > 3) {
    throw new Error('Uso: agent-bridge-widget [start|stop|status]');
  }
  if (process.platform === 'linux' && !process.env.DISPLAY && !process.env.WAYLAND_DISPLAY) {
    throw new Error('No hay una sesión gráfica disponible');
  }
  const executable = require('electron');
  const env = { ...process.env };
  delete env.ELECTRON_RUN_AS_NODE;

  if (action === 'start') {
    const child = spawn(executable, [root, '--widget-start'], {
      cwd: root,
      env,
      detached: true,
      stdio: 'ignore',
      windowsHide: true,
    });
    await new Promise((resolve, reject) => {
      child.once('spawn', resolve);
      child.once('error', reject);
    });
    child.unref();
    return;
  }

  function request(command) {
    const result = spawnSync(executable, [root, `--widget-${command}`], {
      cwd: root,
      env,
      stdio: ['ignore', 'ignore', 'pipe'],
      timeout: 5000,
      windowsHide: true,
    });
    if (result.error) throw result.error;
    if (result.status !== 0 && result.status !== absent) {
      const reason = result.stderr.toString().trim() || (result.signal ?? result.status);
      throw new Error(`Electron no pudo consultar la instancia: ${reason}`);
    }
    return result.status === 0;
  }

  const running = request(action);
  if (action === 'status') {
    console.log(running ? 'Widget activo' : 'Widget detenido');
    process.exitCode = running ? 0 : 1;
    return;
  }
  if (running) {
    const deadline = Date.now() + 5000;
    while (request('status')) {
      if (Date.now() >= deadline) throw new Error('El widget no se detuvo a tiempo');
      await delay(150);
    }
  }
  console.log('Widget detenido');
}

launch().catch((error) => {
  if (error.code === 'MODULE_NOT_FOUND') {
    console.error('Electron no está instalado. Ejecuta npm install en el directorio del widget.');
  } else {
    console.error(error.message);
  }
  process.exitCode = 2;
});
