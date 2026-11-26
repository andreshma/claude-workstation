"""ws_mcp_policy — shared code of ws-mcp-filter and ws-mcp-tools (ADR-027: WS-AI-031, WS-AI-011, WS-AI-012).

  · the filter policy, ~/.config/ws-mcp/filter.json (the kit's, guard-protected): which tools each server may
    show and run per protection level (WS_LEVEL) and per profile (WS_PROFILE, WS_MEMORY), size caps, redaction,
    provenance stamping of memory writes and the tool-pinning mode; the owner's own rules go in filter.local.json
    next to it (Menu → Settings), which install.sh never touches: its server entries are applied after the kit's
    (they can only narrow the tools; their defaults and pinTools replace the kit's)
  · the tool-definition pins (rug-pull detection), ~/.local/share/ws-kit/mcp-tools.lock.json: per server, the
    sha256 of each tool's definition (name, title, description, input and output schema, annotations), the server's
    reported version and the kit lock identity the pins were taken under (npm package-lock, local trust sha256 or
    URL). A definition that changes while that identity stays the same is a rug pull: the filter withholds it until
    the owner approves it with `ws-mcp-tools approve NAME` in a terminal (never from Claude)
  · pending changes, ~/.local/state/ws-mcp/tools-pending/<name>.json, written by the filter, read by ws-mcp-tools

Python 3 standard library only. Every file is written 0600 in a 0700 folder, atomically, under an flock, and never
through a symbolic link.
"""

from __future__ import annotations

import contextlib
import fcntl
import fnmatch
import hashlib
import json
import os
import re
import time
from pathlib import Path

H = Path.home()
CONF = Path(os.environ.get("WS_MCP_FILTER_CONF") or H / ".config/ws-mcp/filter.json")
PINS = Path(
    os.environ.get("WS_MCP_TOOLS_LOCK") or H / ".local/share/ws-kit/mcp-tools.lock.json"
)
STATE = Path(os.environ.get("XDG_STATE_HOME") or H / ".local/state") / "ws-mcp"
PENDING = STATE / "tools-pending"
TRUST = Path(os.environ.get("WS_MCP_TRUST") or H / ".local/share/ws-kit/mcp-trust.tsv")
NPM_LOCKS = Path(os.environ.get("WS_NPM_LOCKS") or H / ".local/lib/ws-npm")
NPM_ROOT = Path(os.environ.get("WS_PINNED_ROOT") or H / ".local/share/ws-kit/npm")
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9_.-]{0,31}$")
LEVELS = ("full", "normal", "bare", "solo")
PIN_MODES = ("block", "warn", "off")

# The shapes ws-redact masks (same list as ws-mcp-keepalive; built in pieces so the kit's secret scanners do not
# mistake this file for a leak). A key=value keeps its key.
SECRETS = re.compile(
    "|".join(
        [
            r"\b(?:ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]{20,}",
            r"\bxox[abprs]-[A-Za-z0-9-]{10,}",
            r"\bsk-[A-Za-z0-9_-]{20,}",
            r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b",
            r"\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{4,}",
            r"\b[A-Za-z0-9_.-]{3}[0-9]Q~[A-Za-z0-9_~.-]{30,}",
            r"(?i:bearer|basic)\s+[A-Za-z0-9._~+/=-]{8,}",
            r"[?&](?i:sig)=[^&\s\"]+",
            r"(?<=://)[^/:@\s]+:[^@\s/]+@",
            r"-----BEGIN [A-Z ]*"
            + "PRIV"
            + r"ATE KEY-----[\s\S]*?(?:-----END [A-Z ]*"
            + "PRIV"
            + r"ATE KEY-----|$)",
            (
                r"((?i:password|passwd|pwd|secret|client_secret|token|api[_-]?key|access[_-]?key|accountkey|sharedaccesskey"
                r"|connectionstring)[\"']?\s*[:=]\s*[\"']?)[^\"'\s;,&]+"
            ),
        ]
    )
)

# The built-in policy, used when filter.json is missing or unreadable: no tool is hidden, caps and redaction on,
# pinning blocks. A broken policy file never opens more than this.
DEFAULT_POLICY: dict = {
    "version": 1,
    "defaults": {
        "maxArgBytes": 262144,
        "maxResultBytes": 2097152,
        "redactArgs": True,
        "redactResults": True,
        "pinTools": "block",
        "blockPrivate": False,
    },
    "servers": {},
}


def redact(text: str) -> tuple[str, int]:
    """Masks the recognisable secrets of a string; returns the text and how many were masked."""
    n = 0

    def sub(m: re.Match) -> str:
        nonlocal n
        n += 1
        return (m.group(1) + "***") if m.group(1) else "***"

    return SECRETS.sub(sub, text), n


def redact_tree(v, budget: list[int] | None = None):
    """Redacts every string inside a JSON value; budget[0] accumulates the count."""
    budget = budget if budget is not None else [0]
    if isinstance(v, str):
        s, n = redact(v)
        budget[0] += n
        return s
    if isinstance(v, list):
        return [redact_tree(x, budget) for x in v]
    if isinstance(v, dict):
        return {k: redact_tree(x, budget) for k, x in v.items()}
    return v


