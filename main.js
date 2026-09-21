const { app, BrowserWindow, ipcMain, screen, globalShortcut, Notification, Tray, nativeImage, powerMonitor, Menu } = require('electron');
const { execFile } = require('child_process');
const crypto = require('crypto');
const { startSyncServer, spawnNextOccurrence } = require('./server');
// The pairing QR is a convenience, never a reason for the widget to fail to
// start — a missing or broken module just means the settings panel hides it.
let QRCode = null;
try { QRCode = require('qrcode'); } catch { /* pairing falls back to the copyable URL */ }
const calendar = require('./calendar');
const lockin = require('./lockin');
const path = require('path');
const fs = require('fs');

const MARGIN = 20;
const SIZES = {
  collapsed: { width: 96, height: 96 },
  expanded: { width: 400, height: 648 },
};
const SOUNDS_DIR = '/System/Library/Sounds';
const REMINDER_WINDOW_MS = 60 * 60 * 1000; // don't fire for things more than an hour stale
const MEETING_WINDOW_MS = 2 * 60 * 1000;   // a nudge is only useful right on the mark
const STALE_TASK_MS = 3 * 24 * 60 * 60 * 1000;
const PRIORITY_RANK = { high: 0, med: 1 };

let win = null;
let mode = 'collapsed';
let anchor = null; // bottom-left corner of the widget, in screen coords
let dragState = null;
let anchorSaveTimer = null;
let appState = null; // last known task state, used by the reminder loop
let tray = null;
let fileSettings = {};
let syncServer = null;
const SYNC_PORT = 43917;
const firedReminders = new Set();
const firedSummaries = new Set();
const firedMeetings = new Set();

const dataFile = () => path.join(app.getPath('userData'), 'tasks.json');
const settingsFile = () => path.join(app.getPath('userData'), 'settings.json');

function readJson(file) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return null;
  }
}

function writeJson(file, data) {
  try {
    fs.writeFileSync(file, JSON.stringify(data, null, 2));
  } catch (err) {
    console.error('Failed to write', file, err);
  }
}

const clamp = (v, min, max) => Math.min(Math.max(v, min), max);

function defaultAnchor() {
  const wa = screen.getPrimaryDisplay().workArea;
  return { x: wa.x + MARGIN, y: wa.y + wa.height - MARGIN };
}

function boundsFor(m) {
  const { width, height } = SIZES[m];
  const wa = screen.getDisplayNearestPoint(anchor).workArea;
  return {
    x: clamp(anchor.x, wa.x, wa.x + wa.width - width),
    y: clamp(anchor.y - height, wa.y, wa.y + wa.height - height),
    width,
    height,
  };
}

function persistAnchor() {
  clearTimeout(anchorSaveTimer);
  anchorSaveTimer = setTimeout(() => {
    fileSettings.anchor = anchor;
    writeJson(settingsFile(), fileSettings);
  }, 300);
}

function updateAnchorFromWindow() {
  const b = win.getBounds();
  anchor = { x: b.x, y: b.y + b.height };
  persistAnchor();
}

function setMode(m) {
  if (!win) return;
  mode = m;
  win.setBounds(boundsFor(m));
  win.webContents.send('mode-changed', m);
  if (m === 'expanded') {
    win.show();
    win.focus();
    calendar.refresh(); // throttled internally — a no-op if we just looked
  }
}

function toggleMode() {
  setMode(mode === 'collapsed' ? 'expanded' : 'collapsed');
}

/* ---------- Sounds & reminders ---------- */

function listSounds() {
  try {
    return fs
      .readdirSync(SOUNDS_DIR)
      .filter((f) => f.endsWith('.aiff'))
      .map((f) => f.replace(/\.aiff$/, ''))
      .sort();
  } catch {
    return ['Glass'];
  }
}

function playSound(name) {
  const file = path.join(SOUNDS_DIR, `${name}.aiff`);
  if (fs.existsSync(file)) execFile('/usr/bin/afplay', [file], () => {});
}

function settingsOf(state) {
  return (state && state.settings) || {};
}

function fireReminder(task, kind) {
  const key = `${task.id}:${kind}`;
  if (firedReminders.has(key)) return;
  firedReminders.add(key);

  const sound = settingsOf(appState).sound || 'Glass';
  playSound(sound);

  if (Notification.isSupported()) {
    const n = new Notification({
      title: kind === 'start' ? 'Time to start' : 'Deadline today',
      body: task.text,
      silent: true, // we play the chosen sound ourselves
    });
    n.on('click', () => setMode('expanded'));
    n.show();
  }

  if (win) win.webContents.send('reminder-fired', { id: task.id, kind });
}

