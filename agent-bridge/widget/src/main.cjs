'use strict';

const { app, BrowserWindow, clipboard, ipcMain, Menu, nativeImage, screen, session, Tray } = require('electron');
const fs = require('node:fs');
const path = require('node:path');
const { execFile } = require('node:child_process');
const { pathToFileURL } = require('node:url');
const { fetchDashboard } = require('./poll.cjs');
const { normalizeGroupOpen } = require('./metrics.js');
const { effortOptions, modelOptions, validateControl, authorizeAdminAction } = require('./control.cjs');

const root = path.join(__dirname, '..');
const width = 340;
const minHeight = 46;
const intervals = [5, 10, 30];
const command = process.argv.includes('--widget-status') ? 'status'
  : process.argv.includes('--widget-stop') ? 'stop'
    : process.argv.includes('--widget-start') ? 'start' : 'show';
const capture = process.argv.includes('--capture') || process.env.BRIDGE_CAPTURE === '1';
const captureFeed = process.argv.includes('--capture-feed') || process.env.BRIDGE_CAPTURE_FEED === '1';
const defaults = { alwaysOnTop: true, showInTaskbar: false, interval: 5, collapsed: false, compact: false, opacity: 100, fontSize: 12, sort: 'urgency', groupOpen: { working: true, free: false } };
const settingsPath = path.join(app.getPath('userData'), 'widget.json');
const appIcon = path.join(root, 'assets', 'agent-bridge.png');

app.setName('Agent Bridge');
if (process.platform === 'linux') {
  app.setDesktopName('agent-bridge.desktop');
  app.commandLine.appendSwitch('class', 'agent-bridge');
}

let window;
let tray;
let settings = defaults;
let snapshot = { data: null, disconnected: false };
let pollingTimer;
let currentPoll;
let saveTimer;
let captureStarted = false;
let quitting = false;

app.commandLine.appendSwitch('disable-background-networking');
app.commandLine.appendSwitch('disable-extensions');
app.commandLine.appendSwitch('disk-cache-size', '1048576');
app.commandLine.appendSwitch('js-flags', '--max-old-space-size=128');
if (process.platform === 'linux') {
  app.commandLine.appendSwitch('ozone-platform-hint', 'auto');
  if (process.env.BRIDGE_WIDGET_X11 === '1') {
    app.commandLine.appendSwitch('ozone-platform', 'x11');
    app.commandLine.appendSwitch('use-gl', 'angle');
    app.commandLine.appendSwitch('use-angle', 'swiftshader');
  }
}

function readSettings() {
  try {
    const stored = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
    return {
      alwaysOnTop: stored.alwaysOnTop !== false,
      showInTaskbar: stored.showInTaskbar === true,
      collapsed: stored.collapsed === true,
      interval: intervals.includes(stored.interval) ? stored.interval : defaults.interval,
      compact: stored.compact === true,
      opacity: [80, 90, 100].includes(stored.opacity) ? stored.opacity : defaults.opacity,
      fontSize: [11, 12, 14].includes(stored.fontSize) ? stored.fontSize : defaults.fontSize,
      sort: stored.sort === 'manual' ? 'manual' : 'urgency',
      groupOpen: normalizeGroupOpen(stored.groupOpen),
      bounds: stored.bounds,
    };
  } catch {
    return { ...defaults };
  }
}

function saveSettings() {
  clearTimeout(saveTimer);
  if (window && !window.isDestroyed()) settings.bounds = window.getBounds();
  try {
    fs.mkdirSync(path.dirname(settingsPath), { recursive: true });
    fs.writeFileSync(`${settingsPath}.tmp`, JSON.stringify(settings), { mode: 0o600 });
    fs.renameSync(`${settingsPath}.tmp`, settingsPath);
  } catch (error) {
    console.error('No se pudieron guardar los ajustes del widget:', error.message);
  }
}

