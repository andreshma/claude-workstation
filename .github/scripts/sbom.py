#!/usr/bin/env python3
"""sbom.py — CycloneDX 1.5 SBOM of the third-party components the claude-workstation kit installs or calls.

Usage:
    python3 .github/scripts/sbom.py [--root DIR] [-o FILE]   writes the SBOM (stdout by default)
    python3 .github/scripts/sbom.py --check FILE             validates an SBOM's structure; exit 1 on errors

Sources (WS-SEC-018): files/mcp-servers.lock.json and the committed package-lock.json files (npm packages with
their sha512), files/mcp-servers.json (remote MCP servers as services), the TOOLS table of ws-tools (what
`ws-tools install` brings in and from where), the tmux plugins of files/home/.tmux.conf, the GitHub Actions pinned
in .github/workflows and the CI tools pinned by version there. Python 3 standard library only.
"""

import argparse
import base64
import json
import re
import sys
import uuid
from datetime import UTC, datetime
from pathlib import Path
from urllib.parse import quote

SPEC = "1.5"


def npm_purl(name, version):
    """Package URL of an npm package (scope encoded as %40)."""
    return "pkg:npm/" + quote(name, safe="/") + "@" + quote(version, safe="")


def sri_hashes(integrity):
    """CycloneDX hashes from an npm Subresource Integrity string (sha512-<base64>)."""
    out = []
    for part in (integrity or "").split():
        alg, _, b64 = part.partition("-")
        name = {
            "sha512": "SHA-512",
            "sha384": "SHA-384",
            "sha256": "SHA-256",
            "sha1": "SHA-1",
        }.get(alg)
        if name and b64:
            out.append({"alg": name, "content": base64.b64decode(b64).hex()})
    return out


def prop(name, value):
    return {"name": "ws:" + name, "value": str(value)}


def kit_version(root):
    m = re.search(
        r"^version:\s*([0-9][^\s]*)",
        (root / "CITATION.cff").read_text(encoding="utf-8"),
        re.MULTILINE,
    )
    return m.group(1) if m else "unknown"


def npm_components(root):
    """Every package of every pinned package-lock.json, tagged with what the kit uses it for."""
    lock = json.loads(
        (root / "files/mcp-servers.lock.json").read_text(encoding="utf-8")
    )
    roles = {}
    for kind in ("servers", "tools"):
        for key, entry in lock.get(kind, {}).items():
            if entry.get("source") == "npm":
                roles[entry["npm"]] = (kind[:-1], key, entry)
    comps = []
    for pl in sorted(
        (root / "files/home/.local/lib/ws-npm").glob("*/package-lock.json")
    ):
        data = json.loads(pl.read_text(encoding="utf-8"))
        role = roles.get(pl.parent.name)
        for path, pkg in sorted(data.get("packages", {}).items()):
            if not path:
                continue
            name = path.split("node_modules/")[-1]
            c = {
                "type": "library",
                "bom-ref": npm_purl(name, pkg["version"]),
                "name": name,
                "version": pkg["version"],
                "purl": npm_purl(name, pkg["version"]),
                "hashes": sri_hashes(pkg.get("integrity")),
                "properties": [
                    prop("lock", str(pl.relative_to(root))),
                    prop("optional", pkg.get("optional", False)),
                ],
            }
            if pkg.get("license"):
                c["licenses"] = [{"expression": pkg["license"]}]
            if role:
                c["properties"].append(prop("role", f"{role[0]}:{role[1]}"))
                if role[2].get("optIn"):
                    c["properties"].append(prop("optIn", True))
            comps.append(c)
    return comps


def local_and_remote(root):
    lock = json.loads(
        (root / "files/mcp-servers.lock.json").read_text(encoding="utf-8")
    )
    servers = json.loads((root / "files/mcp-servers.json").read_text(encoding="utf-8"))
    comps, services = [], []
    for key, entry in sorted(lock.get("servers", {}).items()):
        if entry.get("source") == "local":
            comps.append(
                {
                    "type": "application",
                    "bom-ref": "local:" + key,
                    "name": key,
                    "properties": [
                        prop("role", "server:" + key),
                        prop("trust", entry.get("trust", "")),
                        prop("command", servers.get(key, {}).get("command", "")),
                    ],
                }
            )
        elif entry.get("source") == "remote":
            services.append(
                {
                    "bom-ref": "service:" + key,
                    "name": key,
                    "endpoints": [entry["url"]],
                    "authenticated": False,
                    "x-trust-boundary": True,
                }
            )
    return comps, services


