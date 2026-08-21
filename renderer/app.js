'use strict';

// Muted editorial palette — dusty azul first (Azul Tech), sage second (Personal).
const LABEL_COLORS = ['#7d9bb8', '#8fa876', '#c97b5a', '#d9a441', '#a98ba8', '#6fa39c', '#b8a06a', '#94a0ab'];
const CONFETTI_COLORS = ['#d9a441', '#f0eadd', '#8fa876', '#c97b5a', '#7d9bb8'];
const ARC_CIRCUMFERENCE = 2 * Math.PI * 28;
const PRIORITY_RANK = { high: 0, med: 1 };
const FAR_FUTURE = 8.64e15;
const DAY_MS = 86400000;
const WEEKDAYS = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
const REPEAT_LABEL = { daily: 'Daily', weekly: 'Weekly', monthly: 'Monthly' };

const DEFAULT_SETTINGS = {
  sound: 'Glass',
  deadlineReminders: true,
  deadlineTime: '09:00',
  morningBrief: true,
  briefTime: '08:30',
  weeklyReview: true,
  reviewTime: '17:00',
  focusMinutes: 25,
  bubbleStyle: 'pet',
  menubar: true,
  lastBriefDate: null,
  lastReviewDate: null,
};

let state = {
  tasks: [],
  labels: [
    { name: 'Azul Tech', color: LABEL_COLORS[0] },
    { name: 'Personal', color: LABEL_COLORS[1] },
  ],
  settings: { ...DEFAULT_SETTINGS },
  focus: null, // { taskId, startedAt, endAt, minutes }
  focusLog: [], // { date: 'YYYY-MM-DD', taskId, label, ms }
  notes: [], // topic cards: { id, label, title, body, createdAt, updatedAt }
};

let activeLabel = null; // null = All; selected chip filters AND labels new tasks
let openTaskId = null;

const $ = (id) => document.getElementById(id);
const els = {
  bubble: $('bubble'),
  bubbleCount: $('bubble-count'),
  bubbleCheck: $('bubble-check'),
  bubbleBadge: $('bubble-badge'),
  arcFill: $('arc-fill'),
  panel: $('panel'),
  dateLine: $('date-line'),
  progressStrip: $('progress-strip'),
  progressFill: $('progress-fill'),
  progressText: $('progress-text'),
  focusStrip: $('focus-strip'),
  focusTask: $('focus-task'),
  focusTime: $('focus-time'),
  focusStop: $('focus-stop'),
  settingsBtn: $('settings-btn'),
  collapseBtn: $('collapse-btn'),
  input: $('task-input'),
  addBtn: $('add-btn'),
  parseHint: $('parse-hint'),
  chipRow: $('chip-row'),
  pendingList: $('pending-list'),
  doneBlock: $('done-block'),
  doneList: $('done-list'),
  doneCount: $('done-count'),
  clearDone: $('clear-done'),
  emptyState: $('empty-state'),
  confettiLayer: $('confetti-layer'),
  settings: $('settings'),
  settingsBack: $('settings-back'),
  statToday: $('stat-today'),
  statWeek: $('stat-week'),
  statPending: $('stat-pending'),
  statOverdue: $('stat-overdue'),
  statFocusToday: $('stat-focus-today'),
  statFocusWeek: $('stat-focus-week'),
  attentionBlock: $('attention-block'),
  attentionList: $('attention-list'),
  focusLabelBlock: $('focus-label-block'),
  focusLabelList: $('focus-label-list'),
  labelList: $('label-list'),
  notesView: $('notes-view'),
  notesBtn: $('notes-btn'),
  notesBack: $('notes-back'),
  noteNew: $('note-new'),
  notesChips: $('notes-chips'),
  noteCards: $('note-cards'),
  notesEmpty: $('notes-empty'),
  noteEditor: $('note-editor'),
  editorBack: $('editor-back'),
  editorScope: $('editor-scope'),
  editorCopy: $('editor-copy'),
  editorDelete: $('editor-delete'),
  editorTitle: $('editor-title'),
  editorBody: $('editor-body'),
  quitBtn: $('quit-btn'),
  focusMinutes: $('focus-minutes'),
  soundSelect: $('sound-select'),
  soundPlay: $('sound-play'),
  deadlineToggle: $('deadline-toggle'),
  deadlineTime: $('deadline-time'),
  briefToggle: $('brief-toggle'),
  briefTime: $('brief-time'),
  reviewToggle: $('review-toggle'),
  reviewTime: $('review-time'),
  bubbleStyle: $('bubble-style'),
  menubarToggle: $('menubar-toggle'),
  loginCheckbox: $('login-checkbox'),
};

const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 7);

function save() {
  window.api.saveState(state);
}

let saveTimer = null;
function debouncedSave() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(save, 400);
}

/* ---------- Small SVG helpers ---------- */

function checkSvg() {
  return `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="4"
            stroke-linecap="round" stroke-linejoin="round"><path d="M4 12.5l5 5L20 6.5"/></svg>`;
}

function flagSvg(size = 10) {
  return `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="currentColor" stroke="currentColor"
      stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/>
      <line x1="4" y1="22" x2="4" y2="15" fill="none"/></svg>`;
}

function clockSvg() {
  return `<svg viewBox="0 0 24 24" width="10" height="10" fill="none" stroke="currentColor"
      stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
      <circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>`;
}

function repeatSvg() {
  return `<svg viewBox="0 0 24 24" width="10" height="10" fill="none" stroke="currentColor"
      stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M17 2l4 4-4 4"/><path d="M3 11v-1a4 4 0 0 1 4-4h14"/>
      <path d="M7 22l-4-4 4-4"/><path d="M21 13v1a4 4 0 0 1-4 4H3"/></svg>`;
}

function notesSvg() {
  return `<svg viewBox="0 0 24 24" width="10" height="10" fill="none" stroke="currentColor"
      stroke-width="2.4" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h9"/></svg>`;
}

function playSvg() {
  return `<svg viewBox="0 0 24 24" width="9" height="9" fill="currentColor"><path d="M6 4l14 8-14 8z"/></svg>`;
}

function stopSvg() {
  return `<svg viewBox="0 0 24 24" width="9" height="9" fill="currentColor"><rect x="5" y="5" width="14" height="14" rx="2"/></svg>`;
}

/* ---------- Data helpers ---------- */

function labelFor(name) {
  return state.labels.find((l) => l.name === name) || null;
}

function visibleTasks() {
  return activeLabel ? state.tasks.filter((t) => t.label === activeLabel) : state.tasks;
}

