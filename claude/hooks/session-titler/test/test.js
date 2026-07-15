#!/usr/bin/env node
/* Minimal test suite for session-titler. Run: node test/test.js */
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const T = require('../lib/session-title');

let pass = 0, fail = 0;
function test(name, fn) {
  try { fn(); pass++; console.log(`  ✓ ${name}`); }
  catch (e) { fail++; console.log(`  ✗ ${name}\n    ${e.message}`); }
}

function session(fields, tasks = [], files = []) {
  const header = [
    `# Session: ${fields.date || '2026-01-01'}`,
    `**Date:** ${fields.date || '2026-01-01'}`,
    `**Started:** 00:00`,
    `**Last Updated:** 00:00`,
    `**Project:** ${fields.project || 'unknown'}`,
    `**Branch:** ${fields.branch || 'main'}`,
    `**Worktree:** {{ .chezmoi.homeDir }}/${fields.project || 'x'}`,
    ''
  ].join('\n');
  let body = '<!-- ECC:SUMMARY:START -->\n## Session Summary\n\n### Tasks\n';
  for (const t of tasks) body += `- ${t}\n`;
  if (files.length) { body += '\n### Files Modified\n'; for (const f of files) body += `- ${f}\n`; }
  body += '\n<!-- ECC:SUMMARY:END -->\n';
  return `${header}\n---\n${body}`;
}

console.log('session-title:');

test('clean strips ide_opened_file block, keeps trailing text', () => {
  const c = T.splitSession; // touch import
  assert.ok(c);
  const msg = '<ide_opened_file>The user opened the file foo.py in the IDE. This may or may not be related.</ide_opened_file> add rate limiting to the gateway';
  const title = T.generateTitle(session({ project: 'gw' }, [msg]));
  assert.ok(/rate limiting/i.test(title), `got: ${title}`);
  assert.ok(!/ide_opened_file/i.test(title));
});

test('strips dangling html comment (truncated capture)', () => {
  const msg = '<!-- COST CONTROL: No extended thinking for search agents. Exten';
  const title = T.generateTitle(session({ project: 'research' }, [msg, 'commit']));
  assert.ok(!/COST CONTROL/.test(title || ''), `got: ${title}`);
});

test('skips noise acks (done/commit/proceed)', () => {
  const title = T.generateTitle(session({ project: 'p' }, ['done', 'commit', 'proceed', 'refactor the auth middleware']));
  assert.ok(/refactor/i.test(title), `got: ${title}`);
});

test('action verb beats vague question', () => {
  const title = T.generateTitle(session({ project: 'p' }, ['what do you think of my repos?', 'migrate the database to postgres']));
  assert.ok(/migrate/i.test(title), `got: ${title}`);
});

test('falls back to file topics when all tasks are noise', () => {
  const title = T.generateTitle(session({ project: 'pga' }, ['done', 'commit'], [
    '{{ .chezmoi.homeDir }}/pga/middleware/ratelimit.go', '{{ .chezmoi.homeDir }}/pga/auth/apikey.go'
  ]));
  assert.ok(/ratelimit|apikey/i.test(title), `got: ${title}`);
});

test('ignores .claude/plans random slug files', () => {
  const title = T.generateTitle(session({ project: 'pga' }, ['done'], [
    '{{ .chezmoi.homeDir }}/.claude/plans/snazzy-singing-lantern.md', '{{ .chezmoi.homeDir }}/pga/webhook.go'
  ]));
  assert.ok(!/snazzy|singing|lantern/i.test(title || ''), `got: ${title}`);
});

test('slug is kebab, stopwords removed', () => {
  const slug = T.generateSlug(session({ project: 'gw' }, ['add rate limiting to the gateway']));
  assert.ok(/^[a-z0-9-]+$/.test(slug), `got: ${slug}`);
  assert.ok(slug.startsWith('gw-'), `got: ${slug}`);
  assert.ok(!/-to-|-the-/.test(slug), `stopwords leaked: ${slug}`);
});

