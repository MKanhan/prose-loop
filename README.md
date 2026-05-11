# prose-loop

Iterative LLM-driven prose improvement loop for books.

`prose-loop` treats your manuscript like agent-loopable code: it scores every chapter on a configurable rubric, rewrites the weakest ones, compares before/after, and only keeps changes that a separate critic pass judges as improvements. Git is the safety net — rejected cycles revert cleanly; accepted ones land as commits you can read, blame, or undo.

It's a single Bash script wrapping the Claude CLI. No Python virtualenv to manage, no framework to learn.

## How it works

1. **Tag baseline.** Every run starts by tagging the current git state so you can diff or revert.
2. **Evaluate.** All chapters scored on 7 dimensions (relevance, originality, prose quality, balance, accessibility, commercial value, accuracy). Weighted composite per chapter and globally. Output is structured JSON.
3. **Rewrite weakest.** The N chapters with the lowest composites (default 3) get rewritten — same voice, same arguments, sharper prose.
4. **Compare.** A separate critic pass reads BEFORE and AFTER snapshots and votes BETTER / SAME / WORSE per chapter. ACCEPT vs. REJECT is determined by this vote, not by the score moving.
5. **Commit or revert.** ACCEPT → `git commit` with the cycle's deltas. REJECT → `git checkout --` to wipe the rewrite. Repeat until improvement stalls or `--max-cycles` is hit.

## Install

```bash
git clone https://github.com/<your-account>/prose-loop.git
```

Requirements:

- [`claude` CLI](https://docs.claude.com/en/docs/claude-code/overview) installed and authenticated.
- `python3` (macOS default; any 3.7+).
- `git` initialized in your book project.

No prose-loop install step. The script lives wherever you cloned it.

## Quick start

```bash
cd /path/to/your-book/         # must be a git repo with chapter .md files
~/path/to/prose-loop/prose_loop.sh --dry-run --model sonnet
```

What `--dry-run` does: runs one evaluation pass, writes scores to `prose_scores/`, prints the table below, exits. No rewrites. Use this to feel out cost and calibrate the rubric before committing to a real loop.

```text
═══════════════════════════════════════════════════════════════════════════
 Prose Loop — Score Evolution
═══════════════════════════════════════════════════════════════════════════
 Cycle   Composite Relev   Orig    Prose   Bal     Acess   Comm    Acc
──────────────────────────────────────────────────────────────────────────
 0       6.13    5.5     5.5     6.3     6.0     7.2     5.7     6.3
═══════════════════════════════════════════════════════════════════════════

 Per-chapter scores (latest evaluation):
───────────────────────────────────────────────────────────────────────────
  cap_02.md                     5.75 █████░░░░░ ◄
  cap_01.md                     6.01 ██████░░░░ ◄
  cap_03.md                     6.62 ██████░░░░ ◄
  ◄ = priority for next rewrite | BETTER/SAME/WORSE = last comparison
═══════════════════════════════════════════════════════════════════════════
```

(Sample from the bundled `tests/fixtures/mini-book/` — see `examples/sample-run/` for the full JSON output that produced it.)

When you're ready for real cycles, drop `--dry-run`:

```bash
~/path/to/prose-loop/prose_loop.sh --max-cycles 3 --model opus
```

## Configuration

Common flags (see `--help` for the full list):

| Flag | Default | Notes |
|---|---|---|
| `--dry-run` | off | Eval only, no rewrites. Always do this first. |
| `--model MODEL` | `opus` | Pass `sonnet` for iteration; `opus` for finals. |
| `--max-cycles N` | 5 | Hard ceiling. Loop usually stops earlier when comparator REJECTs. |
| `--chapter FILE` | all | Repeatable or comma-separated. Iterate on one weak chapter without moving files. |
| `--priority-count N` | 3 | How many chapters to rewrite per cycle. |
| `--rubric PATH` | `rubrics/default.json` | Use a different scoring rubric. |
| `--delta FLOAT` | 0.2 | Min composite gain to keep changes (used as a secondary check). |

## Custom rubrics

The default rubric (7 dimensions, weights summing to 7.7) is tuned for commercial nonfiction. To use a different one — or to write your own — see [`rubrics/README.md`](rubrics/README.md).

The rubric keys are EN identifiers regardless of book language. The critique text the evaluator writes is auto-localized: it picks up `lang:` from your book project's `CLAUDE.md` and responds in that language. You don't need a localized rubric — write your book in any language, get critique in that same language.

## Privacy

prose-loop is a thin client. Every evaluation and rewrite call sends to Anthropic:

- The full text of the chapters being scored / rewritten.
- The `Vision` and `Guidelines` sections of your book project's `CLAUDE.md` (if present).
- The evaluator instructions (templated from the rubric).

Raw Claude responses are logged locally to `prose_scores/raw_cycle_*_*.txt` for debugging. These contain everything the model said, including any reasoning about your prose. They never leave your machine.

For manuscripts with NDAs, embargo dates, or non-public material, review Anthropic's [API privacy terms](https://www.anthropic.com/legal/privacy) before pointing prose-loop at them.

## Cost

prose-loop spends Anthropic API credits on every cycle. Order of magnitude:

- **Per cycle**, ignoring baseline, prose-loop makes ~3 calls (rewrite + comparator + post-eval). The baseline run adds one more.
- **Token cost** scales with manuscript length. The bundled `mini-book` fixture (3 chapters, ~1,800 words) is < $0.50 for a baseline eval on Sonnet. Linear scaling: a 50,000-word manuscript is ~$10–15 baseline on Sonnet, ~5× more on Opus.
- **Strategies for keeping cost down**:
  - `--dry-run --model sonnet` for every exploratory pass.
  - `--chapter cap_07.md` to iterate on a single weak chapter instead of the whole book.
  - `--priority-count 1` to make each cycle rewrite only one chapter.
  - Reserve `--model opus` for the final pass when the rubric is dialed in.

Anthropic publishes [current pricing](https://www.anthropic.com/pricing). Estimates above use 2026 pricing and will age.

## Limitations

- **The evaluator is an LLM.** Scores fluctuate ±0.3 between runs on identical content. Treat composites as ordinal (who's worst), not interval (by how much).
- **Requires git.** The script tags baselines and commits accepted cycles. Without git in your book project, it refuses to start.
- **English UI.** Flags, prompts, and help text are English. The *critique itself* is written in your book's language (auto-detected from `lang:` in your book's `CLAUDE.md`).
- **Single-pass per cycle.** No reflection, no chain-of-thought scaffolding beyond what the rubric instructions induce. If you want fancier loops, fork.
- **No streaming.** Each cycle blocks until Claude finishes. Plan for minutes, not seconds.

## License

[MIT](LICENSE). Use, modify, redistribute. Attribution appreciated but not required.

## Contact / acknowledgments

Built by Marcelo Kanhan — [kanhan.com.br](https://kanhan.com.br), [build portfolio](https://kanhan.com.br/en/build/), [Substack](https://substack.kanhan.com). Inspired by autoresearch-style agent loops in code, applied sideways to prose. <!-- audit:allow operator portfolio + substack -->

Issues, ideas, and PRs welcome.