function dueValue(task) {
  if (!task.due) return FAR_FUTURE;
  const t = Date.parse(task.due + 'T00:00:00');
  return Number.isFinite(t) ? t : FAR_FUTURE;
}

function startOfToday() {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

function todayStr() {
  return toDateStr(new Date());
}

function toDateStr(d) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function toLocalDateTimeStr(d) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${toDateStr(d)}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

function dayDiff(ts) {
  return Math.floor((ts - startOfToday()) / DAY_MS);
}

function formatDue(due) {
  const ts = Date.parse(due + 'T00:00:00');
  if (!Number.isFinite(ts)) return null;
  const diff = dayDiff(ts);
  const short = new Date(ts).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  if (diff < 0) return { text: `Overdue · ${short}`, cls: 'overdue' };
  if (diff === 0) return { text: 'Today', cls: 'today' };
  if (diff === 1) return { text: 'Tomorrow', cls: 'soon' };
  return { text: short, cls: '' };
}

function formatStart(startAt) {
  const ts = Date.parse(startAt);
  if (!Number.isFinite(ts)) return null;
  const d = new Date(ts);
  const time = d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
  const diff = dayDiff(ts);
  if (ts <= Date.now()) return { text: `Started · ${time}`, cls: 'today' };
  if (diff === 0) return { text: time, cls: 'soon' };
  if (diff === 1) return { text: `Tomorrow · ${time}`, cls: '' };
  const short = d.toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
  return { text: `${short} · ${time}`, cls: '' };
}

function formatMinutes(ms) {
  const mins = Math.round(ms / 60000);
  if (mins < 60) return `${mins}m`;
  return `${Math.floor(mins / 60)}h ${mins % 60}m`;
}

/* ---------- Natural-language quick add ---------- */

function parseQuickAdd(raw) {
  let text = ' ' + raw + ' ';
  const out = { priority: null, due: null, startAt: null, label: activeLabel, repeat: null };

  const eat = (match) => {
    text = text.replace(match, ' ');
  };

  // Priority: !high / !h / !med / !m
  let m = text.match(/\s!(high|h)(?=\s)/i);
  if (m) { out.priority = 'high'; eat(m[0]); }
  else if ((m = text.match(/\s!(med|medium|m)(?=\s)/i))) { out.priority = 'med'; eat(m[0]); }

  // Label: @azul (prefix-matches a label name, spaces ignored)
  if ((m = text.match(/\s@([\w-]+)/))) {
    const q = m[1].toLowerCase();
    const found = state.labels.find((l) =>
      l.name.toLowerCase().replace(/\s+/g, '').startsWith(q)
    );
    if (found) { out.label = found.name; eat(m[0]); }
  }

  // Repeat: every day / every week / every month / every monday
  if ((m = text.match(/\severy\s?(day|week|month|monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?=\s)/i))) {
    const w = m[1].toLowerCase();
    out.repeat = w === 'day' ? 'daily' : w === 'month' ? 'monthly' : 'weekly';
    if (WEEKDAYS.includes(w)) out.repeatWeekday = w;
    eat(m[0]);
  }

  // Date words
  let dateBase = null;
  if ((m = text.match(/\s(today|tonight)(?=\s)/i))) { dateBase = new Date(); eat(m[0]); }
  else if ((m = text.match(/\s(tomorrow|tmrw|tmr)(?=\s)/i))) {
    dateBase = new Date(Date.now() + DAY_MS); eat(m[0]);
  } else if ((m = text.match(/\sin (\d{1,2}) days?(?=\s)/i))) {
    dateBase = new Date(Date.now() + parseInt(m[1], 10) * DAY_MS); eat(m[0]);
  } else if ((m = text.match(/\s(?:on |next )?(monday|tuesday|wednesday|thursday|friday|saturday|sunday|mon|tue|wed|thu|fri|sat|sun)(?=\s)/i))) {
    const names = WEEKDAYS.map((w) => [w, w.slice(0, 3)]);
    const q = m[1].toLowerCase();
    const idx = names.findIndex(([full, short]) => full === q || short === q);
    if (idx >= 0) {
      const now = new Date();
      let ahead = (idx - now.getDay() + 7) % 7;
      if (ahead === 0) ahead = 7;
      dateBase = new Date(Date.now() + ahead * DAY_MS);
      eat(m[0]);
    }
  }

  // A repeat weekday ("every monday") implies the first occurrence's date
  if (!dateBase && out.repeatWeekday) {
    const idx = WEEKDAYS.indexOf(out.repeatWeekday);
    const now = new Date();
    let ahead = (idx - now.getDay() + 7) % 7;
    if (ahead === 0) ahead = 7;
    dateBase = new Date(Date.now() + ahead * DAY_MS);
  }

  // Time: 3pm / 3:30pm / 15:00 / at 9
  let timeParts = null;
  if ((m = text.match(/\s(?:at )?(\d{1,2})(?::(\d{2}))?\s?(am|pm)(?=\s)/i))) {
    let h = parseInt(m[1], 10) % 12;
    if (m[3].toLowerCase() === 'pm') h += 12;
    timeParts = [h, m[2] ? parseInt(m[2], 10) : 0];
    eat(m[0]);
  } else if ((m = text.match(/\s(?:at )?([01]?\d|2[0-3]):([0-5]\d)(?=\s)/))) {
    timeParts = [parseInt(m[1], 10), parseInt(m[2], 10)];
    eat(m[0]);
  }

  if (timeParts) {
    const d = dateBase ? new Date(dateBase) : new Date();
    d.setHours(timeParts[0], timeParts[1], 0, 0);
    if (!dateBase && d.getTime() <= Date.now()) d.setTime(d.getTime() + DAY_MS);
    out.startAt = toLocalDateTimeStr(d);
    out.due = toDateStr(d);
  } else if (dateBase) {
    out.due = toDateStr(dateBase);
  }

  out.text = text.replace(/\s+/g, ' ').trim();
  return out;
}

function renderParseHint() {
  const raw = els.input.value;
  if (!raw.trim()) { els.parseHint.hidden = true; return; }
  const p = parseQuickAdd(raw);
  const bits = [];
  if (p.priority) bits.push(p.priority === 'high' ? '⚑ High' : '⚑ Medium');
  if (p.startAt) {
    const info = formatStart(p.startAt);
    if (info) bits.push('Starts ' + info.text.replace('Started · ', ''));
  } else if (p.due) {
    const info = formatDue(p.due);
    if (info) bits.push('Due ' + info.text);
  }
  if (p.repeat) bits.push('↻ ' + REPEAT_LABEL[p.repeat]);
  if (p.label && p.label !== activeLabel) bits.push(p.label);
  els.parseHint.hidden = bits.length === 0;
  els.parseHint.textContent = bits.join('  ·  ');
}

/* ---------- Task rows ---------- */

function metaChip(cls, html, text) {
  const span = document.createElement('span');
  span.className = 'meta-item ' + cls;
  if (html) span.innerHTML = html;
  if (text) span.appendChild(document.createTextNode(text));
  return span;
}

function buildMeta(task) {
  const meta = document.createElement('div');
  meta.className = 'task-meta';

  if (task.priority) {
    meta.appendChild(
      metaChip(`flag-${task.priority}`, flagSvg(), task.priority === 'high' ? 'High' : 'Medium')
    );
  }

  if (task.startAt) {
    const info = formatStart(task.startAt);
    if (info) meta.appendChild(metaChip('start-chip ' + info.cls, clockSvg(), info.text));
  }

  if (task.due) {
    const info = formatDue(task.due);
    if (info) meta.appendChild(metaChip('due-chip ' + info.cls, null, info.text));
  }

  if (task.repeat) {
    meta.appendChild(metaChip('', repeatSvg(), REPEAT_LABEL[task.repeat]));
  }

  if (task.focusedMs) {
    meta.appendChild(metaChip('', null, formatMinutes(task.focusedMs)));
  }

  const label = labelFor(task.label);
  if (label && !activeLabel) {
    const tag = metaChip('', null, label.name);
    const dot = document.createElement('span');
    dot.className = 'dot';
    dot.style.background = label.color;
    tag.prepend(dot);
    meta.appendChild(tag);
  }

  if (task.notes && task.notes.trim()) {
    meta.appendChild(metaChip('notes-glyph', notesSvg(), null));
  }

  return meta.childNodes.length ? meta : null;
}

function detailRow(labelText, ...controls) {
  const row = document.createElement('div');
  row.className = 'detail-row';
  const label = document.createElement('span');
  label.className = 'detail-label';
  label.textContent = labelText;
  row.appendChild(label);
  for (const c of controls) row.appendChild(c);
  return row;
}

function segControl(options, current, onPick) {
  const seg = document.createElement('div');
  seg.className = 'seg';
  for (const [text, value, cls] of options) {
    const btn = document.createElement('button');
    btn.className = 'seg-btn' + (current === value ? ' active' : '') + (cls ? ` ${cls}` : '');
    if (cls) btn.innerHTML = flagSvg(9);
    btn.appendChild(document.createTextNode(text));
    btn.addEventListener('click', () => onPick(value));
    seg.appendChild(btn);
  }
  return seg;
}

function clearButton(title, onClick) {
  const btn = document.createElement('button');
  btn.className = 'clear-due';
  btn.title = title;
  btn.innerHTML = `<svg viewBox="0 0 24 24" width="10" height="10" fill="none" stroke="currentColor"
      stroke-width="2.4" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>`;
  btn.addEventListener('click', onClick);
  return btn;
}

function buildDetail(task) {
  const wrap = document.createElement('div');
  wrap.className = 'task-detail';

  // Label assignment
  const labelChips = document.createElement('div');
  labelChips.className = 'detail-chips';
  const mkLabelChip = (name, color, isActive, value) => {
    const chip = document.createElement('button');
    chip.className = 'chip' + (isActive ? ' active' : '');
    if (color) {
      const dot = document.createElement('span');
      dot.className = 'dot';
      dot.style.background = color;
      chip.appendChild(dot);
    }
    chip.appendChild(document.createTextNode(name));
    chip.addEventListener('click', () => {
      task.label = value;
      save();
      render();
    });
    labelChips.appendChild(chip);
  };
  mkLabelChip('None', null, !task.label, null);
  for (const label of state.labels) {
    mkLabelChip(label.name, label.color, task.label === label.name, label.name);
  }
  wrap.appendChild(detailRow('Label', labelChips));

  const notes = document.createElement('textarea');
  notes.placeholder = 'Add notes…';
  notes.value = task.notes || '';
  notes.addEventListener('input', () => {
    task.notes = notes.value;
    debouncedSave();
  });
  wrap.appendChild(notes);

  // Focus session
  const focusBtn = document.createElement('button');
  const isFocused = state.focus && state.focus.taskId === task.id;
  focusBtn.className = 'focus-btn' + (isFocused ? ' stop' : '');
  focusBtn.innerHTML = isFocused ? stopSvg() : playSvg();
  focusBtn.appendChild(
    document.createTextNode(
      isFocused ? 'Stop session' : `Focus · ${state.settings.focusMinutes} min`
    )
  );
  focusBtn.addEventListener('click', () => (isFocused ? stopFocus(false) : startFocus(task.id)));
  wrap.appendChild(detailRow('Focus', focusBtn));

  // Priority
  wrap.appendChild(
    detailRow(
      'Priority',
      segControl(
        [['None', null], ['Medium', 'med', 'seg-med'], ['High', 'high', 'seg-high']],
        task.priority || null,
        (v) => { task.priority = v; save(); render(); }
      )
    )
  );

  // Repeat
  const repeatSeg = document.createElement('div');
  repeatSeg.className = 'seg';
  for (const [text, value] of [['Off', null], ['Daily', 'daily'], ['Weekly', 'weekly'], ['Monthly', 'monthly']]) {
    const btn = document.createElement('button');
    btn.className = 'seg-btn' + ((task.repeat || null) === value ? ' active' : '');
    btn.textContent = text;
    btn.addEventListener('click', () => { task.repeat = value; save(); render(); });
    repeatSeg.appendChild(btn);
  }
  wrap.appendChild(detailRow('Repeat', repeatSeg));

  // Start time (reminder fires at this moment)
  const start = document.createElement('input');
  start.type = 'datetime-local';
  start.value = task.startAt || '';
  start.addEventListener('change', () => {
    task.startAt = start.value || null;
    task.reminded = false;
    save();
    render();
  });
  const startControls = [start];
  if (task.startAt) startControls.push(clearButton('Remove start time', () => {
    task.startAt = null;
    task.reminded = false;
    save();
    render();
  }));
  wrap.appendChild(detailRow('Starts', ...startControls));

  // Deadline
  const date = document.createElement('input');
  date.type = 'date';
  date.value = task.due || '';
  date.addEventListener('change', () => {
    task.due = date.value || null;
    task.dueReminded = false;
    save();
    render();
  });
  const dueControls = [date];
  if (task.due) dueControls.push(clearButton('Remove deadline', () => {
    task.due = null;
    task.dueReminded = false;
    save();
    render();
  }));
  wrap.appendChild(detailRow('Deadline', ...dueControls));

  return wrap;
}

function taskRow(task) {
  const li = document.createElement('li');
  li.className = 'task' + (task.done ? ' done' : '') + (openTaskId === task.id ? ' open' : '');
  li.dataset.id = task.id;

  const main = document.createElement('div');
  main.className = 'task-main';

  const checkbox = document.createElement('button');
  checkbox.className = 'checkbox';
  checkbox.setAttribute('aria-label', task.done ? 'Mark as not done' : 'Mark as done');
  checkbox.innerHTML = checkSvg();
  checkbox.addEventListener('click', () => toggleTask(task.id, li));

  const body = document.createElement('div');
  body.className = 'task-body';
  body.addEventListener('click', () => {
    openTaskId = openTaskId === task.id ? null : task.id;
    render();
  });

  if (openTaskId === task.id) {
    // Open task: the title becomes editable in place.
    const title = document.createElement('input');
    title.type = 'text';
    title.className = 'detail-title';
    title.value = task.text;
    title.maxLength = 200;
    const commitTitle = () => {
      const v = title.value.trim();
      if (v && v !== task.text) {
        task.text = v;
        save();
        render();
      } else {
        title.value = task.text;
      }
    };
    title.addEventListener('change', commitTitle);
    title.addEventListener('keydown', (e) => {
      if (e.key === 'Enter') { commitTitle(); title.blur(); }
      e.stopPropagation();
    });
    // Clicking into the title edits it — it shouldn't collapse the task.
    title.addEventListener('click', (e) => e.stopPropagation());
    body.appendChild(title);
  } else {
    const text = document.createElement('div');
    text.className = 'task-text';
    text.textContent = task.text;
    text.title = task.text;
    body.appendChild(text);
  }

  const meta = buildMeta(task);
  if (meta) body.appendChild(meta);

  const del = document.createElement('button');
  del.className = 'delete-btn';
  del.setAttribute('aria-label', 'Delete task');
  del.innerHTML = `<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor"
      stroke-width="2.2" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>`;
  del.addEventListener('click', () => deleteTask(task.id));

  main.append(checkbox, body, del);
  li.appendChild(main);

  if (openTaskId === task.id) li.appendChild(buildDetail(task));

  return li;
}

/* ---------- Chips ---------- */

function renderChips() {
  els.chipRow.textContent = '';

  const mkChip = (name, color, isActive, onClick) => {
    const chip = document.createElement('button');
    chip.className = 'chip' + (isActive ? ' active' : '');
    if (color) {
      const dot = document.createElement('span');
      dot.className = 'dot';
      dot.style.background = color;
      chip.appendChild(dot);
    }
    chip.appendChild(document.createTextNode(name));
    chip.addEventListener('click', onClick);
    els.chipRow.appendChild(chip);
    return chip;
  };

  mkChip('All', null, activeLabel === null, () => {
    activeLabel = null;
    render();
  });

  for (const label of state.labels) {
    const pending = state.tasks.filter((t) => t.label === label.name && !t.done).length;
    const title = pending ? `${label.name} · ${pending} pending` : label.name;
    const chip = mkChip(label.name, label.color, activeLabel === label.name, () => {
      activeLabel = activeLabel === label.name ? null : label.name;
      render();
      els.input.focus();
    });
    chip.title = title;
  }

  const addChip = document.createElement('button');
  addChip.className = 'chip add-chip';
  addChip.textContent = '+ Label';
  addChip.addEventListener('click', () => showNewLabelInput(addChip));
  els.chipRow.appendChild(addChip);
}

function showNewLabelInput(addChip) {
  const input = document.createElement('input');
  input.id = 'new-label-input';
  input.placeholder = 'Label name…';
  input.maxLength = 24;
  els.chipRow.replaceChild(input, addChip);
  input.focus();

  const commit = () => {
    const name = input.value.trim();
    if (name && !labelFor(name)) {
      const color = LABEL_COLORS[state.labels.length % LABEL_COLORS.length];
      state.labels.push({ name, color });
      activeLabel = name;
      save();
    }
    render();
  };

  input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') commit();
    if (e.key === 'Escape') render();
    e.stopPropagation();
  });
  input.addEventListener('blur', commit);
}

