'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('bridgeWidget', {
  initial: () => ipcRenderer.invoke('dashboard:initial'),
  readFeed: (name) => ipcRenderer.invoke('feed:read', name),
  onCaptureFeed: (callback) => ipcRenderer.on('capture:feed', () => callback()),
  onUpdate: (callback) => {
    ipcRenderer.on('dashboard:update', (_event, snapshot) => callback(snapshot));
  },
  onSettings: (callback) => ipcRenderer.on('dashboard:settings', (_event, settings) => callback(settings)),
  visibility: (visible) => ipcRenderer.send('dashboard:visible', visible),
  setGroupOpen: (group, open) => ipcRenderer.send('dashboard:group-open', group, open),
  layout: (height, collapsed, renderedData) => {
    ipcRenderer.send('dashboard:layout', height, collapsed, renderedData);
  },
});
