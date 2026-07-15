/**
 * session-title.js — Heuristic session titles, slugs, and drift detection.
 *
 * Self-contained: depends only on Node core so it never breaks when the
 * everything-claude-code (ECC) plugin updates. ECC's session-end hook writes
 * `~/.claude/sessions/<date>-<id>-session.tmp` files keyed only by date; this
 * library derives a human-readable title + kebab slug from each file's content
 * and detects when that content has drifted enough to warrant a re-title.
 *
 * Session file shape (written by ECC):
 *   # Session: 2026-04-08            <- heading (we rewrite this)
 *   **Date:** 2026-04-08
 *   **Started:** 06:40
 *   **Last Updated:** 06:40
 *   **Project:** meta-sharper
 *   **Branch:** main
 *   **Worktree:** {{ .chezmoi.homeDir }}/meta-sharper
 *   ---
 *   <!-- ECC:SUMMARY:START -->
 *   ## Session Summary
 *   ### Tasks
 *   - <user message>
 *   ### Files Modified
 *   - <path>
 *   ...
 */

'use strict';

const crypto = require('crypto');

// Markers we inject into the header block. parseSessionMetadata in ECC already
// reads **Title:** generically; the others are ours and ignored by ECC.
const TITLE_FIELD = 'Title';
const SLUG_FIELD = 'Slug';
const FINGERPRINT_FIELD = 'TitleFingerprint';

const MAX_TITLE_LEN = 72;
const MAX_SLUG_LEN = 48;
const MAX_TOPIC_WORDS = 6;

// User messages that carry no topical signal — skip when picking a topic.
// Matched against the whole (cleaned) message, case-insensitively.
const NOISE_EXACT = new Set([
  'done', 'proceed', 'yes', 'no', 'ok', 'okay', 'continue', 'go ahead',
  'thanks', 'thank you', 'sure', 'yep', 'nope', 'next', 'go on', 'right',
  'commit', 'commit for now', 'done. proceed', 'continue from where you left off.',
  'continue from where you left off', 'push', 'go', 'do it', 'yeah'
]);

// Prefixes that mark a low-signal acknowledgement/continuation.
const NOISE_PREFIXES = [
  'done', 'proceed', 'commit', 'continue from where', 'go ahead', 'thanks'
];

// A real task usually leads with (or contains early) an action verb. We boost
// messages that match so an actionable line beats a vague question.
const ACTION_VERBS = /\b(add|remove|fix|build|create|implement|refactor|update|setup|set up|configure|analyse|analyze|sync|improve|optimi[sz]e|run|migrate|write|generate|review|audit|deploy|install|wire|integrate|port|clean|debug|test|document|rename|delete|enable|disable)\b/i;

// Stopwords stripped when slugifying a topic into a key.
const STOPWORDS = new Set([
  'the', 'a', 'an', 'and', 'or', 'but', 'of', 'to', 'in', 'on', 'for', 'with',
  'is', 'are', 'was', 'were', 'be', 'been', 'i', 'you', 'we', 'it', 'this',
  'that', 'these', 'those', 'my', 'your', 'our', 'me', 'do', 'does', 'did',
  'can', 'could', 'should', 'would', 'will', 'how', 'what', 'why', 'when',
  'please', 'lets', 'let', 'maybe', 'guess', 'think', 'about', 'from', 'into',
  'at', 'as', 'so', 'if', 'then', 'now', 'just', 'also', 'add', 'update'
]);

/**
 * Read a `**Label:** value` field from a header string.
 * @param {string} text
 * @param {string} label
 * @returns {string|null}
 */
function readField(text, label) {
  if (!text) return null;
  const re = new RegExp(`\\*\\*${escapeRegExp(label)}:\\*\\*\\s*(.+)$`, 'm');
  const m = text.match(re);
  return m ? m[1].trim() : null;
}

