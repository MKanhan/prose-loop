# Tests

Smoke tests for `prose_loop.sh` and `scripts/audit-scan.sh`. There is no test framework — just shell commands you can run by hand and a fixture book.

## Fixture

`tests/fixtures/mini-book/` contains 3 short synthetic chapters in English on the topic of paper folding. The fixture is a small standalone "book project" with its own `CLAUDE.md` (telling prose-loop the book language and vision) and `chapters/` directory.

The fixture is synthetic — none of the content is from a real manuscript. Use it freely for testing and demos.

## Running smoke tests

You'll need `claude` CLI authenticated and `python3` available. The Anthropic calls cost money; pass `--model sonnet` to keep verification under ~$2.

### Setup the fixture as a git repo

`prose_loop.sh` requires a git repo to operate (it tags baselines and commits cycles). Initialize one inside the fixture before running:

```bash
cd tests/fixtures/mini-book
git init -q
git add CLAUDE.md chapters/
git commit -q -m "fixture: initial state"
cd -
```

### Smoke test: default rubric (EN keys)

```bash
cd tests/fixtures/mini-book
bash ../../../prose_loop.sh --dry-run --model sonnet
cat prose_scores/cycle_0_eval.json | python3 -m json.tool | head -30
```

Expected: 3 chapter entries with EN keys (`prose_quality`, `accessibility`, etc.), composite in [1, 10].

### Smoke test: PT-BR rubric (preserves v1.1.0 behavior)

```bash
cd tests/fixtures/mini-book
rm -rf prose_scores/
bash ../../../prose_loop.sh --dry-run --model sonnet --rubric ../../../rubrics/pt-br-nonfiction.json
cat prose_scores/cycle_0_eval.json | python3 -m json.tool | head -30
```

Expected: PT-BR keys (`qualidade_prosa`, `acessibilidade`, etc.). Composites should be within ~±0.5 of the default-rubric run on the same content.

### Smoke test: targeted chapter

```bash
cd tests/fixtures/mini-book
rm -rf prose_scores/
bash ../../../prose_loop.sh --dry-run --model sonnet --chapter cap_01.md
python3 -c "import json; d=json.load(open('prose_scores/cycle_0_eval.json')); print('chapters scored:', len(d['chapters']))"
```

Expected: `chapters scored: 1`.

### Smoke test: priority count

```bash
cd tests/fixtures/mini-book
rm -rf prose_scores/
bash ../../../prose_loop.sh --dry-run --model sonnet --priority-count 1
python3 -c "import json; d=json.load(open('prose_scores/cycle_0_eval.json')); print('priority:', d['global']['priority_chapters'])"
```

Expected: priority list of length 1.

### Audit scan

```bash
bash scripts/audit-scan.sh --self-test
bash scripts/audit-scan.sh
```

Both should exit 0.

## Cleaning up

The fixture's git repo and `prose_scores/` are not tracked by the main repo (covered by `.gitignore`). You can reset between runs with:

```bash
cd tests/fixtures/mini-book
rm -rf prose_scores/ .git/
```
