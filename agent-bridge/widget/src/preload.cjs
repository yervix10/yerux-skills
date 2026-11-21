'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('bridgeWidget', {
  initial: () => ipcRenderer.invoke('dashboard:initial'),
  onUpdate: (callback) => {
    ipcRenderer.on('dashboard:update', (_event, snapshot) => callback(snapshot));
  },
  layout: (height, collapsed, renderedData) => {
    ipcRenderer.send('dashboard:layout', height, collapsed, renderedData);
  },
});
