// Embedded sync server: serves the iPhone web app and a small JSON API
// backed by the same task state the widget uses.
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.woff2': 'font/woff2',
  '.png': 'image/png',
};

const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);
const LABEL_COLORS = ['#7d9bb8', '#8fa876', '#c97b5a', '#d9a441', '#a98ba8', '#6fa39c', '#b8a06a', '#94a0ab'];

function pad(n) {
  return String(n).padStart(2, '0');
}

function toDateStr(d) {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function toDateTimeStr(d) {
  return `${toDateStr(d)}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function shiftDateStr(str, repeat) {
  const d = new Date(str + 'T00:00:00');
  if (isNaN(d)) return str;
  if (repeat === 'daily') d.setDate(d.getDate() + 1);
  else if (repeat === 'weekly') d.setDate(d.getDate() + 7);
  else d.setMonth(d.getMonth() + 1);
  return toDateStr(d);
}

function shiftDateTimeStr(str, repeat) {
  const d = new Date(str);
  if (isNaN(d)) return str;
  if (repeat === 'daily') d.setDate(d.getDate() + 1);
  else if (repeat === 'weekly') d.setDate(d.getDate() + 7);
  else d.setMonth(d.getMonth() + 1);
  return toDateTimeStr(d);
}

// Mirrors the widget's behavior when a repeating task is completed.
function spawnNextOccurrence(state, task) {
  const next = {
    ...task,
    id: uid(),
    done: false,
    doneAt: null,
    createdAt: Date.now(),
    reminded: false,
    dueReminded: false,
    focusedMs: 0,
    eventId: null, // the next occurrence isn't the event we already booked
  };
  if (task.due) next.due = shiftDateStr(task.due, task.repeat);
  if (task.startAt) next.startAt = shiftDateTimeStr(task.startAt, task.repeat);
  if (!task.due && !task.startAt) next.due = shiftDateStr(toDateStr(new Date()), task.repeat);
  let guard = 0;
  while (next.due && Date.parse(next.due + 'T23:59:59') < Date.now() && guard++ < 400) {
    next.due = shiftDateStr(next.due, task.repeat);
    if (next.startAt) next.startAt = shiftDateTimeStr(next.startAt, task.repeat);
  }
  state.tasks.unshift(next);
}

function detectUrls(port, token) {
  const urls = { lan: null, tailscale: null };
  const ifaces = os.networkInterfaces();
  for (const name of Object.keys(ifaces)) {
    for (const addr of ifaces[name] || []) {
      if (addr.family !== 'IPv4' || addr.internal) continue;
      const ip = addr.address;
      if (ip.startsWith('100.')) {
        urls.tailscale = `http://${ip}:${port}/?key=${token}`;
      } else if (/^(192\.168\.|10\.|172\.(1[6-9]|2\d|3[01])\.)/.test(ip)) {
        if (!urls.lan) urls.lan = `http://${ip}:${port}/?key=${token}`;
      }
    }
  }
  return urls;
}

