#!/usr/bin/env bash
#
# tests/supply-kit-update.sh — signed kit updates (WS-SEC-015) against a fixture remote in a temporary folder:
# ws-kit-update offers and applies only a vX.Y.Z tag signed by a key in the installed allowed_signers, refuses an
# unsigned tag, a tag signed by another key, a lightweight tag and a re-pointed tag, ignores the branch tip, accepts
# an unsigned tag only with --allow-unsigned (logged), and still rolls back when the tests fail after applying.
#
# Usage: bash tests/supply-kit-update.sh      (exit 0 = all OK; needs git >= 2.34 and ssh-keygen)
set -uo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
PASS=0 FAIL=0
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then PASS=$((PASS+1)); echo "  ok   $d"; else FAIL=$((FAIL+1)); echo "  FAIL $d"; fi; }
not()   { ! "$@"; }
command -v ssh-keygen >/dev/null || { echo "  skip: ssh-keygen missing"; exit 0; }
U="$ROOT/files/home/.local/bin/ws-kit-update"

# A git identity and config of their own: nothing from the real ~/.gitconfig, no hooks.
export HOME="$T/home" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$T/gitconfig"; mkdir -p "$HOME"; unset XDG_CONFIG_HOME
git config --global user.name ci; git config --global user.email ci@example.invalid; git config --global init.defaultBranch main
git config --global core.hooksPath /dev/null; git config --global gpg.format ssh; git config --global tag.gpgSign false
ssh-keygen -q -t ed25519 -N '' -C maintainer -f "$T/maint"; ssh-keygen -q -t ed25519 -N '' -C other -f "$T/other"
mkdir -p "$HOME/.config/ws-kit"
cp "$ROOT/files/home/.config/ws-kit/allowed_signers" "$HOME/.config/ws-kit/allowed_signers"
SIG="$HOME/.config/ws-kit/allowed_signers"
FB="$T/bin"; mkdir -p "$FB"; printf '#!/bin/sh\nexit 0\n' > "$FB/ws-test"; printf '#!/bin/sh\nexit 0\n' > "$FB/tmux"; chmod 755 "$FB"/*
export PATH="$FB:$PATH" WS_KIT="$T/clone" WS_KIT_UPDATE_LOG="$T/update.log"

# Upstream repo with v1.0.0; the clone is the user's kit.
git init -q "$T/up"; printf '#!/bin/sh\necho installed >> "$HOME/installs"\n' > "$T/up/install.sh"
git -C "$T/up" add install.sh; git -C "$T/up" commit -qm 'feat: v1'
sign() { git -C "$T/up" -c user.signingkey="$1.pub" tag -s "$2" -m "$2" "${3:-HEAD}"; }
sign "$T/maint" v1.0.0
git clone -q "$T/up" "$T/clone"
commit() { echo "$1" >> "$T/up/notes"; git -C "$T/up" add notes; git -C "$T/up" commit -qm "feat: $1"; }

echo "1) no key yet"
commit two; sign "$T/maint" v1.1.0
check "--check reports 11 when no maintainer key is installed" bash -c "'$U' --check; [[ \$? -eq 11 ]]"
check "the update is refused and nothing moves" bash -c "! '$U' --apply && [[ \$(git -C '$T/clone' describe --tags) == v1.0.0 ]]"
printf 'ci@example.invalid namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$T/maint.pub")" >> "$SIG"

echo "2) signed release"
check "--check reports 10 for a signed tag" bash -c "'$U' --check; [[ \$? -eq 10 ]]"
check "  and says it is signed" grep -q 'signed ✔' <("$U" --check)
commit tip-only   # commit after the tag: the branch tip must not be installed
check "--apply moves to the tag" "$U" --apply
check "  to the tag's commit, not the branch tip" bash -c "[[ \$(git -C '$T/clone' rev-parse HEAD) == \$(git -C '$T/up' rev-parse v1.1.0^{commit}) ]]"
check "  and ran install.sh" test -s "$HOME/installs"
check "up to date afterwards" bash -c "'$U' --check; [[ \$? -eq 0 ]]"

echo "3) refused releases"
commit three; git -C "$T/up" tag -a v1.2.0 -m unsigned
check "an unsigned annotated tag is refused" bash -c "'$U' --check; [[ \$? -eq 11 ]]"
check "  and --apply changes nothing" bash -c "! '$U' --apply && [[ \$(git -C '$T/clone' rev-parse HEAD) == \$(git -C '$T/up' rev-parse v1.1.0^{commit}) ]]"
check "  and is logged" grep -q 'refused v1.2.0' "$T/update.log"
git -C "$T/up" tag -d v1.2.0 >/dev/null; sign "$T/other" v1.2.0
check "a tag signed by a key not in allowed_signers is refused" bash -c "'$U' --check; [[ \$? -eq 11 ]]"
git -C "$T/up" tag -d v1.2.0 >/dev/null; git -C "$T/up" tag v1.2.0
check "a lightweight tag is refused" bash -c "'$U' --check; [[ \$? -eq 11 ]]"
# A validly signed tag object (v1.1.0) re-published under a newer name.
git -C "$T/up" tag -d v1.2.0 >/dev/null; commit four; sign "$T/maint" v1.1.1
git -C "$T/up" update-ref refs/tags/v1.3.0 "$(git -C "$T/up" rev-parse refs/tags/v1.1.1)"
check "a signed tag object published under another name is refused" bash -c "'$U' --check; [[ \$? -eq 11 ]]"
git -C "$T/up" tag -d v1.3.0 >/dev/null
check "a tag deleted upstream is forgotten (v1.1.1 is offered again)" grep -q 'v1.1.1, signed' <("$U" --check)

echo "4) forks and rollback"
git -C "$T/up" tag -a v1.4.0 -m unsigned
check "--allow-unsigned applies it" "$U" --apply --allow-unsigned
check "  and logs that it was unsigned" grep -q 'applied UNSIGNED v1.4.0' "$T/update.log"
commit five; sign "$T/maint" v1.5.0
before="$(git -C "$T/clone" rev-parse HEAD)"
printf '#!/bin/sh\nexit 1\n' > "$FB/ws-test"
check "a failing ws-test rolls back to the previous commit" bash -c "! '$U' --apply && [[ \$(git -C '$T/clone' rev-parse HEAD) == $before ]]"
check "  and logs the rollback" grep -q 'rolled back v1.5.0' "$T/update.log"
printf '#!/bin/sh\nexit 0\n' > "$FB/ws-test"
echo local > "$T/clone/dirty"
check "uncommitted changes in the kit stop the update" not "$U" --apply
rm -f "$T/clone/dirty"
check "every key line of the kit's allowed_signers has the git format" \
  bash -c "! grep -vE '^[[:space:]]*(#|\$)' '$ROOT/files/home/.config/ws-kit/allowed_signers' | grep -vE '^[^[:space:]]+ namespaces=\"git\" (ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+|sk-ssh-ed25519@openssh.com) [A-Za-z0-9+/=]+'"

printf '\n%d ok, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