/* ---------- Bubble & progress ---------- */

function renderProgress() {
  const total = state.tasks.length;
  const doneCount = state.tasks.filter((t) => t.done).length;
  const pending = total - doneCount;
  const ratio = total ? doneCount / total : 0;

  const style = state.settings.bubbleStyle === 'dial' ? 'dial' : 'pet';
  document.body.classList.toggle('style-pet', style === 'pet');
  document.body.classList.toggle('style-dial', style === 'dial');

  const focus = activeFocus();

  if (focus) {
    const { elapsed, totalMs, remaining } = focus;
    els.arcFill.style.strokeDashoffset = ARC_CIRCUMFERENCE * (1 - elapsed / totalMs);
    const mins = Math.max(1, Math.ceil(remaining / 60000));
    els.bubbleBadge.hidden = false;
    els.bubbleBadge.textContent = `${mins}′`;
    els.bubbleCount.hidden = true;
    els.bubbleCheck.hidden = true;
    if (style === 'dial') {
      els.bubbleCount.hidden = false;
      els.bubbleCount.textContent = `${mins}′`;
    }
    setPetFace('focus');
  } else {
    els.arcFill.style.strokeDashoffset = ARC_CIRCUMFERENCE * (1 - ratio);
    els.bubbleCount.hidden = pending === 0;
    els.bubbleCheck.hidden = pending !== 0;
    els.bubbleCount.textContent = pending > 99 ? '99' : String(pending);
    els.bubbleBadge.hidden = pending === 0;
    els.bubbleBadge.textContent = pending > 99 ? '99' : String(pending);
    setPetFace(pending === 0 ? 'happy' : 'alert');
  }

  // Panel progress follows the active label filter; the bubble stays global.
  const scoped = visibleTasks();
  const scopedDone = scoped.filter((t) => t.done).length;
  const scopedRatio = scoped.length ? scopedDone / scoped.length : 0;
  els.progressStrip.hidden = scoped.length === 0;
  els.progressFill.style.width = scopedRatio * 100 + '%';
  els.progressText.textContent = activeLabel
    ? `${scopedDone} of ${scoped.length} · ${activeLabel}`
    : `${scopedDone} of ${scoped.length} done`;
}

