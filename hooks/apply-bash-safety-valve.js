#!/usr/bin/env node
// Idempotent installer for the destructive-Bash advisory safety-valve hook.
// Companion to apply-safety-valve.js. Run ONCE per fleet node:
//   node ~/work/agent-context/hooks/apply-bash-safety-valve.js
//
// Same design rationale as apply-safety-valve.js: process.execPath pins the node
// binary per-OS, paths derive from os.homedir() (Windows vs macOS), backs up
// settings.json first with a retention prune, idempotent (refresh not dupe).
// Touches ONLY its own PreToolUse(Bash) entry — other hooks are left intact.

const fs = require('fs');
const os = require('os');
const path = require('path');

const home = os.homedir();
const nodeBin = process.execPath;
const hookScript = path.join(home, 'work', 'agent-context', 'hooks', 'claude-bash-safety-valve.js');
const settingsDir = path.join(home, '.claude');
const settingsPath = path.join(settingsDir, 'settings.json');

const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+/, '').replace('T', '-');

function isOurEntry(entry) {
  return Array.isArray(entry.hooks) && entry.hooks.some(
    (h) => Array.isArray(h.args) && h.args.some((a) => String(a).endsWith('claude-bash-safety-valve.js'))
  );
}

if (!fs.existsSync(settingsDir)) fs.mkdirSync(settingsDir, { recursive: true });

let settings = {};
if (fs.existsSync(settingsPath)) {
  settings = JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
  const backup = path.join(settingsDir, `settings.json.bak-${stamp}-before-bash-valve-hook`);
  fs.copyFileSync(settingsPath, backup);
  const olds = fs.readdirSync(settingsDir)
    .filter((f) => /^settings\.json\.bak-.*-before-bash-valve-hook$/.test(f))
    .sort();
  while (olds.length > 3) fs.unlinkSync(path.join(settingsDir, olds.shift()));
}

settings.hooks = settings.hooks || {};
settings.hooks.PreToolUse = settings.hooks.PreToolUse || [];

const entry = {
  matcher: 'Bash',
  hooks: [{ type: 'command', command: nodeBin, args: [hookScript], timeout: 10, statusMessage: 'bash-safety-valve' }],
};

const existing = settings.hooks.PreToolUse.find(isOurEntry);
let action;
if (existing) {
  const idx = settings.hooks.PreToolUse.indexOf(existing);
  settings.hooks.PreToolUse[idx] = entry;
  action = 'updated (idempotent refresh)';
} else {
  settings.hooks.PreToolUse.push(entry);
  action = 'added';
}

fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2) + '\n', 'utf8');

console.log(JSON.stringify({
  host: os.hostname(),
  platform: process.platform,
  action,
  nodeBin,
  hookScript,
  hookScriptExists: fs.existsSync(hookScript),
  settingsPath,
  preToolUseCount: settings.hooks.PreToolUse.length,
  settingsValid: true,
}, null, 2));
