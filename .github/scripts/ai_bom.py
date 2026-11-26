#!/usr/bin/env python3
"""ai_bom.py — regenerates the inventory tables of docs/governance/AI-BOM.md from the files they describe (WS-GOV-002).

The generated tables sit between «<!-- ai-bom:begin NAME -->» and «<!-- ai-bom:end NAME -->»; everything else in the
document (data, risk, upstream, retention) is written by hand. Sources:
  models   files/home/.claude/settings.json (.model, .fallbackModel, .modelSettings), the agents' front matter,
           files/home/.local/lib/ws-routing.sh (routing_model) and the model names the kit scripts pass to Claude
  agents   files/home/.claude/agents/*.md front matter (model, effort, tools, disallowedTools)
  mcp      files/mcp-servers.json, files/mcp-servers.lock.json and the always-ask rules in settings.json
  tools    files/home/.local/lib/ws-npm/*/package.json (npm packages installed with ws-pinned)
  hooks    .hooks in settings.json (event, matcher, script and what it wraps, timeout)
  plugins  .enabledPlugins and .extraKnownMarketplaces in settings.json
--check also fails when a generated row has no hand-written entry in its section (its key in backticks), so a
model, server, tool or hook added without its data and risk is caught.

Usage: python3 .github/scripts/ai_bom.py --check [--root DIR]    exit 1 when AI-BOM.md is out of date
       python3 .github/scripts/ai_bom.py --write [--root DIR]    rewrites the generated tables
       python3 .github/scripts/ai_bom.py --print NAME            prints one generated table
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

SCRIPT_DIRS = (
    "files/home/.local/bin",
    "files/home/.config/tmux-claude",
    "files/home/.claude/hooks",
    "files/home/.local/lib",
)
SKIP_SCRIPTS = {"ws-test"}  # test fixtures, not models the kit uses
MODEL_RE = re.compile(r"^(claude-[a-z0-9-]+|opus|sonnet|haiku|fable)$")
SECTION = {
    "models": "Models",
    "agents": "Agents",
    "mcp": "MCP servers",
    "tools": "Agent tools",
    "hooks": "Hooks",
    "plugins": "Instructions, plugins and skills",
}
MARK = re.compile(
    r"(<!-- ai-bom:begin (\w+) -->\n)(.*?)(<!-- ai-bom:end \2 -->)", re.DOTALL
)


def row(cells) -> str:
    return "| " + " | ".join(str(c).replace("|", "\\|") for c in cells) + " |"


def front_matter(p: Path) -> dict:
    t = p.read_text(encoding="utf-8")
    m = re.match(r"^---\n(.*?)\n---", t, re.DOTALL)
    out = {}
    for line in m.group(1).splitlines() if m else []:
        k, _, v = line.partition(":")
        if v:
            out[k.strip()] = v.strip()
    return out


def load(root: Path) -> dict:
    s = json.loads(
        (root / "files/home/.claude/settings.json").read_text(encoding="utf-8")
    )
    mcp = json.loads((root / "files/mcp-servers.json").read_text(encoding="utf-8"))
    lock = json.loads(
        (root / "files/mcp-servers.lock.json").read_text(encoding="utf-8")
    ).get("servers", {})
    agents = {
        p.stem: front_matter(p)
        for p in sorted((root / "files/home/.claude/agents").glob("*.md"))
    }
    return {
        "settings": s,
        "mcp": mcp.get("mcpServers", mcp),
        "lock": lock,
        "agents": agents,
    }


def script_models(root: Path) -> dict[str, set[str]]:
    pats = [
        re.compile(r"--model[ =]([a-z][a-z0-9-]+)"),
        re.compile(r'"--model",\s*"([a-z0-9-]+)"'),
        re.compile(r"_MODEL:-([a-z0-9-]+)"),
        re.compile(r'"model":\s*"(claude-[a-z0-9-]+)"'),
    ]
    out: dict[str, set[str]] = {}
    for d in SCRIPT_DIRS:
        for f in sorted((root / d).glob("*")):
            if (
                not f.is_file()
                or f.name in SKIP_SCRIPTS
                or f.suffix in (".json", ".txt", ".tmux", ".conf")
            ):
                continue
            try:
                t = f.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            for p in pats:
                for m in p.findall(t):
                    if MODEL_RE.match(m):
                        out.setdefault(m, set()).add(f.name)
    return out


def t_models(root: Path, d: dict) -> list[str]:
    s = d["settings"]
    where: dict[str, list[str]] = {}

    def add(m, w):
        where.setdefault(m, []).append(w)

    if s.get("model"):
        add(s["model"], "`settings.json` `.model` (default)")
    for i, m in enumerate(s.get("fallbackModel") or []):
        add(m, f"`.fallbackModel[{i}]`")
    for m, v in (s.get("modelSettings") or {}).items():
        add(m, "`.modelSettings` (" + ", ".join(f"{k} {x}" for k, x in v.items()) + ")")
    for a, fm in d["agents"].items():
        if fm.get("model"):
            add(fm["model"], f"agent `{a}`")
    rt = (root / "files/home/.local/lib/ws-routing.sh").read_text(encoding="utf-8")
    for lvl, m in re.findall(r"(\w+)\) echo (claude-[a-z0-9-]+)", rt):
        add(m, f"routing level `{lvl}`")
    for m, files in sorted(script_models(root).items()):
        add(m, "scripts " + ", ".join(f"`{f}`" for f in sorted(files)))
    out = ["| Model | Set in |", "|---|---|"]
    for m in sorted(where, key=lambda x: (not x.startswith("claude-"), x)):
        out.append(row([f"`{m}`", "; ".join(where[m])]))
    return out


def t_agents(root: Path, d: dict) -> list[str]:
    out = ["| Agent | Model | Effort | Tool limits |", "|---|---|---|---|"]
    for a, fm in d["agents"].items():
        lim = "; ".join(
            f"`{k}: {fm[k]}`" for k in ("tools", "disallowedTools") if fm.get(k)
        )
        lim = lim or "None (inherits the session)"
        out.append(
            row([f"`{a}`", f"`{fm.get('model', '-')}`", fm.get("effort", "-"), lim])
        )
    return out


def pin_of(name: str, lock: dict) -> tuple[str, str]:
    e = lock.get(name)
    if not e:
        return "Not in the lock (install.sh skips it)", "-"
    src = e.get("source")
    if src == "npm":
        p = f"`{e.get('package')}@{e.get('version')}`, npm sha512 in the lock"
        if e.get("prerelease"):
            p += " (prerelease)"
    elif src == "local":
        p = "sha256 pinned on first registration (`~/.local/share/ws-kit/mcp-trust.tsv`)"
    elif src == "remote":
        p = "URL only (server side)"
    else:
        p = str(src)
    return p, "Yes" if e.get("optIn") else "No"


def t_mcp(root: Path, d: dict) -> list[str]:
    ask = d["settings"].get("permissions", {}).get("ask", [])
    out = [
        "| Server | Transport | Command or URL | Pin | Opt-in | Confinement | Always-ask rules |",
        "|---|---|---|---|---|---|---|",
    ]
    for n, v in d["mcp"].items():
        if not isinstance(v, dict):
            continue
        target = v.get("url") or " ".join(
            [v.get("command", "")] + list(v.get("args") or [])
        )
        pin, opt = pin_of(n, d["lock"])
        nask = sum(1 for r in ask if r.startswith(f"mcp__{n}__"))
        jail = v.get("jail")
        if v.get("type") == "http":
            conf = "remote (runs at the provider)"
        elif isinstance(jail, dict):
            conf = "ws-mcp-jail" + (", network" if jail.get("net") else ", no network")
            conf += ", own Azure config" if jail.get("azureConfig") else ""
        else:
            why = str(v.get("jailOptOut") or "no reason given").split(":")[0]
            conf = f"not confined ({why})"
        out.append(
            row(
                [
                    f"`{n}`",
                    v.get("type", "stdio"),
                    f"`{target.strip()}`",
                    pin,
                    opt,
                    conf,
                    nask,
                ]
            )
        )
    return out


def t_tools(root: Path, d: dict) -> list[str]:
    used = {e.get("npm"): n for n, e in d["lock"].items() if e.get("npm")}
    out = [
        "| Package folder | Package and version | Lock | Used as |",
        "|---|---|---|---|",
    ]
    for p in sorted((root / "files/home/.local/lib/ws-npm").glob("*/package.json")):
        deps = json.loads(p.read_text(encoding="utf-8")).get("dependencies", {})
        pv = ", ".join(f"`{k}@{v}`" for k, v in deps.items())
        lock = p.parent / "package-lock.json"
        rel = lock.relative_to(root).as_posix() if lock.is_file() else "missing"
        out.append(
            row(
                [
                    f"`{p.parent.name}`",
                    pv,
                    f"`{rel}`",
                    f"MCP server `{used[p.parent.name]}`"
                    if p.parent.name in used
                    else "CLI tool",
                ]
            )
        )
    return out


def hook_label(h: dict) -> str:
    """The hook script and what it wraps: «memory-filter.sh → win-hook.sh → mempalace.exe»."""
    cmd = str(h.get("command", "")).split()
    chain = [Path(cmd[0].replace("\\", "/")).name] if cmd else ["?"]
    for a in list(cmd[1:]) + [str(x) for x in h.get("args") or []]:
        if re.search(r"[/\\]|\.(exe|sh|py|ps1)$", a):
            chain.append(Path(a.replace("\\", "/")).name)
        if len(chain) == 4:
            break
    return " → ".join(f"`{c}`" for c in chain)


def t_hooks(root: Path, d: dict) -> list[str]:
    seen: dict[str, dict] = {}
    for ev, groups in (d["settings"].get("hooks") or {}).items():
        for g in groups:
            m = g.get("matcher")
            for h in g.get("hooks", []):
                e = seen.setdefault(
                    hook_label(h),
                    {"events": [], "if": [], "timeout": set(), "fail": ""},
                )
                where = ev + (f" (`{m}`)" if m else "")
                if where not in e["events"]:
                    e["events"].append(where)
                if h.get("if"):
                    e["if"].append(re.sub(r"^Bash\((.*?)( \*)?\)$", r"\1", h["if"]))
                if h.get("timeout"):
                    e["timeout"].add(str(h["timeout"]))
                if h.get("onFailure"):
                    e["fail"] = f"; onFailure `{h['onFailure']}`"
    out = ["| Hook | Events (matcher) | Timeout (s) |", "|---|---|---|"]
    for lab, e in sorted(seen.items()):
        ev = (
            e["events"]
            if len(e["events"]) <= 4
            else sorted({x.split(" ")[0] for x in e["events"]})
        )
        txt = "; ".join(ev) + (
            " if the command starts with " + ", ".join(f"`{x}`" for x in e["if"])
            if e["if"]
            else ""
        )
        out.append(
            row([lab, txt + e["fail"], ", ".join(sorted(e["timeout"], key=int)) or "-"])
        )
    return out


def t_plugins(root: Path, d: dict) -> list[str]:
    s = d["settings"]
    out = ["| Plugin or marketplace | Setting | Value |", "|---|---|---|"]
    for k, v in (s.get("enabledPlugins") or {}).items():
        out.append(row([f"`{k}`", "`enabledPlugins`", "enabled" if v else "disabled"]))
    for k, v in (s.get("extraKnownMarketplaces") or {}).items():
        out.append(row([f"`{k}`", "`extraKnownMarketplaces`", json.dumps(v)[:80]]))
    if len(out) == 2:
        out.append(row(["None", "-", "-"]))
    return out


TABLES = {
    "models": t_models,
    "agents": t_agents,
    "mcp": t_mcp,
    "tools": t_tools,
    "hooks": t_hooks,
    "plugins": t_plugins,
}


def keys(lines: list[str]) -> list[str]:
    """First backticked word of each data row: the key a hand-written entry must mention."""
    out = []
    for line in lines[2:]:
        m = re.match(r"^\| `([^`]+)`", line)
        if m:
            out.append(m.group(1))
    return out


def render(text: str, root: Path) -> tuple[str, list[str]]:
    d = load(root)
    missing: list[str] = []
    found = set()

    def sub(m: re.Match) -> str:
        name = m.group(2)
        if name not in TABLES:
            return m.group(0)
        found.add(name)
        return m.group(1) + "\n".join(TABLES[name](root, d)) + "\n" + m.group(4)

    new = MARK.sub(sub, text)
    for name in TABLES:
        if name not in found:
            missing.append(f"no «ai-bom:begin {name}» block in AI-BOM.md")
    # Hand-written coverage: every generated key appears in backticks in its section, outside the generated block.
    for name, fn in TABLES.items():
        sec = re.search(
            rf"^## {re.escape(SECTION[name])}\n(.*?)(?=^## |\Z)",
            new,
            re.DOTALL | re.MULTILINE,
        )
        if not sec:
            missing.append(f"no «## {SECTION[name]}» section")
            continue
        hand = MARK.sub("", sec.group(1))
        for k in keys(fn(root, d)):
            if k != "None" and f"`{k}`" not in hand:
                missing.append(
                    f"{SECTION[name]}: `{k}` has no hand-written entry (data and risk)"
                )
    return new, missing


def main(argv: list[str]) -> int:
    root = (
        Path(argv[argv.index("--root") + 1])
        if "--root" in argv
        else Path(__file__).resolve().parents[2]
    )
    doc = root / "docs/governance/AI-BOM.md"
    if "--print" in argv:
        name = argv[argv.index("--print") + 1]
        print("\n".join(TABLES[name](root, load(root))))
        return 0
    text = doc.read_text(encoding="utf-8")
    new, missing = render(text, root)
    if "--write" in argv:
        doc.write_text(new, encoding="utf-8")
        print(f"✔ {doc.relative_to(root)} regenerated")
    elif "--check" in argv:
        if new != text:
            import difflib

            sys.stdout.writelines(
                difflib.unified_diff(
                    text.splitlines(True),
                    new.splitlines(True),
                    "committed",
                    "generated",
                    n=0,
                )
            )
            print(
                "✖ docs/governance/AI-BOM.md is out of date: python3 .github/scripts/ai_bom.py --write"
            )
            missing.append("stale")
        else:
            print("✔ the AI-BOM tables match the files they describe")
    else:
        print(__doc__)
        return 2
    for m in missing:
        if m != "stale":
            print(f"✖ {m}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
