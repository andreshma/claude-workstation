#!/usr/bin/env python3
"""ws_compliance — continuous compliance evidence for the kit's control catalogue (WS-GOV-005, WS-GOV-009).

Reads docs/compliance/controls.yaml, validates it, runs every machine-checkable `check` of each control and reports
the result per control and per framework with the coverage. It never changes the system, the catalogue or a
control's status: a failing check of an `implemented` control is a regression (exit 1); a passing check of a
`missing` control is listed as a candidate for a status review.

The catalogue is UNTRUSTED input: a `check` is never handed to a shell. Each item is split with shlex and must
match one of the allow-listed read-only forms below, or it is not run:
  bash tests/<name>.sh                 a suite of the kit (run from the kit root)
  test -f|-d|-x|-s <path>              <path> relative to the kit root, no «..»
  jq -e <filter> <file>...             files relative to the kit root
  grep [-qEFiwxcr]... [-e] <pattern> <file>...
  live: <command>                      needs the installed workstation; never run with --ci. Kit commands with their
                                       read-only arguments only (see LIVE), «gh api repos/<o>/<r>/…» (GET) and
                                       «git config --global --get <key>»
  manual: <text>                       a human check: reported as not-run (manual)
`check: none` means there is no check. A check that cannot run here (missing tool, live in CI, manual) is
reported as not-run, never as a failure.

Usage:
  ws-audit --compliance [--json] [--kit DIR] [--catalogue FILE] [--only ID[,ID…]] [--no-run]
      workstation mode: validates, runs every check (live ones too), prints a table per control and per framework,
      writes ~/.local/share/ws-telemetry/compliance.json. The kit is $WS_KIT (default ~/code/claude-workstation,
      the checkout ws-kit-update uses); the catalogue is <kit>/docs/compliance/controls.yaml unless
      --catalogue or $WS_COMPLIANCE_CATALOGUE says otherwise.
  python3 files/home/.local/lib/ws_compliance.py --ci [--kit DIR]       (tests/compliance.sh)
      repository mode: schema, traceability to frameworks.md, evidence files and line ranges, every non-live check
      (exit 1 when an implemented control fails), and the coverage tables of assessment.md must match the catalogue.
  python3 files/home/.local/lib/ws_compliance.py --write-assessment [--kit DIR]
      regenerates the tables of assessment.md between its «compliance:begin/end» markers.
Exit: 0 ok · 1 regression or invalid catalogue (or stale assessment in --ci) · 2 usage or unreadable catalogue.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import re
import shlex
import shutil
import subprocess  # nosec B404 - argv lists from an allow list, never a shell
import sys
import textwrap
from pathlib import Path

STATUSES = ("implemented", "partial", "missing", "not-applicable")
RISKS = ("high", "medium", "low")
EFFORTS = ("S", "M", "L")
REQUIRED = (
    "id",
    "title",
    "objective",
    "maps_to",
    "status",
    "evidence",
    "check",
    "gap",
    "risk",
    "remediation",
    "effort",
)
ID_RE = re.compile(r"^WS-(AI|SEC|GOV)-\d{3}$")
FAMILIES = (
    ("WS-AI", "`WS-AI` (AI and agent)"),
    ("WS-SEC", "`WS-SEC` (general security)"),
    ("WS-GOV", "`WS-GOV` (governance)"),
)
# Read-only kit commands a `live:` check may run, with their exact arguments.
LIVE = {
    "ws-audit": [["--verify-log"]],
    "ws-pinned": [["verify"]],
    "ws-gate": [["bypasses"]],
    "ws-test": [[]],
    "ws-verify": [[]],
    "ws-stop-all": [["--status"]],
    "ws-anomaly": [["--json"]],
}
TIMEOUT = {"bash": 1200, "ws-test": 2400}


# --- YAML subset ------------------------------------------------------------------------------------------------
# The catalogue is written by PyYAML (block style, width 116): block mappings, block sequences (also indentless,
# under a key) and plain, single- or double-quoted scalars that may fold over several lines. That subset is parsed
# here with the standard library; tests/compliance.sh checks it against PyYAML when PyYAML is installed.


class YamlError(ValueError):
    pass


def _lines(text: str) -> list[tuple[int, int, str]]:
    out = []
    for n, raw in enumerate(text.splitlines(), 1):
        s = raw.rstrip()
        if not s.strip() or s.lstrip().startswith("#"):
            continue
        if "\t" in raw[: len(raw) - len(raw.lstrip())]:
            raise YamlError(f"line {n}: tab in indentation")
        out.append((n, len(s) - len(s.lstrip(" ")), s.lstrip(" ")))
    return out


def _scalar(first: str, cont: list[str], n: int):
    """A scalar that starts with `first` and continues with the (already stripped) lines in `cont`."""
    if first[:1] in ("'", '"'):
        q = first[0]
        body = " ".join([first] + cont)
        if not body.endswith(q) or len(body) < 2:
            raise YamlError(f"line {n}: unterminated quoted scalar")
        inner = body[1:-1]
        if q == "'":
            if re.search(r"(?<!')'(?!')", inner.replace("''", "")):
                raise YamlError(f"line {n}: stray quote in a single-quoted scalar")
            return inner.replace("''", "'")
        try:
            return json.loads('"' + inner.replace("\\'", "'") + '"')
        except ValueError as e:
            raise YamlError(f"line {n}: bad double-quoted scalar ({e})") from None
    if not cont and first in ("[]", "{}"):
        return [] if first == "[]" else {}
    if first[:1] in ("|", ">", "&", "*", "!", "{", "[") or first.startswith("? "):
        raise YamlError(
            f"line {n}: YAML feature outside the catalogue's subset: {first[:20]}"
        )
    s = " ".join([first] + cont)
    if " #" in s:
        s = s.split(" #", 1)[0].rstrip()
    if re.fullmatch(r"-?\d+", s):
        return int(s)
    return {"true": True, "false": False, "null": None, "~": None}.get(s, s)


def _key(rest: str, n: int) -> tuple[str, str] | None:
    """(key, value text) when `rest` is a «key: value» or «key:» line, else None."""
    m = re.match(r"^([A-Za-z_][A-Za-z0-9_-]*):(?:\s+(.*))?$", rest)
    if not m:
        return None
    return m.group(1), (m.group(2) or "")


def load_yaml(text: str):
    lines = _lines(text)
    pos = 0

    def cont_lines(min_indent: int) -> list[str]:
        nonlocal pos
        out = []
        while pos < len(lines) and lines[pos][1] >= min_indent:
            out.append(lines[pos][2])
            pos += 1
        return out

    def node(indent: int):
        """A block node whose first line is at `indent`."""
        if pos >= len(lines):
            return None
        _, ind, rest = lines[pos]
        if ind != indent:
            raise YamlError(f"line {lines[pos][0]}: unexpected indentation")
        return seq(indent) if rest == "-" or rest.startswith("- ") else mapping(indent)

    def seq(indent: int) -> list:
        nonlocal pos
        out = []
        while pos < len(lines):
            n, ind, rest = lines[pos]
            if ind != indent or not (rest == "-" or rest.startswith("- ")):
                break
            item = rest[2:].lstrip() if rest != "-" else ""
            sub = (
                indent
                + 2
                + (len(rest[2:]) - len(rest[2:].lstrip()) if rest != "-" else 0)
            )
            if not item:
                pos += 1
                out.append(
                    node(lines[pos][1])
                    if pos < len(lines) and lines[pos][1] > indent
                    else None
                )
            elif _key(item, n) is not None and item[:1] not in ("'", '"'):
                # «- key: value»: a mapping whose first key sits after the dash.
                lines[pos] = (n, sub, item)
                out.append(mapping(sub))
            else:
                pos += 1
                out.append(_scalar(item, cont_lines(indent + 1), n))
        return out

    def mapping(indent: int) -> dict:
        nonlocal pos
        out: dict = {}
        while pos < len(lines):
            n, ind, rest = lines[pos]
            if ind < indent:
                break
            if ind > indent:
                raise YamlError(f"line {n}: unexpected indentation")
            if rest.startswith("- ") or rest == "-":
                break
            kv = _key(rest, n)
            if kv is None:
                raise YamlError(f"line {n}: expected «key: value»")
            k, v = kv
            if k in out:
                raise YamlError(f"line {n}: duplicate key {k}")
            pos += 1
            if v:
                out[k] = _scalar(v, cont_lines(indent + 1), n)
            elif pos < len(lines) and (
                lines[pos][1] > indent
                or (lines[pos][1] == indent and lines[pos][2].startswith("- "))
            ):
                out[k] = node(lines[pos][1])
            else:
                out[k] = None
        return out

    if not lines:
        return None
    doc = node(lines[0][1])
    if pos != len(lines):
        raise YamlError(f"line {lines[pos][0]}: content after the document")
    return doc


# --- catalogue -------------------------------------------------------------------------------------------------


def load_catalogue(path: Path) -> dict:
    doc = load_yaml(path.read_text(encoding="utf-8"))
    if not isinstance(doc, dict) or not isinstance(doc.get("controls"), list):
        raise YamlError("no «controls» list")
    return doc


def risk_level(c: dict) -> str:
    return str(c.get("risk", "")).split(":", 1)[0].strip()


def frameworks_index(md: str) -> dict[str, dict[str, set[str]]]:
    """{prefix: {item id: {control ids}}} from frameworks.md, «Item IDs used in the catalogue»."""
    idx: dict[str, dict[str, set[str]]] = {}
    part = md.split("## Item IDs used in the catalogue", 1)
    if len(part) < 2:
        return idx
    cur = None
    for line in part[1].splitlines():
        m = re.match(r"^### `([^`]+)`", line)
        if m:
            cur = idx.setdefault(m.group(1), {})
            continue
        if line.startswith("## "):
            break
        m = re.match(r"^\| `([^`]+)` \|.*\| ([^|]*) \|$", line)
        if cur is not None and m:
            cur[m.group(1)] = set(re.findall(r"WS-(?:AI|SEC|GOV)-\d{3}", m.group(2)))
    return idx


def evidence_path(e: str) -> tuple[str, list[tuple[int, int]], str] | None:
    """(path, line ranges, anchor) when an evidence item names a repository file, else None.
    Forms: path · path:12 · path:12-30 · path:3-8,17,40-42 · path.md#anchor, each optionally followed by « (note)»."""
    tok = e.split(" ", 1)[0].rstrip(",;")
    m = re.match(r"^([A-Za-z0-9_./@-]+?)(?::([\d,-]+)|#([a-z0-9-]+))?$", tok)
    if (
        not m
        or "/" not in m.group(1)
        and not re.search(r"\.(md|json|ya?ml|sh|txt|toml|py)$", m.group(1))
    ):
        return None
    ranges = []
    for part in (m.group(2) or "").split(","):
        if part:
            a, _, b = part.partition("-")
            if not a.isdigit() or (b and not b.isdigit()):
                return m.group(1), [(1, 0)], ""
            ranges.append((int(a), int(b or a)))
    return m.group(1), ranges, m.group(3) or ""