def ws_tools(root):
    """The TOOLS table of ws-tools: name|group|version command|how to install."""
    text = (root / "files/home/.local/bin/ws-tools").read_text(encoding="utf-8")
    # Pins of ws-tools.lock: name version source asset sha256 sig (WS-SEC-016).
    pins = {}
    lock = root / "files/home/.local/lib/ws-tools.lock"
    if lock.is_file():
        for line in lock.read_text(encoding="utf-8").splitlines():
            f = line.split()
            if len(f) >= 6 and not line.lstrip().startswith("#"):
                pins[f[0]] = f
    comps = []
    for name, group, _cmd, how in re.findall(
        r'^\s+"([^|"]+)\|([^|"]+)\|([^|"]*)\|([^"]+)"$', text, re.MULTILINE
    ):
        source, _, what = how.partition(":")
        c = {
            "type": "application",
            "bom-ref": "ws-tools:" + name,
            "name": name,
            "properties": [
                prop("group", group),
                prop("install", source),
                prop("from", what),
            ],
        }
        if source == "apt":
            c["purl"] = "pkg:deb/ubuntu/" + quote(what, safe="")
        elif source == "pipx":
            c["purl"] = "pkg:pypi/" + quote(re.sub(r"\[.*\]$", "", what), safe="")
        if name in pins:
            _, ver, src, _asset, sha, sig = pins[name][:6]
            c["version"] = ver
            c["properties"] += [
                prop("pinnedIn", "ws-tools.lock"),
                prop("signature", sig),
            ]
            if re.fullmatch(r"[0-9a-f]{64}", sha):
                c["hashes"] = [{"alg": "SHA-256", "content": sha}]
            if src.startswith("pypi:"):
                c["purl"] = f"pkg:pypi/{quote(src[5:], safe='')}@{ver}"
            elif src.startswith("github:"):
                c["purl"] = f"pkg:github/{src[7:]}@{ver}"
        c["bom-ref"] = "ws-tools:" + name
        comps.append(c)
    return comps


def tmux_plugins(root):
    """The @plugin lines of .tmux.conf, with the commit plugins.lock pins each one to (WS-SEC-016)."""
    text = (root / "files/home/.tmux.conf").read_text(encoding="utf-8")
    pins = {}
    lock = root / "files/home/.config/tmux-claude/plugins.lock"
    if lock.is_file():
        for line in lock.read_text(encoding="utf-8").splitlines():
            f = line.split()
            if len(f) >= 3 and not line.lstrip().startswith("#"):
                pins[f[0]] = f[2]
    comps = []
    for p in sorted(set(re.findall(r"^set -g @plugin '([^']+)'", text, re.MULTILINE))):
        commit = pins.get(p.split("/")[-1])
        c = {
            "type": "library",
            "bom-ref": "pkg:github/" + p,
            "name": p,
            "purl": "pkg:github/" + p + (f"@{commit}" if commit else ""),
            "properties": [
                prop("installedBy", "ws-plugins"),
                prop("pinned", bool(commit)),
            ],
        }
        if commit:
            c["version"] = commit
            c["hashes"] = [{"alg": "SHA-1", "content": commit}]
        comps.append(c)
    return comps


def ci_components(root):
    comps, seen = [], set()
    for wf in sorted((root / ".github/workflows").glob("*.yml")):
        text = wf.read_text(encoding="utf-8")
        for action, sha, ver in re.findall(
            r"uses:\s*([\w.-]+/[\w.-]+)(?:/[\w./-]+)?@([0-9a-f]{40})\s*#\s*(\S+)", text
        ):
            ref = f"pkg:github/{action}@{ver}"
            if ref in seen:
                continue
            seen.add(ref)
            comps.append(
                {
                    "type": "application",
                    "bom-ref": ref,
                    "name": action,
                    "version": ver,
                    "purl": ref,
                    "hashes": [{"alg": "SHA-1", "content": sha}],
                    "properties": [prop("scope", "ci")],
                }
            )
        for tool, ver in re.findall(
            r"^\s+([A-Z]+)_VERSION:\s*([0-9][\w.]*)", text, re.MULTILINE
        ):
            ref = f"ci:{tool.lower()}@{ver}"
            if ref in seen:
                continue
            seen.add(ref)
            comps.append(
                {
                    "type": "application",
                    "bom-ref": ref,
                    "name": tool.lower(),
                    "version": ver,
                    "properties": [prop("scope", "ci"), prop("workflow", wf.name)],
                }
            )
    return comps


