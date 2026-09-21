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
  // Evening kickoff — the brief that lands when the work actually happens.
  eveningKickoff: true,
  kickoffTime: '21:30',
  lastKickoffDate: null,
  // Calendar
  meetingNudge: true,
  meetingNudgeMinutes: 10,
  calendarIds: null, // null = every calendar; an array is an explicit pick
  agendaFolded: false,
  // Lock-in
  lockInMinutes: 60,
  lockInWithFocus: true,
};

const STALE_DAYS = 3;
const AGENDA_GAP_MIN = 30; // shorter gaps aren't worth calling free time

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
let calendarSnap = { events: [], calendars: [], status: 'unknown', error: null };
let lockinState = { active: false };

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
  // Lock-in
  lockinBtn: $('lockin-btn'),
  lockinStrip: $('lockin-strip'),
  lockinLabel: $('lockin-label'),
  lockinTime: $('lockin-time'),
  lockinPlus: $('lockin-plus'),
  lockinStop: $('lockin-stop'),
  lockinMenu: $('lockin-menu'),
  lockinCustomMin: $('lockin-custom-min'),
  lockinCustomGo: $('lockin-custom-go'),
  lockinFocusToggle: $('lockin-focus-toggle'),
  lockinMinutes: $('lockin-minutes'),
  lockinWithFocus: $('lockin-with-focus'),
  // Agenda
  agenda: $('agenda'),
  agendaFree: $('agenda-free'),
  agendaCollapse: $('agenda-collapse'),
  agendaList: $('agenda-list'),
  calendarCta: $('calendar-cta'),
  calendarCtaText: $('calendar-cta-text'),
  calendarConnect: $('calendar-connect'),
  calendarConnect2: $('calendar-connect-2'),
  calendarStatus: $('calendar-status'),
  calendarPicker: $('calendar-picker'),
  // Insights
  agingBlock: $('aging-block'),
  agingList: $('aging-list'),
  clientBlock: $('client-block'),
  clientList: $('client-list'),
  // Reminders
  kickoffToggle: $('kickoff-toggle'),
  kickoffTime: $('kickoff-time'),
  nudgeToggle: $('nudge-toggle'),
  nudgeMinutes: $('nudge-minutes'),
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

function taskAgeDays(task) {
  if (!task.createdAt) return 0;
  return Math.floor((Date.now() - task.createdAt) / DAY_MS);
}

/// A task is "aging" only when nothing else is already flagging it — an
/// overdue date or a start time is a louder signal than age on its own.
function isAging(task) {
  return !task.done && !task.due && !task.startAt && taskAgeDays(task) >= STALE_DAYS;
}

function ageClass(days) {
  if (days >= 14) return 'hot';
  if (days >= 7) return 'warm';
  return '';
}

/* ---------- Calendar helpers ---------- */

function endOfToday() {
  const d = new Date();
  d.setHours(23, 59, 59, 999);
  return d.getTime();
}

function eventStart(ev) { return Date.parse(ev.start); }
function eventEnd(ev) { return Date.parse(ev.end || ev.start); }

function liveEvents() {
  return (calendarSnap.events || []).filter((e) => e.status !== 'canceled');
}

function todaysEvents() {
  const from = startOfToday();
  const to = endOfToday();
  return liveEvents()
    .filter((e) => {
      const s = eventStart(e);
      if (!Number.isFinite(s)) return false;
      return e.allDay ? s <= to && eventEnd(e) >= from : s <= to && eventEnd(e) >= from;
    })
    .sort((a, b) => (a.allDay ? 0 : 1) - (b.allDay ? 0 : 1) || eventStart(a) - eventStart(b));
}