def md_anchors(text: str) -> set[str]:
    """GitHub-style heading anchors of a Markdown file (code fences skipped; duplicates get -1, -2…)."""
    out: set[str] = set()
    seen: dict[str, int] = {}
    fence = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            fence = not fence
        if fence or not re.match(r"^#{1,6} ", line):
            continue
        h = re.sub(
            r"[^\w\- ]", "", line.lstrip("#").strip().lower().replace("`", "")
        ).replace(" ", "-")
        n = seen.get(h, 0)
        seen[h] = n + 1
        out.add(h if n == 0 else f"{h}-{n}")
    return out


def safe_rel(p: str) -> bool:
    return (
        bool(p)
        and not p.startswith(("/", "~", "-"))
        and ".." not in Path(p).parts
        and "$" not in p
    )


def parse_check(item) -> tuple[str, list[str] | str, str]:
    """(kind, argv or text, error). kind: run | live | manual | none."""
    if not isinstance(item, str) or not item.strip():
        return "none", "", "a check item must be a non-empty string"
    s = item.strip()
    if s == "none":
        return "none", "", ""
    if s.startswith("manual:"):
        return "manual", s[7:].strip(), "" if s[7:].strip() else "empty manual check"
    kind = "run"
    if s.startswith("live:"):
        kind, s = "live", s[5:].strip()
    try:
        argv = shlex.split(s)
    except ValueError as e:
        return kind, [], f"cannot split «{s}»: {e}"
    why = allowed(argv, kind)
    return kind, argv, why