/**
 * Split a session file into { heading, headerBody, separator, body }.
 * headerBody is the metadata lines between the heading and the `---` separator.
 * Returns null-ish parts gracefully if the file is malformed.
 * @param {string} content
 */
function splitSession(content) {
  const safe = content || '';
  const sepIdx = safe.indexOf('\n---\n');
  const header = sepIdx === -1 ? safe : safe.slice(0, sepIdx);
  const body = sepIdx === -1 ? '' : safe.slice(sepIdx + '\n---\n'.length);

  const headingMatch = header.match(/^#\s+(.+)$/m);
  const heading = headingMatch ? headingMatch[0] : null;
  const headingText = headingMatch ? headingMatch[1].trim() : null;

  return {
    heading,
    headingText,
    header,
    body,
    hasSeparator: sepIdx !== -1
  };
}

/**
 * Pull the signal we title from: project, first meaningful user task, and a
 * couple of distinctive file basenames.
 * @param {string} content
 */
function extractSignal(content) {
  const { header, body } = splitSession(content);

  const project = readField(header, 'Project');
  const branch = readField(header, 'Branch');

  // Tasks live as `- <text>` lines under `### Tasks`.
  const tasks = extractListSection(body, 'Tasks');
  const files = extractListSection(body, 'Files Modified');

  const topicTask = pickTopicTask(tasks);
  const fileTopics = pickFileTopics(files);

  return {
    project: project && project !== 'unknown' ? project : null,
    branch: branch && branch !== 'unknown' ? branch : null,
    topicTask,
    fileTopics,
    taskCount: tasks.length,
    fileCount: files.length
  };
}

/**
 * Extract `- item` lines under a `### <name>` heading.
 * @param {string} body
 * @param {string} name
 * @returns {string[]}
 */
function extractListSection(body, name) {
  if (!body) return [];
  const re = new RegExp(`###\\s+${escapeRegExp(name)}\\s*\\n([\\s\\S]*?)(?=\\n###|\\n## |\\n<!--|$)`);
  const m = body.match(re);
  if (!m) return [];
  return m[1]
    .split('\n')
    .map(l => l.replace(/^[-*]\s*\[?[ x]?\]?\s*/, '').trim())
    .filter(Boolean);
}

/**
 * Strip XML/HTML-ish tags, command echoes, and comments from a captured user
 * message, returning the real human text. ECC sometimes prepends an
 * <ide_opened_file>…</ide_opened_file> block before the actual message, or
 * captures a slash-command echo — we want what a human actually typed.
 * @param {string} raw
 * @returns {string}
 */
function cleanMessage(raw) {
  if (!raw) return '';
  let t = raw;
  // Drop paired tag blocks and their inner content (ide_opened_file, task-
  // notification, command-message/name/args, system-reminder, etc.).
  t = t.replace(/<([a-z][\w-]*)\b[^>]*>[\s\S]*?<\/\1>/gi, ' ');
  // Drop HTML comments — terminated OR unterminated (the 200-char capture
  // often cuts a comment mid-stream, leaving a dangling "<!-- ...").
  t = t.replace(/<!--[\s\S]*?-->/g, ' ').replace(/<!--[\s\S]*$/g, ' ');
  // Drop remaining standalone/opening/dangling tags.
  t = t.replace(/<\/?[a-z][\w-]*\b[^>]*>?/gi, ' ');
  // Drop slash-command echoes anywhere (e.g. "/workspace.research", "invoke /workspace.plan").
  t = t.replace(/\/[a-z][\w.:-]*\b/gi, ' ');
  // Strip leading filler/ack clauses ("okay, sorry so ...", "well, ...").
  t = t.replace(/^\s*(okay|ok|well|so|hmm|sorry|alright|right|actually|hey|um|uh)\b[\s,]+/i, '');
  t = t.replace(/^\s*(okay|ok|well|so|hmm|sorry|alright|right|actually)\b[\s,]+/i, '');
  t = t.replace(/`+/g, '').replace(/\s+/g, ' ').trim();
  return t;
}

/**
 * Is this message a markdown/command-doc dump rather than a real instruction?
 * (e.g. a pasted "# Plan Command ... ## What This Command Does" block, or a
 * "Status: ... Next: ..." summary the model wrote back.)
 * @param {string} t cleaned message
 */
function isDocDump(t) {
  if (/^#{1,6}\s/.test(t)) return true;            // leads with a markdown heading
  if (/^Status:\s/i.test(t)) return true;          // status summary echo
  if (/\bThis command (invokes|does)\b/i.test(t)) return true;
  if (/^Caveat:\s/i.test(t)) return true;          // Claude Code resume preamble
  if (/^The messages below were generated/i.test(t)) return true;
  if (/^The user selected (the )?lines?\b/i.test(t)) return true; // ide_selection leak
  if (/^The user opened the file\b/i.test(t)) return true;        // ide_opened_file leak
  return false;
}

function isNoise(t) {
  if (!t || t.length < 6) return true;
  const lower = t.toLowerCase().replace(/[.!?]+$/, '').trim();
  if (NOISE_EXACT.has(lower)) return true;
  if (NOISE_PREFIXES.some(p => lower === p || lower.startsWith(p + ' '))) return true;
  if (isDocDump(t)) return true;
  return false;
}

/**
 * Choose the user task that best describes the session's work.
 * Scores candidates: actionable verbs win, questions lose, length is a mild
 * tiebreaker. Falls back to the first non-noise message, then the longest.
 * @param {string[]} tasks
 * @returns {string|null}
 */
function pickTopicTask(tasks) {
  const candidates = [];
  for (const raw of tasks) {
    const t = cleanMessage(raw);
    if (isNoise(t)) continue;
    let score = 0;
    if (ACTION_VERBS.test(t)) score += 10;
    if (/^(what|how|why|when|do you|does|can you|should)\b/i.test(t)) score -= 4; // vague question
    if (/\?$/.test(t)) score -= 2;
    score += Math.min(t.length, 80) / 40; // mild length preference, capped
    candidates.push({ t, score });
  }
  if (candidates.length === 0) {
    // Everything scored as noise. Take the longest cleaned message that isn't a
    // doc-dump/status echo; if none qualify, give up (title falls back to files).
    const cleaned = tasks
      .map(cleanMessage)
      .filter(t => !isNoise(t)) // isNoise already covers length + docdump + acks
      .sort((a, b) => b.length - a.length);
    return cleaned[0] || null;
  }
  candidates.sort((a, b) => b.score - a.score);
  return candidates[0].t;
}

/**
 * Derive up to two distinctive topic words from modified file paths.
 * Prefers project-meaningful basenames over generic ones (README, index...).
 * @param {string[]} files
 * @returns {string[]}
 */
function pickFileTopics(files) {
  const generic = new Set([
    'readme', 'index', 'main', 'package', 'config', 'mod', 'init', '__init__',
    'go', 'work', 'dockerfile', 'makefile', 'go.work', 'go.mod', 'gemfile',
    'cargo', 'setup', 'tsconfig', 'eslintrc', '.env', 'env'
  ]);
  const counts = new Map();
  for (const f of files) {
    // Skip Claude plan files — their names are random word-salad slugs, not topics.
    if (/\/\.claude\/plans\//.test(f) || /\/plans\/[a-z]+-[a-z]+-[a-z]+\.md$/.test(f)) continue;
    const base = f.split('/').pop().replace(/\.[^.]+$/, '').toLowerCase();
    if (!base || generic.has(base)) continue;
    if (/^stub-\d+$/.test(base)) continue;     // generated stub ids
    if (/^[a-f0-9]{8,}$/.test(base)) continue;  // hash-like names
    counts.set(base, (counts.get(base) || 0) + 1);
  }
  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 2)
    .map(([base]) => base);
}

/**
 * Condense a free-text task into a short topic phrase for the title.
 * @param {string} task
 * @returns {string}
 */
function condenseTopic(task) {
  if (!task) return '';
  let t = task
    .replace(/`+/g, '')
    .replace(/https?:\/\/\S+/g, '')
    .replace(/\s+/g, ' ')
    .trim();
  // Drop a leading polite/filler clause up to first comma if it's short.
  t = t.replace(/^(please|can you|could you|i want to|i'd like to|let's|lets|i think|maybe)\s+/i, '');
  const words = t.split(' ').slice(0, MAX_TOPIC_WORDS).join(' ');
  return words.replace(/[.,;:!?]+$/, '').trim();
}

/**
 * Build a human-readable title from a session's content.
 * Shape: "<project>: <topic>"  or just "<topic>" when no project.
 * @param {string} content
 * @returns {string}
 */
function generateTitle(content) {
  const sig = extractSignal(content);
  const topic = condenseTopic(sig.topicTask);

  let title;
  if (topic && sig.project) {
    title = `${sig.project}: ${topic}`;
  } else if (topic) {
    title = topic;
  } else if (sig.project && sig.fileTopics.length) {
    title = `${sig.project}: ${sig.fileTopics.join(' & ')}`;
  } else if (sig.project) {
    title = sig.project;
  } else if (sig.fileTopics.length) {
    title = sig.fileTopics.join(' & ');
  } else {
    title = null;
  }

  if (!title) return null;
  if (title.length > MAX_TITLE_LEN) {
    title = title.slice(0, MAX_TITLE_LEN - 1).replace(/\s+\S*$/, '') + '…';
  }
  return capitalizeFirst(title);
}

/**
 * Build a kebab-case slug usable as an alias key.
 * Shape: "<project>-<topic-words>", stopwords removed, deduped.
 * @param {string} content
 * @returns {string}
 */
function generateSlug(content) {
  const sig = extractSignal(content);
  const parts = [];
  if (sig.project) parts.push(sig.project);

  const topicSource = sig.topicTask || sig.fileTopics.join(' ');
  const topicWords = (topicSource || '')
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, ' ')
    .split(/[\s-]+/)
    .filter(w => w && !STOPWORDS.has(w))
    .slice(0, 4);

  parts.push(...topicWords);

  const seen = new Set();
  const slug = parts
    .map(p => p.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, ''))
    .filter(Boolean)
    .filter(p => (seen.has(p) ? false : seen.add(p)))
    .join('-')
    .slice(0, MAX_SLUG_LEN)
    .replace(/-+$/g, '');

  return slug || null;
}

