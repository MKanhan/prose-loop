# Changelog

All notable changes to this project are documented here. Format loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.2.0] - 2026-05-11

### Added
- `--rubric PATH` flag for external scoring rubric JSONs.
- `rubrics/default.json` — 7 EN-keyed dimensions, weight total 7.7.
- `rubrics/README.md` — schema doc and instructions for custom rubrics.
- `--chapter FILE` flag, repeatable or comma-separated, to target specific chapters without moving files.
- `--priority-count N` flag to tune how many chapters get rewritten per cycle (default 3).
- `scripts/audit-scan.sh` — PII / private-reference scanner for pre-publication audits.
- `tests/fixtures/mini-book/` — 3 synthetic English chapters used for smoke tests.
- `tests/README.md` — manual smoke test walkthrough.
- `examples/sample-run/` — reference output (JSON + score table) from running prose-loop on the bundled fixture.

### Changed
- Scoring dimension keys are now stable EN identifiers (`relevance_currency`, `prose_quality`, …) regardless of book language. The *critique text* the evaluator writes is localized to the book's language, picked up from `lang:` in the book project's `CLAUDE.md`. This separates the machine-readable schema (EN) from the human-readable output (book language).
- Composite divisor is now `sum(weights)` instead of hardcoded `7.7`. Behavior identical when weights sum to 7.7 (true for the default rubric). Custom rubrics with different weight totals now produce composites that remain in [1, 10].
- Eval / rewrite / comparator prompts now construct their dimension list from the active rubric instead of hardcoding it. Same for the score table header.
- VERSION bumped 1.1.0 → 1.2.0.

### Fixed
- `--help` example paths no longer leak the author's local workspace layout.
- `print_score_table` per-chapter section no longer aborts silently under `set -eo pipefail` when no comparator JSON has been produced yet (e.g. on `--dry-run`).
- Audit scanner exempts LICENSE-class files (LICENSE, NOTICE, AUTHORS, COPYING) from operator-name matching to avoid false positives on copyright holders.

## [1.1.0] - prior to public release

Internal version. Initial behavior:

- 7 PT-BR scoring dimensions hardcoded in the script.
- Composite divisor hardcoded at 7.7.
- ACCEPT/REJECT gate driven by a comparator pass that votes BETTER/SAME/WORSE per chapter, not by raw score deltas.
- Snapshots of pre-rewrite chapters preserved to `prose_scores/snapshots/` for direct BEFORE/AFTER comparison.
- Git tag at baseline; per-cycle commits on ACCEPT; `git checkout --` to revert on REJECT.

Not publicly released.