def allowed(argv: list[str], kind: str) -> str:
    """'' when argv is one of the allow-listed read-only forms, else the reason it is refused."""
    if not argv:
        return "empty command"
    c, a = argv[0], argv[1:]
    if c == "bash":
        ok = len(a) == 1 and re.fullmatch(r"tests/[a-z0-9][a-z0-9-]*\.sh", a[0])
        return "" if ok else "bash only runs tests/<name>.sh, without arguments"
    if c == "test":
        ok = len(a) == 2 and a[0] in ("-f", "-d", "-x", "-s") and safe_rel(a[1])
        return "" if ok else "test takes -f|-d|-x|-s and a relative path"
    if c == "jq":
        ok = len(a) >= 3 and a[0] == "-e" and all(safe_rel(f) for f in a[2:])
        return "" if ok else "jq takes -e <filter> and relative files"
    if c == "grep":
        i = 0
        while i < len(a) and re.fullmatch(r"-[qEFiwxcr]+", a[i]):
            i += 1
        if i < len(a) and a[i] == "-e":
            i += 1
        files = a[i + 1 :]
        ok = i < len(a) and files and all(safe_rel(f) for f in files)
        return "" if ok else "grep takes [-qEFiwxcr] [-e] <pattern> and relative files"
    if kind != "live":
        return f"«{c}» is not allowed outside a live: check"
    if c in LIVE:
        forms = " | ".join(" ".join(x) or "(no arguments)" for x in LIVE[c])
        return "" if a in LIVE[c] else f"{c} may run only with {forms}"
    if c == "gh":
        ok = (
            len(a) == 2
            and a[0] == "api"
            and re.fullmatch(r"repos/[\w.-]+/[\w.-]+(/[\w.-]+)*", a[1])
        )
        return "" if ok else "gh may run only as «gh api repos/<owner>/<repo>/…» (GET)"
    if c == "git":
        ok = (
            len(a) == 4
            and a[:3] == ["config", "--global", "--get"]
            and re.fullmatch(r"[\w.-]+", a[3])
        )
        return "" if ok else "git may run only as «git config --global --get <key>»"
    return f"«{c}» is not an allowed command"


