// Jev: turns a spoken sentence into a labelled task.
//
// Jev is a structured-classification model — text in, typed answers out. It
// does not accept audio, so callers transcribe first (on-device, via the
// Speech framework) and hand the transcript here.
//
// The key never lives in this repo. It is entered in the widget's settings and
// stored with the rest of the app state under userData.
const https = require('https');

const ENDPOINT = 'https://tokenra.io/v1/decisions';
const MODEL = 'jev-latest';
const TIMEOUT_MS = 15000;

/// Builds the question set from the user's own labels, so classification is
/// always scoped to projects that actually exist.
function questionsFor(labels) {
  const criteria = {};
  for (const l of labels) {
    criteria[l.name] = l.hint || `Work belonging to the "${l.name}" project`;
  }
  criteria.none = 'No clear project, or a personal errand with no label';

  return {
    kind: {
      type: 'Choice',
      instructions: 'Is the speaker recording something they must do, or something to remember?',
      criteria: {
        task: 'An action the speaker intends to carry out; has a verb and an outcome',
        note: 'Information, a decision, or a reference to keep; no action implied',
      },
    },
    label: {
      type: 'Choice',
      instructions: 'Which of these projects does this belong to? Answer "none" if unclear.',
      criteria,
    },
    priority: {
      type: 'Choice',
      instructions: 'How urgent does the speaker sound? Only say "high" for an explicit deadline or stated urgency.',
      criteria: {
        high: 'Explicitly urgent, blocking, or tied to a hard deadline',
        med: 'Time-sensitive but not critical',
        none: 'No urgency signalled',
      },
    },
  };
}

function postJson(url, body, key) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body);
    const req = https.request(
      url,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(payload),
          Authorization: `Bearer ${key}`,
        },
        timeout: TIMEOUT_MS,
      },
      (res) => {
        let data = '';
        res.on('data', (c) => { data += c; });
        res.on('end', () => {
          if (res.statusCode < 200 || res.statusCode >= 300) {
            let detail = data.slice(0, 200);
            try { detail = JSON.parse(data).error?.message || detail; } catch { /* keep raw */ }
            reject(new Error(`Jev ${res.statusCode}: ${detail}`));
            return;
          }
          try { resolve(JSON.parse(data)); } catch (e) { reject(new Error('Jev returned malformed JSON')); }
        });
      }
    );
    req.on('timeout', () => { req.destroy(new Error('Jev timed out')); });
    req.on('error', reject);
    req.end(payload);
  });
}

/// Reads one answer out of Jev's response, tolerating the shape shifting
/// slightly — a wrong guess here should degrade to "unlabelled", never throw.
function pick(answers, key) {
  const a = answers && answers[key];
  if (!a) return { value: null, confidence: null };
  const value = typeof a === 'string' ? a : (a.choice ?? a.value ?? null);
  const confidence = typeof a === 'object' ? (a.confidence ?? null) : null;
  return { value: value === 'none' ? null : value, confidence };
}

/**
 * Classifies a transcript into {kind, label, priority}.
 *
 * Returns `{ ok: false, error }` rather than throwing: a failed classification
 * must still let the caller save the raw transcript as a plain task.
 */
async function classify(transcript, { key, labels = [] } = {}) {
  const text = String(transcript || '').trim();
  if (!text) return { ok: false, error: 'nothing was said' };
  if (!key) return { ok: false, error: 'no Jev API key set' };

  try {
    const res = await postJson(
      ENDPOINT,
      {
        model: MODEL,
        state: `A voice note captured by someone managing their own work. Transcript: "${text}"`,
        questions: questionsFor(labels),
      },
      key
    );

    const answers = res.answers || res;
    const kind = pick(answers, 'kind');
    const label = pick(answers, 'label');
    const priority = pick(answers, 'priority');

    return {
      ok: true,
      kind: kind.value === 'note' ? 'note' : 'task',
      // Never invent a label the user doesn't have.
      label: labels.some((l) => l.name === label.value) ? label.value : null,
      priority: ['high', 'med'].includes(priority.value) ? priority.value : null,
      confidence: {
        kind: kind.confidence,
        label: label.confidence,
        priority: priority.confidence,
      },
    };
  } catch (err) {
    return { ok: false, error: err.message };
  }
}

module.exports = { classify, questionsFor };