function visibleBounds(stored) {
  const keys = ['x', 'y', 'width', 'height'];
  const valid = stored && keys.every((key) => Number.isSafeInteger(stored[key])) &&
    stored.width > 0 && stored.height > 0;
  const area = (valid ? screen.getDisplayMatching(stored) : screen.getPrimaryDisplay()).workArea;
  const w = Math.min(area.width, valid ? Math.max(300, Math.min(420, stored.width)) : width);
  const h = Math.min(area.height, Math.max(minHeight, valid ? stored.height : 140));
  return {
    width: w,
    height: h,
    x: Math.max(area.x, Math.min(area.x + area.width - w, valid ? stored.x : area.x + area.width - w - 18)),
    y: Math.max(area.y, Math.min(area.y + area.height - h, valid ? stored.y : area.y + 18)),
  };
}

function showWindow() {
  if (!window || window.isDestroyed()) return;
  window.show();
  window.focus();
}

function updateTray() {
  if (!tray) return;
  tray.setContextMenu(Menu.buildFromTemplate([
    { label: 'Mostrar', click: showWindow },
    { label: 'Ocultar', click: () => window.hide() },
    {
      label: 'Mostrar en la barra de tareas',
      type: 'checkbox',
      checked: settings.showInTaskbar,
      click: ({ checked }) => {
        settings.showInTaskbar = checked;
        window.setSkipTaskbar(!checked);
        saveSettings();
        updateTray();
      },
    },
    {
      label: 'Siempre visible',
      type: 'checkbox',
      checked: settings.alwaysOnTop,
      click: ({ checked }) => {
        settings.alwaysOnTop = checked;
        window.setAlwaysOnTop(checked);
        saveSettings();
        updateTray();
      },
    },
    {
      label: 'Intervalo de refresco',
      submenu: intervals.map((seconds) => ({
        label: `${seconds} s`,
        type: 'radio',
        checked: settings.interval === seconds,
        click: () => {
          settings.interval = seconds;
          saveSettings();
          updateTray();
          if (!currentPoll) poll();
        },
      })),
    },
    { label: 'Vista compacta', type: 'checkbox', checked: settings.compact, click: ({ checked }) => { settings.compact = checked; saveSettings(); window.webContents.send('dashboard:settings', settings); updateTray(); } },
    { label: 'Orden por urgencia', type: 'checkbox', checked: settings.sort === 'urgency', click: ({ checked }) => { settings.sort = checked ? 'urgency' : 'manual'; saveSettings(); window.webContents.send('dashboard:settings', settings); updateTray(); } },
    { label: 'Opacidad', submenu: [80, 90, 100].map((value) => ({ label: `${value}%`, type: 'radio', checked: settings.opacity === value, click: () => { settings.opacity = value; saveSettings(); window.webContents.send('dashboard:settings', settings); updateTray(); } })) },
    { label: 'Tamaño de letra', submenu: [11, 12, 14].map((value) => ({ label: `${value}px`, type: 'radio', checked: settings.fontSize === value, click: () => { settings.fontSize = value; saveSettings(); window.webContents.send('dashboard:settings', settings); updateTray(); } })) },
    { type: 'separator' },
    { label: 'Salir', click: () => app.quit() },
  ]));
}

function feedScript() {
  const candidates = [
    process.env.BRIDGE_WIDGET_CMD && path.join(path.dirname(process.env.BRIDGE_WIDGET_CMD), 'bridge-feed'),
    path.join(require('node:os').homedir(), '.claude-bridge', 'bin', 'bridge-feed'),
    path.join(root, '..', 'scripts', 'bridge-feed'),
  ].filter(Boolean);
  return candidates.find((file) => { try { fs.accessSync(file, fs.constants.X_OK); return true; } catch { return false; } });
}

function targetAgent(event, name) {
  if (!window || event.sender !== window.webContents || event.senderFrame !== window.webContents.mainFrame || typeof name !== 'string' || !/^[A-Za-z0-9_-]{1,48}$/.test(name)) return null;
  return snapshot.data?.agents?.find((agent) => agent.name === name) || null;
}