def check_items(c: dict) -> list:
    v = c.get("check")
    if v == "none" or v is None:
        return []
    return v if isinstance(v, list) else [v]


def validate(cat: dict, root: Path) -> list[str]:
    errs: list[str] = []
    fw = (
        frameworks_index(
            (root / "docs/compliance/frameworks.md").read_text(encoding="utf-8")
        )
        if (root / "docs/compliance/frameworks.md").is_file()
        else {}
    )
    if not fw:
        errs.append(
            "docs/compliance/frameworks.md: no «Item IDs used in the catalogue» tables"
        )
    seen: set[str] = set()
    texts: dict[str, str] = {}
    for i, c in enumerate(cat["controls"]):
        cid = c.get("id") if isinstance(c, dict) else None
        where = cid or f"control #{i + 1}"
        if not isinstance(c, dict):
            errs.append(f"{where}: not a mapping")
            continue
        for k in REQUIRED:
            empty_ok = k == "evidence" and c.get("status") in (
                "missing",
                "not-applicable",
            )
            if k not in c or c[k] is None or (c[k] in ("", []) and not empty_ok):
                errs.append(f"{where}: missing {k}")
        extra = set(c) - set(REQUIRED)
        if extra:
            errs.append(f"{where}: unknown fields {sorted(extra)}")
        if not isinstance(cid, str) or not ID_RE.match(cid):
            errs.append(f"{where}: id must look like WS-AI-001")
        elif cid in seen:
            errs.append(f"{cid}: duplicate id")
        seen.add(str(cid))
        if c.get("status") not in STATUSES:
            errs.append(
                f"{where}: status {c.get('status')!r} is not one of {', '.join(STATUSES)}"
            )
        if risk_level(c) not in RISKS:
            errs.append(f"{where}: risk must start with high:, medium: or low:")
        if c.get("effort") not in EFFORTS:
            errs.append(f"{where}: effort must be S, M or L")
        for ref in c.get("maps_to") or []:
            pre, _, item = str(ref).partition(":")
            if pre not in fw or item not in fw[pre]:
                errs.append(f"{where}: maps_to {ref} is not in frameworks.md")
            elif cid not in fw[pre][item]:
                errs.append(f"{where}: frameworks.md lists {ref} without {cid}")
        ev = c.get("evidence") or []
        if c.get("status") in ("implemented", "partial") and (
            not isinstance(ev, list) or not ev
        ):
            errs.append(f"{where}: an {c.get('status')} control needs evidence")
        for e in ev if isinstance(ev, list) else []:
            p = evidence_path(str(e))
            if not p:
                continue
            f, ranges, anchor = p
            fp = root / f
            if not safe_rel(f) or not (fp.is_file() or fp.is_dir()):
                errs.append(f"{where}: evidence {f} does not exist")
                continue
            if (ranges or anchor) and fp.is_file():
                if f not in texts:
                    texts[f] = fp.read_text(encoding="utf-8", errors="replace")
                n = len(texts[f].splitlines())
                for a, b in ranges:
                    if a < 1 or b < a or b > n:
                        errs.append(
                            f"{where}: evidence {f}:{a}-{b} is outside the file ({n} lines)"
                        )
                if anchor and anchor not in md_anchors(texts[f]):
                    errs.append(f"{where}: evidence {f}#{anchor}: no such heading")
        v = c.get("check")
        if not (v == "none" or (isinstance(v, list) and v)):
            errs.append(f"{where}: check must be «none» or a list of check items")
        for it in check_items(c):
            kind, argv, why = parse_check(it)
            if why:
                errs.append(f"{where}: check «{it}»: {why}")
            elif kind == "run" and argv[0] == "bash" and not (root / argv[1]).is_file():
                errs.append(f"{where}: check «{it}»: {argv[1]} does not exist")
    for pre, items in fw.items():
        for item, ids in items.items():
            for cid in sorted(ids - seen):
                errs.append(
                    f"frameworks.md {pre}:{item} names {cid}, which is not in the catalogue"
                )
    return errs


