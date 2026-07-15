#!/usr/bin/env node
/**
 * titler.js — CLI + Stop-hook entry for the session title/key overlay.
 *
 * Modes:
 *   node titler.js hook              Read Stop-hook JSON on stdin; title the
 *                                    current session file if its content has
 *                                    drifted (heuristic, free, no LLM). Exits 0
 *                                    always so it can never block the session.
 *
 *   node titler.js retitle [target] Re-title sessions on demand (heuristic).
 *       target = a slug/short-id/filename, or "all", or omitted (= latest).
 *       --force   re-title even if content fingerprint is unchanged
 *       --no-alias don't create/refresh the slug alias
 *       --llm     print an LLM-titling instruction block for Claude to act on
 *                 (does NOT call any API itself — keeps the hook path free)
 *
 *   node titler.js backfill <target>  Title only if currently untitled
 *                                     (lazy "backfill on access"). target as above.
 *
 *   node titler.js list               Print sessions with title/slug/date (JSON
 *                                     with --json) for the /sessions skill.
 *
 * Self-contained: Node core + ./lib only. Independent of the ECC plugin so a
 * plugin update can't break it.
 */

'use strict';

const fs = require('fs');
const path = require('path');

const store = require('./lib/session-store');
const T = require('./lib/session-title');

function readStdin() {
  try {
    return fs.readFileSync(0, 'utf8');
  } catch {
    return '';
  }
}

/**
 * Resolve a target token to absolute session file path(s).
 * token: undefined/"latest" -> newest file; "all" -> every file; otherwise
 * match by slug alias, short-id substring, or filename.
 * @param {string|undefined} token
 * @returns {string[]}
 */
function resolveTargets(token) {
  const files = store.listSessionFiles();
  if (files.length === 0) return [];

  if (!token || token === 'latest') {
    const newest = files
      .map(f => ({ f, m: safeMtime(f) }))
      .sort((a, b) => b.m - a.m)[0];
    return newest ? [newest.f] : [];
  }
  if (token === 'all') return files;

  // Slug alias?
  const aliases = store.loadAliases().aliases;
  if (aliases[token]) {
    const match = files.find(f => path.basename(f) === aliases[token].sessionPath);
    if (match) return [match];
  }

  // Filename or short-id substring.
  const byName = files.filter(f => {
    const base = path.basename(f);
    return base === token || base === `${token}.tmp` || base.includes(token);
  });
  return byName;
}

function safeMtime(f) {
  try { return fs.statSync(f).mtimeMs; } catch { return 0; }
}

/* ------------------------------- hook mode ------------------------------- */

function runHook() {
  // Stop-hook stdin carries { transcript_path, ... }. We don't need it — ECC's
  // session-end hook has already written the .tmp file by the time async Stop
  // hooks run. We title the newest session file on content drift.
  readStdin(); // drain stdin so the pipe closes cleanly
  const targets = resolveTargets('latest');
  const state = store.loadState();
  for (const f of targets) {
    try {
      const key = path.basename(f);
      const prev = state.sessions[key];
      // Protect manually-set (LLM/`set`) titles: only auto-retitle a manual
      // title if the content has actually drifted since it was set.
      if (prev && prev.manual) {
        const content = fs.readFileSync(f, 'utf8');
        if (T.contentFingerprint(content) === prev.fingerprint) continue;
      }
      // force:false => only rewrites when fingerprint changed (drift). alias:true
      // keeps the slug key fresh as the title evolves.
      store.titleSessionFile(f, { force: false, alias: true });
    } catch {
      // never block the session
    }
  }
  process.exit(0);
}

/* ----------------------------- command modes ----------------------------- */

function runRetitle(args) {
  const force = args.includes('--force');
  const noAlias = args.includes('--no-alias');
  const llm = args.includes('--llm');
  const token = args.find(a => !a.startsWith('--'));

  const targets = resolveTargets(token);
  if (targets.length === 0) {
    console.log(`No matching session for "${token || 'latest'}".`);
    process.exit(1);
  }

  if (llm) {
    printLlmInstructions(targets);
    process.exit(0);
  }

  const results = [];
  for (const f of targets) {
    results.push(store.titleSessionFile(f, { force, alias: !noAlias }));
  }
  printResults(results);
  process.exit(0);
}

function runBackfill(args) {
  const token = args.find(a => !a.startsWith('--'));
  const noAlias = args.includes('--no-alias');
  const targets = resolveTargets(token);
  const results = [];
  for (const f of targets) {
    let content;
    try { content = fs.readFileSync(f, 'utf8'); } catch { continue; }
    // Only act if still the bare default (untitled). Otherwise leave alone.
    if (T.hasDefaultTitleOnly(content)) {
      results.push(store.titleSessionFile(f, { force: true, alias: !noAlias }));
    }
  }
  if (results.length === 0) {
    console.log('Already titled (or no signal); nothing to backfill.');
  } else {
    printResults(results);
  }
  process.exit(0);
}