function setPetFace(face) {
  els.bubble.classList.remove('pet-alert', 'pet-happy', 'pet-focus');
  els.bubble.classList.add(`pet-${face}`);
}

/* ---------- Focus sessions ---------- */

function activeFocus() {
  if (!state.focus) return null;
  const task = state.tasks.find((t) => t.id === state.focus.taskId);
  if (!task || task.done) { state.focus = null; save(); return null; }
  const now = Date.now();
  const totalMs = state.focus.endAt - state.focus.startedAt;
  return {
    task,
    totalMs,
    elapsed: Math.min(now - state.focus.startedAt, totalMs),
    remaining: Math.max(0, state.focus.endAt - now),
  };
}

function startFocus(taskId) {
  const minutes = state.settings.focusMinutes || 25;
  state.focus = {
    taskId,
    startedAt: Date.now(),
    endAt: Date.now() + minutes * 60000,
    minutes,
  };
  save();
  render();
}

function logFocus(task, ms) {
  if (ms < 30000) return; // ignore accidental blips
  task.focusedMs = (task.focusedMs || 0) + ms;
  state.focusLog.push({ date: todayStr(), taskId: task.id, label: task.label, ms });
  if (state.focusLog.length > 2000) state.focusLog = state.focusLog.slice(-1000);
}

