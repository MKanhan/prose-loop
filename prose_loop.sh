#!/usr/bin/env bash
set -euo pipefail

# Allow nested Claude CLI invocations (when called from Claude Code)
unset CLAUDECODE 2>/dev/null || true

# ─────────────────────────────────────────────────────────
# prose_loop.sh — Iterative prose improvement loop for books
# Uses Claude CLI to evaluate, critique, and rewrite chapters.
# Project-agnostic.
# ─────────────────────────────────────────────────────────

VERSION="1.2.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
MAX_CYCLES=5
CHAPTERS_DIR=""
MODEL="opus"
DELTA_MIN="0.2"
DRY_RUN=false
RUBRIC_PATH=""
CHAPTER_FILTER=()
PRIORITY_COUNT=3

# Derived at runtime
PROJECT_DIR="$PWD"
SCORES_DIR="$PROJECT_DIR/prose_scores"
LOG_FILE=""

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# Book context (populated by detect_book_context)
BOOK_LANG=""
BOOK_VISION=""
BOOK_GUIDELINES=""

# ─── Helpers ──────────────────────────────────────────────

info()  { echo -e "${CYAN}▸${NC} $*"; }
ok()    { echo -e "${GREEN}✓${NC} $*"; }
warn()  { echo -e "${YELLOW}!${NC} $*"; }
err()   { echo -e "${RED}✗${NC} $*" >&2; }

usage() {
  cat <<EOF
${BOLD}prose_loop${NC} v$VERSION — Iterative prose improvement loop

${BOLD}Usage:${NC} prose_loop.sh [options]
  Run from a book project root (git repo with chapter .md files).

${BOLD}Options:${NC}
  --max-cycles N      Max improvement cycles (default: $MAX_CYCLES)
  --chapters-dir DIR  Chapter directory (default: auto-detect)
  --chapter FILE      Target specific chapter(s). Repeatable; also
                      accepts comma-separated list. Default: all .md.
  --priority-count N  Chapters to rewrite per cycle (default: $PRIORITY_COUNT)
  --model MODEL       Claude model (default: $MODEL)
  --delta FLOAT       Min score improvement to keep (default: $DELTA_MIN)
  --rubric PATH       Scoring rubric JSON (default: rubrics/default.json)
  --dry-run           Evaluate only, no rewriting
  --help              Show this help

${BOLD}Example:${NC}
  cd ~/path/to/your-book/
  ~/path/to/prose-loop/prose_loop.sh --max-cycles 3
EOF
  exit 0
}

# ─── Argument parsing ────────────────────────────────────

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --max-cycles)  MAX_CYCLES="$2"; shift 2 ;;
      --chapters-dir) CHAPTERS_DIR="$2"; shift 2 ;;
      --chapter)
        local items
        IFS=',' read -ra items <<< "$2"
        for item in "${items[@]}"; do
          CHAPTER_FILTER+=("$item")
        done
        shift 2 ;;
      --priority-count) PRIORITY_COUNT="$2"; shift 2 ;;
      --model)       MODEL="$2"; shift 2 ;;
      --delta)       DELTA_MIN="$2"; shift 2 ;;
      --rubric)      RUBRIC_PATH="$2"; shift 2 ;;
      --dry-run)     DRY_RUN=true; shift ;;
      --help|-h)     usage ;;
      *) err "Unknown option: $1"; usage ;;
    esac
  done
}

# ─── Rubric ──────────────────────────────────────────────

