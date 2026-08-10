#!/usr/bin/env node
// Advisory safety-valve for Claude Code — Anthropic playbook "Pattern B / Step 2"
// (How Anthropic teams use Claude Code, 2026-05). Cross-platform; wired as a
// PreToolUse(Edit|Write) hook in ~/.claude/settings.json on every fleet node.
//
// NON-BLOCKING by design: it never returns a deny/continue:false decision and
// always exits 0, so it does not fight the fleet's high-autonomy posture
// (bypassPermissions / danger-full-access). The git pre-commit drift guard stays
// the hard (blocking) line at commit time.
//
// Wired on BOTH tool events, because each output field reaches a different
// audience: `systemMessage` is shown to the operator only — the agent never sees
// it — and PreToolUse has no field that feeds the agent. So PreToolUse warns the
// operator ("本番ファイルを編集しようとしています。意図的ですか？", per the playbook),
// and PostToolUse hands the agent itself an `additionalContext` nudge right after
// the edit, so an unattended agent still gets the chance to reconsider.

const SENSITIVE = [
  { re: /(^|[\/\\])(prod|production|prd)([\/\\._-]|$)/i, why: '本番(prod/production)パス' },
  { re: /\.env($|\.)(?!example|template|sample)/i,       why: '.env(機密環境変数)' },
  { re: /(secret|credential)/i,                          why: 'secret/credential を含むパス' },
  { re: /\.(pem|key|p12|pfx)$/i,                          why: '秘密鍵/証明書ファイル' },
  { re: /(^|[\/\\])(id_rsa|id_ed25519|authorized_keys)($|[\/\\.])/i, why: 'SSH鍵' },
  { re: /(^|[\/\\])\.(aws|ssh|gnupg|kube)([\/\\])/i,      why: '機密ディレクトリ(.aws/.ssh/.gnupg/.kube)' },
  { re: /(^|[\/\\])\.(npmrc|netrc|pgpass|pypirc)$/i,      why: 'トークンを含む設定ファイル' },
  { re: /[\/\\]\.codex[\/\\]auth\.json$/i,               why: 'Codex 認証ファイル' },
];

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { raw += c; });
process.stdin.on('end', () => {
  let p = '';
  let event = '';
  try {
    const j = JSON.parse(raw || '{}');
    event = j.hook_event_name || '';
    const ti = j.tool_input || {};
    p = ti.file_path || ti.path || ti.notebook_path || '';
  } catch { /* advisory only — never throw */ }

  const hit = p && SENSITIVE.find((s) => s.re.test(p));
  if (hit) {
    if (event === 'PostToolUse') {
      process.stdout.write(JSON.stringify({
        hookSpecificOutput: {
          hookEventName: 'PostToolUse',
          additionalContext: `直前の編集は ${hit.why} に触れています: ${p}\n意図的でなければ差し戻しを検討してください。意図的なら、その理由を作業記録に1行残して続行してください。`,
        },
      }));
    } else {
      process.stdout.write(JSON.stringify({
        systemMessage: `⚠️  ${hit.why} を編集しようとしています: ${p}\n   意図的か確認してください(このフックは警告のみ・ブロックしません)。`,
      }));
    }
  }
  process.exit(0);
});
