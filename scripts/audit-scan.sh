#!/usr/bin/env bash
# audit-scan.sh — scan repository files for PII / private references
# before public commit. The pattern set includes operator-specific strings
# hardcoded by design — keep this script self-excluded from its own scan
# (otherwise patterns would self-match).
#
# Per-line allow-list: any line containing the literal string 'audit:allow'
# is skipped. Use it for intentional public refs (e.g. portfolio URL).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

usage() {
  cat <<EOF
audit-scan.sh — PII / private-reference scanner

Usage:
  audit-scan.sh [options]

Options:
  --self-test       Run validation against fixture. Exit 0 if all
                    pattern categories detected as expected.
  --report PATH     Write scan report to PATH (in addition to stdout).
  --quiet           Suppress per-hit output (count + exit code only).
  --help            Show this help.

Exit codes:
  0    No hits (or all hits skipped via 'audit:allow' marker).
  1    Hits found.
  2    Script / environment error.
EOF
}

REPORT_PATH=""
QUIET=0
SELF_TEST=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --self-test) SELF_TEST=1; shift ;;
    --report)    REPORT_PATH="$2"; shift 2 ;;
    --quiet)     QUIET=1; shift ;;
    --help|-h)   usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

enumerate_files() {
  if [[ -d "$REPO_ROOT/.git" ]]; then
    (cd "$REPO_ROOT" && git ls-files) | grep -v '^scripts/audit-scan.sh$' || true
  else
    cd "$REPO_ROOT"
    {
      [[ -f prose_loop.sh ]] && echo prose_loop.sh
      [[ -f CLAUDE.md ]] && echo CLAUDE.md
      [[ -f prose-loop_log.md ]] && echo prose-loop_log.md
      [[ -f LICENSE ]] && echo LICENSE
      [[ -f README.md ]] && echo README.md
      [[ -f CHANGELOG.md ]] && echo CHANGELOG.md
      [[ -d scripts ]] && find scripts -type f -name '*.sh' ! -name 'audit-scan.sh'
      [[ -d rubrics ]] && find rubrics -type f -name '*.json'
      [[ -d .github ]] && find .github -type f \( -name '*.yml' -o -name '*.yaml' \)
      [[ -d examples ]] && find examples -type f
    } 2>/dev/null || true
  fi
}

run_scan() {
  local files_list_file
  files_list_file=$(mktemp)
  enumerate_files > "$files_list_file"

  local rc=0
  python3 - "$files_list_file" "$REPO_ROOT" <<'PYEOF' || rc=$?
import sys, re, os

PATTERNS = [
    ("email",           re.compile(r"[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}")),
    ("user_path",       re.compile(r"(/Users/|/home/[a-z])")),
    ("operator_names",  re.compile(r"\b(marcelo|kanhan|collecto)\b", re.IGNORECASE)),
    ("workspace_infra", re.compile(r"Documents/Infra")),
    ("workspace_proj",  re.compile(r"Documents/projects/(?!prose-loop)")),
    ("private_proj",    re.compile(r"\b(janis|bartleby|agent-lgpd|paper9|autollecto|arena|libri|cultivation)\b", re.IGNORECASE)),
]
ALLOW_MARKER = "audit:allow"
# Files where author/holder name is expected by convention — skip whole file.
AUTHOR_FILES = {"LICENSE", "LICENSE.MD", "LICENSE.TXT", "NOTICE", "AUTHORS", "CONTRIBUTORS", "COPYING"}

files_list_path = sys.argv[1]
repo_root = sys.argv[2]

with open(files_list_path) as f:
    files = [ln.strip() for ln in f if ln.strip()]

total_hits = 0
by_file = {}

for relpath in files:
    if os.path.basename(relpath).upper() in AUTHOR_FILES:
        continue
    abspath = os.path.join(repo_root, relpath)
    try:
        with open(abspath, encoding="utf-8", errors="replace") as fh:
            for lineno, line in enumerate(fh, start=1):
                if ALLOW_MARKER in line:
                    continue
                for name, rx in PATTERNS:
                    m = rx.search(line)
                    if m:
                        by_file.setdefault(relpath, []).append((lineno, name, m.group(0)))
                        total_hits += 1
                        break
    except FileNotFoundError:
        continue
    except OSError as e:
        print(f"WARN: cannot read {abspath}: {e}", file=sys.stderr)

for path in sorted(by_file):
    print(f"== {path} ==")
    for lineno, name, match in by_file[path]:
        print(f"  line {lineno}: pattern={name} match={match!r}")
    print()

print(f"Total: {total_hits} hits in {len(by_file)} file(s)")
sys.exit(1 if total_hits > 0 else 0)
PYEOF
  rm -f "$files_list_file"
  return $rc
}