resolve_rubric_path() {
  if [[ -z "$RUBRIC_PATH" ]]; then
    RUBRIC_PATH="$SCRIPT_DIR/rubrics/default.json"
  fi
  if [[ ! -f "$RUBRIC_PATH" ]]; then
    err "Rubric not found: $RUBRIC_PATH"
    exit 2
  fi
  if ! python3 -c "import json; json.load(open('$RUBRIC_PATH'))" 2>/dev/null; then
    err "Rubric is not valid JSON: $RUBRIC_PATH"
    exit 2
  fi
  if ! python3 - "$RUBRIC_PATH" <<'PYEOF'
import json, sys
r = json.load(open(sys.argv[1]))
assert 'dimensions' in r and isinstance(r['dimensions'], list) and len(r['dimensions']) >= 1, "missing or empty 'dimensions'"
required = {'key', 'label', 'short', 'weight', 'description'}
for d in r['dimensions']:
    missing = required - d.keys()
    assert not missing, f"dimension {d.get('key', '?')} missing fields: {missing}"
    assert isinstance(d['weight'], (int, float)) and d['weight'] > 0, f"dimension {d['key']} has non-positive weight"
PYEOF
  then
    err "Rubric schema invalid: $RUBRIC_PATH"
    exit 2
  fi
  info "Rubric: ${BOLD}$(basename "$RUBRIC_PATH")${NC} ($(python3 -c "import json;r=json.load(open('$RUBRIC_PATH'));print(len(r['dimensions']),'dims, total weight',sum(d['weight'] for d in r['dimensions']))"))"
}

# ─── Dependency checks ───────────────────────────────────

check_dependencies() {
  local missing=0
  for cmd in claude python3 git; do
    if ! command -v "$cmd" &>/dev/null; then
      err "Required: $cmd not found"
      missing=$((missing + 1))
    fi
  done
  if ! git rev-parse --git-dir &>/dev/null 2>&1; then
    err "Not a git repository. Run from a book project root."
    missing=$((missing + 1))
  fi
  [[ $missing -gt 0 ]] && exit 1

  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    warn "Working tree has uncommitted changes. Consider committing first."
  fi
}

# ─── Chapter discovery ───────────────────────────────────

detect_chapters_dir() {
  if [[ -n "$CHAPTERS_DIR" ]]; then
    [[ -d "$CHAPTERS_DIR" ]] || { err "Directory not found: $CHAPTERS_DIR"; exit 1; }
    return
  fi
  if [[ -d "$PROJECT_DIR/capitulos" ]]; then
    CHAPTERS_DIR="capitulos"
  elif [[ -d "$PROJECT_DIR/chapters" ]]; then
    CHAPTERS_DIR="chapters"
  else
    err "No chapters directory found. Use --chapters-dir to specify."
    exit 1
  fi
  info "Chapters directory: ${BOLD}$CHAPTERS_DIR/${NC}"
}