function stopFocus(completed) {
  const focus = activeFocus();
  state.focus = null;
  if (focus) {
    logFocus(focus.task, focus.elapsed);
    if (completed) {
      window.api.previewSound(state.settings.sound);
      try {
        new Notification('Focus session complete', { body: focus.task.text, silent: true });
      } catch { /* notifications unavailable — sound and pulse still land */ }
      els.bubble.classList.remove('pulse');
      void els.bubble.offsetWidth;
      els.bubble.classList.add('pulse');
    }
  }
  save();
  render();
}

function renderFocusStrip() {
  const focus = activeFocus();
  els.focusStrip.hidden = !focus;
  if (!focus) return;
  els.focusTask.textContent = focus.task.text;
  const secs = Math.ceil(focus.remaining / 1000);
  const mm = Math.floor(secs / 60);
  const ss = String(secs % 60).padStart(2, '0');
  els.focusTime.textContent = `${mm}:${ss}`;
}

function focusTick() {
  if (!state.focus) return;
  const focus = activeFocus();
  if (focus && focus.remaining <= 0) {
    stopFocus(true);
    return;
  }
  renderFocusStrip();
  // Keep the bubble countdown fresh without a full re-render.
  if (focus) {
    const mins = Math.max(1, Math.ceil(focus.remaining / 60000));
    els.bubbleBadge.textContent = `${mins}′`;
    if (state.settings.bubbleStyle === 'dial') els.bubbleCount.textContent = `${mins}′`;
    els.arcFill.style.strokeDashoffset =
      ARC_CIRCUMFERENCE * (1 - focus.elapsed / focus.totalMs);
  }
}

/* ---------- Render ---------- */

function render() {
  const tasks = visibleTasks();
  const pending = tasks
    .filter((t) => !t.done)
    .sort(
      (a, b) =>
        (PRIORITY_RANK[a.priority] ?? 2) - (PRIORITY_RANK[b.priority] ?? 2) ||
        dueValue(a) - dueValue(b) ||
        b.createdAt - a.createdAt
    );
  const done = tasks.filter((t) => t.done).sort((a, b) => (b.doneAt || 0) - (a.doneAt || 0));

  els.pendingList.textContent = '';
  for (const t of pending) els.pendingList.appendChild(taskRow(t));

  els.doneList.textContent = '';
  for (const t of done) els.doneList.appendChild(taskRow(t));

  els.doneBlock.hidden = done.length === 0;
  els.doneCount.textContent = String(done.length);
  els.emptyState.hidden = !(pending.length === 0 && done.length === 0);

  els.input.placeholder = activeLabel ? `Add to ${activeLabel}…` : 'What needs doing?';

  renderChips();
  renderProgress();
  renderFocusStrip();
  if (!els.settings.hidden) renderInsights();
}

/* ---------- Insights / settings ---------- */

function renderInsights() {
  const today = startOfToday();
  const now = Date.now();
  const doneTasks = state.tasks.filter((t) => t.done);

  els.statToday.textContent = doneTasks.filter((t) => (t.doneAt || 0) >= today).length;
  els.statWeek.textContent = doneTasks.filter((t) => (t.doneAt || 0) >= now - 7 * DAY_MS).length;
  els.statPending.textContent = state.tasks.filter((t) => !t.done).length;

  const overdue = state.tasks.filter((t) => !t.done && t.due && dueValue(t) < today);
  const stalled = state.tasks.filter(
    (t) => !t.done && t.startAt && Date.parse(t.startAt) <= now && !(t.due && dueValue(t) < today)
  );
  els.statOverdue.textContent = overdue.length;

  const tStr = todayStr();
  const weekCut = now - 7 * DAY_MS;
  let focusToday = 0;
  let focusWeek = 0;
  const focusByLabel = {};
  for (const entry of state.focusLog) {
    const ts = Date.parse(entry.date + 'T00:00:00');
    if (entry.date === tStr) focusToday += entry.ms;
    if (Number.isFinite(ts) && ts >= weekCut - DAY_MS) {
      focusWeek += entry.ms;
      const label =
        entry.label !== undefined
          ? entry.label
          : state.tasks.find((t) => t.id === entry.taskId)?.label ?? null;
      const key = label || 'No label';
      focusByLabel[key] = (focusByLabel[key] || 0) + entry.ms;
    }
  }
  els.statFocusToday.textContent = formatMinutes(focusToday);
  els.statFocusWeek.textContent = formatMinutes(focusWeek);

  // Focus time per label, past 7 days
  els.focusLabelList.textContent = '';
  const labelEntries = Object.entries(focusByLabel).sort((a, b) => b[1] - a[1]);
  els.focusLabelBlock.hidden = labelEntries.length === 0;
  for (const [name, ms] of labelEntries.slice(0, 6)) {
    const li = document.createElement('li');
    li.className = 'attention-item';
    const text = document.createElement('span');
    text.className = 'attention-text';
    const label = labelFor(name);
    if (label) {
      const dot = document.createElement('span');
      dot.className = 'dot';
      dot.style.background = label.color;
      dot.style.marginRight = '7px';
      text.appendChild(dot);
    }
    text.appendChild(document.createTextNode(name));
    const time = document.createElement('span');
    time.className = 'attention-why';
    time.textContent = formatMinutes(ms);
    li.append(text, time);
    els.focusLabelList.appendChild(li);
  }

  els.attentionList.textContent = '';
  const attention = [
    ...overdue.map((t) => ({ task: t, why: 'Overdue' })),
    ...stalled.map((t) => ({ task: t, why: 'Started' })),
  ];
  els.attentionBlock.hidden = attention.length === 0;

  for (const { task, why } of attention.slice(0, 8)) {
    const li = document.createElement('li');
    li.className = 'attention-item';
    const name = document.createElement('span');
    name.className = 'attention-text';
    name.textContent = task.text;
    const tag = document.createElement('span');
    tag.className = 'attention-why' + (why === 'Overdue' ? ' overdue' : '');
    tag.textContent = why;
    li.append(name, tag);
    li.addEventListener('click', () => {
      activeLabel = null;
      openTaskId = task.id;
      closeSettings();
      render();
    });
    els.attentionList.appendChild(li);
  }
}