def canonical(v) -> bytes:
    return json.dumps(
        v, sort_keys=True, separators=(",", ":"), ensure_ascii=False
    ).encode()


def tool_hash(tool: dict) -> str:
    """sha256 of what a tool tells the model and accepts: name, title, description, schemas and annotations."""
    keep = {
        k: tool.get(k)
        for k in (
            "name",
            "title",
            "description",
            "inputSchema",
            "outputSchema",
            "annotations",
        )
        if k in tool
    }
    return hashlib.sha256(canonical(keep)).hexdigest()


def digest(hashes: dict) -> str:
    return hashlib.sha256(canonical(sorted(hashes.items()))).hexdigest()


def glob_any(name: str, patterns) -> bool:
    return any(fnmatch.fnmatchcase(name, p) for p in (patterns or []))


# ---------------------------------------------------------------------------------------------------- files
def _safe_dir(d: Path) -> None:
    d.mkdir(parents=True, exist_ok=True, mode=0o700)
    if d.is_symlink():
        raise OSError(f"{d} is a symbolic link")
    os.chmod(d, 0o700)


def read_json(p: Path):
    """The JSON in p, or None (missing, a link, not this user's, unreadable or invalid)."""
    try:
        fd = os.open(p, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC)
    except OSError:
        return None
    try:
        st = os.fstat(fd)
        if st.st_mode & 0o170000 != 0o100000 or st.st_uid != os.getuid():
            return None
        with os.fdopen(fd, "rb", closefd=False) as f:
            return json.loads(f.read(8 * 1024 * 1024) or b"null")
    except (OSError, ValueError):
        return None
    finally:
        os.close(fd)


def write_json(p: Path, data) -> None:
    """Atomic 0600 write (temp file in the same 0700 folder, then rename)."""
    _safe_dir(p.parent)
    tmp = p.with_name(f".{p.name}.{os.getpid()}.tmp")
    fd = os.open(
        tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600
    )
    try:
        os.write(
            fd,
            json.dumps(data, indent=1, sort_keys=True, ensure_ascii=False).encode()
            + b"\n",
        )
        os.fsync(fd)
    finally:
        os.close(fd)
    os.replace(tmp, p)


@contextlib.contextmanager
def locked(p: Path):
    """An exclusive flock on <p>.lock for the read-modify-write of p (several tabs run a filter each)."""
    _safe_dir(p.parent)
    fd = os.open(
        p.with_name(p.name + ".lock"),
        os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC,
        0o600,
    )
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        os.close(fd)


# ---------------------------------------------------------------------------------------------------- policy
def load_policy() -> tuple[dict, str]:
    """(policy, note). A missing file is the built-in policy; an invalid one too, with a note saying so."""
    if not CONF.exists():
        return DEFAULT_POLICY, ""
    p = read_json(CONF)
    if not isinstance(p, dict) or not isinstance(p.get("servers", {}), dict):
        return (
            DEFAULT_POLICY,
            f"{CONF} is not valid (or not a regular file of this user): built-in policy used",
        )
    d = dict(DEFAULT_POLICY["defaults"])
    d.update({k: v for k, v in (p.get("defaults") or {}).items() if k in d})
    note, local = "", {}
    lp = CONF.with_name("filter.local.json")
    if lp.exists():
        lo = read_json(lp)
        if isinstance(lo, dict) and isinstance(lo.get("servers", {}), dict):
            d.update({k: v for k, v in (lo.get("defaults") or {}).items() if k in d})
            local = lo.get("servers") or {}
        else:
            note = f"{lp} is not valid: ignored (the kit's policy applies)"
    return {
        "version": 1,
        "defaults": d,
        "servers": p.get("servers") or {},
        "local": local,
    }, note


def context() -> dict:
    """The tab this server serves: level (WS_LEVEL, set by tmux-level and tmux-solo), profile and memory mode."""
    lvl = os.environ.get("WS_LEVEL", "")
    prof = os.environ.get("WS_PROFILE", "")
    mem = os.environ.get("WS_MEMORY", "")
    return {
        "level": lvl if lvl in LEVELS else "default",
        "profile": prof if NAME_RE.match(prof or "-x") else "",
        "memory": mem
        if (mem in ("on", "off") or re.match(r"^wing:[A-Za-z0-9_.-]{1,64}$", mem))
        else "",
    }