/**
 * Stable fingerprint of the *topical* content (project + tasks + files),
 * NOT timestamps. Used to detect drift: if this changes, the title may be stale.
 * @param {string} content
 * @returns {string}
 */
function contentFingerprint(content) {
  const { body, header } = splitSession(content);
  const project = readField(header, 'Project') || '';
  const tasks = extractListSection(body, 'Tasks').join('');
  const files = extractListSection(body, 'Files Modified').join('');
  const basis = `${project}${tasks}${files}`;
  return crypto.createHash('sha1').update(basis).digest('hex').slice(0, 12);
}

/**
 * Is the current heading just the bare ECC default ("Session: <date>")?
 * @param {string} content
 * @returns {boolean}
 */
function hasDefaultTitleOnly(content) {
  const { headingText } = splitSession(content);
  if (!headingText) return true;
  return /^Session:\s*\d{4}-\d{2}-\d{2}$/.test(headingText.trim());
}

function capitalizeFirst(s) {
  if (!s) return s;
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

module.exports = {
  TITLE_FIELD,
  SLUG_FIELD,
  FINGERPRINT_FIELD,
  readField,
  splitSession,
  extractSignal,
  extractListSection,
  generateTitle,
  generateSlug,
  contentFingerprint,
  hasDefaultTitleOnly,
  escapeRegExp
};
