const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  loadState: () => ipcRenderer.invoke('state:load'),
  saveState: (state) => ipcRenderer.send('state:save', state),
  setMode: (mode) => ipcRenderer.send('mode:set', mode),
  onModeChanged: (cb) => ipcRenderer.on('mode-changed', (_e, mode) => cb(mode)),
  onReminderFired: (cb) => ipcRenderer.on('reminder-fired', (_e, info) => cb(info)),
  onSummaryFired: (cb) => ipcRenderer.on('summary-fired', (_e, info) => cb(info)),
  onExternalState: (cb) => ipcRenderer.on('external-state', (_e, state) => cb(state)),
  getSyncInfo: () => ipcRenderer.invoke('sync:info'),
  onOpenInsights: (cb) => ipcRenderer.on('open-insights', () => cb()),
  dragStart: () => ipcRenderer.send('drag:start'),
  dragEnd: () => ipcRenderer.invoke('drag:end'),
  listSounds: () => ipcRenderer.invoke('sounds:list'),
  previewSound: (name) => ipcRenderer.send('sounds:preview', name),
  onMeetingNudge: (cb) => ipcRenderer.on('meeting-nudge', (_e, info) => cb(info)),

  // Calendar (EventKit bridge, two-way)
  calendarGet: () => ipcRenderer.invoke('calendar:get'),
  calendarRefresh: () => ipcRenderer.invoke('calendar:refresh'),
  calendarRequest: () => ipcRenderer.invoke('calendar:request'),
  calendarList: () => ipcRenderer.invoke('calendar:list'),
  calendarCreate: (body) => ipcRenderer.invoke('calendar:create', body),
  calendarUpdate: (id, body) => ipcRenderer.invoke('calendar:update', id, body),
  calendarDelete: (id) => ipcRenderer.invoke('calendar:delete', id),
  onCalendarState: (cb) => ipcRenderer.on('calendar-state', (_e, snap) => cb(snap)),

  // Lock-in (caffeinate)
  lockinStatus: () => ipcRenderer.invoke('lockin:status'),
  lockinStart: (minutes, reason) => ipcRenderer.invoke('lockin:start', minutes, reason),
  lockinStop: () => ipcRenderer.invoke('lockin:stop'),
  lockinExtend: (minutes) => ipcRenderer.invoke('lockin:extend', minutes),
  onLockinState: (cb) => ipcRenderer.on('lockin-state', (_e, s) => cb(s)),

  quit: () => ipcRenderer.send('app:quit'),
  getOpenAtLogin: () => ipcRenderer.invoke('login-item:get'),
  setOpenAtLogin: (open) => ipcRenderer.send('login-item:set', open),
});