def build(root):
    npm = npm_components(root)
    local, services = local_and_remote(root)
    comps = npm + local + ws_tools(root) + tmux_plugins(root) + ci_components(root)
    version = kit_version(root)
    return {
        "bomFormat": "CycloneDX",
        "specVersion": SPEC,
        "serialNumber": "urn:uuid:" + str(uuid.uuid4()),
        "version": 1,
        "metadata": {
            "timestamp": datetime.now(UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "tools": {
                "components": [
                    {"type": "application", "name": "sbom.py", "version": version}
                ]
            },
            "component": {
                "type": "application",
                "bom-ref": "pkg:github/andreshma/claude-workstation@" + version,
                "name": "claude-workstation",
                "version": version,
                "purl": "pkg:github/andreshma/claude-workstation@" + version,
                "licenses": [{"license": {"id": "Apache-2.0"}}],
            },
        },
        "components": comps,
        "services": services,
        "dependencies": [
            {
                "ref": "pkg:github/andreshma/claude-workstation@" + version,
                "dependsOn": [c["bom-ref"] for c in comps],
            }
        ],
    }


def check(doc):
    """Structural validation of the parts of CycloneDX 1.5 this generator uses. Returns a list of errors."""
    errs = []
    if doc.get("bomFormat") != "CycloneDX":
        errs.append("bomFormat must be CycloneDX")
    if doc.get("specVersion") not in ("1.4", "1.5", "1.6"):
        errs.append("unsupported specVersion")
    if not re.fullmatch(r"urn:uuid:[0-9a-f-]{36}", doc.get("serialNumber", "")):
        errs.append("serialNumber must be urn:uuid:<uuid>")
    refs = set()
    for i, c in enumerate(doc.get("components", [])):
        where = f"components[{i}] ({c.get('name')})"
        if c.get("type") not in (
            "application",
            "library",
            "framework",
            "container",
            "file",
            "firmware",
        ):
            errs.append(where + ": bad type")
        if not c.get("name"):
            errs.append(where + ": missing name")
        ref = c.get("bom-ref")
        if not ref or ref in refs:
            errs.append(where + ": missing or duplicate bom-ref")
        refs.add(ref)
        if "purl" in c and not re.fullmatch(r"pkg:[a-z]+/[^\s]+", c["purl"]):
            errs.append(where + ": bad purl")
        for h in c.get("hashes", []):
            n = {"SHA-1": 40, "SHA-256": 64, "SHA-384": 96, "SHA-512": 128}.get(
                h.get("alg")
            )
            if not n or not re.fullmatch(f"[0-9a-f]{{{n}}}", h.get("content", "")):
                errs.append(where + ": bad hash")
    for s in doc.get("services", []):
        if not s.get("name") or not s.get("bom-ref") or s["bom-ref"] in refs:
            errs.append("service {}: missing name or bom-ref".format(s.get("name")))
        refs.add(s.get("bom-ref"))
    top = doc.get("metadata", {}).get("component", {}).get("bom-ref")
    for d in doc.get("dependencies", []):
        for r in [d.get("ref")] + d.get("dependsOn", []):
            if r not in refs and r != top:
                errs.append(f"dependency on an unknown bom-ref: {r}")
    if not any(
        c.get("purl", "").startswith("pkg:npm/") and c.get("hashes")
        for c in doc.get("components", [])
    ):
        errs.append("no npm component with its integrity hash")
    return errs


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--root", default=str(Path(__file__).resolve().parents[2]))
    ap.add_argument("-o", "--output")
    ap.add_argument("--check", metavar="FILE")
    a = ap.parse_args()
    if a.check:
        errs = check(json.loads(Path(a.check).read_text(encoding="utf-8")))
        for e in errs:
            print("sbom: " + e, file=sys.stderr)
        print("sbom: " + ("ok" if not errs else f"{len(errs)} errors"))
        return 1 if errs else 0
    doc = build(Path(a.root))
    text = json.dumps(doc, indent=2) + "\n"
    if a.output:
        Path(a.output).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