function runList(args) {
  const asJson = args.includes('--json');
  const limit = parseInt((args.find(a => a.startsWith('--limit=')) || '').split('=')[1], 10) || 30;
  const files = store.listSessionFiles()
    .map(f => ({ f, m: safeMtime(f) }))
    .sort((a, b) => b.m - a.m)
    .slice(0, limit);

  const rows = files.map(({ f }) => {
    let content = '';
    try { content = fs.readFileSync(f, 'utf8'); } catch { /* ignore */ }
    const header = T.splitSession(content).header;
    return {
      file: path.basename(f),
      title: T.readField(header, T.TITLE_FIELD) || T.splitSession(content).headingText || '(untitled)',
      slug: T.readField(header, T.SLUG_FIELD) || '',
      date: T.readField(header, 'Date') || '',
      project: T.readField(header, 'Project') || ''
    };
  });

  if (asJson) {
    console.log(JSON.stringify(rows, null, 2));
    process.exit(0);
  }

  console.log('Title                                            Slug                         Date');
  console.log('─'.repeat(96));
  for (const r of rows) {
    console.log(
      r.title.slice(0, 48).padEnd(49) +
      r.slug.slice(0, 28).padEnd(29) +
      r.date
    );
  }
  process.exit(0);
}

function printResults(results) {
  for (const r of results) {
    if (!r.ok) {
      console.log(`✗ ${path.basename(r.filePath)} — ${r.error}`);
    } else if (!r.title) {
      console.log(`· ${path.basename(r.filePath)} — ${r.note || 'no signal'}`);
    } else {
      const changed = r.changed ? '✓' : '=';
      const alias = r.aliased ? `  [alias: ${r.slug}]` : '';
      console.log(`${changed} ${r.title}${alias}`);
    }
  }
}

/**
 * Emit a block instructing the *calling Claude* to produce a high-quality
 * title/slug and apply it via `titler.js set`. No API call happens here.
 */
function printLlmInstructions(targets) {
  console.log('LLM_RETITLE_REQUEST');
  console.log('For each session below, read it, then produce a concise title');
  console.log('(<= 72 chars, "<project>: <what was done>") and a kebab slug,');
  console.log('and apply with:');
  console.log('  node ' + __filename + ' set <filename> --title "<title>" --slug "<slug>"');
  console.log('');
  for (const f of targets) {
    console.log(`SESSION_FILE: ${f}`);
  }
}

function runSet(args) {
  const token = args.find(a => !a.startsWith('--'));
  const title = flagValue(args, '--title');
  const slug = flagValue(args, '--slug');
  const noAlias = args.includes('--no-alias');
  if (!token || !title) {
    console.log('Usage: titler.js set <filename> --title "<title>" [--slug "<slug>"] [--no-alias]');
    process.exit(1);
  }
  const targets = resolveTargets(token);
  if (targets.length === 0) {
    console.log(`No matching session for "${token}".`);
    process.exit(1);
  }
  const f = targets[0];
  let content;
  try { content = fs.readFileSync(f, 'utf8'); } catch (e) {
    console.log(`✗ read failed: ${e.message}`); process.exit(1);
  }
  const finalSlug = slug || T.generateSlug(content);
  const fp = T.contentFingerprint(content);
  const next = store.renderTitleIntoContent(content, title, finalSlug, fp);

  if (!store.atomicWrite(f, next)) { console.log('✗ write failed'); process.exit(1); }

  // Record as a MANUAL title so the heuristic hook won't downgrade it unless
  // the session content drifts.
  const state = store.loadState();
  state.sessions[path.basename(f)] = {
    fingerprint: fp, title, slug: finalSlug || null, manual: true, updatedAt: new Date().toISOString()
  };
  store.saveState(state);

  let aliased = false;
  if (!noAlias && finalSlug) {
    aliased = store.registerAlias(finalSlug, path.basename(f), title).ok;
  }
  console.log(`✓ ${title}${aliased ? `  [alias: ${finalSlug}]` : ''}`);
  process.exit(0);
}

function flagValue(args, flag) {
  const i = args.indexOf(flag);
  if (i !== -1 && args[i + 1]) return args[i + 1];
  const eq = args.find(a => a.startsWith(`${flag}=`));
  return eq ? eq.slice(flag.length + 1) : null;
}

/* --------------------------------- main --------------------------------- */

const [, , cmd, ...rest] = process.argv;

switch (cmd) {
  case 'hook': runHook(); break;
  case 'retitle': runRetitle(rest); break;
  case 'backfill': runBackfill(rest); break;
  case 'set': runSet(rest); break;
  case 'list': runList(rest); break;
  default:
    console.log('Usage: titler.js <hook|retitle|backfill|set|list> [target] [flags]');
    console.log('  retitle [target] [--force] [--no-alias] [--llm]');
    console.log('  backfill [target] [--no-alias]   (titles only if untitled)');
    console.log('  set <target> --title "..." [--slug "..."]');
    console.log('  list [--json] [--limit=N]');
    process.exit(cmd ? 1 : 0);
}
