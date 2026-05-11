# prose-loop

## Meta
type: software
lang: en
status: shipped
public: https://github.com/MKanhan/prose-loop
version: 1.2.0 (released 2026-05-11)

## Vision
Iterative prose improvement loop for books. Inspired by agent loops from code (autoresearch-style), applied to prose: evaluate → critique → rewrite → re-evaluate → keep or discard. Uses the Claude CLI as the engine, git for safety, and structured scoring for objectivity.

Independent, project-agnostic. Works for any book, any language. Auto-detects language and context from the target project's CLAUDE.md.

## Usage

```bash
# From any book project directory
cd ~/path/to/your-book/
~/path/to/prose-loop/prose_loop.sh [options]

# Or from Claude Code
bash ~/path/to/prose-loop/prose_loop.sh --max-cycles 5
```

### Parameters
| Flag | Default | Description |
|---|---|---|
| `--max-cycles N` | 5 | Maximum improvement cycles |
| `--chapters-dir DIR` | auto | Chapter directory (`capitulos/` or `chapters/`) |
| `--chapter FILE` | all | Target specific chapter(s). Repeatable or comma-separated |
| `--priority-count N` | 3 | Chapters to rewrite per cycle |
| `--model MODEL` | opus | Claude model for evaluation and rewriting |
| `--delta FLOAT` | 0.3 | Minimum score improvement to keep changes |
| `--rubric PATH` | rubrics/default.json | Scoring rubric JSON (see rubrics/README.md) |
| `--dry-run` | off | Evaluate only, no rewriting |

### How it works
1. Tags current git state as baseline
2. Evaluates all chapters on 7 dimensions (1-10 scale), outputs JSON
3. Rewrites the 3-4 weakest chapters based on critique
4. Re-evaluates. If improved >= delta: commit. If not: revert and stop.
5. Repeats up to max-cycles.

### Output
Creates `prose_scores/` in the book project with:
- `cycle_N_eval.json` — structured scores + critique per cycle
- `raw_cycle_N_*.txt` — raw Claude output (debug)
- `prose_loop.log` — machine-readable execution log

### Requirements
- `claude` CLI installed and authenticated
- `python3` (macOS default)
- `git` initialized in the book project

## Scoring dimensions (default rubric)
| Dimension | Weight | Key |
|---|---|---|
| Relevance & currency | 1.0 | `relevance_currency` |
| Originality of analogies/cases | 1.0 | `originality` |
| Prose quality | 1.5 | `prose_quality` |
| Chapter balance | 0.8 | `balance` |
| Accessibility | 1.2 | `accessibility` |
| Commercial value | 1.0 | `commercial_value` |
| Accuracy & references | 1.2 | `accuracy_references` |

Composite = sum(score × weight) / sum(weights). Default total weight: 7.7. Keys are stable EN identifiers; critique text is auto-localized to the book's `lang:` from its `CLAUDE.md`. Override the rubric via `--rubric PATH` — see `rubrics/README.md` for schema.

## Roadmap

Sprint de open-source publication concluída em 2026-05-11 (v1.2.0). Specs locais em `.local/specs/` (não-tracked — planejamento interno).

### Done
- Spec 01 — PII audit + scanner (`scripts/audit-scan.sh`).
- Spec 02 — git init, MIT LICENSE, .gitignore.
- Spec 03 — Rubric externalization (EN default, `--rubric` flag).
- Spec 04 — `--chapter`, `--priority-count`.
- Spec 05 — README, CHANGELOG, examples/sample-run/.
- Spec 06 — shellcheck-clean, CI, tag v1.2.0, push to github.com/MKanhan/prose-loop, release, entry em kanhan.com.br/en/build/. <!-- audit:allow operator portfolio site -->

### Backlog (post-v1.2.0; pull when demand surfaces)
- Model routing (Sonnet para eval, Opus para rewrite) — cost optimization.
- HTML report generation a partir dos JSONs em `prose_scores/`.
- Asciinema cast para `examples/`.
- Multi-OS matrix no CI (macOS + Linux).
- Pacote homebrew / asdf — só se demanda externa aparecer.
- Dependabot, branch protection.
