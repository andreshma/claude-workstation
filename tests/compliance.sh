#!/usr/bin/env bash
#
# tests/compliance.sh — continuous compliance evidence in CI (WS-GOV-005). Runs the repository mode of
# files/home/.local/lib/ws_compliance.py (the engine behind «ws-audit --compliance») on this checkout:
#   · the catalogue docs/compliance/controls.yaml is valid: required fields, statuses, risk and effort values, unique
#     ids, every maps_to item listed in docs/compliance/frameworks.md (and that table names the control back);
#   · every evidence file exists, every cited line range is inside its file and every cited #anchor is a heading;
#   · every check that is not tagged live passes for the implemented controls (live ones need the workstation);
#   · the coverage tables of docs/compliance/assessment.md equal the counts computed from the catalogue.
# Then it tests the engine itself on fixtures: the YAML subset parser against PyYAML (when installed), the allow
# list of check commands (the catalogue is untrusted input: nothing reaches a shell), and each failure mode.
#
# Usage: bash tests/compliance.sh      (exit 0 = all OK) · to refresh the tables after a status change:
#        python3 files/home/.local/lib/ws_compliance.py --write-assessment
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }
ENG="$ROOT/files/home/.local/lib/ws_compliance.py"
eng() { python3 -I "$ENG" "$@"; }

echo "== The kit's catalogue (repository mode)"
if [[ -n "${WS_COMPLIANCE_RUNNING:-}" ]]; then
  echo "  (skipped: already inside a compliance run)"
else
  eng --ci --kit "$ROOT" > "$T/ci.out" 2>&1; rc=$?
  sed -n '/^Control catalogue/,$p' "$T/ci.out" | grep -vE '^  · ' | sed 's/^/    /'
  check "controls.yaml is valid, no implemented control regresses and assessment.md is current" test "$rc" -eq 0
fi
check "ws-audit --compliance reaches the same engine" bash -c "python3 -I '$ROOT/files/home/.local/bin/ws-audit' --compliance --no-run --kit '$ROOT' | grep -q 'catalogue valid'"
check "the JSON report carries totals and the controls" bash -c "python3 -I '$ENG' --kit '$ROOT' --no-run --json | jq -e '.total.controls > 0 and (.errors | length) == 0'"

echo "== YAML subset parser"
if python3 -c 'import yaml' 2>/dev/null; then
  check "the stdlib parser reads controls.yaml exactly as PyYAML does" python3 - "$ROOT" <<'EOF'
import sys, yaml
sys.path.insert(0, sys.argv[1] + "/files/home/.local/lib")
import ws_compliance as w
t = open(sys.argv[1] + "/docs/compliance/controls.yaml", encoding="utf-8").read()
sys.exit(0 if w.load_yaml(t) == yaml.safe_load(t) else 1)
EOF
else
  echo "  (PyYAML not installed: parser cross-check skipped)"
