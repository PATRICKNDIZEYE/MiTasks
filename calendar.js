// Calendar bridge: wraps the native EventKit helper in a cached, polled API.
//
// The helper is a short-lived process — we spawn it, read one JSON payload and
// let it exit. Everything the UI reads comes from `cache`, which a background
// poll keeps warm, so opening the panel never waits on a subprocess.
const { execFile } = require('child_process');
const path = require('path');
const fs = require('fs');

const DAY_MS = 86400000;
const REFRESH_MS = 5 * 60 * 1000;
const WINDOW_BACK_DAYS = 1;   // yesterday, so "ran late" meetings still show
const WINDOW_AHEAD_DAYS = 14;

// Exit code 2 is the helper's dedicated "user hasn't granted access" signal.
const NOT_AUTHORIZED = 2;

let cache = { events: [], calendars: [], status: 'unknown', fetchedAt: 0, error: null };
let refreshTimer = null;
let inFlight = null;
let onChange = () => {};
let getSettings = () => ({});

function helperPath() {
  const { app } = require('electron');
  // Packaged: shipped via extraResource. Dev: straight out of the repo.
  const packaged = path.join(process.resourcesPath, 'mitasks-cal');
  if (app.isPackaged && fs.existsSync(packaged)) return packaged;
  return path.join(__dirname, 'native', 'bin', 'mitasks-cal');
}

function run(args, { stdin = null, timeout = 20000 } = {}) {
  return new Promise((resolve) => {
    const bin = helperPath();
    if (!fs.existsSync(bin)) {
      resolve({ ok: false, code: -1, data: { error: 'calendar helper not built' } });
      return;
    }
    const child = execFile(bin, args, { timeout, maxBuffer: 8 * 1024 * 1024 }, (err, stdout) => {
      let data = null;
      try { data = JSON.parse(stdout); } catch { /* helper died before printing */ }
      const code = err && typeof err.code === 'number' ? err.code : err ? 1 : 0;
      resolve({
        ok: !err,
        code,
        data: data ?? { error: err ? err.message : 'no output from calendar helper' },
      });
    });
    if (stdin !== null) {
      child.stdin.end(typeof stdin === 'string' ? stdin : JSON.stringify(stdin));
    }
  });
}

/* ---------- Permission ---------- */

async function authStatus() {
  const res = await run(['auth'], { timeout: 8000 });
  return (res.data && res.data.status) || 'unknown';
}

// The prompt is modal and user-driven, so this one gets a long leash.
async function requestAccess() {
  const res = await run(['request'], { timeout: 130000 });
  const status = (res.data && res.data.status) || 'unknown';
  cache.status = status;
  if (status === 'fullAccess') await refresh(true);
  return res.data || { status };
}

/* ---------- Reads ---------- */

function windowRange() {
  const from = new Date();
  from.setHours(0, 0, 0, 0);
  from.setTime(from.getTime() - WINDOW_BACK_DAYS * DAY_MS);
  const to = new Date(from.getTime() + (WINDOW_BACK_DAYS + WINDOW_AHEAD_DAYS) * DAY_MS);
  return { from: from.toISOString(), to: to.toISOString() };
}

async function listCalendars() {
  const res = await run(['calendars']);
  if (!res.ok) {
    if (res.code === NOT_AUTHORIZED) cache.status = res.data.status || 'denied';
    return [];
  }
  cache.calendars = Array.isArray(res.data) ? res.data : [];
  return cache.calendars;
}

async function fetchEvents() {
  const { from, to } = windowRange();
  const args = ['events', '--from', from, '--to', to];

  // null/undefined means every calendar; an array is an explicit pick, and an
  // empty array genuinely means "show me nothing".
  const selected = getSettings().calendarIds;
  if (Array.isArray(selected)) {
    if (!selected.length) return [];
    args.push('--cal', selected.join(','));
  }

  const res = await run(args, { timeout: 25000 });
  if (!res.ok) {
    if (res.code === NOT_AUTHORIZED) cache.status = res.data.status || 'denied';
    cache.error = res.data.error || 'calendar read failed';
    return null;
  }
  cache.error = null;
  return Array.isArray(res.data) ? res.data : [];
}

/// Pulls calendars + events into the cache. Overlapping calls share one run.
async function refresh(force = false) {
  if (inFlight) return inFlight;
  if (!force && Date.now() - cache.fetchedAt < 30000) return cache;

  inFlight = (async () => {
    const status = await authStatus();
    cache.status = status;
    if (status !== 'fullAccess') {
      cache.events = [];
      cache.fetchedAt = Date.now();
      return cache;
    }
    await listCalendars();
    const events = await fetchEvents();
    if (events) cache.events = events;
    cache.fetchedAt = Date.now();
    return cache;
  })();

  try {
    await inFlight;
  } finally {
    inFlight = null;
  }
  onChange(cache);
  return cache;
}

/* ---------- Writes ---------- */

async function createEvent(body) {
  const res = await run(['create'], { stdin: body });
  if (res.ok) await refresh(true);
  return res.ok ? { ok: true, event: res.data } : { ok: false, error: res.data.error };
}

async function updateEvent(id, body) {
  const res = await run(['update', '--id', String(id)], { stdin: body });
  if (res.ok) await refresh(true);
  return res.ok ? { ok: true, event: res.data } : { ok: false, error: res.data.error };
}

async function deleteEvent(id) {
  const res = await run(['delete', '--id', String(id)]);
  if (res.ok) await refresh(true);
  return res.ok ? { ok: true } : { ok: false, error: res.data.error };
}

/* ---------- Lifecycle ---------- */

function start({ settings, notify }) {
  getSettings = settings || getSettings;
  onChange = notify || onChange;
  refresh(true);
  clearInterval(refreshTimer);
  refreshTimer = setInterval(() => refresh(true), REFRESH_MS);
}

function stop() {
  clearInterval(refreshTimer);
  refreshTimer = null;
}

const snapshot = () => cache;

module.exports = {
  authStatus,
  requestAccess,
  listCalendars,
  refresh,
  snapshot,
  createEvent,
  updateEvent,
  deleteEvent,
  start,
  stop,
};