# --- running the checks ----------------------------------------------------------------------------------------


def run_one(kind: str, argv: list[str], root: Path, ci: bool) -> tuple[str, str]:
    """(result, detail). result: pass | fail | not-run."""
    if kind == "live" and ci:
        return "not-run", "live (needs the workstation)"
    if argv[0] == "bash" and argv[1] == "tests/compliance.sh":
        return "not-run", "self (this run is that check)"
    exe = shutil.which(argv[0])
    if not exe:
        return "not-run", f"{argv[0]} is not installed here"
    env = dict(os.environ, WS_COMPLIANCE_RUNNING="1")
    try:
        r = subprocess.run(
            [exe] + argv[1:],
            check=False,
            cwd=root,
            env=env,
            stdin=subprocess.DEVNULL,  # nosec B603
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
            timeout=TIMEOUT.get(argv[0], 60),
        )
    except subprocess.TimeoutExpired:
        return "fail", "timed out"
    except OSError as e:
        return "not-run", f"could not start: {e}"
    tail = " ".join(r.stdout.strip().splitlines()[-1:])[:160]
    return (
        ("pass", tail)
        if r.returncode == 0
        else ("fail", f"exit {r.returncode}: {tail}")
    )


def run_checks(
    cat: dict, root: Path, ci: bool, only: set[str] | None, progress
) -> dict[str, dict]:
    cache: dict[tuple[str, tuple[str, ...]], tuple[str, str]] = {}
    out: dict[str, dict] = {}
    for c in cat["controls"]:
        if only and c["id"] not in only:
            continue
        items = []
        for it in check_items(c):
            kind, argv, why = parse_check(it)
            if why:
                items.append(
                    {"check": it, "result": "not-run", "detail": f"refused: {why}"}
                )
                continue
            if kind == "manual":
                items.append({"check": it, "result": "not-run", "detail": "manual"})
                continue
            key = (kind, tuple(argv))
            if key not in cache:
                progress(f"{c['id']}: {it}")
                cache[key] = run_one(kind, argv, root, ci)
            res, det = cache[key]
            items.append({"check": it, "result": res, "detail": det})
        rs = {i["result"] for i in items}
        result = "fail" if "fail" in rs else "pass" if "pass" in rs else "not-run"
        out[c["id"]] = {"status": c["status"], "result": result, "items": items}
    return out


# --- coverage --------------------------------------------------------------------------------------------------


def pct(n: int, d: int) -> str:
    return f"{n} ({round(100 * n / d) if d else 0} %)"


def fw_order(cat: dict, root: Path) -> list[str]:
    md = root / "docs/compliance/frameworks.md"
    order = (
        list(frameworks_index(md.read_text(encoding="utf-8"))) if md.is_file() else []
    )
    used = {
        str(r).split(":", 1)[0] for c in cat["controls"] for r in c.get("maps_to") or []
    }
    return [p for p in order if p in used] + sorted(used - set(order))


