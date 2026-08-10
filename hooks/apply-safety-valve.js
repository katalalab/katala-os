#!/usr/bin/env node
// Idempotent installer for the Claude Code advisory safety-valve hook
// (Anthropic playbook Pattern B / Step 2). Run ONCE per fleet node:
//   node ~/work/agent-context/hooks/apply-safety-valve.js
//
// Why a Node installer instead of editing settings.json by hand: it uses
// process.execPath as the hook's node binary (so the exact, resolvable node is
// pinned per-OS — no PATH assumption), derives every path from os.homedir()
// (Windows C:\… vs macOS /Users/… handled automatically), backs up first with a
// retention prune, and is idempotent (re-running refreshes rather than dupes).

const fs = require('fs');
const os = require('os');
const path = require('path');

const home = os.homedir();
const nodeBin = process.execPath;
const hookScript = path.join(home, 'work', 'agent-context', 'hooks', 'claude-safety-valve.js');
const settingsDir = path.join(home, '.claude');
const settingsPath = path.join(settingsDir, 'settings.json');

const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+/, '').replace('T', '-');

function isOurEntry(entry) {
  return Array.isArray(entry.hooks) && entry.hooks.some(
    (h) => Array.isArray(h.args) && h.args.some((a) => String(a).endsWith('claude-safety-valve.js'))
  );
}

if (!fs.existsSync(settingsDir)) fs.mkdirSync(settingsDir, { recursive: true });

let settings = {};
if (fs.existsSync(settingsPath)) {
  settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
  // Backup + retention (keep 3 newest of this prefix).
  const backup = path.join(settingsDir, `settings.json.bak-${stamp}-before-playbook-hook`);
  fs.copyFileSync(settingsPath, backup);
  const olds = fs.readdirSync(settingsDir)
    .filter((f) => /^settings\.json\.bak-.*-before-playbook-hook$/.test(f))
    .sort();
  while (olds.length > 3) fs.unlinkSync(path.join(settingsDir, olds.shift()));
}

settings.hooks = settings.hooks || {};

const entry = {
  matcher: 'Edit|Write|NotebookEdit',
  hooks: [{ type: 'command', command: nodeBin, args: [hookScript], timeout: 10, statusMessage: 'safety-valve' }],
};

// Both events, one script: PreToolUse warns the operator (systemMessage is
// user-facing only), PostToolUse feeds the agent itself (additionalContext).
const actions = {};
for (const event of ['PreToolUse', 'PostToolUse']) {
  const list = (settings.hooks[event] = settings.hooks[event] || []);
  const existing = list.find(isOurEntry);
  if (existing) {
    list[list.indexOf(existing)] = entry;
    actions[event] = 'updated (idempotent refresh)';
  } else {
    list.push(entry);
    actions[event] = 'added';
  }
}

fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n', 'utf8');

console.log(JSON.stringify({
  host: os.hostname(),
  platform: process.platform,
  actions,
  nodeBin,
  hookScript,
  hookScriptExists: fs.existsSync(hookScript),
  settingsPath,
  preToolUseCount: settings.hooks.PreToolUse.length,
  postToolUseCount: settings.hooks.PostToolUse.length,
  settingsValid: true,
}, null, 2));
