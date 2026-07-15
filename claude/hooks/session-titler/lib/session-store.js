/**
 * session-store.js — File-level read/write for session titles and slug aliases.
 *
 * Self-contained (Node core only). Owns:
 *   - rewriting a session file's heading and header Title/Slug/
 *     TitleFingerprint fields
 *   - reading/writing ~/.claude/session-aliases.json (same schema ECC uses)
 *
 * All writes are atomic (temp file + rename) and idempotent.
 */

'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

const T = require('./session-title');

function homeDir() {
  return process.env.CLAUDE_HOME || os.homedir();
}
function claudeDir() {
  return path.join(homeDir(), '.claude');
}
function sessionsDir() {
  return path.join(claudeDir(), 'sessions');
}
function aliasesPath() {
  return path.join(claudeDir(), 'session-aliases.json');
}
function statePath() {
  // Drift/manual state the overlay owns. Kept OUT of the session file because
  // ECC's session-end Stop hook rebuilds the header and would strip in-file
  // fields. The visible `# heading` + `**Title:**` survive ECC; this sidecar
  // is the source of truth for "has the content drifted since we titled it"
  // and "was this title set manually (don't downgrade to heuristic)".
  return path.join(claudeDir(), 'session-titler-state.json');
}

function loadState() {
  const p = statePath();
  if (!fs.existsSync(p)) return { version: '1.0', sessions: {} };
  try {
    const d = JSON.parse(fs.readFileSync(p, 'utf8'));
    if (!d.sessions || typeof d.sessions !== 'object') return { version: '1.0', sessions: {} };
    return d;
  } catch {
    return { version: '1.0', sessions: {} };
  }
}

function saveState(state) {
  return atomicWrite(statePath(), JSON.stringify(state, null, 2));
}

/**
 * Atomic write via temp file + rename.
 * @param {string} filePath
 * @param {string} content
 * @returns {boolean}
 */
function atomicWrite(filePath, content) {
  const tmp = `${filePath}.titler.tmp`;
  try {
    fs.writeFileSync(tmp, content, 'utf8');
    fs.renameSync(tmp, filePath);
    return true;
  } catch (err) {
    try { if (fs.existsSync(tmp)) fs.unlinkSync(tmp); } catch { /* best-effort */ }
    return false;
  }
}

/**
 * Insert or replace a `**Label:** value` line within the header region only
 * (before the `---` separator). Inserted after Worktree/last known field if new.
 * @param {string} content
 * @param {string} label
 * @param {string} value
 * @returns {string}
 */
function upsertHeaderField(content, label, value) {
  const sepIdx = content.indexOf('\n---\n');
  if (sepIdx === -1) return content; // malformed; leave untouched
  let header = content.slice(0, sepIdx);
  const rest = content.slice(sepIdx);

  const re = new RegExp(`^\\*\\*${T.escapeRegExp(label)}:\\*\\*\\s*.*$`, 'm');
  const line = `**${label}:** ${value}`;

  if (re.test(header)) {
    header = header.replace(re, line);
  } else {
    // Insert after the last **Field:** line in the header (keeps block tidy).
    const lines = header.split('\n');
    let lastFieldIdx = -1;
    for (let i = 0; i < lines.length; i++) {
      if (/^\*\*[^*]+:\*\*/.test(lines[i])) lastFieldIdx = i;
    }
    if (lastFieldIdx === -1) {
      lines.push(line);
    } else {
      lines.splice(lastFieldIdx + 1, 0, line);
    }
    header = lines.join('\n');
  }
  return header + rest;
}

/**
 * Replace the `# ...` heading text.
 * @param {string} content
 * @param {string} newHeadingText
 * @returns {string}
 */
