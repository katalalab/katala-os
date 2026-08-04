#!/usr/bin/env node
// Advisory safety-valve for destructive Bash — companion to claude-safety-valve.js.
// Wired as a PreToolUse(Bash) hook in ~/.claude/settings.json on every fleet node.
//
// WHY: the original safety-valve only inspects Edit|Write file paths and is blind
// to destructive shell commands. Under the fleet's bypassPermissions /
// danger-full-access posture, irreversible Bash (rm -rf, git reset --hard,
// git clean -fdx, DROP/TRUNCATE, dd, mkfs, force-push, Remove-Item -Recurse
// -Force) runs with no prompt and no surface. This closes that gap.
//
// NON-BLOCKING by design: never returns deny/continue:false, always exits 0, so
// it does not fight the high-autonomy posture. It only surfaces a systemMessage
// reminding the operator/agent that the Hard Rules require a backup + retention +
// restore path before destructive ops. The git pre-commit guard stays the hard
// (blocking) line at commit time.

const fs = require('fs');
const os = require('os');
const path = require('path');

const DESTRUCTIVE = [
  { re: /\brm\b(?=[^|;&\n]*\s-[a-z]*r)(?=[^|;&\n]*\s-[a-z]*f)/i,    why: 'rm -r -f(再帰的強制削除)' },
  { re: /\brm\b(?=[^|;&\n]*--recursive)(?=[^|;&\n]*(?:--force|\s-[a-z]*f))/i, why: 'rm --recursive --force' },
  { re: /\brm\b(?=[^|;&\n]*--force)(?=[^|;&\n]*(?:--recursive|\s-[a-z]*r))/i,  why: 'rm --force --recursive' },
  { re: /\bgit\s+reset\s+--hard\b/i,                                why: 'git reset --hard(作業ツリー破棄)' },
  { re: /\bgit\s+clean\s+-[a-z]*f/i,                                why: 'git clean -f(未追跡ファイル削除)' },
  { re: /\bgit\s+checkout\s+--\s+\./i,                              why: 'git checkout -- .(全変更破棄)' },
  { re: /\bgit\s+push\b[^\n]*(?:--force(?!-with-lease)|\s-f\b)/i,   why: 'git push --force(履歴上書き)' },
  { re: /\b(?:DROP|TRUNCATE)\s+(?:TABLE|DATABASE|SCHEMA)\b/i,       why: 'SQL DROP/TRUNCATE(データ破棄)' },
  { re: /\bdd\b[^\n]*\bof=\/dev\//i,                                why: 'dd of=/dev/...(ディスク上書き)' },
  { re: /\bmkfs\b/i,                                                why: 'mkfs(ファイルシステム作成=破壊)' },
  { re: />\s*\/dev\/(?:sd[a-z]|nvme\d|disk\d)/i,                    why: '生デバイスへの書き込み' },
  { re: /\bRemove-Item\b[^\n]*-Recurse[^\n]*-Force|\bRemove-Item\b[^\n]*-Force[^\n]*-Recurse/i, why: 'Remove-Item -Recurse -Force(再帰的強制削除)' },
  { re: /\b(?:rmdir|rd)\s+\/s\b/i,                                  why: 'rmdir /s(ディレクトリ再帰削除)' },
  { re: /\bformat\s+[a-z]:/i,                                       why: 'format ドライブ(初期化)' },
];

// --- State-marker guard ---
// WHY: validating a state marker with touch/rm destroyed its contents once,
// unrecoverably. When rm/touch/mv touches an operational signal (NEEDS_*, ENABLE
// flags, *.marker, latest.json and friends),
// rm/touch/mv が触れるときは、実行前に (1)既存確認 (2)内容を退避ファイルへ保存 のうえ
// 退避パス+内容抜粋を警告表示する。非ブロッキング(警告のみ)は本弁の設計思想どおり維持。
// 退避先 ~/.claude/marker-backups/ は最新40件保持・超過分を同処理内でprune(Hard Rules準拠)。
const MARKER_BASENAME = [
  { re: /^NEEDS_[A-Z0-9_]+/,      what: 'NEEDS_* 運用シグナル' },
  { re: /^ENABLE$/,               what: 'ENABLE 起動フラグ' },
  { re: /\.marker$/i,             what: '*.marker' },
  { re: /^latest\.(json|md)$/i,   what: 'latest.json/md(正準ポインタ)' },
];
const BACKUP_DIR = path.join(os.homedir(), '.claude', 'marker-backups');
const BACKUP_KEEP = 40;
const CONTENT_CAP = 64 * 1024;   // 退避ファイルへの読み込み上限
const EXCERPT_CAP = 500;         // systemMessage 内の内容抜粋上限

function basenameAny(p) {
  return String(p).split(/[\\/]/).pop() || '';
}

// rm/touch/mv セグメントの引数トークンからマーカーパターン一致を拾う。
// mv は移動元(消える)と移動先(上書きされ得る)の両方が対象なので全トークンを見る。
function markerTargets(cmd) {
  const out = [];
  for (const seg of String(cmd).split(/\|\||&&|;|\||\n/)) {
    const m = seg.match(/^\s*(?:sudo\s+)?(rm|touch|mv)\b([\s\S]*)$/);
    if (!m) continue;
    const tokens = m[2].match(/"[^"]*"|'[^']*'|\S+/g) || [];
    for (const t0 of tokens) {
      const t = t0.replace(/^["']|["']$/g, '');
      if (!t || t.startsWith('-')) continue;
      // glob文字はパターン照合用にプレースホルダへ置換(NEEDS_* → NEEDS_X が一致するように)
      const probe = basenameAny(t).replace(/[*?]/g, 'X');
      const hit = MARKER_BASENAME.find((p) => p.re.test(probe));
      if (hit) out.push({ verb: m[1], target: t, what: hit.what });
    }
  }
  return out;
}

function backupMarker(absPath) {
  fs.mkdirSync(BACKUP_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[-:]/g, '').replace(/\..+/, '').replace('T', '-');
  const safeName = basenameAny(absPath).replace(/[^A-Za-z0-9._-]/g, '_');
  let dest = path.join(BACKUP_DIR, `${stamp}-${safeName}`);
  // 同一秒内の同名退避を上書きしない(内容喪失防止が本弁の目的)
  for (let i = 1; fs.existsSync(dest); i++) dest = path.join(BACKUP_DIR, `${stamp}-${safeName}.${i}`);
  const fd = fs.openSync(absPath, 'r');
  let content;
  try {
    const buf = Buffer.alloc(CONTENT_CAP);
    const n = fs.readSync(fd, buf, 0, CONTENT_CAP, 0);
    content = buf.slice(0, n).toString('utf8');
  } finally {
    fs.closeSync(fd);
  }
  fs.writeFileSync(dest, content, 'utf8');
  const olds = fs.readdirSync(BACKUP_DIR).sort();
  while (olds.length > BACKUP_KEEP) fs.unlinkSync(path.join(BACKUP_DIR, olds.shift()));
  return { dest, content };
}

function markerWarnings(cmd, cwd) {
  const lines = [];
  const seen = new Set();
  for (const t of markerTargets(cmd)) {
    if (/[*?]/.test(t.target)) {
      lines.push(`🛡️ stateマーカー保護: ${t.verb} の glob「${t.target}」が ${t.what} に一致(展開先未解決)。実体を確認し退避してから実行してください。`);
      continue;
    }
    const abs = path.isAbsolute(t.target) ? t.target : path.join(cwd, t.target);
    if (seen.has(abs)) continue;
    seen.add(abs);
    let st;
    try { st = fs.statSync(abs); } catch { continue; }   // 既存確認: 無ければ新規作成等の通常運用なので沈黙
    if (st.isDirectory()) {
      lines.push(`🛡️ stateマーカー保護: ${t.verb} が既存の ${t.what} ディレクトリ ${abs} に触れます。内容確認+退避してから実行してください。`);
      continue;
    }
    try {
      const { dest, content } = backupMarker(abs);
      const excerpt = content.slice(0, EXCERPT_CAP) || '(空ファイル)';
      lines.push(`🛡️ stateマーカー保護: ${t.verb} が既存マーカー ${abs} に触れます。\n   内容を退避済み: ${dest}\n   --- 内容(先頭${EXCERPT_CAP}字) ---\n   ${excerpt}`);
    } catch (e) {
      lines.push(`🛡️ stateマーカー保護: ${t.verb} が既存マーカー ${abs} に触れますが退避に失敗(${e.message})。手動で内容確認+退避してから実行してください。`);
    }
  }
  return lines;
}

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { raw += c; });
process.stdin.on('end', () => {
  let cmd = '';
  let cwd = process.cwd();
  try {
    const j = JSON.parse(raw || '{}');
    cmd = (j.tool_input && j.tool_input.command) || '';
    if (j.cwd) cwd = j.cwd;
  } catch { /* advisory only — never throw */ }

  const msgs = [];
  const hit = cmd && DESTRUCTIVE.find((d) => d.re.test(cmd));
  if (hit) {
    msgs.push(`⚠️  ${hit.why} を実行しようとしています:\n   ${cmd.slice(0, 200)}\n   不可逆の可能性。Hard Rules はバックアップ(retention付き)+復元手順の事前宣言を要求します(このフックは警告のみ・ブロックしません)。`);
  }
  try {
    if (cmd) msgs.push(...markerWarnings(cmd, cwd));
  } catch { /* advisory only — never throw */ }

  if (msgs.length) {
    process.stdout.write(JSON.stringify({ systemMessage: msgs.join('\n') }));
  }
  process.exit(0);
});
