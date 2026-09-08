// Lock-in: holds a caffeinate assertion so the Mac won't idle-sleep or lock.
//
// caffeinate is spawned as a child and killed to cancel. -u is the flag that
// actually keeps the lock screen away (it asserts "the user is active"), and it
// needs -t or it expires after five seconds.
const { spawn } = require('child_process');

const CAFFEINATE = '/usr/bin/caffeinate';
const MIN_MINUTES = 1;
const MAX_MINUTES = 8 * 60;

let child = null;
let session = null; // { startedAt, endAt, minutes, reason }
let onChange = () => {};

function clamp(minutes) {
  const n = Math.round(Number(minutes));
  if (!Number.isFinite(n)) return 60;
  return Math.min(MAX_MINUTES, Math.max(MIN_MINUTES, n));
}

function status() {
  if (!session) return { active: false };
  return {
    active: true,
    startedAt: session.startedAt,
    endAt: session.endAt,
    minutes: session.minutes,
    reason: session.reason,
    remaining: Math.max(0, session.endAt - Date.now()),
  };
}

function clear(notify = true) {
  session = null;
  child = null;
  if (notify) onChange(status());
}

/// Starts (or restarts) a lock-in. Returns the resulting status.
function start(minutes, reason = 'manual') {
  const mins = clamp(minutes);
  stop(false); // a second start replaces the first rather than stacking assertions

  const seconds = mins * 60;
  //  -d display  -i idle sleep  -m disk  -s system (AC only)  -u user active
  const proc = spawn(CAFFEINATE, ['-d', '-i', '-m', '-s', '-u', '-t', String(seconds)], {
    stdio: 'ignore',
    detached: false,
  });

  proc.on('error', () => clear());
  // Covers both the -t timeout firing and anything killing caffeinate from outside.
  proc.on('exit', () => {
    if (child === proc) clear();
  });

  child = proc;
  session = {
    startedAt: Date.now(),
    endAt: Date.now() + seconds * 1000,
    minutes: mins,
    reason,
  };
  onChange(status());
  return status();
}

function stop(notify = true) {
  if (child) {
    const proc = child;
    child = null; // detach first so the exit handler doesn't double-fire
    try { proc.kill('SIGTERM'); } catch { /* already gone */ }
  }
  const wasActive = !!session;
  session = null;
  if (notify && wasActive) onChange(status());
  return status();
}

/// Extends an active session, or starts a fresh one if nothing is running.
function extend(extraMinutes) {
  if (!session) return start(extraMinutes);
  const remainingMs = Math.max(0, session.endAt - Date.now());
  const total = Math.round(remainingMs / 60000) + clamp(extraMinutes);
  return start(total, session.reason);
}

function init(notify) {
  onChange = notify || onChange;
}

module.exports = { init, start, stop, extend, status, MIN_MINUTES, MAX_MINUTES };
