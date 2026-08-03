#!/usr/bin/env bash
# explorer.exe reachable via PATH, and python3/node/git resolve to the Linux
# tools, not shadowed by the Windows PATH (appendWindowsPath must stay false).
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh

TEST_NAME="06-windows-interop"
header "Windows interop and appendWindowsPath=false"

# --- Linux tooling must win, never a /mnt/* shadow --------------------------
for c in python3 node git; do
    p=$(command -v "$c") || fail "$c not found on PATH"
    case "$p" in
        /mnt/*) fail "$c resolved to $p" \
                "appendWindowsPath must stay false in /etc/wsl.conf - a Windows $c is shadowing the Linux one." ;;
    esac
    printf '  %-8s %s\n' "$c" "$p"
done

# --- explorer.exe: only meaningful inside a real WSL session ----------------
if [ ! -d /mnt/c/Windows ]; then
    note "no /mnt/c/Windows - not a WSL session, skipping the explorer.exe check"
    pass "Linux tooling not shadowed (explorer.exe unverifiable outside WSL)"
fi

p=$(command -v explorer.exe) || fail "explorer.exe not found on PATH" \
    "Check [automount] in /etc/wsl.conf - it provides /mnt/c."
[ -e /usr/local/bin/explorer.exe ] || fail "explorer.exe: No such file or directory" \
    "Check [automount] in /etc/wsl.conf - it provides /mnt/c."
printf '  %-8s %s\n' "explorer.exe" "$p"

# Deliberately never executed: running it here would pop a GUI window on the
# trainer's desktop during an automated run.

pass "explorer.exe on PATH, Linux tooling not shadowed"