function accountHome(name) {
  const bridge = process.env.BRIDGE_DIR || path.join(require('node:os').homedir(), '.claude-bridge');
  try { return fs.readFileSync(path.join(bridge, 'names.conf'), 'utf8').split(/\r?\n/).find((line) => line.split('=')[1] === name)?.split('=')[0] || ''; } catch { return ''; }
}

function sessionIdentity() {
  if (process.env.BRIDGE_NAME) return process.env.BRIDGE_NAME;
  const bridge = process.env.BRIDGE_DIR || path.join(require('node:os').homedir(), '.claude-bridge');
  if (process.env.CLAUDE_CONFIG_DIR) {
    try { return fs.readFileSync(path.join(bridge, 'names.conf'), 'utf8').split(/\r?\n/).find((line) => line.split('=')[0] === process.env.CLAUDE_CONFIG_DIR.replace(/\/$/, ''))?.split('=')[1] || ''; } catch { return ''; }
  }
  const codexHome = (process.env.CODEX_HOME || path.join(require('node:os').homedir(), '.codex')).replace(/\/$/, '');
  try { return fs.readFileSync(path.join(bridge, 'names.conf'), 'utf8').split(/\r?\n/).find((line) => line.split('=')[0] === codexHome)?.split('=')[1] || ''; } catch { return ''; }
}

function adminActionAllowed() {
  const admin = snapshot.data?.agents?.find((item) => item.role === 'admin')?.name;
  let recordedAdmin = '';
  try { recordedAdmin = fs.readFileSync(path.join(process.env.BRIDGE_DIR || path.join(require('node:os').homedir(), '.claude-bridge'), 'admin'), 'utf8').trim(); } catch {}
  return Boolean(admin && admin === recordedAdmin && sessionIdentity() === admin);
}

function runAdminAction(agent, args) {
  const script = feedScript();
  if (!script) return Promise.reject(new Error('No se encontró el CLI del bridge'));
  const commandPath = path.join(path.dirname(script), 'agent');
  const admin = snapshot.data?.agents?.find((item) => item.role === 'admin')?.name;
  if (!adminActionAllowed() || !agent || agent.role === 'admin') return Promise.reject(new Error(sessionIdentity() !== admin ? 'Para cambiar workers, inicia el widget desde la sesión admin.' : 'Acción reservada a workers y al admin activo'));
  let recordedAdmin = ''; try { recordedAdmin = fs.readFileSync(path.join(process.env.BRIDGE_DIR || path.join(require('node:os').homedir(), '.claude-bridge'), 'admin'), 'utf8').trim(); } catch {}
  const authError = authorizeAdminAction({ dashboardAdmin: admin, recordedAdmin, sessionName: sessionIdentity(), target: agent });
  if (authError) return Promise.reject(new Error(authError));
  return new Promise((resolve, reject) => execFile(commandPath, args, {
    encoding: 'utf8', timeout: 8000, maxBuffer: 128 * 1024,
    env: { ...process.env, BRIDGE_NAME: admin },
  }, (error, stdout, stderr) => error ? reject(new Error((stderr || error.message).trim())) : resolve(stdout.trim())));
}

async function poll(force = false) {
  clearTimeout(pollingTimer);
  if (quitting || !window || window.isDestroyed() || (!force && (!window.isVisible() || window.isMinimized())) || currentPoll) return;
  const started = Date.now();
  currentPoll = new AbortController();
  const signal = currentPoll.signal;
  try {
    snapshot = { data: await fetchDashboard(signal), disconnected: false };
    failures = 0;
  } catch (error) {
    // A cancelled poll (window hidden/shown) is not a connection failure.
    if (signal.aborted) { currentPoll = undefined; return rearm(started); }
    failures += 1;
    console.error('poll falló:', error && error.message);
    if (failures >= 3) snapshot = { ...snapshot, disconnected: true };
  } finally {
    currentPoll = undefined;
  }
  if (quitting) return;
  if (!window.isDestroyed() && !window.webContents.isLoadingMainFrame()) {
    window.webContents.send('dashboard:update', snapshot);
  }
  rearm(started);
}