def coverage(cat: dict, root: Path) -> dict:
    cs = cat["controls"]
    fams = {}
    for pre, _ in FAMILIES:
        sel = [c for c in cs if c["id"].startswith(pre + "-")]
        fams[pre] = {s: sum(c["status"] == s for c in sel) for s in STATUSES} | {
            "controls": len(sel)
        }
    risks = {
        r: {
            "all": sum(risk_level(c) == r for c in cs),
            "open": sum(
                risk_level(c) == r and c["status"] in ("partial", "missing") for c in cs
            ),
        }
        for r in RISKS
    }
    effort = {
        e: sum(c["effort"] == e and c["status"] in ("partial", "missing") for c in cs)
        for e in EFFORTS
    }
    per_fw, per_item = {}, {}
    for pre in fw_order(cat, root):
        sel = [
            c
            for c in cs
            if any(str(r).split(":", 1)[0] == pre for r in c.get("maps_to") or [])
        ]
        per_fw[pre] = {s: sum(c["status"] == s for c in sel) for s in STATUSES} | {
            "controls": len(sel)
        }
        items: dict[str, list[str]] = {}
        for c in sel:
            for r in c["maps_to"]:
                p, _, it = str(r).partition(":")
                if p == pre:
                    items.setdefault(it, []).append(c["status"])
        rated = {s: 0 for s in STATUSES}
        for sts in items.values():
            live = [s for s in sts if s != "not-applicable"]
            if not live:
                rated["not-applicable"] += 1
            elif all(s == "implemented" for s in live):
                rated["implemented"] += 1
            elif all(s == "missing" for s in live):
                rated["missing"] += 1
            else:
                rated["partial"] += 1
        per_item[pre] = rated | {"items": len(items), "controls": len(sel)}
    high = [
        c
        for c in cs
        if risk_level(c) == "high" and c["status"] in ("partial", "missing")
    ]
    return {
        "families": fams,
        "risks": risks,
        "effort_open": effort,
        "frameworks": per_fw,
        "items": per_item,
        "total": {s: sum(c["status"] == s for c in cs) for s in STATUSES}
        | {"controls": len(cs)},
        "high_open": [
            {"id": c["id"], "status": c["status"], "effort": c["effort"]} for c in high
        ],
    }


# --- assessment.md blocks --------------------------------------------------------------------------------------


def md_row(cells) -> str:
    return "| " + " | ".join(str(x) for x in cells) + " |"


def block_summary(cv: dict) -> list[str]:
    out = [
        "| Family | Controls | Implemented | Partial | Missing | Not applicable |",
        "|---|---|---|---|---|---|",
    ]
    for pre, label in FAMILIES:
        f = cv["families"][pre]
        out.append(
            md_row(
                [
                    label,
                    f["controls"],
                    f["implemented"],
                    f["partial"],
                    f["missing"],
                    f["not-applicable"],
                ]
            )
        )
    t = cv["total"]
    out.append(
        md_row(["**Total**"] + [f"**{t[k]}**" for k in ("controls",) + STATUSES])
    )
    out += [
        "",
        "| Risk | All controls | Open gaps (partial or missing) |",
        "|---|---|---|",
    ]
    for r in RISKS:
        out.append(
            md_row([r.capitalize(), cv["risks"][r]["all"], cv["risks"][r]["open"]])
        )
    e = cv["effort_open"]
    hi = cv["high_open"]
    his = ", ".join(f"{h['id']} ({h['status']}, {h['effort']})" for h in hi) or "none"
    out += [""] + textwrap.wrap(
        f"Open gaps by effort: {e['S']} small, {e['M']} medium, {e['L']} large. "
        f"Open high-risk gaps: {his}.",
        116,
        break_on_hyphens=False,
    )
    return out


def block_frameworks(cv: dict) -> list[str]:
    out = [
        "| Framework | Controls | Implemented | Partial | Missing | N/A |",
        "|---|---|---|---|---|---|",
    ]
    for pre, f in cv["frameworks"].items():
        n = f["controls"]
        out.append(md_row([pre, n] + [pct(f[s], n) for s in STATUSES]))
    return out