list_chapter_files() {
  if [[ ${#CHAPTER_FILTER[@]} -eq 0 ]]; then
    find "$PROJECT_DIR/$CHAPTERS_DIR" -maxdepth 1 -name '*.md' | sort
  else
    for f in "${CHAPTER_FILTER[@]}"; do
      local path="$PROJECT_DIR/$CHAPTERS_DIR/$f"
      if [[ ! -f "$path" ]]; then
        err "Chapter file not found: $f (looked in $CHAPTERS_DIR/)"
        exit 1
      fi
      echo "$path"
    done | sort
  fi
}

# ─── Book context ────────────────────────────────────────

detect_book_context() {
  local claude_md="$PROJECT_DIR/CLAUDE.md"
  if [[ ! -f "$claude_md" ]]; then
    warn "No CLAUDE.md found. Running without book context."
    BOOK_LANG="pt-BR"
    return
  fi

  BOOK_LANG=$(grep -m1 '^lang:' "$claude_md" 2>/dev/null | sed 's/^lang: *//' || echo "pt-BR")
  BOOK_VISION=$(sed -n '/^## Vision/,/^## /{ /^## Vision/d; /^## /d; p; }' "$claude_md" 2>/dev/null | head -5 || echo "")
  BOOK_GUIDELINES=$(sed -n '/^## Guidelines/,/^## /{ /^## Guidelines/d; /^## /d; p; }' "$claude_md" 2>/dev/null | head -5 || echo "")

  info "Language: ${BOLD}$BOOK_LANG${NC}"
}

# ─── Setup ────────────────────────────────────────────────

setup_scores_dir() {
  mkdir -p "$SCORES_DIR"
  LOG_FILE="$SCORES_DIR/prose_loop.log"
}

create_baseline_tag() {
  local tag="prose_baseline_$(date +%Y%m%d_%H%M%S)"
  git tag "$tag" 2>/dev/null || true
  ok "Baseline tagged: $tag"
}

# ─── JSON extraction ─────────────────────────────────────

extract_json() {
  local output="$1"
  local target_file="$2"

  python3 << 'PYEOF' - "$output" "$target_file"
import sys, json

text = sys.argv[1]
target = sys.argv[2]

start_marker = 'EVAL_JSON_START'
end_marker = 'EVAL_JSON_END'

start = text.find(start_marker)
end = text.find(end_marker)

if start == -1 or end == -1:
    sys.exit(1)

json_str = text[start + len(start_marker):end].strip()
data = json.loads(json_str)
with open(target, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

composite = data.get('global', {}).get('composite', -1)
print(f"{composite:.2f}")
PYEOF
}

extract_comparison() {
  local output="$1"
  local target_file="$2"

  python3 << 'PYEOF' - "$output" "$target_file"
import sys, json

text = sys.argv[1]
target = sys.argv[2]

start_marker = 'COMPARE_JSON_START'
end_marker = 'COMPARE_JSON_END'

start = text.find(start_marker)
end = text.find(end_marker)

if start == -1 or end == -1:
    sys.exit(1)

json_str = text[start + len(start_marker):end].strip()
data = json.loads(json_str)
with open(target, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

# Sanity check: trust comparator unless clearly wrong
verdicts = [ch['verdict'] for ch in data['chapters']]
comparator_says = data['overall_verdict']
worse_count = verdicts.count('WORSE')

if comparator_says == 'ACCEPT' and worse_count <= len(verdicts) // 2:
    result = 'ACCEPT'
elif comparator_says == 'REJECT':
    result = 'REJECT'
else:
    result = 'REJECT'  # sanity override

better = verdicts.count('BETTER')
same = verdicts.count('SAME')
worse = worse_count
print(f"{result}|{better}|{same}|{worse}")
PYEOF
}

parse_composite() {
  python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(f\"{d['global']['composite']:.2f}\")
" "$1"
}

compare_scores() {
  local prev="$1" new="$2" delta="$3"
  python3 -c "print('true' if ($new - $prev) >= $delta else 'false')"
}

# Compare only the chapters that were actually rewritten (priority chapters).
# Non-modified chapters introduce evaluator noise that drowns real improvements.
compare_priority_scores() {
  local prev_eval="$1" new_eval="$2" delta="$3"
  python3 << PYEOF - "$prev_eval" "$new_eval" "$delta"
import json, sys

prev = json.load(open(sys.argv[1]))
curr = json.load(open(sys.argv[2]))
delta = float(sys.argv[3])

priority = prev['global'].get('priority_chapters', [])
if not priority:
    print("false|0.00|0.00|0.00")
    sys.exit(0)

prev_by_file = {c['file']: c for c in prev['chapters'] if not c.get('is_divider')}
curr_by_file = {c['file']: c for c in curr['chapters'] if not c.get('is_divider')}

prev_avg = sum(prev_by_file[f]['composite'] for f in priority if f in prev_by_file) / len(priority)
curr_avg = sum(curr_by_file[f]['composite'] for f in priority if f in curr_by_file) / len(priority)
diff = curr_avg - prev_avg

improved = "true" if diff >= delta else "false"
print(f"{improved}|{prev_avg:.2f}|{curr_avg:.2f}|{diff:.2f}")
PYEOF
}

# ─── Logging ──────────────────────────────────────────────

log_entry() {
  echo "$(date +%Y-%m-%dT%H:%M:%S) | $*" >> "$LOG_FILE"
}

# ─── Evaluator ────────────────────────────────────────────

build_eval_prompt() {
  local cycle="$1"
  local filter_csv=""
  if [[ ${#CHAPTER_FILTER[@]} -gt 0 ]]; then
    filter_csv=$(IFS=,; echo "${CHAPTER_FILTER[*]}")
  fi
  python3 - "$RUBRIC_PATH" "$cycle" "$BOOK_LANG" "$BOOK_VISION" "$BOOK_GUIDELINES" "$CHAPTERS_DIR" "$PRIORITY_COUNT" "$filter_csv" <<'PYEOF'
import json, sys

rubric_path, cycle, book_lang, book_vision, book_guidelines, chapters_dir, priority_count, filter_csv = sys.argv[1:]
r = json.load(open(rubric_path))
dims = r['dimensions']
total = sum(d['weight'] for d in dims)

dim_lines = "\n".join(
    f"   - {d['key']} (weight {d['weight']}): {d['description']}"
    for d in dims
)
formula_terms = " + ".join(f"{d['key']}*{d['weight']}" for d in dims)
scores_lines = ",\n".join(f'        "{d["key"]}": 0.0' for d in dims)
global_scores_lines = ",\n".join(f'      "{d["key"]}": 0.0' for d in dims)

if filter_csv:
    targets = [f.strip() for f in filter_csv.split(',') if f.strip()]
    target_clause = "Score ONLY these specific files (do not look at any others): " + ", ".join(targets)
else:
    target_clause = f"Use the Glob tool to list all .md files in {chapters_dir}/, then Read EVERY .md file found."

print(f"""You are a senior literary critic and book editor evaluating a manuscript.
You are RIGOROUS and HONEST — never generous. A score of 7 means "good, publishable with revisions." A score of 9 means "exceptional, competitive with bestsellers in this category." Most non-fiction manuscripts score 5-7.

BOOK CONTEXT:
Language: {book_lang}
Vision: {book_vision}
Guidelines: {book_guidelines}

TASK:
1. {target_clause}
2. Use the Read tool to read each chapter in full.
3. Identify which files are actual chapters vs. structural dividers (part pages, front matter — typically very short files <200 words with only headings/epigraphs). Score ONLY actual chapters.
4. For each chapter, score on these {len(dims)} dimensions (1.0-10.0 scale, use decimals):

{dim_lines}

5. Calculate weighted composite per chapter:
   composite = ({formula_terms}) / {total}

6. Calculate global score as average of chapter composites.

7. For each chapter provide:
   - 2-3 specific, actionable critique points (not vague praise). Write critique in {book_lang}.
   - 1-2 key strengths
   - 2-3 priority improvements (concrete actions)

8. Identify the {priority_count} chapters with LOWEST composite scores as priority_chapters (if fewer chapters were scored, list all of them).

9. List the top 3 global issues affecting the whole book.

OUTPUT FORMAT — THIS IS CRITICAL:
Output your evaluation as JSON between these EXACT markers. No markdown code fences inside. Raw JSON only.

EVAL_JSON_START
{{
  "cycle": {cycle},
  "chapters": [
    {{
      "file": "filename.md",
      "title": "Chapter title from the heading",
      "word_count": 0,
      "is_divider": false,
      "scores": {{
{scores_lines}
      }},
      "composite": 0.0,
      "critique": "Specific actionable critique in {book_lang}",
      "strengths": ["strength 1"],
      "priorities": ["concrete action 1", "concrete action 2"]
    }}
  ],
  "global": {{
    "scores": {{
{global_scores_lines}
    }},
    "composite": 0.0,
    "top_issues": ["issue 1", "issue 2", "issue 3"],
    "priority_chapters": ["file1.md", "file2.md", "file3.md"]
  }}
}}
EVAL_JSON_END

After the markers you may add a brief natural language summary.""")
PYEOF
}

run_evaluator() {
  local cycle="$1"
  local prompt
  prompt=$(build_eval_prompt "$cycle")
  local raw_file="$SCORES_DIR/raw_cycle_${cycle}_eval.txt"
  local json_file="$SCORES_DIR/cycle_${cycle}_eval.json"

  info "Evaluating (cycle $cycle)..." >&2

  local output
  output=$(cd "$PROJECT_DIR" && claude --model "$MODEL" --allowedTools "Read,Glob" -p "$prompt" 2>&1) || {
    echo "$output" > "$raw_file"
    return 1
  }

  echo "$output" > "$raw_file"

  local composite
  composite=$(extract_json "$output" "$json_file") || {
    warn "JSON extraction failed. Retrying..." >&2
    local retry_output
    retry_output=$(claude --model "$MODEL" --allowedTools "" -p "The following text contains a book evaluation with JSON data. Extract ONLY the JSON object and output it between EVAL_JSON_START and EVAL_JSON_END markers. Fix any JSON syntax errors. Output NOTHING else.

TEXT:
$output" 2>&1) || return 1

    composite=$(extract_json "$retry_output" "$json_file") || {
      err "JSON extraction failed after retry."
      return 1
    }
  }

  ok "Composite score: ${BOLD}$composite${NC}" >&2
  log_entry "cycle=$cycle | type=eval | composite=$composite"
  echo "$composite"  # Only this goes to stdout for capture
}

# ─── Rewriter ─────────────────────────────────────────────

run_rewriter() {
  local prev_cycle="$1"
  local eval_file="$SCORES_DIR/cycle_${prev_cycle}_eval.json"
  local raw_file="$SCORES_DIR/raw_cycle_$((prev_cycle + 1))_rewrite.txt"

  local priority_chapters
  priority_chapters=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(', '.join(d['global']['priority_chapters']))
" "$eval_file")

  info "Rewriting priority chapters: ${BOLD}$priority_chapters${NC}"

  local prompt
  prompt=$(cat << RWEOF
You are a master prose editor working on a $BOOK_LANG manuscript. Your job is to improve specific chapters based on a professional evaluation.

BOOK CONTEXT:
Language: $BOOK_LANG
Vision: $BOOK_VISION
Guidelines: $BOOK_GUIDELINES

TASK:
1. Read the evaluation file at prose_scores/cycle_${prev_cycle}_eval.json
2. Focus on the priority_chapters listed in the global section
3. Read each priority chapter file from $CHAPTERS_DIR/
4. For each priority chapter, apply the specific critique and priority improvements from the evaluation

RULES — READ CAREFULLY:
- PRESERVE: author voice, all factual claims, all references and notes (the [N] numbering system), section headings (##), epigraphs, opening italicized paragraphs
- IMPROVE: clarity, rhythm, paragraph cohesion, transitions between sections, sentence variety, accessibility to non-technical readers
- DO NOT add generic AI prose ("In today's rapidly evolving landscape...", "It is worth noting that...", "This raises important questions about...")
- DO NOT remove or alter references, change core arguments, add unsupported content
- DO NOT make the text condescending. The audience is intelligent non-specialists.
- Concatenate related short paragraphs into cohesive ones (avoid telegraphic style)
- Improve topic sentences and paragraph flow
- Vary sentence length for rhythm (mix short punchy with longer analytical)
- Keep the same approximate word count per chapter (±15%)

Use the Edit tool to modify chapter files in place. Make targeted edits traceable to specific critique points.

After editing, briefly list what you changed per chapter (2-3 sentences each).
End your response with exactly: REWRITE_DONE
RWEOF
)

  local output
  output=$(cd "$PROJECT_DIR" && claude --model "$MODEL" --allowedTools "Read,Edit,Glob" -p "$prompt" 2>&1) || {
    echo "$output" > "$raw_file"
    return 1
  }

  echo "$output" > "$raw_file"

  if ! echo "$output" | grep -q "REWRITE_DONE"; then
    warn "Rewriter did not emit REWRITE_DONE signal"
  fi

  log_entry "cycle=$((prev_cycle + 1)) | type=rewrite | chapters=$priority_chapters"
  ok "Rewrite complete"
}

# ─── Snapshots ────────────────────────────────────────────

save_snapshots() {
  local cycle="$1"
  local eval_file="$2"
  local snapshot_dir="$SCORES_DIR/snapshots/cycle_${cycle}"

  mkdir -p "$snapshot_dir"

  local priority_chapters
  priority_chapters=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
for f in d['global']['priority_chapters']:
    print(f)
" "$eval_file")

  while IFS= read -r chapter_file; do
    [[ -z "$chapter_file" ]] && continue
    local src="$PROJECT_DIR/$CHAPTERS_DIR/$chapter_file"
    if [[ -f "$src" ]]; then
      cp "$src" "$snapshot_dir/$chapter_file"
    else
      warn "Snapshot: file not found: $src"
    fi
  done <<< "$priority_chapters"

  ok "Snapshots saved to $snapshot_dir/"
  log_entry "cycle=$cycle | type=snapshot | dir=$snapshot_dir"
}

# ─── Comparator ──────────────────────────────────────────

run_comparator() {
  local cycle="$1"
  local eval_file="$2"
  local snapshot_dir="$SCORES_DIR/snapshots/cycle_${cycle}"
  local raw_file="$SCORES_DIR/raw_cycle_${cycle}_compare.txt"
  local json_file="$SCORES_DIR/cycle_${cycle}_compare.json"

  local priority_chapters
  priority_chapters=$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
print(', '.join(d['global']['priority_chapters']))
" "$eval_file")

  info "Comparing BEFORE vs AFTER for: ${BOLD}$priority_chapters${NC}" >&2

  local prompt
  prompt=$(cat << CMPEOF
You are comparing BEFORE and AFTER versions of book chapters that were edited.
Your job is to determine whether the edits improved the prose or not.

BOOK CONTEXT:
Language: $BOOK_LANG
Vision: $BOOK_VISION
Guidelines: $BOOK_GUIDELINES

For each chapter listed below:
1. Read the BEFORE version from prose_scores/snapshots/cycle_${cycle}/<file>
2. Read the AFTER version from $CHAPTERS_DIR/<file>
3. Compare them directly, focusing on: prose quality, flow, clarity, engagement, voice preservation, reference integrity

Verdict per chapter:
- BETTER: Prose clearly improved (better flow, clarity, engagement, issues fixed)
- SAME: No meaningful difference or trade-offs cancel out
- WORSE: Rewrite introduced problems (lost voice, generic prose, removed good material)

Overall verdict:
- ACCEPT: At least 1 BETTER, no WORSE. Or: improvements outweigh regressions significantly.
- REJECT: Majority SAME/WORSE, or a WORSE chapter outweighs the improvements.

Chapters to compare: $priority_chapters

Output JSON between COMPARE_JSON_START / COMPARE_JSON_END markers. No markdown code fences inside. Raw JSON only.

COMPARE_JSON_START
{
  "cycle": $cycle,
  "chapters": [
    {
      "file": "filename.md",
      "verdict": "BETTER|SAME|WORSE",
      "reasoning": "2-3 sentences in $BOOK_LANG",
      "improvements": ["..."],
      "regressions": ["..."]
    }
  ],
  "overall_verdict": "ACCEPT|REJECT",
  "reasoning": "1-2 sentences"
}
COMPARE_JSON_END

After the markers you may add a brief natural language summary.
CMPEOF
)

  local output
  output=$(cd "$PROJECT_DIR" && claude --model "$MODEL" --allowedTools "Read,Glob" -p "$prompt" 2>&1) || {
    echo "$output" > "$raw_file"
    return 1
  }

  echo "$output" > "$raw_file"

  local result
  result=$(extract_comparison "$output" "$json_file") || {
    warn "Comparison JSON extraction failed. Retrying..." >&2
    local retry_output
    retry_output=$(claude --model "$MODEL" --allowedTools "" -p "The following text contains a chapter comparison with JSON data. Extract ONLY the JSON object and output it between COMPARE_JSON_START and COMPARE_JSON_END markers. Fix any JSON syntax errors. Output NOTHING else.

TEXT:
$output" 2>&1) || return 1

    result=$(extract_comparison "$retry_output" "$json_file") || {
      err "Comparison JSON extraction failed after retry."
      return 1
    }
  }

  local verdict better same worse
  IFS='|' read -r verdict better same worse <<< "$result"

  ok "Comparison: ${BOLD}$verdict${NC} (${GREEN}$better BETTER${NC}, $same SAME, ${RED}$worse WORSE${NC})" >&2
  log_entry "cycle=$cycle | type=compare | verdict=$verdict | better=$better | same=$same | worse=$worse"
  echo "$result"  # Only this goes to stdout for capture
}

# ─── Score table ──────────────────────────────────────────

print_score_table() {
  echo ""
  echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD} Prose Loop — Score Evolution${NC}"
  echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════════${NC}"

  python3 - "$RUBRIC_PATH" "$SCORES_DIR" <<'PYEOF'
import json, sys, glob, os

rubric_path, scores_dir = sys.argv[1:]
r = json.load(open(rubric_path))
dims = r['dimensions']

header_cols = ["Cycle", "Composite"] + [d['short'] for d in dims]
header_line = " " + " ".join(f"{c:<7}" for c in header_cols)
print(header_line)
print("─" * len(header_line))

cycle_files = sorted(glob.glob(os.path.join(scores_dir, 'cycle_*_eval.json')))
for f in cycle_files:
    d = json.load(open(f))
    g = d['global']
    s = g.get('scores', {})
    c = d.get('cycle', '?')
    row = [f"{c}", f"{g['composite']:.2f}"] + [f"{s.get(dim['key'], 0):.1f}" for dim in dims]
    print(" " + " ".join(f"{v:<7}" for v in row))
PYEOF

  echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════════${NC}"

  # Per-chapter scores for latest cycle
  local latest
  latest=$(ls -t "$SCORES_DIR"/cycle_*_eval.json 2>/dev/null | head -1)
  if [[ -n "$latest" ]]; then
    echo ""
    echo -e "${BOLD} Per-chapter scores (latest evaluation):${NC}"
    echo -e "───────────────────────────────────────────────────────────────────────────"

    # Find latest comparison file for verdict annotations
    local latest_cmp
    latest_cmp=$(ls -t "$SCORES_DIR"/cycle_*_compare.json 2>/dev/null | head -1)

    python3 << PYEOF - "$latest" "${latest_cmp:-}"
import json, sys

d = json.load(open(sys.argv[1]))
cmp_file = sys.argv[2] if len(sys.argv) > 2 and sys.argv[2] else None

cmp_verdicts = {}
if cmp_file:
    try:
        cmp = json.load(open(cmp_file))
        for ch in cmp.get('chapters', []):
            cmp_verdicts[ch['file']] = ch['verdict']
    except Exception:
        pass

chapters = [c for c in d['chapters'] if not c.get('is_divider', False)]
chapters.sort(key=lambda x: x['composite'])
for ch in chapters:
    score = ch['composite']
    bar = '█' * int(score) + '░' * (10 - int(score))
    markers = []
    if ch['file'] in d['global'].get('priority_chapters', []):
        markers.append('◄')
    v = cmp_verdicts.get(ch['file'])
    if v:
        markers.append(v)
    suffix = ' ' + ' '.join(markers) if markers else ''
    print(f"  {ch['file']:<28s} {score:>5.2f} {bar}{suffix}")
PYEOF
    echo -e "  ${DIM}◄ = priority for next rewrite | BETTER/SAME/WORSE = last comparison${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════════════════${NC}"
  fi
}

# ─── Cleanup trap ─────────────────────────────────────────

cleanup_on_exit() {
  if [[ -n "$(git diff --name-only -- "$CHAPTERS_DIR/" 2>/dev/null)" ]]; then
    warn "Interrupted — reverting uncommitted chapter changes"
    git checkout -- "$CHAPTERS_DIR/" 2>/dev/null || true
  fi
}

# ─── Main loop ────────────────────────────────────────────

run_loop() {
  local cycle=0 errors=0
  local prev_composite new_composite

  # Setup
  create_baseline_tag
  setup_scores_dir

  # Baseline evaluation
  prev_composite=$(run_evaluator 0) || {
    err "Baseline evaluation failed."
    exit 1
  }

  if [[ "$DRY_RUN" == true ]]; then
    print_score_table
    ok "Dry run complete."
    return 0
  fi

  # Loop
  local prev_eval_cycle=0
  while [[ $cycle -lt $MAX_CYCLES ]]; do
    cycle=$((cycle + 1))
    echo ""
    echo -e "${BOLD}${CYAN}── Cycle $cycle/$MAX_CYCLES ──${NC}"

    local prev_eval="$SCORES_DIR/cycle_${prev_eval_cycle}_eval.json"

    # 1. Snapshot priority chapters BEFORE rewrite
    save_snapshots "$cycle" "$prev_eval" || {
      err "Snapshot failed. Stopping."
      break
    }

    # 2. Rewrite
    run_rewriter "$prev_eval_cycle" || {
      errors=$((errors + 1))
      err "Rewriter failed (error $errors/3)"
      if [[ $errors -ge 3 ]]; then
        err "3 consecutive failures. Stopping."
        break
      fi
      continue
    }
    errors=0

    # 3. Compare BEFORE vs AFTER (direct comparison)
    local comparison
    comparison=$(run_comparator "$cycle" "$prev_eval") || {
      errors=$((errors + 1))
      err "Comparator failed (error $errors/3). Reverting rewrite."
      git checkout -- "$CHAPTERS_DIR/"
      if [[ $errors -ge 3 ]]; then
        err "3 consecutive failures. Stopping."
        break
      fi
      continue
    }
    errors=0

    local verdict better same worse
    IFS='|' read -r verdict better same worse <<< "$comparison"

    # 4. Decide based on comparator verdict
    if [[ "$verdict" == "ACCEPT" ]]; then
      ok "Rewrite accepted (${GREEN}$better BETTER${NC}, $same SAME, ${RED}$worse WORSE${NC})"

      # 5. Full evaluation (only on ACCEPT)
      new_composite=$(run_evaluator "$cycle") || {
        errors=$((errors + 1))
        err "Post-accept evaluation failed (error $errors/3). Keeping rewrite, skipping scores."
        # Still commit the accepted rewrite even if eval fails
        git add "$CHAPTERS_DIR/" "$SCORES_DIR/"
        git commit -m "prose_loop(cycle$cycle): accepted ($better BETTER, $same SAME, $worse WORSE) [eval failed]"
        log_entry "cycle=$cycle | type=commit | verdict=$verdict | eval=failed"
        # Keep prev_eval_cycle unchanged — no new eval to reference
        continue
      }
      errors=0

      git add "$CHAPTERS_DIR/" "$SCORES_DIR/"
      git commit -m "prose_loop(cycle$cycle): accepted ($better BETTER, $same SAME, $worse WORSE) | global $new_composite"
      log_entry "cycle=$cycle | type=commit | verdict=$verdict | better=$better | same=$same | worse=$worse | global=$new_composite"
      prev_composite="$new_composite"
      prev_eval_cycle=$cycle
    else
      warn "Rewrite rejected by comparator ($better BETTER, $same SAME, $worse WORSE)"
      git checkout -- "$CHAPTERS_DIR/"
      log_entry "cycle=$cycle | type=reverted | verdict=$verdict | better=$better | same=$same | worse=$worse"
      break
    fi
  done

  # Finish
  print_score_table
  echo ""
  ok "Prose loop complete. $cycle cycle(s) executed."

  # Optional PDF
  if [[ -f "$PROJECT_DIR/gerar_pdf.py" ]]; then
    echo ""
    echo -ne "${CYAN}▸${NC} Generate PDF with updated chapters? [y/n] > "
    read -r yn
    if [[ "$yn" == "y" ]]; then
      python3 "$PROJECT_DIR/gerar_pdf.py"
    fi
  fi
}

# ─── Main ─────────────────────────────────────────────────

main() {
  parse_args "$@"
  echo ""
  echo -e "${BOLD}═══════════════════════════════════${NC}"
  echo -e "${BOLD} prose_loop${NC} v$VERSION"
  echo -e "${BOLD}═══════════════════════════════════${NC}"
  echo ""

  check_dependencies
  resolve_rubric_path
  detect_chapters_dir
  detect_book_context

  local chapter_count
  chapter_count=$(list_chapter_files | wc -l | tr -d ' ')
  info "Found ${BOLD}$chapter_count${NC} .md files in $CHAPTERS_DIR/"
  info "Max cycles: ${BOLD}$MAX_CYCLES${NC} | Model: ${BOLD}$MODEL${NC} | Delta: ${BOLD}$DELTA_MIN${NC}"
  [[ "$DRY_RUN" == true ]] && info "Mode: ${BOLD}DRY RUN${NC} (evaluate only)"
  echo ""

  trap cleanup_on_exit EXIT INT TERM
  run_loop
}

main "$@"
