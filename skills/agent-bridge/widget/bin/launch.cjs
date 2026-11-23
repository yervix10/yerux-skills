'use strict';

const { spawn, spawnSync } = require('node:child_process');
const path = require('node:path');
const { setTimeout: delay } = require('node:timers/promises');

const root = path.join(__dirname, '..');
const absent = 3;

// Widget main processes (children carry --type=...): any copy started from any folder, e.g. a dev clone and ~/.agent-bridge/app.
function widgetPids(exceptRoot) {
  if (process.platform === 'win32') return [];
  const out = spawnSync('ps', ['-eo', 'pid=,args='], { encoding: 'utf8', timeout: 5000 });
  if (out.status !== 0) return [];
  return out.stdout.split('\n').map((line) => /^\s*(\d+)\s+(.*)$/.exec(line)).filter(Boolean)
    .filter((m) => Number(m[1]) !== process.pid && /--widget-start(\s|$)/.test(m[2]) && !/--type=/.test(m[2]) && /electron/i.test(m[2]) && /agent-bridge[\\/]widget/.test(m[2]) && !(exceptRoot && m[2].includes(exceptRoot)))
    .map((m) => Number(m[1]));
}
function killStray(exceptRoot) {
  const pids = widgetPids(exceptRoot);
  for (const pid of pids) { try { process.kill(pid, 'SIGTERM'); } catch { /* already gone */ } }
  return pids.length;
}

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
  const useX11 = process.platform === 'linux' && env.BRIDGE_WIDGET_X11 === '1' && Boolean(env.DISPLAY);
  if (useX11) env.BRIDGE_WIDGET_X11 = '1';
  const graphicsArgs = useX11
    ? ['--ozone-platform=x11', '--use-gl=angle', '--use-angle=swiftshader'] : [];

  if (action === 'start') {
    killStray(root); // a copy started from another folder would run old code next to this one
    const child = spawn(executable, [...graphicsArgs, root, '--widget-start'], {
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

  const running = request(action) || (action === 'status' && widgetPids().length > 0);
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
  if (action === 'stop') {
    // copies the graceful request could not reach (other install folder, hung instance)
    if (killStray() > 0) {
      const until = Date.now() + 4000;
      while (widgetPids().length > 0 && Date.now() < until) await delay(150);
      for (const pid of widgetPids()) { try { process.kill(pid, 'SIGKILL'); } catch { /* gone */ } }
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