function replaceHeading(content, newHeadingText) {
  if (/^#\s+.+$/m.test(content)) {
    return content.replace(/^#\s+.+$/m, `# ${newHeadingText}`);
  }
  // No heading at all — prepend one.
  return `# ${newHeadingText}\n${content}`;
}

/**
 * Render a title/slug/fingerprint into a session file's content (in memory).
 * Pure: no drift logic here (the caller decides whether to apply). The in-file
 * fields are best-effort visibility — the sidecar state is authoritative.
 * @param {string} content
 * @param {string} title
 * @param {string|null} slug
 * @param {string} fingerprint
 * @returns {string}
 */
function renderTitleIntoContent(content, title, slug, fingerprint) {
  let next = content;
  next = replaceHeading(next, title); // heading becomes the descriptive title
  next = upsertHeaderField(next, T.TITLE_FIELD, title);
  if (slug) next = upsertHeaderField(next, T.SLUG_FIELD, slug);
  next = upsertHeaderField(next, T.FINGERPRINT_FIELD, fingerprint);
  return next;
}

/**
 * Heuristically title a single session file on disk.
 *
 * Drift logic (sidecar-backed):
 *   - If the content fingerprint is unchanged since we last titled it and not
 *     forced → no-op.
 *   - If the title was set manually (LLM/`set`) and content hasn't drifted →
 *     no-op (don't downgrade a good title to a heuristic one).
 *   - If content drifted (or forced, or never titled) → regenerate.
 *
 * @param {string} filePath absolute path to a *-session.tmp file
 * @param {object} [opts] { force, alias } alias=true also registers slug alias
 * @returns {object} result { ok, filePath, title, slug, changed, aliased, error }
 */
function titleSessionFile(filePath, opts = {}) {
  let content;
  try {
    content = fs.readFileSync(filePath, 'utf8');
  } catch (err) {
    return { ok: false, filePath, error: `read failed: ${err.message}` };
  }

  const key = path.basename(filePath);
  const fingerprint = T.contentFingerprint(content);
  const state = loadState();
  const prev = state.sessions[key];

  // No drift since last title and not forced → leave it alone.
  if (!opts.force && prev && prev.fingerprint === fingerprint) {
    return { ok: true, filePath, title: prev.title, slug: prev.slug, changed: false, aliased: false };
  }

  const title = T.generateTitle(content);
  const slug = T.generateSlug(content);
  if (!title) {
    return { ok: true, filePath, title: null, slug: null, changed: false, aliased: false, note: 'no signal to title' };
  }

  const nextContent = renderTitleIntoContent(content, title, slug, fingerprint);
  const changed = nextContent !== content;
  if (changed && !atomicWrite(filePath, nextContent)) {
    return { ok: false, filePath, error: 'write failed' };
  }

  // Persist drift state (heuristic title → manual:false).
  state.sessions[key] = { fingerprint, title, slug: slug || null, manual: false, updatedAt: new Date().toISOString() };
  saveState(state);

  let aliased = false;
  if (opts.alias && slug) {
    aliased = registerAlias(slug, key, title).ok;
  }

  return { ok: true, filePath, title, slug, changed, aliased };
}

/* ---------------------------- alias storage ---------------------------- */

const ALIAS_VERSION = '1.0';

function loadAliases() {
  const p = aliasesPath();
  if (!fs.existsSync(p)) {
    return { version: ALIAS_VERSION, aliases: {}, metadata: { totalCount: 0, lastUpdated: new Date().toISOString() } };
  }
  try {
    const data = JSON.parse(fs.readFileSync(p, 'utf8'));
    if (!data.aliases || typeof data.aliases !== 'object') {
      return { version: ALIAS_VERSION, aliases: {}, metadata: { totalCount: 0, lastUpdated: new Date().toISOString() } };
    }
    if (!data.version) data.version = ALIAS_VERSION;
    return data;
  } catch {
    return { version: ALIAS_VERSION, aliases: {}, metadata: { totalCount: 0, lastUpdated: new Date().toISOString() } };
  }
}

function saveAliases(data) {
  data.metadata = {
    totalCount: Object.keys(data.aliases).length,
    lastUpdated: new Date().toISOString()
  };
  return atomicWrite(aliasesPath(), JSON.stringify(data, null, 2));
}

/**
 * Register (or refresh) a slug alias pointing at a session filename.
 * Schema matches ECC's session-aliases.js so /sessions can resolve it.
 * Slug collisions across different sessions get a numeric suffix.
 * @param {string} slug
 * @param {string} sessionFilename basename, e.g. "2026-04-08-abc-session.tmp"
 * @param {string|null} title
 * @returns {object} { ok, alias }
 */
function registerAlias(slug, sessionFilename, title = null) {
  if (!slug || !/^[a-zA-Z0-9_-]+$/.test(slug)) {
    return { ok: false, error: 'invalid slug' };
  }
  const reserved = new Set(['list', 'help', 'remove', 'delete', 'create', 'set']);
  if (reserved.has(slug.toLowerCase())) slug = `s-${slug}`;

  const data = loadAliases();

  // If this slug already maps to this same session, just refresh title/time.
  const existing = data.aliases[slug];
  if (existing && existing.sessionPath === sessionFilename) {
    existing.title = title || existing.title || null;
    existing.updatedAt = new Date().toISOString();
    return saveAliases(data) ? { ok: true, alias: slug } : { ok: false, error: 'save failed' };
  }

  // Collision with a *different* session — suffix until unique.
  let finalSlug = slug;
  if (existing && existing.sessionPath !== sessionFilename) {
    let n = 2;
    while (data.aliases[`${slug}-${n}`] && data.aliases[`${slug}-${n}`].sessionPath !== sessionFilename) n++;
    finalSlug = `${slug}-${n}`;
  }

  const now = new Date().toISOString();
  const prev = data.aliases[finalSlug];
  data.aliases[finalSlug] = {
    sessionPath: sessionFilename,
    createdAt: prev ? prev.createdAt : now,
    updatedAt: now,
    title: title || null
  };

  return saveAliases(data) ? { ok: true, alias: finalSlug } : { ok: false, error: 'save failed' };
}

/**
 * List all *-session.tmp files in the sessions dir (absolute paths).
 * @returns {string[]}
 */
function listSessionFiles() {
  const dir = sessionsDir();
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir)
    .filter(f => f.endsWith('-session.tmp'))
    .map(f => path.join(dir, f));
}

module.exports = {
  homeDir,
  claudeDir,
  sessionsDir,
  aliasesPath,
  atomicWrite,
  upsertHeaderField,
  replaceHeading,
  renderTitleIntoContent,
  titleSessionFile,
  statePath,
  loadState,
  saveState,
  loadAliases,
  saveAliases,
  registerAlias,
  listSessionFiles
};
