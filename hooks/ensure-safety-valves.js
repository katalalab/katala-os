#!/usr/bin/env node
// Self-heal for the PreToolUse safety valves (companion to apply-safety-valve.js
// and apply-bash-safety-valve.js).
//
// The valves are advisory and non-blocking, so anything that rewrites
// ~/.claude/settings.json can drop them with no visible symptom — Orca did
// exactly that on gpu-node-a between 2026-07-18 and 2026-07-25 and nothing
// noticed for eight days. This checks first and only re-runs the idempotent
// installers when a valve is actually missing, so a healthy node is never
// rewritten (each installer run would otherwise churn a backup).
//
// Exit 0 = healthy or repaired. Exit 1 = could not repair; the non-zero
// LastTaskResult is itself the escalation path, because KatalaAgentOpsHealth
// reports failing Katala* scheduled tasks every morning. No retry loop lives
// here on purpose.
//
// Refuses to act on an unparseable settings.json (the installers would crash
// mid-flight). Before repairing it takes its own pre-repair snapshot and rolls
// back to that on any bad outcome — the installers' own backups cannot be used
// for this, because when both valves are repaired the newest of those is the
// half-repaired state, not the state we started from.
// Snapshot retention (declared): keeps the 3 newest
// settings.json.bak-*-before-valve-heal and prunes older ones each run.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const home = os.homedir();
const settingsDir = path.join(home, '.claude');
const settingsPath = path.join(settingsDir, 'settings.json');
const hookDir = path.join(home, 'work', 'agent-context', 'hooks');

const VALVES = [
  { script: 'claude-safety-valve.js', installer: 'apply-safety-valve.js', label: 'edit' },
  { script: 'claude-bash-safety-valve.js', installer: 'apply-bash-safety-valve.js', label: 'bash' },
];

function report(obj, code) {
  console.log(JSON.stringify(Object.assign({ host: os.hostname() }, obj)));
  process.exit(code);
}

function readSettings() {
  return JSON.parse(fs.readFileSync(settingsPath, 'utf8'));
}

// Match the installer's own identity check (hook args ending in the script
// name) rather than a substring of the serialized hook block.
function missingValves(settings) {
  const entries = (settings.hooks || {}).PreToolUse || [];
  const installed = new Set();
  for (const entry of entries) {
    for (const hook of entry.hooks || []) {
      for (const arg of hook.args || []) {
        const base = String(arg).split(/[\\/]/).pop();
        installed.add(base);
      }
    }
  }
  return VALVES.filter((v) => !installed.has(v.script)).map((v) => v.label);
}

if (!fs.existsSync(settingsPath)) report({ action: 'no-settings-file', path: settingsPath }, 1);

let before;
try {
  before = readSettings();
} catch (e) {
  // Repairing on top of invalid JSON would abort each installer after it has
  // already taken a backup; leave the file for a human and fail loudly.
  report({ action: 'settings-unparseable', error: String(e.message) }, 1);
}

const wasMissing = missingValves(before);
if (wasMissing.length === 0) report({ action: 'ok', missing: [] }, 0);

const keysBefore = Object.keys(before).sort().join(',');

const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+/, '').replace('T', '-');
const snapshot = path.join(settingsDir, `settings.json.bak-${stamp}-before-valve-heal`);
fs.copyFileSync(settingsPath, snapshot);
const snaps = fs.readdirSync(settingsDir)
  .filter((f) => /^settings\.json\.bak-.*-before-valve-heal$/.test(f))
  .sort();
while (snaps.length > 3) fs.unlinkSync(path.join(settingsDir, snaps.shift()));

function rollback(action, extra) {
  fs.copyFileSync(snapshot, settingsPath);
  report(Object.assign({ action, rolledBackFrom: path.basename(snapshot) }, extra), 1);
}

const installerCodes = {};
for (const valve of VALVES.filter((v) => wasMissing.includes(v.label))) {
  const run = spawnSync(process.execPath, [path.join(hookDir, valve.installer)], { stdio: 'ignore' });
  installerCodes[valve.installer] = run.status === null ? `signal:${run.signal}` : run.status;
}

let after;
try {
  after = readSettings();
} catch (e) {
  rollback('repair-corrupted-settings', { installerCodes, error: String(e.message) });
}

// A repair must only add a hook entry. Anything else means the file was
// rewritten under us (concurrent editor) — go back to the pre-repair snapshot.
if (Object.keys(after).sort().join(',') !== keysBefore) {
  rollback('repair-key-drift', { installerCodes });
}

// Partial repair is deliberately KEPT, not rolled back: the two valves are
// independent PreToolUse entries, so one installed valve protects more than
// zero, and exit 1 puts the rest on the next morning's failing-jobs report.
// Codex review 2026-07-26 argued for rolling back here — dissent recorded in
// work/agent-context/NEEDS_REVIEW.md, pending operator ratification.
const stillMissing = missingValves(after);
report({
  action: stillMissing.length === 0 ? 'repaired' : 'repair-failed-partial-kept',
  wasMissing,
  stillMissing,
  installerCodes,
  snapshot: path.basename(snapshot),
}, stillMissing.length === 0 ? 0 : 1);
