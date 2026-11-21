'use strict';

const { app, BrowserWindow, ipcMain, Menu, nativeImage, screen, session, Tray } = require('electron');
const fs = require('node:fs');
const path = require('node:path');
const { pathToFileURL } = require('node:url');
const { fetchDashboard } = require('./poll.cjs');

const root = path.join(__dirname, '..');
const width = 340;
const minHeight = 46;
const intervals = [5, 10, 30];
const command = process.argv.includes('--widget-status') ? 'status'
  : process.argv.includes('--widget-stop') ? 'stop'
    : process.argv.includes('--widget-start') ? 'start' : 'show';
const capture = process.argv.includes('--capture');
const defaults = { alwaysOnTop: true, showInTaskbar: false, interval: 5, collapsed: false, compact: false, opacity: 100, fontSize: 12, sort: 'urgency' };
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
  const files = new Set(['index.html', 'style.css', 'renderer.js', 'metrics.js'].map(
    (name) => pathToFileURL(path.join(__dirname, name)).href,
  ));
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
    if (fromWidget(event)) return { snapshot, collapsed: settings.collapsed, settings };
  });
  ipcMain.on('dashboard:visible', (event, visible) => {
    if (!fromWidget(event) || typeof visible !== 'boolean') return;
    clearTimeout(pollingTimer);
    if (visible) poll(); else currentPoll?.abort();
  });
  ipcMain.on('dashboard:layout', (event, height, collapsed, renderedData) => {
    if (!fromWidget(event) || !Number.isSafeInteger(height) || typeof collapsed !== 'boolean') return;
    const bounds = window.getBounds();
    const area = screen.getDisplayMatching(bounds).workArea;
    const targetHeight = Math.max(minHeight, Math.min(height, area.height));
    const y = Math.max(area.y, Math.min(bounds.y, area.y + area.height - targetHeight));
    if (bounds.height !== targetHeight || bounds.y !== y) {
      if (bounds.y !== y) window.setBounds({ y, height: targetHeight });
      else window.setSize(bounds.width, targetHeight);
    }
    if (settings.collapsed !== collapsed) {
      settings.collapsed = collapsed;
      saveSettings();
    }
    if (capture && renderedData === true && snapshot.data && !snapshot.disconnected) captureWindow();
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