test('fingerprint stable across timestamp-only changes', () => {
  const a = session({ project: 'p', date: '2026-01-01' }, ['build the thing']);
  const b = a.replace('**Last Updated:** 00:00', '**Last Updated:** 23:59');
  assert.strictEqual(T.contentFingerprint(a), T.contentFingerprint(b));
});

test('fingerprint changes when tasks change', () => {
  const a = session({ project: 'p' }, ['build the thing']);
  const b = session({ project: 'p' }, ['build the thing', 'now add tests']);
  assert.notStrictEqual(T.contentFingerprint(a), T.contentFingerprint(b));
});

test('hasDefaultTitleOnly true for bare date heading', () => {
  assert.strictEqual(T.hasDefaultTitleOnly(session({ date: '2026-01-01' }, ['x'])), true);
});

test('title length capped at 72', () => {
  const long = 'implement an extremely long and detailed feature with many many words that exceeds the limit easily for sure';
  const title = T.generateTitle(session({ project: 'proj' }, [long]));
  assert.ok(title.length <= 72, `len=${title.length}: ${title}`);
});

// ---- store integration (real disk, temp HOME) ----
const store = require('../lib/session-store');
console.log('session-store:');

test('titleSessionFile writes title + records state + alias', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'titler-'));
  const sdir = path.join(tmp, '.claude', 'sessions');
  fs.mkdirSync(sdir, { recursive: true });
  const file = path.join(sdir, '2026-01-01-demo-session.tmp');
  fs.writeFileSync(file, session({ project: 'demo', date: '2026-01-01' }, ['add a login form']));
  const old = process.env.CLAUDE_HOME; process.env.CLAUDE_HOME = tmp;
  try {
    const r = store.titleSessionFile(file, { force: false, alias: true });
    assert.ok(r.ok && r.title && /login/i.test(r.title), JSON.stringify(r));
    assert.ok(r.aliased, 'should create alias');
    const content = fs.readFileSync(file, 'utf8');
    assert.ok(/^# demo:/m.test(content) || /^# Demo:/m.test(content), 'heading rewritten');
    const state = JSON.parse(fs.readFileSync(path.join(tmp, '.claude', 'session-titler-state.json'), 'utf8'));
    assert.ok(state.sessions['2026-01-01-demo-session.tmp'], 'state recorded');
    // second run = no-op (no drift)
    const r2 = store.titleSessionFile(file, { force: false, alias: true });
    assert.strictEqual(r2.changed, false, 'second run should be no-op');
  } finally {
    if (old === undefined) delete process.env.CLAUDE_HOME; else process.env.CLAUDE_HOME = old;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

test('ECC header-rebuild resilience: no-op when content unchanged', () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'titler-'));
  const sdir = path.join(tmp, '.claude', 'sessions');
  fs.mkdirSync(sdir, { recursive: true });
  const file = path.join(sdir, '2026-01-02-demo-session.tmp');
  fs.writeFileSync(file, session({ project: 'demo', date: '2026-01-02' }, ['build the dashboard']));
  const old = process.env.CLAUDE_HOME; process.env.CLAUDE_HOME = tmp;
  try {
    store.titleSessionFile(file, { force: false, alias: true });
    // Simulate ECC stripping in-file Title/Slug/Fingerprint but keeping heading.
    let c = fs.readFileSync(file, 'utf8');
    c = c.split('\n').filter(l => !/^\*\*(Title|Slug|TitleFingerprint):/.test(l)).join('\n');
    fs.writeFileSync(file, c);
    const r = store.titleSessionFile(file, { force: false, alias: true });
    assert.strictEqual(r.changed, false, 'sidecar fp should make this a no-op despite stripped fields');
  } finally {
    if (old === undefined) delete process.env.CLAUDE_HOME; else process.env.CLAUDE_HOME = old;
    fs.rmSync(tmp, { recursive: true, force: true });
  }
});

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
