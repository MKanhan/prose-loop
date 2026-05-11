# examples

## `sample-run/`

Output from a single baseline evaluation of the bundled fixture (`tests/fixtures/mini-book/` — 3 synthetic English chapters on origami geometry).

- `cycle_0_eval.json` — full evaluator output. JSON shape: per-chapter scores on 7 dimensions, weighted composite, critique text, strengths, priority improvements; global aggregate; `priority_chapters` list. All keys EN (default rubric).
- `score-table.txt` — `print_score_table` output, ANSI escapes stripped. Same view you get at the end of a `--dry-run` in the terminal.

The run that produced these was `--dry-run --model sonnet` against the fixture. Composite came in at 6.13 — middle of the range the evaluator targets ("good, publishable with revisions"). Reasonable for a 1,800-word synthetic mini-book that was never edited.

### Reproduce

```bash
cd tests/fixtures/mini-book
git init -q && git add . && git commit -q -m "fixture"
bash ../../prose_loop.sh --dry-run --model sonnet
```

The JSON will land in `tests/fixtures/mini-book/prose_scores/cycle_0_eval.json`. The score table prints to stdout. Your numbers will differ a bit — evaluator output fluctuates ±0.3 between runs on identical content.

## What's not here

- **Full-cycle output** (eval → rewrite → compare → post-eval). A real cycle costs ~4× a baseline; not bundled. Run prose-loop on the fixture without `--dry-run` to see one.
- **Real-book output.** Bundling a real manuscript would make this repo a privacy problem and a maintenance burden. The fixture is enough to demonstrate shape.