function checkReminders() {
  if (!appState || !Array.isArray(appState.tasks)) return;
  const now = Date.now();
  const settings = settingsOf(appState);

  for (const task of appState.tasks) {
    if (task.done) continue;

    if (task.startAt && !task.reminded) {
      const ts = Date.parse(task.startAt);
      if (Number.isFinite(ts) && ts <= now && now - ts < REMINDER_WINDOW_MS) {
        fireReminder(task, 'start');
      }
    }

    if (settings.deadlineReminders !== false && task.due && !task.dueReminded) {
      const ts = Date.parse(`${task.due}T${settings.deadlineTime || '09:00'}`);
      if (Number.isFinite(ts) && ts <= now && now - ts < REMINDER_WINDOW_MS) {
        fireReminder(task, 'due');
      }
    }
  }

  checkMeetings(now, settings);
  checkSummaries(now, settings);
}

/* ---------- Pre-meeting nudges ---------- */

function fireMeetingNudge(ev) {
  const key = `${ev.id}:${ev.start}`;
  if (firedMeetings.has(key)) return;
  firedMeetings.add(key);

  playSound(settingsOf(appState).sound || 'Glass');
  if (Notification.isSupported()) {
    const mins = Math.max(1, Math.round((Date.parse(ev.start) - Date.now()) / 60000));
    const n = new Notification({
      title: `${ev.title} · in ${mins} min`,
      body: ev.location || ev.calendar || '',
      silent: true,
    });
    n.on('click', () => setMode('expanded'));
    n.show();
  }
  if (win) win.webContents.send('meeting-nudge', { id: ev.id, title: ev.title, start: ev.start });
}

function checkMeetings(now, settings) {
  if (settings.meetingNudge === false) return;
  const lead = (Number(settings.meetingNudgeMinutes) || 10) * 60 * 1000;

  for (const ev of calendar.snapshot().events) {
    if (ev.allDay || ev.status === 'canceled' || !ev.start) continue;
    const ts = Date.parse(ev.start);
    if (!Number.isFinite(ts)) continue;
    // Fire once, close to the mark — never replay a meeting we slept through.
    const fireAt = ts - lead;
    if (fireAt <= now && now - fireAt < MEETING_WINDOW_MS) fireMeetingNudge(ev);
  }
}

/* ---------- Morning brief & weekly review ---------- */

function localDateStr(d) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

const SUMMARY_WINDOW_MS = 6 * 60 * 60 * 1000;

function fireSummary(kind, title, body, openInsights) {
  const today = localDateStr(new Date());
  const key = `${kind}:${today}`;
  if (firedSummaries.has(key)) return;
  firedSummaries.add(key);

  playSound(settingsOf(appState).sound || 'Glass');
  if (Notification.isSupported()) {
    const n = new Notification({ title, body, silent: true });
    n.on('click', () => {
      setMode('expanded');
      if (openInsights && win) win.webContents.send('open-insights');
    });
    n.show();
  }
  if (win) win.webContents.send('summary-fired', { kind, date: today });
}