/* ---------- Notes: one card per topic ---------- */

let notesLabel = null;
let openNoteId = null;
let noteDeletePending = false;

function notesFor(label) {
  return state.notes
    .filter((n) => (label ? n.label === label : true))
    .sort((a, b) => (b.updatedAt || 0) - (a.updatedAt || 0));
}

function noteById(id) {
  return state.notes.find((n) => n.id === id) || null;
}

function relativeDay(ts) {
  if (!ts) return '';
  const diff = dayDiff(ts);
  if (diff >= 0) return 'Today';
  if (diff === -1) return 'Yesterday';
  return new Date(ts).toLocaleDateString(undefined, { month: 'short', day: 'numeric' });
}

function renderNotesList() {
  // Label scope chips
  els.notesChips.textContent = '';
  const mk = (name, color, isActive, value) => {
    const chip = document.createElement('button');
    chip.className = 'chip' + (isActive ? ' active' : '');
    if (color) {
      const dot = document.createElement('span');
      dot.className = 'dot';
      dot.style.background = color;
      chip.appendChild(dot);
    }
    chip.appendChild(document.createTextNode(name));
    chip.addEventListener('click', () => {
      notesLabel = value;
      renderNotesList();
    });
    els.notesChips.appendChild(chip);
  };
  mk('All', null, notesLabel === null, null);
  for (const label of state.labels) mk(label.name, label.color, notesLabel === label.name, label.name);

  const notes = notesFor(notesLabel);
  els.noteCards.textContent = '';
  els.notesEmpty.hidden = notes.length > 0;

  for (const note of notes) {
    const li = document.createElement('li');
    li.className = 'note-card';

    const title = document.createElement('p');
    title.className = 'note-title';
    title.textContent = note.title.trim() || 'Untitled';

    const preview = document.createElement('p');
    preview.className = 'note-preview';
    preview.textContent = (note.body || '').trim();
    if (!preview.textContent) preview.remove();

    const meta = document.createElement('p');
    meta.className = 'note-meta';
    const label = labelFor(note.label);
    if (label && !notesLabel) {
      const dot = document.createElement('span');
      dot.className = 'dot';
      dot.style.background = label.color;
      meta.appendChild(dot);
      meta.appendChild(document.createTextNode(label.name + '  ·  '));
    }
    meta.appendChild(document.createTextNode(relativeDay(note.updatedAt)));

    const del = document.createElement('button');
    del.className = 'note-del' + (noteCardDeletePending === note.id ? ' confirm' : '');
    del.title = noteCardDeletePending === note.id ? 'Click again to delete' : 'Delete note';
    del.setAttribute('aria-label', 'Delete note');
    del.innerHTML = `<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor"
        stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
        <path d="M3 6h18M8 6V4a1 1 0 0 1 1-1h6a1 1 0 0 1 1 1v2M19 6l-1 14a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2L5 6"/></svg>`;
    del.addEventListener('click', (e) => {
      e.stopPropagation();
      clearTimeout(noteCardDeleteTimer);
      if (noteCardDeletePending === note.id) {
        noteCardDeletePending = null;
        state.notes = state.notes.filter((n) => n.id !== note.id);
        save();
        renderNotesList();
      } else {
        noteCardDeletePending = note.id;
        renderNotesList();
        noteCardDeleteTimer = setTimeout(() => {
          noteCardDeletePending = null;
          renderNotesList();
        }, 3000);
      }
    });

    li.appendChild(title);
    if (preview.textContent) li.appendChild(preview);
    li.appendChild(meta);
    li.appendChild(del);
    li.addEventListener('click', () => openNoteEditor(note.id));
    els.noteCards.appendChild(li);
  }
}

let noteCardDeletePending = null;
let noteCardDeleteTimer = null;

function openNoteEditor(id) {
  const note = noteById(id);
  if (!note) return;
  openNoteId = id;
  noteDeletePending = false;
  els.editorDelete.classList.remove('confirm');
  els.editorScope.textContent = note.label || 'All work';
  els.editorTitle.value = note.title;
  els.editorBody.value = note.body;
  els.noteEditor.hidden = false;
  requestAnimationFrame(() => (note.title ? els.editorBody : els.editorTitle).focus());
}

function closeNoteEditor() {
  els.noteEditor.hidden = true;
  openNoteId = null;
  renderNotesList();
}

function newNote() {
  const note = {
    id: uid(),
    label: notesLabel,
    title: '',
    body: '',
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };
  state.notes.push(note);
  save();
  openNoteEditor(note.id);
}

function touchOpenNote() {
  const note = noteById(openNoteId);
  if (!note) return;
  note.title = els.editorTitle.value;
  note.body = els.editorBody.value;
  note.updatedAt = Date.now();
  debouncedSave();
}

function deleteOpenNote() {
  if (!noteDeletePending) {
    noteDeletePending = true;
    els.editorDelete.classList.add('confirm');
    setTimeout(() => {
      noteDeletePending = false;
      els.editorDelete.classList.remove('confirm');
    }, 3000);
    return;
  }
  state.notes = state.notes.filter((n) => n.id !== openNoteId);
  save();
  closeNoteEditor();
}

async function copyOpenNote() {
  const note = noteById(openNoteId);
  if (!note) return;
  const text = [note.title.trim(), note.body.trim()].filter(Boolean).join('\n\n');
  try {
    await navigator.clipboard.writeText(text);
    els.editorCopy.textContent = 'Copied';
  } catch {
    els.editorCopy.textContent = 'Failed';
  }
  setTimeout(() => { els.editorCopy.textContent = 'Copy'; }, 1600);
}