let failures = 0;
function rearm(started) {
  if (quitting || !window || window.isDestroyed()) return;
  if (window.isVisible() && !window.isMinimized()) pollingTimer = setTimeout(poll, Math.max(0, settings.interval * 1000 - (Date.now() - started)));
}

async function captureWindow() {
  if (captureStarted) return;
  captureStarted = true;
  try {
    // Wait for the renderer to paint at the size requested in the same IPC message.
    await new Promise((resolve) => setTimeout(resolve, 350));
    const image = await window.webContents.capturePage();
    if (image.isEmpty()) throw new Error('La ventana no produjo una imagen');
    const filename = path.join(root, 'docs', 'screenshot.png');
    fs.mkdirSync(path.dirname(filename), { recursive: true });
    fs.writeFileSync(filename, image.toPNG());
    console.log(`Captura guardada en ${filename}`);
    app.quit();
  } catch (error) {
    console.error(error.message);
    app.exit(1);
  }
}

async function createWidget() {
  settings = readSettings();

  if (process.platform === 'darwin') {
    app.dock?.hide();
    app.setActivationPolicy?.('accessory');
  }

  const local = session.fromPartition('widget');
  const files = new Set([
    ...['index.html', 'style.css', 'renderer.js', 'metrics.js'].map((name) => path.join(__dirname, name)),
    path.join(root, 'assets', 'agent-bridge-64.png'),
  ].map((filename) => pathToFileURL(filename).href));
  local.webRequest.onBeforeRequest((details, callback) => callback({ cancel: !files.has(details.url) }));
  local.setPermissionCheckHandler(() => false);
  local.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));

  const bounds = visibleBounds(settings.bounds);
  window = new BrowserWindow({
    ...bounds,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    title: 'Agent Bridge',
    icon: appIcon,
    skipTaskbar: !settings.showInTaskbar,
    ...(process.platform === 'win32' ? { type: 'toolbar' } : {}),
    ...(process.platform === 'linux' ? { type: process.env.BRIDGE_WIDGET_X11 === '1' ? 'dock' : 'utility' } : {}),
    // Wayland requires a resizable surface for the compositor to accept smaller dimensions.
    resizable: process.platform === 'linux',
    movable: true,
    maximizable: false,
    fullscreenable: false,
    minWidth: Math.min(300, bounds.width),
    maxWidth: 420,
    minHeight,
    alwaysOnTop: settings.alwaysOnTop,
    show: false,
    webPreferences: {
      session: local,
      preload: path.join(__dirname, 'preload.cjs'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true,
      devTools: false,
      spellcheck: false,
      backgroundThrottling: true,
    },
  });
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', (event) => event.preventDefault());
  window.webContents.on('will-attach-webview', (event) => event.preventDefault());

  const fromWidget = (event) => event.sender === window.webContents &&
    event.senderFrame === window.webContents.mainFrame;
  ipcMain.handle('dashboard:initial', (event) => {
    if (fromWidget(event)) return { snapshot, collapsed: settings.collapsed, settings, captureFeed };
  });
  ipcMain.handle('feed:read', (event, name) => {
    if (!fromWidget(event) || typeof name !== 'string' || !snapshot.data?.agents?.some(a => a.name === name)) return null;
    const unavailable = { name, state: { status: 'unavailable' }, events: [] };
    const script = feedScript();
    if (!script) return unavailable;
    return new Promise((resolve) => {
      const agent = snapshot.data.agents.find(item => item.name === name);
      const limit = agent?.role === 'admin' ? '200' : '60';
      execFile(script, [name, '--json', '--limit', limit], { encoding: 'utf8', timeout: 8000, maxBuffer: 4 * 1024 * 1024, env: process.env }, (error, stdout) => {
        if (error) { console.error('feed falló:', error.message); return resolve(unavailable); }
        try { resolve(JSON.parse(stdout)); } catch { resolve(unavailable); }
      });
    });
  });
  ipcMain.handle('control:options', async (event, name) => {
    const agent = targetAgent(event, name);
    if (!agent) return null;
    if (agent.kind === 'claude') return { model: modelOptions(agent.kind), effort: effortOptions(agent.kind), configuredModel: agent.set_model || 'default', configuredEffort: agent.set_effort || 'default', authorized: adminActionAllowed() };
    if (agent.kind !== 'codex') return { model: [], effort: [], configuredModel: 'default', configuredEffort: 'default', authorized: adminActionAllowed() };
    return new Promise((resolve) => execFile('codex', ['debug', 'models'], { encoding: 'utf8', timeout: 8000, maxBuffer: 2 * 1024 * 1024, env: { ...process.env, CODEX_HOME: accountHome(agent.name) || process.env.CODEX_HOME } }, (error, stdout) => {
      let models = [];
      try { if (!error) models = JSON.parse(stdout).models.filter((m) => m.visibility !== 'hide').map((m) => m.slug); } catch {}
      resolve({ model: modelOptions(agent.kind, models), effort: effortOptions(agent.kind), configuredModel: agent.set_model || 'default', configuredEffort: agent.set_effort || 'default', authorized: adminActionAllowed() });
    }));
  });
  ipcMain.handle('control:execute', async (event, request) => {
    if (!request || typeof request !== 'object') return { ok: false, message: 'Solicitud inválida' };
    const agent = targetAgent(event, request.name);
    if (!agent) return { ok: false, message: 'Agente no disponible en el dashboard' };
    try {
      let codexModels = [];
      if (agent.kind === 'codex' && request.action === 'model') codexModels = await new Promise((resolve) => execFile('codex', ['debug', 'models'], { encoding: 'utf8', timeout: 8000, maxBuffer: 2 * 1024 * 1024, env: { ...process.env, CODEX_HOME: accountHome(agent.name) || process.env.CODEX_HOME } }, (_error, stdout) => { try { resolve(JSON.parse(stdout).models.filter(m => m.visibility !== 'hide').map(m => m.slug)); } catch { resolve([]); } }));
      const validationError = validateControl(agent, request, codexModels);
      if (validationError) throw new Error(validationError);
      if (request.action === 'model') {
        return { ok: true, message: await runAdminAction(agent, ['model', agent.name, request.value]) };
      }
      if (request.action === 'effort') {
        return { ok: true, message: await runAdminAction(agent, ['effort', agent.name, request.value]) };
      }
      if (request.action === 'compact') return { ok: true, message: await runAdminAction(agent, ['compact', agent.name]) };
      throw new Error('Acción no permitida');
    } catch (error) { return { ok: false, message: error.message }; }
  });
  ipcMain.handle('control:copy-compact', (event) => {
    if (!window || event.sender !== window.webContents || event.senderFrame !== window.webContents.mainFrame) return false;
    let recordedAdmin = ''; try { recordedAdmin = fs.readFileSync(path.join(process.env.BRIDGE_DIR || path.join(require('node:os').homedir(), '.claude-bridge'), 'admin'), 'utf8').trim(); } catch {}
    if (!recordedAdmin || !snapshot.data?.agents?.some((agent) => agent.role === 'admin' && agent.name === recordedAdmin)) return false;
    clipboard.writeText('/compact'); return true;
  });
  ipcMain.handle('control:copy-text', (event, value) => {
    if (!window || event.sender !== window.webContents || event.senderFrame !== window.webContents.mainFrame || typeof value !== 'string' || value.length > 4000) return false;
    clipboard.writeText(value); return true;
  });
  ipcMain.on('dashboard:visible', (event, visible) => {
    if (!fromWidget(event) || typeof visible !== 'boolean') return;
    clearTimeout(pollingTimer);
    if (visible) poll(); else currentPoll?.abort();
  });
  ipcMain.on('dashboard:group-open', (event, group, open) => {
    if (!fromWidget(event) || !['working', 'free'].includes(group) || typeof open !== 'boolean') return;
    settings.groupOpen = { ...settings.groupOpen, [group]: open };
    saveSettings();
  });
  ipcMain.on('dashboard:layout', (event, height, collapsed, renderedData) => {
    if (!fromWidget(event) || !Number.isSafeInteger(height) || typeof collapsed !== 'boolean') return;
    const bounds = window.getBounds();
    const area = screen.getDisplayMatching(bounds).workArea;
    // Leave room for panels/docks the compositor doesn't report; the list scrolls past this cap.
    const maxHeight = Math.max(minHeight, Math.floor(Math.min(area.height * 0.85, area.height - 90)));
    const targetHeight = Math.max(minHeight, Math.min(height, maxHeight));
    const y = Math.max(area.y, Math.min(bounds.y, area.y + area.height - targetHeight));
    if (bounds.height !== targetHeight || bounds.y !== y) {
      if (bounds.y !== y) window.setBounds({ y, height: targetHeight });
      else window.setSize(bounds.width, targetHeight);
    }
    if (settings.collapsed !== collapsed) {
      settings.collapsed = collapsed;
      saveSettings();
    }
    if (capture && !captureFeed && renderedData === true && snapshot.data && !snapshot.disconnected) captureWindow();
  });

  window.on('move', () => {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveSettings, 200);
  });
  window.on('resize', () => {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(saveSettings, 200);
  });
  window.on('close', (event) => {
    if (tray && !quitting) {
      event.preventDefault();
      window.hide();
    }
  });
  window.on('show', () => poll());
  window.on('hide', () => { clearTimeout(pollingTimer); currentPoll?.abort(); });
  window.on('minimize', () => { clearTimeout(pollingTimer); currentPoll?.abort(); });

  try {
    const icon = nativeImage.createFromPath(path.join(root, 'assets',
      process.platform === 'win32' ? 'bridge.ico' : process.platform === 'darwin' ? 'bridgeTemplate.png' : 'agent-bridge.png'));
    tray = new Tray(icon);
    tray.setToolTip('Agent Bridge');
    tray.on('click', () => window.isVisible() ? window.hide() : showWindow());
    updateTray();
  } catch (error) {
    console.error('Bandeja del sistema no disponible:', error.message);
  }
  window.once('ready-to-show', showWindow);
  await window.loadFile(path.join(__dirname, 'index.html'));
  poll(true);
  if (capture && captureFeed) {
    setTimeout(() => {
      if (window && !window.isDestroyed()) {
        window.webContents.send('capture:feed');
        setTimeout(captureWindow, 1500);
      }
    }, 2500).unref();
  }
  if (capture) {
    const deadline = setTimeout(() => {
      if (!captureStarted) {
        console.error('No se recibieron datos del bridge para la captura');
        app.exit(1);
      }
    }, 25_000);
    deadline.unref();
  }
}

const acquired = app.requestSingleInstanceLock({ command });
if (!acquired) {
  if (capture) console.error('Cierra la instancia activa antes de capturar');
  app.exit(capture ? 1 : 0);
} else if (command === 'status' || command === 'stop') {
  app.exit(3);
} else {
  app.on('second-instance', (_event, _argv, _cwd, data) => {
    if (data?.command === 'stop') app.quit();
    else if (data?.command === 'show') showWindow();
  });
  app.on('activate', showWindow);
  app.on('before-quit', () => {
    quitting = true;
    clearTimeout(pollingTimer);
    currentPoll?.abort();
    if (window && !window.isDestroyed()) saveSettings();
  });
  app.whenReady().then(createWidget).catch((error) => {
    console.error(error);
    app.exit(1);
  });
}