/// Total booked milliseconds in [from, to], with overlapping meetings merged so
/// a double-booked hour is only counted once.
function busyMs(events, from, to) {
  const spans = events
    .filter((e) => !e.allDay)
    .map((e) => [Math.max(eventStart(e), from), Math.min(eventEnd(e), to)])
    .filter(([a, b]) => Number.isFinite(a) && Number.isFinite(b) && b > a)
    .sort((a, b) => a[0] - b[0]);

  let total = 0;
  let curStart = null;
  let curEnd = null;
  for (const [a, b] of spans) {
    if (curEnd === null || a > curEnd) {
      if (curEnd !== null) total += curEnd - curStart;
      curStart = a;
      curEnd = b;
    } else if (b > curEnd) {
      curEnd = b;
    }
  }
  if (curEnd !== null) total += curEnd - curStart;
  return total;
}

function eventTimeLabel(ev) {
  if (ev.allDay) return 'All day';
  const d = new Date(eventStart(ev));
  return d.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit' });
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

  // Nothing else is flagging this one and it's been sitting a while.
  if (isAging(task)) {
    const days = taskAgeDays(task);
    meta.appendChild(metaChip(`age-chip ${ageClass(days)}`, clockSvg(), `${days}d old`));
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

  // Two-way: put this task's start time on a real calendar.
  if (calendarSnap.status === 'fullAccess') {
    const calBtn = document.createElement('button');
    calBtn.className = 'focus-btn';
    if (task.eventId) {
      calBtn.textContent = 'Remove from calendar';
      calBtn.addEventListener('click', () => unblockTime(task, calBtn));
    } else if (task.startAt) {
      calBtn.textContent = `Block ${state.settings.focusMinutes || 25} min`;
      calBtn.addEventListener('click', () => blockTime(task, calBtn));
    } else {
      calBtn.textContent = 'Set a start time first';
      calBtn.disabled = true;
    }
    wrap.appendChild(detailRow('Calendar', calBtn));
  }

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
  // A session that lets the screen lock is a session you abandon.
  if (state.settings.lockInWithFocus !== false) startLockin(minutes, 'focus');
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
  // Only release the assertion if the session is what took it.
  if (lockinState.active && lockinState.reason === 'focus') {
    window.api.lockinStop().then((s) => { lockinState = s; renderLockin(); });
  }
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

/* ---------- Agenda ---------- */

function taskPlusSvg() {
  return `<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor"
      stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg>`;
}

function notePlusSvg() {
  return `<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor"
      stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
      <path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></svg>`;
}

function agendaRow(ev, now) {
  const li = document.createElement('li');
  const live = !ev.allDay && eventStart(ev) <= now && eventEnd(ev) > now;
  const past = !ev.allDay && eventEnd(ev) <= now;
  li.className = 'agenda-item' + (live ? ' now' : '') + (past ? ' past' : '');

  const rail = document.createElement('span');
  rail.className = 'agenda-rail';
  if (ev.color && !live) rail.style.background = ev.color;

  const time = document.createElement('span');
  time.className = 'agenda-time';
  time.textContent = eventTimeLabel(ev);

  const body = document.createElement('div');
  body.className = 'agenda-body';
  const name = document.createElement('div');
  name.className = 'agenda-name';
  name.textContent = ev.title;
  name.title = ev.title;
  body.appendChild(name);

  // One line of context, in order of how much it tells you.
  const bits = [];
  if (live) bits.push('Now');
  if (ev.location) bits.push(ev.location);
  else if (ev.attendeeCount) bits.push(`${ev.attendeeCount} people`);
  else if (ev.calendar) bits.push(ev.calendar);
  if (bits.length) {
    const sub = document.createElement('div');
    sub.className = 'agenda-sub';
    sub.textContent = bits.join(' · ');
    body.appendChild(sub);
  }

  const actions = document.createElement('div');
  actions.className = 'agenda-actions';
  const action = (svg, title, fn) => {
    const b = document.createElement('button');
    b.innerHTML = svg;
    b.title = title;
    b.addEventListener('click', (e) => { e.stopPropagation(); fn(); });
    actions.appendChild(b);
  };
  action(taskPlusSvg(), 'Make a task from this', () => taskFromEvent(ev));
  action(notePlusSvg(), 'Prepare a note for this', () => noteFromEvent(ev));

  li.append(rail, time, body, actions);
  return li;
}

function renderAgenda() {
  const status = calendarSnap.status;
  const connected = status === 'fullAccess';
  const blocked = status === 'denied' || status === 'restricted';

  els.agenda.hidden = !connected;
  els.calendarCta.hidden = connected;

  if (!connected) {
    els.calendarCtaText.textContent = blocked
      ? 'Calendar access is off. Turn miTasks on in System Settings → Privacy & Security → Calendars.'
      : "See today's meetings alongside your tasks.";
    els.calendarConnect.hidden = blocked;
    return;
  }

  const now = Date.now();
  const events = todaysEvents();
  els.agenda.classList.toggle('folded', !!state.settings.agendaFolded);

  const free = Math.max(0, endOfToday() - now - busyMs(events, now, endOfToday()));
  const left = events.filter((e) => !e.allDay && eventEnd(e) > now).length;
  els.agendaFree.textContent = events.length
    ? `${formatMinutes(free)} free` + (left ? ` · ${left} to go` : '')
    : 'Nothing booked';

  els.agendaList.textContent = '';
  let prevEnd = null;
  for (const ev of events) {
    if (!ev.allDay && prevEnd !== null) {
      const gap = eventStart(ev) - prevEnd;
      if (gap >= AGENDA_GAP_MIN * 60000) {
        const li = document.createElement('li');
        li.className = 'agenda-gap';
        li.textContent = `${formatMinutes(gap)} open`;
        els.agendaList.appendChild(li);
      }
    }
    els.agendaList.appendChild(agendaRow(ev, now));
    if (!ev.allDay) prevEnd = Math.max(prevEnd ?? 0, eventEnd(ev));
  }
}

function taskFromEvent(ev) {
  const start = new Date(eventStart(ev));
  state.tasks.unshift({
    id: uid(),
    text: ev.title,
    label: activeLabel,
    done: false,
    createdAt: Date.now(),
    doneAt: null,
    notes: [ev.location, ev.notes].filter(Boolean).join('\n\n').slice(0, 5000),
    priority: null,
    due: toDateStr(start),
    startAt: ev.allDay ? null : toLocalDateTimeStr(start),
    repeat: null,
    reminded: false,
    dueReminded: false,
    focusedMs: 0,
    // Deliberately NOT `eventId`: that field means "miTasks made this event"
    // and the detail panel offers to delete it. This meeting already existed,
    // so we only record where it came from.
    sourceEventId: ev.id,
  });
  save();
  render();
}

function noteFromEvent(ev) {
  const lines = [];
  if (Number.isFinite(eventStart(ev))) {
    lines.push(
      new Date(eventStart(ev)).toLocaleString(undefined, {
        weekday: 'long', month: 'long', day: 'numeric',
        hour: 'numeric', minute: '2-digit',
      })
    );
  }
  if (ev.location) lines.push(ev.location);
  if (Array.isArray(ev.attendees) && ev.attendees.length) lines.push('With: ' + ev.attendees.join(', '));

  const note = {
    id: uid(),
    label: activeLabel,
    title: ev.title,
    body: lines.length ? lines.join('\n') + '\n\n' : '',
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };
  state.notes.push(note);
  save();
  openNotes();
  openNoteEditor(note.id);
}

/* Two-way: put a task's start time on a real calendar. */

async function blockTime(task, btn) {
  if (!task.startAt) return;
  btn.disabled = true;
  btn.textContent = 'Blocking…';
  const res = await window.api.calendarCreate({
    title: task.text,
    start: task.startAt,
    minutes: state.settings.focusMinutes || 25,
    notes: task.notes || '',
    alarmMinutesBefore: state.settings.meetingNudgeMinutes || 10,
  });
  if (res && res.ok && res.event) {
    task.eventId = res.event.id;
    save();
    render();
    return;
  }
  btn.textContent = (res && res.error) ? String(res.error).slice(0, 38) : 'Could not block';
  setTimeout(render, 2600);
}

async function unblockTime(task, btn) {
  btn.disabled = true;
  btn.textContent = 'Removing…';
  const res = await window.api.calendarDelete(task.eventId);
  // Drop the link either way — a vanished event shouldn't strand the row.
  task.eventId = null;
  save();
  render();
  if (res && !res.ok) console.warn('calendar delete failed:', res.error);
}

/* ---------- Lock-in ---------- */

function lockinClock(ms) {
  const total = Math.max(0, Math.ceil(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const sec = total % 60;
  const pad = (n) => String(n).padStart(2, '0');
  return h ? `${h}:${pad(m)}:${pad(sec)}` : `${m}:${pad(sec)}`;
}

function renderLockin() {
  const active = !!lockinState.active;
  els.lockinStrip.hidden = !active;
  els.lockinBtn.classList.toggle('active', active);
  if (active) els.lockinMenu.hidden = true;
  if (!active) return;
  els.lockinLabel.textContent = lockinState.reason === 'focus' ? 'Awake · focus' : 'Locked in';
  els.lockinTime.textContent = lockinClock(lockinState.endAt - Date.now());
}

function lockinTick() {
  if (!lockinState.active) return;
  if (lockinState.endAt - Date.now() <= 0) {
    // main will confirm, but drop the strip immediately rather than sit at 0:00.
    lockinState = { active: false };
    renderLockin();
    return;
  }
  els.lockinTime.textContent = lockinClock(lockinState.endAt - Date.now());
}

async function startLockin(minutes, reason = 'manual') {
  els.lockinMenu.hidden = true;
  lockinState = await window.api.lockinStart(minutes, reason);
  renderLockin();
}

/* ---------- Insights: aging & label health ---------- */

function renderAging() {
  const aging = state.tasks.filter(isAging).sort((a, b) => a.createdAt - b.createdAt);
  els.agingBlock.hidden = aging.length === 0;
  els.agingList.textContent = '';

  for (const task of aging.slice(0, 8)) {
    const li = document.createElement('li');
    li.className = 'attention-item';
    const name = document.createElement('span');
    name.className = 'attention-text';
    name.textContent = task.text;
    const days = taskAgeDays(task);
    const tag = document.createElement('span');
    tag.className = 'attention-why' + (ageClass(days) === 'hot' ? ' overdue' : '');
    tag.textContent = `${days}d`;
    li.append(name, tag);
    li.addEventListener('click', () => {
      activeLabel = null;
      openTaskId = task.id;
      closeSettings();
      render();
    });
    els.agingList.appendChild(li);
  }
}

function renderClientHealth() {
  const buckets = new Map();
  for (const task of state.tasks) {
    const key = task.label || null;
    if (!buckets.has(key)) buckets.set(key, []);
    buckets.get(key).push(task);
  }

  const rows = [...buckets].map(([name, tasks]) => {
    const done = tasks.filter((t) => t.done).length;
    const touched = tasks.map((t) => t.doneAt || t.createdAt || 0);
    return {
      name,
      total: tasks.length,
      done,
      open: tasks.length - done,
      last: touched.length ? Math.max(...touched) : 0,
    };
  });

  // Buckets with open work come first, oldest activity at the top — the whole
  // point is spotting the client that has gone quiet.
  rows.sort((a, b) => (b.open ? 1 : 0) - (a.open ? 1 : 0) || a.last - b.last);

  els.clientBlock.hidden = rows.length === 0;
  els.clientList.textContent = '';

  for (const row of rows) {
    const li = document.createElement('li');
    li.className = 'client-row';
    const label = labelFor(row.name);

    const name = document.createElement('span');
    name.className = 'client-name';
    if (label) {
      const dot = document.createElement('span');
      dot.className = 'dot';
      dot.style.background = label.color;
      dot.style.marginRight = '7px';
      name.appendChild(dot);
    }
    name.appendChild(document.createTextNode(row.name || 'No label'));
    name.title = row.name || 'No label';

    const track = document.createElement('div');
    track.className = 'client-track';
    const fill = document.createElement('div');
    fill.className = 'client-fill';
    fill.style.width = (row.total ? (row.done / row.total) * 100 : 0) + '%';
    fill.style.background = label ? label.color : 'rgba(240,234,221,0.3)';
    track.appendChild(fill);

    const meta = document.createElement('span');
    meta.className = 'client-meta';
    const quietDays = row.last ? Math.floor((Date.now() - row.last) / DAY_MS) : 0;
    if (row.open) {
      meta.textContent = quietDays >= 7 ? `${row.open} open · ${quietDays}d` : `${row.open} open`;
      if (quietDays >= 7) meta.classList.add('quiet');
    } else {
      meta.textContent = `${row.done}/${row.total}`;
    }

    li.append(name, track, meta);
    els.clientList.appendChild(li);
  }
}

/* ---------- Calendar settings ---------- */

function renderCalendarSettings() {
  const status = calendarSnap.status;
  const ok = status === 'fullAccess';

  els.calendarStatus.textContent = ok
    ? `${calendarSnap.calendars.length} calendar${calendarSnap.calendars.length === 1 ? '' : 's'} connected`
    : status === 'denied'
      ? 'Off — System Settings › Privacy › Calendars'
      : status === 'restricted'
        ? 'Restricted by policy'
        : 'Not connected';
  els.calendarStatus.className = 'setting-note ' + (ok ? 'ok' : 'bad');
  els.calendarConnect2.hidden = ok || status === 'restricted';

  els.calendarPicker.textContent = '';
  if (!ok) return;

  const selected = state.settings.calendarIds;
  for (const cal of calendarSnap.calendars) {
    const on = !Array.isArray(selected) || selected.includes(cal.id);
    const li = document.createElement('li');
    li.className = 'cal-item' + (on ? '' : ' off');

    const check = document.createElement('span');
    check.className = 'cal-check';
    check.innerHTML = checkSvg();

    const name = document.createElement('span');
    name.className = 'cal-name';
    const dot = document.createElement('span');
    dot.className = 'dot';
    dot.style.background = cal.color || 'rgba(240,234,221,0.3)';
    dot.style.marginRight = '7px';
    name.append(dot, document.createTextNode(cal.title));
    name.title = cal.title;

    const account = document.createElement('span');
    account.className = 'cal-account';
    account.textContent = cal.account || '';

    li.append(check, name, account);
    li.addEventListener('click', () => toggleCalendar(cal.id));
    els.calendarPicker.appendChild(li);
  }
}

function toggleCalendar(id) {
  const all = calendarSnap.calendars.map((c) => c.id);
  const current = Array.isArray(state.settings.calendarIds)
    ? state.settings.calendarIds
    : all.slice();
  const next = current.includes(id) ? current.filter((x) => x !== id) : [...current, id];
  // Everything ticked is the same as no filter — store the simpler form.
  state.settings.calendarIds = next.length === all.length ? null : next;
  save();
  renderCalendarSettings();
  window.api.calendarRefresh();
}

/// Says what actually happened, rather than a generic failure. The three
/// outcomes need different things from the user, so they get different copy.
function accessMessage(res) {
  const status = (res && res.status) || 'unknown';
  if (res && res.error) return `Calendar error: ${res.error}`;
  if (status === 'denied') {
    return 'Denied. Turn miTasks back on in System Settings › Privacy & Security › Calendars.';
  }
  if (status === 'notDetermined') {
    return 'macOS did not show the prompt. Quit miTasks and reopen it from Spotlight, then try again.';
  }
  if (status === 'restricted') return 'Calendar access is restricted by a profile on this Mac.';
  if (status === 'writeOnly') {
    return 'Only write access was granted. miTasks needs full access to show your agenda.';
  }
  return `Calendar access not granted (${status}).`;
}

async function connectCalendar(btn) {
  const original = btn.textContent;
  btn.disabled = true;
  btn.textContent = 'Waiting…';

  let res;
  try {
    res = await window.api.calendarRequest();
  } catch (err) {
    res = { status: 'unknown', error: String(err && err.message ? err.message : err) };
  }
  calendarSnap = (await window.api.calendarGet()) || calendarSnap;

  btn.disabled = false;
  btn.textContent = original;

  // Re-render first, then write the message over the top — both renderers
  // reset this copy, so setting it beforehand would just be overwritten.
  renderAgenda();
  renderCalendarSettings();

  if (calendarSnap.status !== 'fullAccess') {
    const message = accessMessage(res);
    els.calendarCtaText.textContent = message;
    els.calendarStatus.textContent = message;
    els.calendarStatus.className = 'setting-note bad';
    console.warn('calendar request:', JSON.stringify(res));
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
  renderAgenda();
  renderLockin();
  if (!els.settings.hidden) renderInsights();
}

/* ---------- Insights / settings ---------- */

function renderInsights() {
  renderAging();
  renderClientHealth();
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
  renderCalendarSettings();
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
  bindToggle(els.kickoffToggle, 'eveningKickoff');
  bindTime(els.kickoffTime, 'kickoffTime', '21:30');
  bindToggle(els.nudgeToggle, 'meetingNudge');

  const bindNumber = (el, key, min, max, fallback) => {
    el.value = state.settings[key] || fallback;
    el.addEventListener('change', () => {
      const v = parseInt(el.value, 10);
      state.settings[key] = Number.isFinite(v) ? Math.min(max, Math.max(min, v)) : fallback;
      el.value = state.settings[key];
      save();
    });
  };
  bindNumber(els.nudgeMinutes, 'meetingNudgeMinutes', 1, 60, 10);
  bindNumber(els.lockinMinutes, 'lockInMinutes', 1, 480, 60);

  // The tie-in has a control in Advanced and one in the lock-in sheet.
  const syncTie = (on) => {
    els.lockinWithFocus.checked = on;
    els.lockinFocusToggle.checked = on;
  };
  syncTie(state.settings.lockInWithFocus !== false);
  els.lockinWithFocus.addEventListener('change', () => {
    state.settings.lockInWithFocus = els.lockinWithFocus.checked;
    syncTie(els.lockinWithFocus.checked);
    save();
  });

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
    eventId: null, // the next occurrence isn't the event we already booked
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
  // Don't let a half-made choice greet you next time the panel opens.
  if (mode === 'collapsed') els.lockinMenu.hidden = true;
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
    if (t.eventId === undefined) t.eventId = null;
    if (t.sourceEventId === undefined) t.sourceEventId = null;
  });
  state.settings = { ...DEFAULT_SETTINGS, ...(state.settings || {}) };
  // One-time retime: completions here cluster after 22:00, so a stock 08:30
  // brief and a Friday-17:00 review were firing when nobody was looking. Only
  // shifts times still sitting on the old defaults — a deliberate choice stays.
  if (!state.settings.retimedV1) {
    if (state.settings.briefTime === '08:30') state.settings.briefTime = '10:00';
    if (state.settings.reviewTime === '17:00') state.settings.reviewTime = '22:00';
    state.settings.retimedV1 = true;
  }
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
  // Persist immediately so main.js and disk agree about the new settings
  // rather than waiting for whatever the user happens to do first.
  save();

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
    if (kind === 'kickoff') state.settings.lastKickoffDate = date;
    save();
    pulseBubble();
  });

  window.api.onMeetingNudge(() => pulseBubble());

  window.api.onOpenInsights(() => {
    openSettings();
    render();
  });

  // A phone made a change — adopt it. Keep local UI state (filters, open task).
  window.api.onExternalState((incoming) => {
    if (!incoming || !Array.isArray(incoming.tasks)) return;
    state = incoming;
    migrateState();
    render();
  });

  // Populate the iPhone links in Advanced.
  window.api.getSyncInfo().then((info) => {
    const bind = (el, url) => {
      if (!url) { el.textContent = 'not available'; return; }
      el.textContent = url;
      el.addEventListener('click', async () => {
        try {
          await navigator.clipboard.writeText(url);
          const prev = el.textContent;
          el.textContent = 'Copied — open it on your iPhone';
          setTimeout(() => { el.textContent = prev; }, 2000);
        } catch { /* clipboard unavailable */ }
      });
    };
    bind(document.getElementById('sync-url-ts'), info.public || info.tailscale);
    bind(document.getElementById('sync-url-lan'), info.lan);

    // Prefer the Tailscale URL: it keeps working when the Wi-Fi address changes.
    const pairUrl = info.public || info.tailscale || info.lan;
    const img = document.getElementById('sync-qr');
    if (pairUrl && img) {
      window.api.syncQr(pairUrl).then((data) => {
        if (data) img.src = data;
        else img.remove();
      });
    } else if (img) {
      img.remove();
    }
  });

  els.addBtn.addEventListener('click', addTask);
  els.input.addEventListener('input', renderParseHint);
  els.input.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') addTask();
  });
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
      if (!els.lockinMenu.hidden) {
        els.lockinMenu.hidden = true;
      } else if (!els.noteEditor.hidden) {
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

  // Calendar + lock-in both live in the main process; mirror them here.
  calendarSnap = (await window.api.calendarGet()) || calendarSnap;
  lockinState = (await window.api.lockinStatus()) || lockinState;

  window.api.onCalendarState((snap) => {
    if (!snap) return;
    calendarSnap = snap;
    renderAgenda();
    if (!els.settings.hidden) renderCalendarSettings();
  });

  window.api.onLockinState((s) => {
    lockinState = s || { active: false };
    renderLockin();
  });

  setInterval(lockinTick, 1000);

  const applyLockin = (promise) =>
    promise.then((s) => { lockinState = s || { active: false }; renderLockin(); });

  els.lockinBtn.addEventListener('click', () => {
    if (lockinState.active) { applyLockin(window.api.lockinStop()); return; }
    els.lockinMenu.hidden = !els.lockinMenu.hidden;
    if (!els.lockinMenu.hidden) els.lockinCustomMin.value = state.settings.lockInMinutes || 60;
  });
  els.lockinStop.addEventListener('click', () => applyLockin(window.api.lockinStop()));
  els.lockinPlus.addEventListener('click', () => applyLockin(window.api.lockinExtend(15)));
  for (const btn of els.lockinMenu.querySelectorAll('.lockin-opts button')) {
    btn.addEventListener('click', () => startLockin(parseInt(btn.dataset.min, 10)));
  }
  els.lockinCustomGo.addEventListener('click', () => {
    const v = parseInt(els.lockinCustomMin.value, 10);
    if (Number.isFinite(v) && v > 0) startLockin(v);
  });
  els.lockinCustomMin.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') els.lockinCustomGo.click();
    e.stopPropagation();
  });
  els.lockinFocusToggle.addEventListener('change', () => {
    state.settings.lockInWithFocus = els.lockinFocusToggle.checked;
    els.lockinWithFocus.checked = els.lockinFocusToggle.checked;
    save();
  });

  els.agendaCollapse.addEventListener('click', () => {
    state.settings.agendaFolded = !state.settings.agendaFolded;
    save();
    renderAgenda();
  });
  els.calendarConnect.addEventListener('click', () => connectCalendar(els.calendarConnect));
  els.calendarConnect2.addEventListener('click', () => connectCalendar(els.calendarConnect2));

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