function checkSummaries(now, settings) {
  const today = new Date();
  const todayStr = localDateStr(today);
  const tasks = appState.tasks;

  // Morning brief
  if (settings.morningBrief !== false && settings.lastBriefDate !== todayStr) {
    const ts = Date.parse(`${todayStr}T${settings.briefTime || '08:30'}`);
    if (Number.isFinite(ts) && ts <= now && now - ts < SUMMARY_WINDOW_MS) {
      const startToday = new Date(today); startToday.setHours(0, 0, 0, 0);
      const pending = tasks.filter((t) => !t.done);
      const dueToday = pending.filter((t) => t.due === todayStr).length;
      const high = pending.filter((t) => t.priority === 'high').length;
      const overdue = pending.filter(
        (t) => t.due && Date.parse(t.due + 'T23:59:59') < startToday.getTime()
      ).length;
      const bits = [];
      if (dueToday) bits.push(`${dueToday} due today`);
      if (high) bits.push(`${high} high priority`);
      if (overdue) bits.push(`${overdue} overdue`);
      const body = bits.length
        ? `${pending.length} pending · ` + bits.join(' · ')
        : pending.length
          ? `${pending.length} pending — pick your first win.`
          : 'Clear runway today. Add your top task.';
      fireSummary('brief', 'Good morning', body, false);
    }
  }

  // Weekly review — Fridays
  if (settings.weeklyReview !== false && today.getDay() === 5 && settings.lastReviewDate !== todayStr) {
    const ts = Date.parse(`${todayStr}T${settings.reviewTime || '17:00'}`);
    if (Number.isFinite(ts) && ts <= now && now - ts < SUMMARY_WINDOW_MS) {
      const weekCut = now - 7 * 24 * 60 * 60 * 1000;
      const doneWeek = tasks.filter((t) => t.done && (t.doneAt || 0) >= weekCut);
      const perLabel = {};
      for (const t of doneWeek) {
        if (t.label) perLabel[t.label] = (perLabel[t.label] || 0) + 1;
      }
      const top = Object.entries(perLabel).sort((a, b) => b[1] - a[1])[0];
      const slipped = tasks.filter(
        (t) => !t.done && t.due && Date.parse(t.due + 'T23:59:59') < now
      ).length;
      const bits = [`${doneWeek.length} done this week`];
      if (top) bits.push(`${top[0]} leads with ${top[1]}`);
      if (slipped) bits.push(`${slipped} slipped`);
      fireSummary('review', 'Your week in review', bits.join(' · '), true);
    }
  }

  // Evening kickoff — the hours when the work actually happens.
  if (settings.eveningKickoff !== false && settings.lastKickoffDate !== todayStr) {
    const ts = Date.parse(`${todayStr}T${settings.kickoffTime || '21:30'}`);
    if (Number.isFinite(ts) && ts <= now && now - ts < SUMMARY_WINDOW_MS) {
      const startToday = new Date(today); startToday.setHours(0, 0, 0, 0);
      const pending = tasks.filter((t) => !t.done);
      const stale = pending.filter((t) => t.createdAt && now - t.createdAt > STALE_TASK_MS).length;
      const doneToday = tasks.filter((t) => t.done && (t.doneAt || 0) >= startToday.getTime()).length;
      const bits = [];
      if (pending.length) bits.push(`${pending.length} still open`);
      if (stale) bits.push(`${stale} aging`);
      if (doneToday) bits.push(`${doneToday} closed today`);
      fireSummary(
        'kickoff',
        'Evening runway',
        bits.length ? bits.join(' · ') : 'Nothing open — rest easy.',
        false
      );
    }
  }
}

/* ---------- Menu bar ---------- */

function dueTime(task) {
  return task.due ? Date.parse(task.due + 'T00:00:00') : Number.MAX_SAFE_INTEGER;
}

function rankedPending() {
  return (appState?.tasks || [])
    .filter((t) => !t.done)
    .sort(
      (a, b) =>
        (PRIORITY_RANK[a.priority] ?? 2) - (PRIORITY_RANK[b.priority] ?? 2) ||
        dueTime(a) - dueTime(b) ||
        b.createdAt - a.createdAt
    );
}

function nextMeeting() {
  const now = Date.now();
  return (
    calendar
      .snapshot()
      .events.find((e) => !e.allDay && e.status !== 'canceled' && Date.parse(e.end || e.start) > now) || null
  );
}

function shortTime(iso) {
  const d = new Date(iso);
  return Number.isFinite(d.getTime())
    ? d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' })
    : '';
}

// Ticking a task off from the menu bar has to do everything the renderer would.
function completeFromTray(id) {
  const task = (appState?.tasks || []).find((t) => t.id === id);
  if (!task || task.done) return;
  task.done = true;
  task.doneAt = Date.now();
  if (task.repeat) spawnNextOccurrence(appState, task);
  writeJson(dataFile(), appState);
  updateTray();
  if (win) win.webContents.send('external-state', appState);
  if (syncServer) syncServer.broadcast();
}

function trayMenu() {
  const items = [{ label: 'Open miTasks', click: () => setMode('expanded') }, { type: 'separator' }];

  const meeting = nextMeeting();
  if (meeting) {
    items.push({ label: `${shortTime(meeting.start)}   ${meeting.title}`.slice(0, 64), enabled: false });
  } else {
    const connected = calendar.snapshot().status === 'fullAccess';
    items.push({ label: connected ? 'No meetings ahead' : 'Calendar not connected', enabled: false });
  }
  items.push({ type: 'separator' });

  const pending = rankedPending();
  if (pending.length) {
    for (const t of pending.slice(0, 5)) {
      items.push({
        label: `${t.priority === 'high' ? '⚑ ' : ''}${t.text}`.slice(0, 64),
        toolTip: 'Mark done',
        click: () => completeFromTray(t.id),
      });
    }
    if (pending.length > 5) items.push({ label: `+ ${pending.length - 5} more…`, enabled: false });
  } else {
    items.push({ label: 'All clear', enabled: false });
  }

  const lock = lockin.status();
  items.push({ type: 'separator' });
  items.push(
    lock.active
      ? {
          label: `Lock-in · ${Math.ceil(lock.remaining / 60000)} min left — stop`,
          click: () => lockin.stop(),
        }
      : {
          label: 'Lock in',
          submenu: [30, 60, 90, 120].map((m) => ({
            label: `${m} minutes`,
            click: () => lockin.start(m, 'tray'),
          })),
        }
  );
  items.push({ type: 'separator' }, { label: 'Quit miTasks', click: () => app.quit() });

  return Menu.buildFromTemplate(items);
}

