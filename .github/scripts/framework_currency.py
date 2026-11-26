#!/usr/bin/env python3
"""framework_currency.py — are the framework editions recorded in docs/compliance/frameworks.md still current?

Checks the OWASP lists the catalogue leans on most (Top 10 for LLM Applications and Top 10 for Agentic
Applications): fetches each official page named in the Sources table and looks for an edition year newer than the one
recorded. It also watches the Microsoft cloud security benchmark (MCSB, versioned «vN», possibly «(preview)»): a page
that names a newer major version (v3), or a recorded preview that is no longer marked as preview anywhere on the page
(it became generally available), is a change. Network trouble is a warning (exit 0): the check is retried next month. A newer edition prints an
issue-ready message (also to the step summary) and exits 1, so the scheduled run turns red and the owner is told.
The other frameworks are re-verified by hand at the quarterly review (docs/governance/REVIEW-CADENCE.md).

Usage: python3 .github/scripts/framework_currency.py [--summary FILE] [--root DIR] [--page PREFIX=FILE]...
       --page replaces the download of that prefix's page with a local file (tests).
"""

from __future__ import annotations

import html
import re
import sys
import urllib.request
from pathlib import Path

# Prefix whose edition is recorded → (the words that name that list in a title or heading, the prefixes whose official
# pages are read). The LLM list is also read from the 2025 entry's URL, the evergreen landing page of the list.
LISTS = {
    "OWASP-LLM26": (
        r"(?:LLM|GenAI)[^<\n]{0,60}?Top 10|Top 10 for LLM",
        ("OWASP-LLM26", "OWASP-LLM25"),
    ),
    "OWASP-ASI": (r"Top 10 for Agentic", ("OWASP-ASI",)),
}
# Benchmarks versioned «vN»: prefix → the words that name the benchmark in a title or heading.
BENCHMARKS = {"MCSB": r"cloud security benchmark"}
PREVIEW = re.compile(
    r"\bv(\d+)\s*\(preview\)|\bv(\d+) is currently in preview", re.IGNORECASE
)
UA = "framework-currency-check/1.0"


def sources(md: str) -> dict[str, dict]:
    """{prefix: {version, url}} from the Sources table of frameworks.md."""
    out = {}
    for line in md.splitlines():
        m = re.match(
            r"^\| `([^`]+)` \| ([^|]+) \| ([^|]+) \| ([^|]+) \| <([^>]+)>", line
        )
        if m:
            out[m.group(1)] = {
                "name": m.group(2).strip(),
                "version": m.group(3).strip(),
                "url": m.group(5),
            }
    return out


def recorded_year(version: str) -> int | None:
    y = re.findall(r"\b(20\d\d)\b", version)
    return int(y[0]) if y else None


def headings(page: str) -> str:
    """The text of the page's title and h1 to h3 headings."""
    text = " ".join(
        re.findall(
            r"<(?:title|h1|h2|h3)[^>]*>(.*?)</(?:title|h1|h2|h3)>",
            page,
            re.IGNORECASE | re.DOTALL,
        )
    )
    return html.unescape(re.sub(r"<[^>]+>", " ", text))


def benchmark_changes(page: str, recorded: str, words: str) -> list[str]:
    """What changed for a «vN [(preview)]» benchmark: a newer major version named in the title or headings, or the
    recorded preview edition no longer marked as preview anywhere on the page (it became generally available)."""
    m = re.search(r"\bv(\d+)", recorded)
    if not m:
        return []
    have, out = int(m.group(1)), []
    text = headings(page)
    majors = {
        int(v)
        for w in re.finditer(words, text, re.IGNORECASE)
        for v in re.findall(r"\bv(\d+)\b", text[w.start() : w.end() + 40])
    }
    newer = sorted(v for v in majors if v > have)
    if newer:
        out.append("the official page names " + ", ".join(f"v{v}" for v in newer))
    plain = html.unescape(re.sub(r"<[^>]+>", " ", page))
    previews = {int(a or b) for a, b in PREVIEW.findall(plain)}
    if "preview" in recorded.lower() and have in majors and have not in previews:
        out.append(f"v{have} is no longer marked as preview (generally available)")
    return out


def page_years(page: str, words: str) -> set[int]:
    """Edition years in the page's title and headings that name the list."""
    text = headings(page)
    years = set()
    for m in re.finditer(words, text, re.IGNORECASE):
        near = text[max(0, m.start() - 40) : m.end() + 60]
        years |= {int(y) for y in re.findall(r"\b(20\d\d)\b", near)}
    return years