def block_items(cv: dict, old: list[str]) -> list[str]:
    """Item-level table; the «Not mapped» column comes from frameworks.md's closed lists, kept from the old table."""
    keep = {}
    for line in old:
        cells = [x.strip() for x in line.strip().strip("|").split("|")]
        if len(cells) == 8 and cells[0] not in ("Framework", "---"):
            keep[cells[0]] = cells[6]
    out = [
        "| Framework | Items mapped | Implemented | Partial | Missing | N/A | Not mapped | Controls |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for pre, f in cv["items"].items():
        n = f["items"]
        out.append(
            md_row(
                [pre, n]
                + [pct(f[s], n) for s in STATUSES]
                + [keep.get(pre, "-"), f["controls"]]
            )
        )
    return out


def block_gaps(cat: dict) -> list[str]:
    order = {r: i for i, r in enumerate(RISKS)}
    eff = {e: i for i, e in enumerate(EFFORTS)}
    rows = sorted(
        (c for c in cat["controls"] if c["status"] in ("partial", "missing")),
        key=lambda c: (order[risk_level(c)], eff[c["effort"]], c["id"]),
    )
    out = [
        "| Control | Title | Status | Risk | Effort | Gap |",
        "|---|---|---|---|---|---|",
    ]
    for c in rows:
        gap = " ".join(str(c["gap"]).split()).replace("|", "\\|")
        out.append(
            md_row([c["id"], c["title"], c["status"], risk_level(c), c["effort"], gap])
        )
    return out


MARK = re.compile(
    r"(<!-- compliance:begin (\w+) -->\n)(.*?)(<!-- compliance:end \2 -->)", re.DOTALL
)


def render_assessment(text: str, cat: dict, root: Path) -> str:
    cv = coverage(cat, root)

    def sub(m: re.Match) -> str:
        name, old = m.group(2), m.group(3).splitlines()
        body = {
            "summary": lambda: block_summary(cv),
            "frameworks": lambda: block_frameworks(cv),
            "items": lambda: block_items(cv, old),
            "gaps": lambda: block_gaps(cat),
        }.get(name)
        if body is None:
            return m.group(0)
        return m.group(1) + "\n".join(body()) + "\n" + m.group(4)

    return MARK.sub(sub, text)


# --- output ----------------------------------------------------------------------------------------------------


def fw_results(cat: dict, results: dict, root: Path) -> list[dict]:
    rows = []
    for pre in fw_order(cat, root):
        sel = [
            c
            for c in cat["controls"]
            if c["id"] in results
            and any(str(r).split(":", 1)[0] == pre for r in c.get("maps_to") or [])
        ]
        if not sel:
            continue
        st = {s: sum(c["status"] == s for c in sel) for s in STATUSES}
        rs = {
            r: sum(results[c["id"]]["result"] == r for c in sel)
            for r in ("pass", "fail", "not-run")
        }
        applicable = len(sel) - st["not-applicable"]
        rows.append(
            {
                "framework": pre,
                "controls": len(sel),
                **st,
                **rs,
                "coverage_pct": round(100 * st["implemented"] / applicable)
                if applicable
                else 0,
            }
        )
    return rows


def table(rows: list[list], head: list[str]) -> str:
    w = (
        [max(len(str(x)) for x in col) for col in zip(head, *rows, strict=True)]
        if rows
        else [len(h) for h in head]
    )
    fmt = "  ".join(f"{{:{n}}}" for n in w)
    return "\n".join(
        [fmt.format(*head), fmt.format(*("-" * n for n in w))]
        + [fmt.format(*map(str, r)) for r in rows]
    )


def main(argv: list[str] | None = None) -> int:
    a = list(sys.argv[1:] if argv is None else argv)
    if "--compliance" in a:
        a.remove("--compliance")

    def opt(name: str, default=None):
        if name in a:
            i = a.index(name)
            if i + 1 >= len(a):
                print(f"{name} needs a value", file=sys.stderr)
                sys.exit(2)
            v = a[i + 1]
            del a[i : i + 2]
            return v
        return default

    def flag(name: str) -> bool:
        if name in a:
            a.remove(name)
            return True
        return False

    if flag("-h") or flag("--help"):
        print(__doc__)
        return 0
    kit = Path(
        opt("--kit")
        or os.environ.get("WS_KIT")
        or Path.home() / "code/claude-workstation"
    ).expanduser()
    catp = Path(
        opt("--catalogue")
        or os.environ.get("WS_COMPLIANCE_CATALOGUE")
        or kit / "docs/compliance/controls.yaml"
    )
    only_s = opt("--only")
    only = set(only_s.split(",")) if only_s else None
    ci, as_json, no_run, write_assess = (
        flag("--ci"),
        flag("--json"),
        flag("--no-run"),
        flag("--write-assessment"),
    )
    if a:
        print(f"unknown arguments: {' '.join(a)} (see --help)", file=sys.stderr)
        return 2
    if not catp.is_file():
        print(
            f"✖ catalogue not found: {catp}\n  Clone the kit there, or set WS_KIT / --kit / --catalogue.",
            file=sys.stderr,
        )
        return 2
    try:
        cat = load_catalogue(catp)
    except (YamlError, OSError, UnicodeDecodeError) as e:
        print(f"✖ {catp}: {e}", file=sys.stderr)
        return 2
    root = kit if (kit / "docs/compliance").is_dir() else catp.parent.parent.parent
    errs = validate(cat, root)
    assess = root / "docs/compliance/assessment.md"

    if write_assess:
        if errs:
            print("\n".join(f"✖ {e}" for e in errs), file=sys.stderr)
            return 1
        t = assess.read_text(encoding="utf-8")
        assess.write_text(render_assessment(t, cat, root), encoding="utf-8")
        print(f"✔ {assess} regenerated")
        return 0

    log = (
        (lambda m: print(f"  · {m}", file=sys.stderr, flush=True))
        if not as_json
        else (lambda m: None)
    )
    results = {} if no_run else run_checks(cat, root, ci, only, log)
    stale = []
    if ci and assess.is_file():
        t = assess.read_text(encoding="utf-8")
        if not MARK.search(t):
            stale.append("assessment.md has no «compliance:begin» markers")
        elif render_assessment(t, cat, root) != t:
            stale.append(
                "the coverage tables of assessment.md differ from controls.yaml: "
                "python3 files/home/.local/lib/ws_compliance.py --write-assessment"
            )
    regress = [
        i
        for i, r in results.items()
        if r["result"] == "fail" and r["status"] == "implemented"
    ]
    weak = [
        i
        for i, r in results.items()
        if r["result"] == "fail" and r["status"] != "implemented"
    ]
    cand = [
        i
        for i, r in results.items()
        if r["result"] == "pass" and r["status"] == "missing"
    ]
    cv = coverage(cat, root)
    report = {
        "generated": dt.datetime.now().astimezone().isoformat(timespec="seconds"),
        "catalogue": str(catp),
        "mode": "ci" if ci else "workstation",
        "kit_version": cat.get("kit_version"),
        "assessed": cat.get("assessed"),
        "errors": errs,
        "stale": stale,
        "regressions": regress,
        "failing_partial": weak,
        "review_candidates": cand,
        "total": cv["total"],
        "frameworks": fw_results(cat, results, root) if results else [],
        "controls": results,
    }
    if not ci and not no_run:
        out = Path.home() / ".local/share/ws-telemetry/compliance.json"
        try:
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(
                json.dumps(report, indent=1, ensure_ascii=False), encoding="utf-8"
            )
        except OSError:
            pass
    if as_json:
        print(json.dumps(report, indent=1, ensure_ascii=False))
    else:
        t = cv["total"]
        print(
            f"\nControl catalogue {catp} ({t['controls']} controls: {t['implemented']} implemented, "
            f"{t['partial']} partial, {t['missing']} missing, {t['not-applicable']} not applicable)"
        )
        if results:
            rows = [
                [
                    i,
                    r["status"],
                    r["result"],
                    next(
                        (
                            x["check"] + " → " + x["detail"]
                            for x in r["items"]
                            if x["result"] == "fail"
                        ),
                        next((x["detail"] for x in r["items"]), "no check"),
                    )[:90],
                ]
                for i, r in results.items()
            ]
            print("\n" + table(rows, ["Control", "Status", "Check", "Detail"]))
            fr = report["frameworks"]
            print(
                "\n"
                + table(
                    [
                        [
                            f["framework"],
                            f["controls"],
                            f["implemented"],
                            f["partial"],
                            f["missing"],
                            f["not-applicable"],
                            f"{f['coverage_pct']} %",
                            f["pass"],
                            f["fail"],
                            f["not-run"],
                        ]
                        for f in fr
                    ],
                    [
                        "Framework",
                        "Controls",
                        "Impl",
                        "Partial",
                        "Missing",
                        "N/A",
                        "Coverage",
                        "Pass",
                        "Fail",
                        "Not run",
                    ],
                )
            )
            print(
                "\nCoverage = implemented controls over applicable ones. Not run = manual, live in CI, or a tool "
                "missing here."
            )
        for e in errs:
            print(f"✖ catalogue: {e}")
        for s in stale:
            print(f"✖ {s}")
        if regress:
            print(
                f"✖ regression: implemented controls whose check fails: {', '.join(regress)}"
            )
        if weak:
            print(f"! partial or missing controls whose check fails: {', '.join(weak)}")
        if cand:
            print(
                f"! missing controls whose check passes (review the status): {', '.join(cand)}"
            )
        if not (errs or stale or regress):
            print(
                "✔ compliance: catalogue valid"
                + (", no regressions" if results else "")
            )
    return 1 if (errs or stale or regress) else 0


if __name__ == "__main__":
    sys.exit(main())