fi
pyok() { python3 -I -c "import sys; sys.path.insert(0, '$ROOT/files/home/.local/lib'); import ws_compliance as w; $1"; }
check "folded plain and quoted scalars, indentless lists, empty lists" pyok "
d = w.load_yaml('''a: one two
  three
b:
- x
- 'it''s: quoted
  and folded'
c: []
d:
  - id: 1
    e: \"q\"
''')
assert d == {'a': 'one two three', 'b': ['x', \"it's: quoted and folded\"], 'c': [], 'd': [{'id': 1, 'e': 'q'}]}, d"
check "anchors, aliases, tags and block scalars are refused" pyok "
for bad in ('a: &x 1', 'a: *x', 'a: !!python/object x', 'a: |', 'a: {b: 1}'):
    try: w.load_yaml(bad); raise SystemExit('accepted ' + bad)
    except w.YamlError: pass"
check "a duplicate key is refused" pyok "
try: w.load_yaml('a: 1\na: 2'); raise SystemExit(1)
except w.YamlError: pass"

echo "== Allow list of check commands (the catalogue is untrusted)"
allowed() { pyok "k, a, why = w.parse_check('''$1'''); sys.exit(0 if not why else 1)"; }
check "bash tests/<name>.sh"                      allowed "bash tests/guard.sh"
check "test -f with a relative path"              allowed "test -f docs/compliance/controls.yaml"
check "jq -e with relative files"                 allowed "jq -e '.a == 1' files/x.json"
check "grep -qE with relative files"              allowed "grep -qE 'a|b' docs/x.md"
check "live: ws-audit --verify-log"               allowed "live: ws-audit --verify-log"
check "live: gh api repos/<o>/<r>/… (GET)"        allowed "live: gh api repos/o/r/branches/main/protection"
check "manual: free text"                         allowed "manual: look at it"
check "refused: bash -c"                          not allowed "bash -c 'rm -rf ~'"
check "refused: bash with an argument"            not allowed "bash tests/guard.sh --evil"
check "refused: a script outside tests/"          not allowed "bash install.sh"
check "refused: an absolute path"                 not allowed "grep -q root /etc/shadow"
check "refused: a path that climbs out"           not allowed "test -f ../../etc/passwd"
check "refused: ~ in a path"                      not allowed "jq -e . ~/.claude.json"
check "refused: an unknown command"               not allowed "curl -s https://example.invalid"
check "refused: a kit command outside live:"      not allowed "ws-pinned verify"
check "refused: a kit command with other args"    not allowed "live: ws-stop-all --clear"
check "refused: gh api with a method"             not allowed "live: gh api -X DELETE repos/o/r"
check "refused: git other than config --get"      not allowed "live: git push origin main"
check "refused: grep reading patterns from a file" not allowed "grep -f /etc/passwd docs/x.md"
check "shell syntax is never interpreted"         pyok "
k, a, why = w.parse_check('jq -e . a.json; touch pwned')
assert not why and a == ['jq', '-e', '.', 'a.json;', 'touch', 'pwned']   # jq gets file names, no shell runs"

echo "== Failure modes on a fixture catalogue"
F="$T/kit"; mkdir -p "$F/docs/compliance" "$F/tests" "$F/src"
printf '#!/usr/bin/env bash\nexit 0\n' > "$F/tests/pass.sh"; printf '#!/usr/bin/env bash\nexit 3\n' > "$F/tests/fail.sh"
printf 'one\ntwo\nthree\n' > "$F/src/a.sh"
printf '# Doc\n\n## A heading\n' > "$F/docs/doc.md"
cat > "$F/docs/compliance/frameworks.md" <<'EOF'
# Frameworks

## Item IDs used in the catalogue

### `CSF`

| ID | Item | Controls |
|---|---|---|
| `PR.PS-01` | Configuration | WS-SEC-001, WS-SEC-002 |
EOF
cat > "$F/docs/compliance/controls.yaml" <<'EOF'
version: 1
controls:
- id: WS-SEC-001
  title: One
  objective: o
  maps_to:
  - CSF:PR.PS-01
  status: implemented
  evidence:
  - src/a.sh:1-3 (lines)
  - docs/doc.md#a-heading
  check:
  - bash tests/pass.sh
  - 'live: ws-test'
  - 'manual: look'
  gap: none
  risk: 'low: x'
  remediation: none
  effort: S
- id: WS-SEC-002
  title: Two
  objective: o
  maps_to:
  - CSF:PR.PS-01
  status: partial
  evidence:
  - src/a.sh:2
  check:
  - bash tests/fail.sh
  gap: g
  risk: 'high: x'
  remediation: r
  effort: M
EOF
cat > "$F/docs/compliance/assessment.md" <<'EOF'
# Assessment

<!-- compliance:begin summary -->
<!-- compliance:end summary -->

<!-- compliance:begin frameworks -->
<!-- compliance:end frameworks -->
EOF
cp -r "$F" "$T/base"
reset() { rm -rf "$F"; cp -r "$T/base" "$F"; }
ci() { python3 -I "$ENG" --ci --kit "$F" > "$T/out" 2>&1; }
check "a stale assessment fails"                          not ci
check "--write-assessment fills the tables"               python3 -I "$ENG" --write-assessment --kit "$F"
cp "$F/docs/compliance/assessment.md" "$T/base/docs/compliance/assessment.md"
check "then the fixture passes (a failing partial control only warns)" ci
check "the failing partial control is reported"           grep -q 'partial or missing controls whose check fails: WS-SEC-002' "$T/out"
check "the live check is not run in CI"                   bash -c "python3 -I '$ENG' --ci --kit '$F' --json | jq -e '.controls[\"WS-SEC-001\"].items[1] | .result == \"not-run\" and (.detail | test(\"live\"))'"
check "the manual check is reported, not run"             bash -c "python3 -I '$ENG' --ci --kit '$F' --json | jq -e '.controls[\"WS-SEC-001\"].items[2].detail == \"manual\"'"
check "the tables count the statuses"                     grep -q '| \*\*Total\*\* | \*\*2\*\* | \*\*1\*\* | \*\*1\*\* |' "$F/docs/compliance/assessment.md"
sed -i 's/status: partial/status: implemented/' "$F/docs/compliance/controls.yaml"
python3 -I "$ENG" --write-assessment --kit "$F" >/dev/null
check "an implemented control whose check fails is a regression (exit 1)" not ci
check "the regression is named"                           grep -q 'regression: .*WS-SEC-002' "$T/out"
mut() { reset; sed -i "$1" "$F/docs/compliance/controls.yaml"; ci; grep -q "$2" "$T/out"; }
check "duplicate id"           mut 's/WS-SEC-002/WS-SEC-001/' 'duplicate id'
check "invalid status"         mut '0,/status: implemented/s//status: done/' 'is not one of'
check "invalid risk"           mut "s/risk: 'high: x'/risk: 'huge: x'/" 'risk must start'
check "unknown maps_to item"   mut '0,/CSF:PR.PS-01/s//CSF:PR.PS-99/' 'is not in frameworks.md'
check "missing field"          mut '/^  remediation: r$/d' 'missing remediation'
check "missing evidence file"  mut 's#src/a.sh:1-3#src/gone.sh:1-3#' 'does not exist'
check "line range outside the file" mut 's#src/a.sh:1-3#src/a.sh:2-9#' 'outside the file'
check "anchor that is not a heading" mut 's/#a-heading/#no-heading/' 'no such heading'
check "a refused check is a catalogue error" mut 's#bash tests/pass.sh#bash -c id#' 'bash only runs'
check "a missing suite is a catalogue error" mut 's#tests/pass.sh#tests/gone.sh#' 'does not exist'
reset; sed -i 's/WS-SEC-001, WS-SEC-002/WS-SEC-001/' "$F/docs/compliance/frameworks.md"; ci
check "frameworks.md must name the control back" grep -q 'lists CSF:PR.PS-01 without WS-SEC-002' "$T/out"
reset
check "a check never runs through a shell (argv only)" pyok "
import inspect; src = inspect.getsource(w.run_one); assert 'shell=True' not in src and 'os.system' not in src"
check "the catalogue file is not found: exit 2" bash -c "python3 -I '$ENG' --kit '$T/none'; [[ \$? == 2 ]]"

echo "== Framework currency check (fixture pages, no network)"
FC="$ROOT/.github/scripts/framework_currency.py"
printf '<title>OWASP Top 10 for Agentic Applications for 2026</title><h1>Top 10 for Agentic Applications 2026</h1>' > "$T/asi.html"
printf '<title>OWASP GenAI LLM Top 10 2027</title><h2>LLM Top 10 for 2027</h2>' > "$T/llm27.html"
fc() { python3 -I "$FC" --root "$ROOT" --page "OWASP-ASI=$T/asi.html" --page "OWASP-LLM26=$T/asi.html" --page "OWASP-LLM25=$1" --summary "$T/sum.md"; }
check "the recorded editions are current: exit 0" fc "$T/asi.html"
check "a newer LLM edition: exit 1"               not fc "$T/llm27.html"
check "…with an issue-ready summary"              grep -q 'Framework edition changed' "$T/sum.md"
check "an unreadable page only warns (exit 0)"    fc "$T/missing.html"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