def fetch(url: str) -> str:
    if not url.startswith("https://"):
        raise ValueError("only https sources are fetched")
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:  # nosec B310 - https only, fixed official URLs
        return r.read(2_000_000).decode("utf-8", "replace")


def main(argv: list[str]) -> int:
    root = (
        Path(argv[argv.index("--root") + 1])
        if "--root" in argv
        else Path(__file__).resolve().parents[2]
    )
    summary = argv[argv.index("--summary") + 1] if "--summary" in argv else ""
    local = {}
    for i, a in enumerate(argv):
        if a == "--page" and i + 1 < len(argv):
            k, _, v = argv[i + 1].partition("=")
            local[k] = v
    src = sources((root / "docs/compliance/frameworks.md").read_text(encoding="utf-8"))
    changed, warned = [], []
    for prefix, (words, pages) in LISTS.items():
        s = src.get(prefix)
        if not s:
            warned.append(f"{prefix}: not in the Sources table of frameworks.md")
            continue
        have = recorded_year(s["version"])
        seen: set[int] = set()
        for pp in pages:
            url = src.get(pp, {}).get("url", "")
            try:
                page = (
                    Path(local[pp]).read_text(encoding="utf-8")
                    if pp in local
                    else fetch(url)
                )
            except Exception as e:  # noqa: BLE001 — any network failure is a warning, never a red run
                warned.append(
                    f"{prefix}: could not read {url or pp} ({type(e).__name__}: {e})"
                )
                continue
            seen |= page_years(page, words)
        newer = sorted(y for y in seen if have and y > have)
        print(
            f"{prefix}: recorded «{s['version']}», official pages show {sorted(seen) or 'no edition year'}"
        )
        if newer:
            changed.append(
                (
                    prefix,
                    s,
                    ["the official page now names " + ", ".join(map(str, newer))],
                )
            )
    for prefix, words in BENCHMARKS.items():
        s = src.get(prefix)
        if not s:
            warned.append(f"{prefix}: not in the Sources table of frameworks.md")
            continue
        try:
            page = (
                Path(local[prefix]).read_text(encoding="utf-8")
                if prefix in local
                else fetch(s["url"])
            )
        except Exception as e:  # noqa: BLE001 — any network failure is a warning, never a red run
            warned.append(
                f"{prefix}: could not read {s['url']} ({type(e).__name__}: {e})"
            )
            continue
        found = benchmark_changes(page, s["version"], words)
        print(
            f"{prefix}: recorded «{s['version']}», {'; '.join(found) or 'unchanged on the official page'}"
        )
        if found:
            changed.append((prefix, s, found))
    lines = []
    if changed:
        lines += [
            "## Framework edition changed",
            "",
            "The monthly currency check found a newer edition than the one the control catalogue maps to:",
            "",
        ]
        for prefix, s, what in changed:
            lines.append(
                f"- **{s['name']}** (`{prefix}`): recorded `{s['version']}`; {'; '.join(what)} ({s['url']})."
            )
        lines += [
            "",
            "To do (docs/governance/REVIEW-CADENCE.md, quarterly review):",
            "",
            (
                "1. Read the new edition and add it to the Sources and Version notes of "
                "`docs/compliance/frameworks.md`."
            ),
            (
                "2. Map the changed items (a crosswalk like the 2025 to 2026 LLM one) and update `maps_to` in "
                "`docs/compliance/controls.yaml`."
            ),
            (
                "3. Regenerate the tables: `python3 files/home/.local/lib/ws_compliance.py --write-assessment`, "
                "then `bash tests/compliance.sh`."
            ),
            (
                "4. Update the ASI cross-reference in `docs/THREAT_MODEL.md` if the agentic list changed; for MCSB, "
                "re-read the control ids and titles of the new edition (PA-6 was renamed between v1 and v2)."
            ),
        ]
    for w in warned:
        print(f"::warning::{w}")
        lines.append(f"> warning: {w}")
    if not changed:
        print(
            "✔ the OWASP LLM and agentic Top 10 and MCSB editions recorded in frameworks.md are still the newest named"
        )
    if summary and lines:
        with open(summary, "a", encoding="utf-8") as fh:
            fh.write("\n".join(lines) + "\n")
    if changed:
        print("\n".join(lines))
    return 1 if changed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
