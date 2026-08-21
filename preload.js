const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  loadState: () => ipcRenderer.invoke('state:load'),
  saveState: (state) => ipcRenderer.send('state:save', state),
  setMode: (mode) => ipcRenderer.send('mode:set', mode),
  onModeChanged: (cb) => ipcRenderer.on('mode-changed', (_e, mode) => cb(mode)),
  onReminderFired: (cb) => ipcRenderer.on('reminder-fired', (_e, info) => cb(info)),
  onSummaryFired: (cb) => ipcRenderer.on('summary-fired', (_e, info) => cb(info)),
  onOpenInsights: (cb) => ipcRenderer.on('open-insights', () => cb()),
  dragStart: () => ipcRenderer.send('drag:start'),
  dragEnd: () => ipcRenderer.invoke('drag:end'),
  listSounds: () => ipcRenderer.invoke('sounds:list'),
  previewSound: (name) => ipcRenderer.send('sounds:preview', name),
  quit: () => ipcRenderer.send('app:quit'),
  getOpenAtLogin: () => ipcRenderer.invoke('login-item:get'),
  setOpenAtLogin: (open) => ipcRenderer.send('login-item:set', open),
});