function openNotes() {
  closeSettings();
  notesLabel = activeLabel;
  renderNotesList();
  els.notesView.hidden = false;
}

function closeNotes() {
  els.noteEditor.hidden = true;
  openNoteId = null;
  els.notesView.hidden = true;
}

let labelPendingDelete = null;
let labelDeleteTimer = null;

function renderLabelManager() {
  els.labelList.textContent = '';
  for (const label of state.labels) {
    const li = document.createElement('li');
    li.className = 'attention-item';

    const text = document.createElement('span');
    text.className = 'attention-text';
    const dot = document.createElement('span');
    dot.className = 'dot';
    dot.style.background = label.color;
    dot.style.marginRight = '7px';
    text.appendChild(dot);
    text.appendChild(document.createTextNode(label.name));

    const count = state.tasks.filter((t) => t.label === label.name).length;
    const meta = document.createElement('span');
    meta.className = 'attention-why';
    meta.textContent =
      labelPendingDelete === label.name ? 'Sure?' : count ? `${count} tasks` : '';
    if (labelPendingDelete === label.name) meta.classList.add('overdue');

    const del = clearButton(
      labelPendingDelete === label.name ? 'Click again to delete' : 'Delete label',
      () => {
        clearTimeout(labelDeleteTimer);
        if (labelPendingDelete === label.name) {
          labelPendingDelete = null;
          state.labels = state.labels.filter((l) => l.name !== label.name);
          state.tasks.forEach((t) => {
            if (t.label === label.name) t.label = null;
          });
          if (activeLabel === label.name) activeLabel = null;
          save();
          render();
          renderLabelManager();
        } else {
          labelPendingDelete = label.name;
          renderLabelManager();
          labelDeleteTimer = setTimeout(() => {
            labelPendingDelete = null;
            renderLabelManager();
          }, 3000);
        }
      }
    );

    li.append(text, meta, del);
    els.labelList.appendChild(li);
  }
}

function openSettings() {
  closeNotes();
  renderInsights();
  renderLabelManager();
  els.settings.hidden = false;
}

function closeSettings() {
  els.settings.hidden = true;
}

function bindToggle(el, key) {
  el.checked = state.settings[key] !== false;
  el.addEventListener('change', () => {
    state.settings[key] = el.checked;
    save();
  });
}

function bindTime(el, key, fallback) {
  el.value = state.settings[key] || fallback;
  el.addEventListener('change', () => {
    state.settings[key] = el.value || fallback;
    save();
  });
}

async function initSettingsControls() {
  const sounds = await window.api.listSounds();
  els.soundSelect.textContent = '';
  for (const s of sounds) {
    const opt = document.createElement('option');
    opt.value = s;
    opt.textContent = s;
    els.soundSelect.appendChild(opt);
  }
  if (!sounds.includes(state.settings.sound)) state.settings.sound = sounds[0] || 'Glass';
  els.soundSelect.value = state.settings.sound;

  els.soundSelect.addEventListener('change', () => {
    state.settings.sound = els.soundSelect.value;
    save();
    window.api.previewSound(state.settings.sound);
  });
  els.soundPlay.addEventListener('click', () => window.api.previewSound(state.settings.sound));

  bindToggle(els.deadlineToggle, 'deadlineReminders');
  bindTime(els.deadlineTime, 'deadlineTime', '09:00');
  bindToggle(els.briefToggle, 'morningBrief');
  bindTime(els.briefTime, 'briefTime', '08:30');
  bindToggle(els.reviewToggle, 'weeklyReview');
  bindTime(els.reviewTime, 'reviewTime', '17:00');
  bindToggle(els.menubarToggle, 'menubar');

  els.focusMinutes.value = state.settings.focusMinutes || 25;
  els.focusMinutes.addEventListener('change', () => {
    const v = parseInt(els.focusMinutes.value, 10);
    state.settings.focusMinutes = Number.isFinite(v) ? Math.min(120, Math.max(5, v)) : 25;
    els.focusMinutes.value = state.settings.focusMinutes;
    save();
    render();
  });

  els.bubbleStyle.value = state.settings.bubbleStyle === 'dial' ? 'dial' : 'pet';
  els.bubbleStyle.addEventListener('change', () => {
    state.settings.bubbleStyle = els.bubbleStyle.value;
    save();
    render();
  });

  els.loginCheckbox.checked = await window.api.getOpenAtLogin();
  els.loginCheckbox.addEventListener('change', (e) => {
    window.api.setOpenAtLogin(e.target.checked);
  });
}

/* ---------- Actions ---------- */

function addTask() {
  const raw = els.input.value.trim();
  if (!raw) return;
  const parsed = parseQuickAdd(raw);
  if (!parsed.text) return;
  state.tasks.unshift({
    id: uid(),
    text: parsed.text,
    label: parsed.label,
    done: false,
    createdAt: Date.now(),
    doneAt: null,
    notes: '',
    priority: parsed.priority,
    due: parsed.due,
    startAt: parsed.startAt,
    repeat: parsed.repeat,
    reminded: false,
    dueReminded: false,
    focusedMs: 0,
  });
  els.input.value = '';
  els.parseHint.hidden = true;
  save();
  render();
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
  return toLocalDateTimeStr(d);
}

function spawnNextOccurrence(task) {
  const next = {
    ...task,
    id: uid(),
    done: false,
    doneAt: null,
    createdAt: Date.now(),
    reminded: false,
    dueReminded: false,
    focusedMs: 0,
    notes: task.notes,
  };
  if (task.due) next.due = shiftDateStr(task.due, task.repeat);
  if (task.startAt) next.startAt = shiftDateTimeStr(task.startAt, task.repeat);
  if (!task.due && !task.startAt) {
    // A repeating task with no dates re-arms for its next natural day.
    next.due = shiftDateStr(todayStr(), task.repeat);
  }
  // Roll dates forward until they're in the future (covers completing late).
  let guard = 0;
  while (next.due && Date.parse(next.due + 'T23:59:59') < Date.now() && guard++ < 400) {
    next.due = shiftDateStr(next.due, task.repeat);
    if (next.startAt) next.startAt = shiftDateTimeStr(next.startAt, task.repeat);
  }
  state.tasks.unshift(next);
}

function toggleTask(id, row) {
  const task = state.tasks.find((t) => t.id === id);
  if (!task) return;

  if (!task.done) {
    // Let the checkbox fill and the row slide away before it drops to Done.
    row.classList.add('completing');
    setTimeout(() => {
      task.done = true;
      task.doneAt = Date.now();
      if (openTaskId === id) openTaskId = null;
      if (state.focus && state.focus.taskId === id) stopFocus(false);
      if (task.repeat) spawnNextOccurrence(task);
      save();
      render();
      if (state.tasks.length && state.tasks.every((t) => t.done)) celebrate();
    }, 320);
  } else {
    task.done = false;
    task.doneAt = null;
    save();
    render();
  }
}