function updateTray() {
  const enabled = settingsOf(appState).menubar !== false;
  if (!enabled) {
    if (tray) { tray.destroy(); tray = null; }
    return;
  }
  if (!tray) {
    tray = new Tray(nativeImage.createEmpty());
    tray.setToolTip('miTasks');
    // Rebuilt on every click, so the glance is never showing stale state.
    const pop = () => tray.popUpContextMenu(trayMenu());
    tray.on('click', pop);
    tray.on('right-click', pop);
  }
  const pending = (appState?.tasks || []).filter((t) => !t.done).length;
  const awake = lockin.status().active ? '◉ ' : '';
  tray.setTitle(awake + (pending ? `✓ ${pending}` : '✓'), { fontType: 'monospacedDigit' });
}

/* ---------- Window ---------- */

function createWindow() {
  win = new BrowserWindow({
    ...boundsFor('collapsed'),
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
    hasShadow: false,
    resizable: false,
    movable: true,
    fullscreenable: false,
    skipTaskbar: true,
    show: false,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      backgroundThrottling: false,
    },
  });

  win.setAlwaysOnTop(true, 'floating');
  win.setVisibleOnAllWorkspaces(true, { visibleOnFullScreen: false });

  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  win.once('ready-to-show', () => win.show());

  // Panel dragged by its header (native app-region drag) — remember where it lands.
  win.on('moved', () => {
    if (!dragState) updateAnchorFromWindow();
  });

  // Chatbot behavior: clicking away closes the panel back into the bubble.
  win.on('blur', () => {
    if (mode === 'expanded' && !win.webContents.isDevToolsOpened()) {
      setMode('collapsed');
    }
  });
}

if (!app.requestSingleInstanceLock()) {
  app.quit();
}
app.on('second-instance', () => setMode('expanded'));

app.whenReady().then(() => {
  if (process.platform === 'darwin') app.dock.hide();

  fileSettings = readJson(settingsFile()) || {};
  anchor =
    fileSettings.anchor &&
    Number.isFinite(fileSettings.anchor.x) && Number.isFinite(fileSettings.anchor.y)
      ? fileSettings.anchor
      : defaultAnchor();

  if (!fileSettings.syncToken) {
    fileSettings.syncToken = crypto.randomBytes(8).toString('hex');
    writeJson(settingsFile(), fileSettings);
  }

  appState = readJson(dataFile());

  // Phone sync: the widget doubles as a tiny web server for the iPhone app.
  syncServer = startSyncServer({
    port: SYNC_PORT,
    token: fileSettings.syncToken,
    getState: () => {
      if (!appState) appState = { tasks: [], labels: [] };
      if (!Array.isArray(appState.tasks)) appState.tasks = [];
      if (!Array.isArray(appState.labels)) appState.labels = [];
      if (!Array.isArray(appState.notes)) appState.notes = [];
      if (!Array.isArray(appState.focusLog)) appState.focusLog = [];
      return appState;
    },
    commit: (state) => {
      appState = state;
      writeJson(dataFile(), state);
      updateTray();
      if (win) win.webContents.send('external-state', state);
    },
    getCalendar: () => calendar.snapshot(),
    lockin,
  });

  // Lock-in and the agenda both feed the menu bar, so they wire up together.
  lockin.init((status) => {
    if (win) win.webContents.send('lockin-state', status);
    if (syncServer) syncServer.broadcast();
    updateTray();
  });

  calendar.start({
    settings: () => settingsOf(appState),
    notify: (snap) => {
      if (win) win.webContents.send('calendar-state', snap);
      if (syncServer) syncServer.broadcast();
      updateTray();
    },
  });

  createWindow();

  globalShortcut.register('CommandOrControl+Shift+Space', toggleMode);

  screen.on('display-metrics-changed', () => {
    if (win) win.setBounds(boundsFor(mode));
  });

  // Long-running transparent windows can go opaque white after sleep/wake
  // or a GPU reset — re-assert transparency when the system comes back.
  const reassertTransparency = () => {
    if (!win) return;
    win.setBackgroundColor('#00000000');
    win.setBounds(boundsFor(mode));
    win.webContents.invalidate();
  };
  powerMonitor.on('resume', () => {
    reassertTransparency();
    calendar.refresh(true); // meetings may well have moved while we slept
  });
  powerMonitor.on('unlock-screen', reassertTransparency);

  updateTray();

  setInterval(checkReminders, 20 * 1000);
  // First check only once the renderer can receive the reminder-fired event.
  win.webContents.once('did-finish-load', () => setTimeout(checkReminders, 1500));
});

