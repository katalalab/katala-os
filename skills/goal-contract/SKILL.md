---
name: goal-contract
description: Turn an open-ended or /goal objective into a bounded contract — interpretation, 3–5 verifiable completion criteria, and scope exclusions — announced in the first reply, then self-terminate when the criteria are met. Use whenever the operator gives a /goal, an outcome-only instruction ("〜しておいて", "ブラッシュアップして", "最高にして", "全部解消して"), or any task with no obvious finish line.
---

# goal-contract — bounded execution for open-ended goals

Prevents a common failure mode: open-ended goal sessions that run for dozens of turns, burning context on auto-compactions, until the operator has to interrupt and ask for completion criteria.

## When to use

- `/goal` で何かを依頼されたとき（内容を問わず毎回）
- 「環境をブラッシュアップして」「最高の設定にして」「全部進めて」「走り切って」など、終了条件が自明でない依頼
- WARN/エラーの全解消系（「全て解消して」— "全て"の母集団を先に固定する必要がある）

Do **not** use for:

- 単発の具体的コマンド実行や1ファイル修正（終了条件が自明）
- 質問への回答だけのターン

## Procedure

1. **解釈 (1 line).** Restate the goal concretely, naming referents（URL、PR番号、対象マシン、対象ディレクトリ）.
2. **完了条件 (3–5 checks).** Each must be verifiable by a real command or observable state — not "十分に改善した". Examples: 「`verify.sh` が PASS」「WARN 母集団 N 件のうち解消可能な M 件が 0 件」「PR #X のレビューコメント全件に対応コミットあり」.
3. **スコープ外 (1–2 lines).** What this session will NOT do（例: リモートノードへの書き込み、依存追加、baseline編集）.
4. **Announce the block, then run.** Do not wait for approval. The operator grants latitude by default; the contract exists so both sides know when it ends.
5. **Checkpoints.** Every major phase, ≤3 lines: 完了 / 進行中 / 残り + 完了条件 x/y.
6. **Terminate.** When all criteria pass (or remaining ones are blocked by something only the operator can decide), write the final report and END the goal. Do not invent new work. If genuinely useful follow-ups surfaced, list ≤3 as 次アクション候補 instead of doing them.

## Unbounded goals

「人生を最高に」「議論しながらブラッシュアップ」のような無限ゴールは、有限バッチに変換して宣言する:

> 解釈: 無限ゴールのため今回は有限バッチ化 — 影響の大きい改善 上位5件を実施。
> 完了条件: 5件それぞれに 適用+検証コマンド結果 が揃うこと。

Then recommend `/new` for the next batch — goal text is re-injected every turn, so one eternal session wastes context that fresh sessions don't.

## Report format (turn-final)

1. 結論（達成 x/y と一言）
2. 証拠（コマンド+結果、パス）
3. 検証済み / 未検証 の区別
4. 次アクション候補（≤3、実行はしない）