function deleteTask(id) {
  state.tasks = state.tasks.filter((t) => t.id !== id);
  if (openTaskId === id) openTaskId = null;
  if (state.focus && state.focus.taskId === id) state.focus = null;
  save();
  render();
}

function clearDone() {
  state.tasks = state.tasks.filter((t) => !t.done);
  save();
  render();
}

function celebrate() {
  const origin = els.panel.getBoundingClientRect();
  const cx = origin.left + origin.width / 2;
  const cy = origin.top + 64;
  for (let i = 0; i < 20; i++) {
    const p = document.createElement('span');
    p.className = 'confetti';
    p.style.left = cx + 'px';
    p.style.top = cy + 'px';
    p.style.background = CONFETTI_COLORS[i % CONFETTI_COLORS.length];
    p.style.setProperty('--cx', (Math.random() - 0.5) * 240 + 'px');
    p.style.setProperty('--cy', Math.random() * 190 + 40 + 'px');
    p.style.setProperty('--cr', (Math.random() - 0.5) * 480 + 'deg');
    els.confettiLayer.appendChild(p);
    p.addEventListener('animationend', () => p.remove());
  }
}

/* ---------- Mode / window ---------- */

function setBodyMode(mode) {
  document.body.classList.toggle('expanded', mode === 'expanded');
  document.body.classList.toggle('collapsed', mode === 'collapsed');
  if (mode === 'expanded') {
    requestAnimationFrame(() => els.input.focus());
  }
}

/* ---------- Init ---------- */

function renderDate() {
  els.dateLine.textContent = new Date().toLocaleDateString(undefined, {
    weekday: 'long',
    month: 'long',
    day: 'numeric',
  });
}

function migrateState() {
  state.labels.forEach((label, i) => {
    if (!LABEL_COLORS.includes(label.color)) {
      label.color = LABEL_COLORS[i % LABEL_COLORS.length];
    }
  });
  state.tasks.forEach((t) => {
    if (t.notes === undefined) t.notes = '';
    if (t.priority === undefined) t.priority = null;
    if (t.due === undefined) t.due = null;
    if (t.startAt === undefined) t.startAt = null;
    if (t.repeat === undefined) t.repeat = null;
    if (t.reminded === undefined) t.reminded = false;
    if (t.dueReminded === undefined) t.dueReminded = false;
    if (t.focusedMs === undefined) t.focusedMs = 0;
  });
  state.settings = { ...DEFAULT_SETTINGS, ...(state.settings || {}) };
  if (!Array.isArray(state.focusLog)) state.focusLog = [];
  if (!Array.isArray(state.notes)) state.notes = [];
  // Earlier builds stored one-line "points" — fold them into notes.
  if (Array.isArray(state.points) && state.points.length) {
    for (const p of state.points) {
      state.notes.push({
        id: p.id,
        label: p.label ?? null,
        title: p.text || '',
        body: p.notes || '',
        createdAt: p.createdAt || Date.now(),
        updatedAt: p.createdAt || Date.now(),
      });
    }
    state.points = [];
  }
  if (state.focus === undefined) state.focus = null;
}

function pulseBubble() {
  els.bubble.classList.remove('pulse');
  void els.bubble.offsetWidth;
  els.bubble.classList.add('pulse');
}

async function init() {
  const saved = await window.api.loadState();
  if (saved && Array.isArray(saved.tasks)) {
    state = { ...state, ...saved };
  }
  migrateState();

  renderDate();
  setInterval(renderDate, 60 * 1000);
  setInterval(render, 60 * 1000); // keep Today/Started/Overdue chips fresh
  setInterval(focusTick, 1000);

  // Bubble: drag to move the widget, plain click to open.
  els.bubble.addEventListener('mousedown', (e) => {
    if (e.button !== 0) return;
    window.api.dragStart();
    const onUp = async () => {
      document.removeEventListener('mouseup', onUp);
      const moved = await window.api.dragEnd();
      if (!moved) window.api.setMode('expanded');
    };
    document.addEventListener('mouseup', onUp);
  });

  els.collapseBtn.addEventListener('click', () => window.api.setMode('collapsed'));
  window.api.onModeChanged(setBodyMode);

  window.api.onReminderFired(({ id, kind }) => {
    const task = state.tasks.find((t) => t.id === id);
    if (task) {
      if (kind === 'start') task.reminded = true;
      if (kind === 'due') task.dueReminded = true;
      save();
    }
    pulseBubble();
    render();
  });

  window.api.onSummaryFired(({ kind, date }) => {
    if (kind === 'brief') state.settings.lastBriefDate = date;
    if (kind === 'review') state.settings.lastReviewDate = date;
    save();
    pulseBubble();
  });

  window.api.onOpenInsights(() => {
    openSettings();
    render();
  });

  els.addBtn.addEventListener('click', addTask);
  els.input.addEventListener('input', renderParseHint);
  els.input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') addTask();
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      if (!els.noteEditor.hidden) {
        closeNoteEditor();
      } else if (!els.notesView.hidden) {
        closeNotes();
      } else if (!els.settings.hidden) {
        closeSettings();
      } else if (e.target.tagName === 'TEXTAREA' || openTaskId) {
        openTaskId = null;
        render();
      } else {
        window.api.setMode('collapsed');
      }
    }
  });

  els.clearDone.addEventListener('click', clearDone);
  els.settingsBtn.addEventListener('click', openSettings);
  els.settingsBack.addEventListener('click', closeSettings);
  els.focusStop.addEventListener('click', () => stopFocus(false));
  els.quitBtn.addEventListener('click', () => window.api.quit());

  els.notesBtn.addEventListener('click', openNotes);
  els.notesBack.addEventListener('click', closeNotes);
  els.noteNew.addEventListener('click', newNote);
  els.editorBack.addEventListener('click', closeNoteEditor);
  els.editorCopy.addEventListener('click', copyOpenNote);
  els.editorDelete.addEventListener('click', deleteOpenNote);
  els.editorTitle.addEventListener('input', touchOpenNote);
  els.editorBody.addEventListener('input', touchOpenNote);
  els.editorTitle.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') els.editorBody.focus();
    e.stopPropagation();
  });

  await initSettingsControls();
  render();
}

init();
