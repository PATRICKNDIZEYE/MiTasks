// Voice capture for the widget: wraps the mitasks-dictate Swift helper.
//
// Only one session runs at a time. Partial transcripts stream back as they
// arrive so the UI can show words appearing; the final transcript resolves the
// promise returned by stop().
const { execFile, spawn } = require('child_process');
const path = require('path');
const fs = require('fs');

const MAX_SECONDS = 120;

let child = null;
let onPartial = () => {};
let pending = null; // { resolve } for the in-flight stop()

function helperPath() {
  // Packaged, the helper sits beside app.asar in Resources; in dev it is the
  // freshly compiled binary under native/bin.
  const packaged = path.join(process.resourcesPath || '', 'mitasks-dictate');
  if (fs.existsSync(packaged)) return packaged;
  return path.join(__dirname, 'native', 'bin', 'mitasks-dictate');
}

function run(args, timeout = 130000) {
  return new Promise((resolve) => {
    execFile(helperPath(), args, { timeout }, (err, stdout) => {
      const line = String(stdout || '').trim().split('\n').filter(Boolean).pop();
      let parsed = null;
      try { parsed = line ? JSON.parse(line) : null; } catch { /* not JSON */ }
      if (parsed) { resolve(parsed); return; }
      resolve({ error: err ? err.message : 'no response from dictation helper' });
    });
  });
}

/// Current permission, without ever triggering a prompt.
function status() {
  return run(['auth'], 10000);
}

/// Triggers the microphone and speech prompts. Must be called from a user
/// gesture or the dialogs look like they came from nowhere.
function requestAccess() {
  return run(['request']);
}

const isListening = () => child !== null;

/**
 * Starts a listening session. `notify` receives each partial transcript.
 * Resolves once the helper is running, or rejects if it refused to start.
 */
function start(notify) {
  if (child) return Promise.resolve({ ok: true, already: true });
  onPartial = notify || (() => {});

  return new Promise((resolve) => {
    const proc = spawn(helperPath(), ['listen', '--seconds', String(MAX_SECONDS)], {
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    child = proc;

    let settled = false;
    let buffer = '';
    let transcript = '';

    proc.stdout.on('data', (chunk) => {
      buffer += chunk;
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';
      for (const line of lines) {
        if (!line.trim()) continue;
        let msg;
        try { msg = JSON.parse(line); } catch { continue; }

        if (msg.partial != null) {
          transcript = msg.partial;
          onPartial(transcript);
          if (!settled) { settled = true; resolve({ ok: true }); }
        } else if (msg.final != null) {
          transcript = msg.final;
        } else if (msg.error) {
          if (!settled) { settled = true; resolve({ ok: false, error: msg.error }); }
        }
      }
    });

    proc.on('error', () => {
      if (!settled) { settled = true; resolve({ ok: false, error: 'dictation helper failed to launch' }); }
      finish(transcript);
    });

    proc.on('exit', () => { finish(transcript); });

    // The helper is up as soon as it has not died; waiting for the first word
    // would make the button feel unresponsive in a quiet room.
    setTimeout(() => {
      if (!settled && child === proc) { settled = true; resolve({ ok: true }); }
    }, 400);

    function finish(text) {
      if (child === proc) child = null;
      if (pending) {
        const { resolve: done } = pending;
        pending = null;
        done({ ok: true, transcript: text });
      }
    }
  });
}

/// Closes the helper's stdin, which is its cue to flush a final transcript.
function stop() {
  if (!child) return Promise.resolve({ ok: true, transcript: '' });
  const proc = child;

  return new Promise((resolve) => {
    pending = { resolve };
    try { proc.stdin.end(); } catch { /* already gone */ }

    // If the helper somehow never exits, don't leave the caller hanging.
    setTimeout(() => {
      if (pending) {
        pending = null;
        try { proc.kill('SIGTERM'); } catch { /* already gone */ }
        child = null;
        resolve({ ok: true, transcript: '' });
      }
    }, 5000);
  });
}

function shutdown() {
  if (!child) return;
  try { child.kill('SIGTERM'); } catch { /* already gone */ }
  child = null;
}

module.exports = { status, requestAccess, start, stop, isListening, shutdown, MAX_SECONDS };