function startSyncServer({ port, token, getState, commit, getCalendar, lockin }) {
  const clients = new Set();

  const publicState = () => {
    const state = getState() || {};
    return {
      tasks: state.tasks || [],
      labels: state.labels || [],
      notes: Array.isArray(state.notes) ? state.notes : [],
      focus: state.focus || null,
      focusMinutes: (state.settings && state.settings.focusMinutes) || 25,
      // The phone gets the agenda read-only; writes still go through the Mac.
      events: (getCalendar ? getCalendar().events : []) || [],
      lockin: lockin ? lockin.status() : { active: false },
      settings: state.settings || {},
      focusLog: Array.isArray(state.focusLog) ? state.focusLog : [],
    };
  };

  function broadcast() {
    const payload = `data: ${JSON.stringify(publicState())}\n\n`;
    for (const res of clients) {
      try { res.write(payload); } catch { clients.delete(res); }
    }
  }

  function sendJson(res, code, data) {
    const body = JSON.stringify(data);
    res.writeHead(code, { 'Content-Type': 'application/json; charset=utf-8' });
    res.end(body);
  }

  function authed(req, url) {
    if (url.searchParams.get('key') === token) return true;
    const cookies = req.headers.cookie || '';
    return cookies.split(';').some((c) => c.trim() === 'mtkey=' + token);
  }

  function readBody(req) {
    return new Promise((resolve) => {
      let data = '';
      req.on('data', (c) => { data += c; if (data.length > 1e6) req.destroy(); });
      req.on('end', () => {
        try { resolve(JSON.parse(data || '{}')); } catch { resolve({}); }
      });
    });
  }

  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://localhost');
    const p = url.pathname;

    if (!authed(req, url)) {
      res.writeHead(403, { 'Content-Type': 'text/plain' });
      res.end('miTasks: access denied');
      return;
    }

    // App shell
    if (p === '/' && req.method === 'GET') {
      res.writeHead(200, {
        'Content-Type': MIME['.html'],
        'Set-Cookie': `mtkey=${token}; Path=/; Max-Age=63072000; SameSite=Lax`,
      });
      res.end(fs.readFileSync(path.join(__dirname, 'mobile', 'index.html')));
      return;
    }

    if (p.startsWith('/fonts/') && req.method === 'GET') {
      const file = path.join(__dirname, 'renderer', 'fonts', path.basename(p));
      if (fs.existsSync(file)) {
        res.writeHead(200, { 'Content-Type': MIME['.woff2'], 'Cache-Control': 'max-age=31536000' });
        res.end(fs.readFileSync(file));
      } else {
        res.writeHead(404); res.end();
      }
      return;
    }

    // PWA shell: manifest and service worker sit next to index.html.
    if ((p === '/manifest.webmanifest' || p === '/sw.js') && req.method === 'GET') {
      const file = path.join(__dirname, 'mobile', path.basename(p));
      if (!fs.existsSync(file)) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, {
        'Content-Type': p.endsWith('.js') ? 'application/javascript' : 'application/manifest+json',
        'Cache-Control': 'no-cache',
      });
      res.end(fs.readFileSync(file));
      return;
    }

    if (p === '/icon.png' && req.method === 'GET') {
      const file = path.join(__dirname, 'mobile', 'icon.png');
      res.writeHead(200, { 'Content-Type': MIME['.png'], 'Cache-Control': 'max-age=86400' });
      res.end(fs.readFileSync(file));
      return;
    }

    // API
    if (p === '/api/state' && req.method === 'GET') {
      sendJson(res, 200, publicState());
      return;
    }

    if (p === '/api/events' && req.method === 'GET') {
      res.writeHead(200, {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        Connection: 'keep-alive',
      });
      res.write(`data: ${JSON.stringify(publicState())}\n\n`);
      clients.add(res);
      const ping = setInterval(() => {
        try { res.write(': ping\n\n'); } catch { /* handled by close */ }
      }, 25000);
      req.on('close', () => { clearInterval(ping); clients.delete(res); });
      return;
    }

    if (p === '/api/tasks' && req.method === 'POST') {
      const body = await readBody(req);
      const text = String(body.text || '').trim().slice(0, 300);
      if (!text) { sendJson(res, 400, { error: 'text required' }); return; }
      const state = getState();
      const label = state.labels.some((l) => l.name === body.label) ? body.label : null;
      state.tasks.unshift({
        id: uid(), text, label,
        done: false, createdAt: Date.now(), doneAt: null,
        notes: '',
        priority: ['med', 'high'].includes(body.priority) ? body.priority : null,
        due: /^\d{4}-\d{2}-\d{2}$/.test(body.due || '') ? body.due : null,
        startAt: /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(body.startAt || '') ? body.startAt : null,
        repeat: ['daily', 'weekly', 'monthly'].includes(body.repeat) ? body.repeat : null,
        reminded: false, dueReminded: false, focusedMs: 0,
      });
      commit(state);
      broadcast();
      sendJson(res, 200, { ok: true });
      return;
    }

    if (p === '/api/clear-done' && req.method === 'POST') {
      const state = getState();
      state.tasks = state.tasks.filter((t) => !t.done);
      commit(state);
      broadcast();
      sendJson(res, 200, { ok: true });
      return;
    }

    if (p === '/api/labels' && req.method === 'POST') {
      const body = await readBody(req);
      const name = String(body.name || '').trim().slice(0, 24);
      const state = getState();
      if (name && !state.labels.some((l) => l.name === name)) {
        state.labels.push({ name, color: LABEL_COLORS[state.labels.length % LABEL_COLORS.length] });
        commit(state);
        broadcast();
      }
      sendJson(res, 200, { ok: true });
      return;
    }

    if (p === '/api/focus' && req.method === 'POST') {
      const body = await readBody(req);
      const state = getState();
      const task = state.tasks.find((t) => t.id === body.taskId && !t.done);
      if (!task) { sendJson(res, 404, { error: 'task not found' }); return; }
      const minutes = (state.settings && state.settings.focusMinutes) || 25;
      state.focus = { taskId: task.id, startedAt: Date.now(), endAt: Date.now() + minutes * 60000, minutes };
      commit(state);
      broadcast();
      sendJson(res, 200, { ok: true });
      return;
    }

    if (p === '/api/focus' && req.method === 'DELETE') {
      const state = getState();
      if (state.focus) {
        const task = state.tasks.find((t) => t.id === state.focus.taskId);
        const elapsed = Math.min(Date.now() - state.focus.startedAt, state.focus.endAt - state.focus.startedAt);
        if (task && elapsed >= 30000) {
          task.focusedMs = (task.focusedMs || 0) + elapsed;
          if (!Array.isArray(state.focusLog)) state.focusLog = [];
          state.focusLog.push({ date: toDateStr(new Date()), taskId: task.id, label: task.label, ms: elapsed });
        }
        state.focus = null;
        commit(state);
        broadcast();
      }
      sendJson(res, 200, { ok: true });
      return;
    }

    if (p === '/api/notes' && req.method === 'POST') {
      const body = await readBody(req);
      const state = getState();
      if (!Array.isArray(state.notes)) state.notes = [];
      const note = {
        id: uid(),
        label: state.labels.some((l) => l.name === body.label) ? body.label : null,
        title: String(body.title || '').slice(0, 120),
        body: '',
        createdAt: Date.now(),
        updatedAt: Date.now(),
      };
      state.notes.push(note);
      commit(state);
      broadcast();
      sendJson(res, 200, { ok: true, id: note.id });
      return;
    }

    let m = p.match(/^\/api\/notes\/(\w+)$/);
    if (m && req.method === 'PATCH') {
      const body = await readBody(req);
      const state = getState();
      const note = (state.notes || []).find((n) => n.id === m[1]);
      if (!note) { sendJson(res, 404, { error: 'not found' }); return; }
      if ('title' in body) note.title = String(body.title || '').slice(0, 120);
      if ('body' in body) note.body = String(body.body || '').slice(0, 20000);
      note.updatedAt = Date.now();
      commit(state);
      broadcast();
      sendJson(res, 200, { ok: true });
      return;
    }
    if (m && req.method === 'DELETE') {
      const state = getState();
      state.notes = (state.notes || []).filter((n) => n.id !== m[1]);
      commit(state);
      broadcast();
      sendJson(res, 200, { ok: true });
      return;
    }

    // Lock-in: the phone drives the same caffeinate assertion as the widget.
    if (p === '/api/lockin' && req.method === 'POST') {
      if (!lockin) { sendJson(res, 503, { error: 'unavailable' }); return; }
      const body = await readBody(req);
      const minutes = Number(body.minutes);
      if (!Number.isFinite(minutes)) { sendJson(res, 400, { error: 'minutes required' }); return; }
      const status = body.extend ? lockin.extend(minutes) : lockin.start(minutes, 'phone');
      broadcast();
      sendJson(res, 200, status);
      return;
    }

    if (p === '/api/lockin' && req.method === 'DELETE') {
      if (!lockin) { sendJson(res, 503, { error: 'unavailable' }); return; }
      const status = lockin.stop();
      broadcast();
      sendJson(res, 200, status);
      return;
    }

    m = p.match(/^\/api\/tasks\/(\w+)$/);
    if (m && req.method === 'PATCH') {
      const body = await readBody(req);
      const state = getState();
      const task = state.tasks.find((t) => t.id === m[1]);
      if (!task) { sendJson(res, 404, { error: 'not found' }); return; }
      if ('text' in body) {
        const t = String(body.text || '').trim().slice(0, 300);
        if (t) task.text = t;
      }
      if ('notes' in body) task.notes = String(body.notes || '').slice(0, 5000);
      if ('priority' in body) task.priority = ['med', 'high'].includes(body.priority) ? body.priority : null;
      if ('repeat' in body) task.repeat = ['daily', 'weekly', 'monthly'].includes(body.repeat) ? body.repeat : null;
      if ('label' in body) task.label = state.labels.some((l) => l.name === body.label) ? body.label : null;
      if ('due' in body) {
        task.due = /^\d{4}-\d{2}-\d{2}$/.test(body.due || '') ? body.due : null;
        task.dueReminded = false;
      }
      if ('startAt' in body) {
        task.startAt = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(body.startAt || '') ? body.startAt : null;
        task.reminded = false;
      }
      commit(state);
      broadcast();
      sendJson(res, 200, { ok: true });
      return;
    }

    m = p.match(/^\/api\/tasks\/(\w+)\/toggle$/);
    if (m && req.method === 'POST') {
      const state = getState();
      const task = state.tasks.find((t) => t.id === m[1]);
      if (!task) { sendJson(res, 404, { error: 'not found' }); return; }
      task.done = !task.done;
      task.doneAt = task.done ? Date.now() : null;
      if (task.done && task.repeat) spawnNextOccurrence(state, task);
      commit(state);
      broadcast();
      sendJson(res, 200, { ok: true });
      return;
    }

    m = p.match(/^\/api\/tasks\/(\w+)$/);
    if (m && req.method === 'DELETE') {
      const state = getState();
      state.tasks = state.tasks.filter((t) => t.id !== m[1]);
      commit(state);
      broadcast();
      sendJson(res, 200, { ok: true });
      return;
    }

    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not found');
  });

  server.on('error', (err) => console.error('Sync server error:', err.message));
  server.listen(port, '0.0.0.0');

  return {
    broadcast,
    urls: () => detectUrls(port, token),
  };
}

module.exports = { startSyncServer, spawnNextOccurrence };