def server_rules(policy: dict, name: str, ctx: dict) -> dict:
    """Effective rules of one server for this tab: defaults < server entry < level < profile. Every allow list
    that applies must match (they intersect) and every deny list adds up, so a level or a profile can only narrow
    what the server entry allows. A level without its own entry uses the server's «default» level entry."""
    d = dict(policy["defaults"])
    s = policy["servers"].get(name) or {}
    r = {
        **d,
        **{k: v for k, v in s.items() if k in d},
        "allows": [],
        "deny": [],
        "writeTools": s.get("writeTools"),
        "provenance": s.get("provenance") or {},
        "wingTools": s.get("wingTools") or [],
        "memory": bool(s.get("memory")),
    }

    def narrow(rule) -> None:
        if not isinstance(rule, dict):
            return
        if isinstance(rule.get("allow"), list):
            r["allows"].append([x for x in rule["allow"] if isinstance(x, str)])
        r["deny"] += [x for x in (rule.get("deny") or []) if isinstance(x, str)]
        for k in ("maxArgBytes", "maxResultBytes"):
            if isinstance(rule.get(k), int) and rule[k] > 0:
                r[k] = min(r[k], rule[k])

    for layer in (s, (policy.get("local") or {}).get(name) or {}):
        if not isinstance(layer, dict):
            continue
        if layer is not s:
            r.update(
                {
                    k: v
                    for k, v in layer.items()
                    if k in ("pinTools", "redactArgs", "redactResults")
                }
            )
        narrow(layer)
        levels = layer.get("levels") or {}
        narrow(
            levels.get(ctx["level"])
            if ctx["level"] in levels
            else levels.get("default")
        )
        if ctx["profile"]:
            narrow((layer.get("profiles") or {}).get(ctx["profile"]))
    if r["pinTools"] not in PIN_MODES:
        r["pinTools"] = "block"
    return r


def tool_allowed(rules: dict, tool: str) -> tuple[bool, str]:
    if glob_any(tool, rules["deny"]):
        return False, "denied for this tab by ~/.config/ws-mcp/filter.json"
    if any(not glob_any(tool, a) for a in rules["allows"]):
        return False, "not in this tab's allow list (~/.config/ws-mcp/filter.json)"
    return True, ""


# ---------------------------------------------------------------------------------------------------- lock identity
def lock_identity(name: str, real: str) -> str:
    """What the kit pinned this server's code by: a change here is an update the kit reviewed, so new tool
    definitions under a new identity are re-pinned (audited); under the same identity they are a rug pull."""
    try:
        rp = Path(real).resolve()
    except OSError:
        rp = Path(real)
    try:
        rel = rp.relative_to(NPM_ROOT.resolve())
        npm = rel.parts[0]
        lock = NPM_LOCKS / npm / "package-lock.json"
        return f"npm:{npm}:{hashlib.sha256(lock.read_bytes()).hexdigest()[:16]}"
    except (ValueError, IndexError, OSError):
        pass
    try:
        for line in TRUST.read_text(encoding="utf-8", errors="replace").splitlines():
            f = line.split("\t")
            if len(f) >= 3 and f[0] == name:
                return f"local:{f[2][:16]}"
    except OSError:
        pass
    return f"cmd:{rp}"


# ---------------------------------------------------------------------------------------------------- pins
def load_pins() -> dict:
    p = read_json(PINS)
    return (
        p
        if isinstance(p, dict) and isinstance(p.get("servers"), dict)
        else {"version": 1, "servers": {}}
    )


def compare(record: dict | None, hashes: dict) -> dict:
    """added, removed and changed tool names of a tools/list against a pinned record."""
    old = (record or {}).get("tools") or {}
    return {
        "added": sorted(set(hashes) - set(old)),
        "removed": sorted(set(old) - set(hashes)),
        "changed": sorted(k for k in hashes if k in old and old[k] != hashes[k]),
    }


def pin(
    name: str, identity: str, server_version: str, tools: list[dict], how: str
) -> dict:
    """Records (replaces) the pins of a server. Returns the record."""
    hashes = {
        t["name"]: tool_hash(t)
        for t in tools
        if isinstance(t, dict) and isinstance(t.get("name"), str)
    }
    rec = {
        "identity": identity,
        "serverVersion": server_version,
        "tools": hashes,
        "digest": digest(hashes),
        "pinned": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "how": how,
        "definitions": {
            t["name"]: t
            for t in tools
            if isinstance(t, dict) and isinstance(t.get("name"), str)
        },
    }
    with locked(PINS):
        data = load_pins()
        data["servers"][name] = rec
        write_json(PINS, data)
    return rec


def write_pending(
    name: str, identity: str, server_version: str, tools: list[dict], diff: dict
) -> bool:
    """Stores the definitions the filter withheld, for `ws-mcp-tools diff|approve`. True when this exact change was
    not pending before (so the owner is notified once, not once per tab)."""
    hashes = {
        t["name"]: tool_hash(t)
        for t in tools
        if isinstance(t, dict) and isinstance(t.get("name"), str)
    }
    p = PENDING / f"{name}.json"
    rec = {
        "identity": identity,
        "serverVersion": server_version,
        "digest": digest(hashes),
        "diff": diff,
        "seen": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "definitions": {
            t["name"]: t
            for t in tools
            if isinstance(t, dict) and isinstance(t.get("name"), str)
        },
    }
    with locked(p):
        old = read_json(p)
        new = not (isinstance(old, dict) and old.get("digest") == rec["digest"])
        write_json(p, rec)
    return new
