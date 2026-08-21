const { app, BrowserWindow, ipcMain, screen, globalShortcut, Notification, Tray, nativeImage, powerMonitor } = require('electron');
const { execFile } = require('child_process');
const path = require('path');
const fs = require('fs');

const MARGIN = 20;
const SIZES = {
  collapsed: { width: 96, height: 96 },
  expanded: { width: 400, height: 648 },
};
const SOUNDS_DIR = '/System/Library/Sounds';
const REMINDER_WINDOW_MS = 60 * 60 * 1000; // don't fire for things more than an hour stale

let win = null;
let mode = 'collapsed';
let anchor = null; // bottom-left corner of the widget, in screen coords
let dragState = null;
let anchorSaveTimer = null;
let appState = null; // last known task state, used by the reminder loop
let tray = null;
const firedReminders = new Set();
const firedSummaries = new Set();

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
  anchorSaveTimer = setTimeout(() => writeJson(settingsFile(), { anchor }), 300);
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

  checkSummaries(now, settings);
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
}

/* ---------- Menu bar ---------- */

function updateTray() {
  const enabled = settingsOf(appState).menubar !== false;
  if (!enabled) {
    if (tray) { tray.destroy(); tray = null; }
    return;
  }
  if (!tray) {
    tray = new Tray(nativeImage.createEmpty());
    tray.setToolTip('miTasks');
    tray.on('click', toggleMode);
  }
  const pending = (appState?.tasks || []).filter((t) => !t.done).length;
  tray.setTitle(pending ? `✓ ${pending}` : '✓', { fontType: 'monospacedDigit' });
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

app.whenReady().then(() => {
  if (process.platform === 'darwin') app.dock.hide();

  const settings = readJson(settingsFile());
  anchor =
    settings && settings.anchor &&
    Number.isFinite(settings.anchor.x) && Number.isFinite(settings.anchor.y)
      ? settings.anchor
      : defaultAnchor();

  appState = readJson(dataFile());

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
  powerMonitor.on('resume', reassertTransparency);
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
});
ipcMain.on('mode:set', (_e, m) => setMode(m));
ipcMain.handle('sounds:list', () => listSounds());
ipcMain.on('sounds:preview', (_e, name) => playSound(String(name).replace(/[^\w -]/g, '')));
ipcMain.on('app:quit', () => app.quit());
ipcMain.handle('login-item:get', () => app.getLoginItemSettings().openAtLogin);
ipcMain.on('login-item:set', (_e, open) => {
  app.setLoginItemSettings({ openAtLogin: !!open });
});

app.on('will-quit', () => globalShortcut.unregisterAll());

app.on('window-all-closed', () => app.quit());
