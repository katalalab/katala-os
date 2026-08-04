#!/usr/bin/env node
// grok PreToolUse → Claude形式安全弁アダプタ(advisory・fail-open)。
// 使い方: node grok-valve-adapter.js <claude-valve-script.js>
//
// WHY: grokのhook入力はcamelCase(toolName/toolInput)、Claude弁はsnake_case
// (tool_name/tool_input)を読む。検知ロジックをSSOT(claude-*-valve.js)に
// 一本化したまま grok から使うため、形だけ変換して既存弁を子プロセス実行する。
// 弁の systemMessage は stderr に流す(grokスクロールバックの注釈に載る)。
// 常に {"decision":"allow"} を返す非ブロッキング設計 — フリートの
// 高自律ポスチャを崩さない。grok の Edit/Write 相当(search_replace)の入力
// フィールド名は toolInput.file_path/path を候補順に写像する。
const { spawnSync } = require('child_process');

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => { raw += c; });
process.stdin.on('end', () => {
  let msg = '';
  try {
    const j = JSON.parse(raw || '{}');
    const ti = j.toolInput || {};
    const claudeShape = JSON.stringify({
      tool_name: j.toolName || '',
      tool_input: {
        command: ti.command,
        file_path: ti.file_path || ti.path || ti.target_file,
        path: ti.path,
      },
      cwd: j.cwd || process.cwd(),
    });
    const r = spawnSync(process.execPath, [process.argv[2]], {
      input: claudeShape, encoding: 'utf8', timeout: 4000,
    });
    const out = (r.stdout || '').trim();
    if (out) {
      try { msg = JSON.parse(out).systemMessage || ''; } catch { msg = out; }
    }
  } catch { /* advisory only — never throw */ }
  if (msg) process.stderr.write(msg + '\n');
  process.stdout.write(JSON.stringify({ decision: 'allow' }));
  process.exit(0);
});