/* Manual drag for the bubble: main follows the cursor, and reports back
   whether the gesture was a drag or a plain click. */
ipcMain.on('drag:start', () => {
  if (!win || dragState) return;
  const cursor = screen.getCursorScreenPoint();
  const [wx, wy] = win.getPosition();
  dragState = {
    offX: cursor.x - wx,
    offY: cursor.y - wy,
    startX: cursor.x,
    startY: cursor.y,
    moved: false,
    timer: setInterval(() => {
      const c = screen.getCursorScreenPoint();
      if (Math.abs(c.x - dragState.startX) + Math.abs(c.y - dragState.startY) > 4) {
        dragState.moved = true;
      }
      if (dragState.moved) {
        win.setPosition(c.x - dragState.offX, c.y - dragState.offY);
      }
    }, 10),
  };
});

ipcMain.handle('drag:end', () => {
  if (!dragState) return false;
  clearInterval(dragState.timer);
  const moved = dragState.moved;
  dragState = null;
  if (moved) updateAnchorFromWindow();
  return moved;
});

ipcMain.handle('state:load', () => readJson(dataFile()));
ipcMain.on('state:save', (_e, state) => {
  appState = state;
  writeJson(dataFile(), state);
  updateTray();
  if (syncServer) syncServer.broadcast();
});
ipcMain.on('mode:set', (_e, m) => setMode(m));
ipcMain.handle('sounds:list', () => listSounds());
ipcMain.on('sounds:preview', (_e, name) => playSound(String(name).replace(/[^\w -]/g, '')));
ipcMain.handle('sync:info', () => ({
  ...(syncServer ? syncServer.urls() : {}),
  public: fileSettings.publicUrl
    ? `${fileSettings.publicUrl}/?key=${fileSettings.syncToken}`
    : null,
}));
/* Calendar — every handler resolves to a plain object so the renderer can
   render an error state instead of throwing. */
ipcMain.handle('calendar:get', () => calendar.snapshot());
ipcMain.handle('calendar:refresh', () => calendar.refresh(true));
ipcMain.handle('calendar:request', () => calendar.requestAccess());
ipcMain.handle('calendar:list', () => calendar.listCalendars());
ipcMain.handle('calendar:create', (_e, body) => calendar.createEvent(body));
ipcMain.handle('calendar:update', (_e, id, body) => calendar.updateEvent(id, body));
ipcMain.handle('calendar:delete', (_e, id) => calendar.deleteEvent(id));

/* Lock-in */
ipcMain.handle('sync:qr', async (_e, url) => {
  if (!url || !QRCode) return null;
  // Dark-on-light with a quiet zone — phone cameras need the contrast.
  return QRCode.toDataURL(url, { width: 360, margin: 2, errorCorrectionLevel: 'M',
    color: { dark: '#141210', light: '#f0eadd' } }).catch(() => null);
});

ipcMain.handle('lockin:status', () => lockin.status());
ipcMain.handle('lockin:start', (_e, minutes, reason) => lockin.start(minutes, reason));
ipcMain.handle('lockin:stop', () => lockin.stop());
ipcMain.handle('lockin:extend', (_e, minutes) => lockin.extend(minutes));

ipcMain.on('app:quit', () => app.quit());
ipcMain.handle('login-item:get', () => app.getLoginItemSettings().openAtLogin);
ipcMain.on('login-item:set', (_e, open) => {
  app.setLoginItemSettings({ openAtLogin: !!open });
});

app.on('will-quit', () => {
  globalShortcut.unregisterAll();
  lockin.stop(false); // never leave a caffeinate assertion behind
  calendar.stop();
});

app.on('window-all-closed', () => app.quit());