self_test() {
  local fixture
  fixture=$(mktemp -d)

  cat > "$fixture/sample.md" <<'FIXTURE'
Self-test fixture — every pattern category should be detected here.
Email: someone@example.com
Path: /Users/operator/proj
Name: marcelo
Workspace infra: Documents/Infra/foo
Workspace projects: Documents/projects/other-thing
Private project: Janis
This line is allow-listed: marcelo (audit:allow)
FIXTURE

  cat > "$fixture/clean.md" <<'FIXTURE'
This file is clean. No hits expected.
Word "prose-loop" should not match Documents/projects/prose-loop either.
Documents/projects/prose-loop is the canonical excluded path.
FIXTURE

  local rc=0
  python3 - "$fixture/sample.md" "$fixture/clean.md" <<'PYEOF' || rc=$?
import sys, re, os

PATTERNS = [
    ("email",           re.compile(r"[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}")),
    ("user_path",       re.compile(r"(/Users/|/home/[a-z])")),
    ("operator_names",  re.compile(r"\b(marcelo|kanhan|collecto)\b", re.IGNORECASE)),
    ("workspace_infra", re.compile(r"Documents/Infra")),
    ("workspace_proj",  re.compile(r"Documents/projects/(?!prose-loop)")),
    ("private_proj",    re.compile(r"\b(janis|bartleby|agent-lgpd|paper9|autollecto|arena|libri|cultivation)\b", re.IGNORECASE)),
]
ALLOW_MARKER = "audit:allow"

categories_hit = set()
total_hits = 0
hits_in_clean = 0
allow_hits = 0

for path in sys.argv[1:]:
    is_clean = "clean.md" in path
    with open(path) as fh:
        for line in fh:
            if ALLOW_MARKER in line:
                allow_hits += 1
                continue
            for name, rx in PATTERNS:
                if rx.search(line):
                    categories_hit.add(name)
                    total_hits += 1
                    if is_clean:
                        hits_in_clean += 1
                    break

expected = {"email", "user_path", "operator_names", "workspace_infra", "workspace_proj", "private_proj"}
missing = expected - categories_hit

print(f"Categories detected: {sorted(categories_hit)}")
print(f"Total hits in sample: {total_hits}")
print(f"Hits in clean file: {hits_in_clean}")
print(f"Allow-marker lines skipped: {allow_hits}")

if missing:
    print(f"FAIL: missing categories: {sorted(missing)}")
    sys.exit(1)
if hits_in_clean > 0:
    print(f"FAIL: clean file should have zero hits")
    sys.exit(1)
if allow_hits == 0:
    print(f"FAIL: allow-list mechanism not exercised")
    sys.exit(1)
print("self-test passed")
PYEOF
  rm -rf "$fixture"
  return $rc
}

if [[ $SELF_TEST -eq 1 ]]; then
  self_test
  exit $?
fi

if output=$(run_scan); then rc=0; else rc=$?; fi

if [[ $QUIET -eq 1 ]]; then
  echo "$output" | tail -1
else
  echo "$output"
fi

if [[ -n "$REPORT_PATH" ]]; then
  echo "$output" > "$REPORT_PATH"
fi

exit "$rc"
