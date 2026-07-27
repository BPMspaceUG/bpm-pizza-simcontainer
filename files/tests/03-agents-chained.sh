#!/usr/bin/env bash
# The complex one: Claude translates, calls Codex through the Bash tool, and
# reports back. Covers both agents, Claude's tool execution and agent-to-agent
# invocation in a single run - which several exercises depend on.
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh

TEST_NAME="03-agents-chained"
header "Claude calls Codex"

require_gateway

read -r -d '' PROMPT <<'EOP' || true
Übersetze den Satz "Das Pferd frisst keinen Gurkensalat" ins Chinesische.
Führe danach mit dem Bash-Tool genau diesen Befehl aus und ersetze dabei UEBERSETZUNG durch dein Ergebnis:
codex exec --skip-git-repo-check --sandbox read-only "Hier ist eine chinesische Uebersetzung von: Das Pferd frisst keinen Gurkensalat. Uebersetzung: UEBERSETZUNG. Uebersetze sie woertlich zurueck ins Deutsche und kritisiere sie in zwei Saetzen. Antworte auf Deutsch."
Gib zum Schluss aus: 1) deine chinesische Übersetzung, 2) die vollständige Antwort von Codex.
EOP

note "this takes 30-60 seconds"
out=$(claude --dangerously-skip-permissions -p "$PROMPT" 2>&1)
printf '%s\n' "$out" | sed 's/^/  /'

# Han characters prove Claude produced the translation.
printf '%s' "$out" | grep -qP '[\x{4e00}-\x{9fff}]' \
    || fail "no Chinese characters in the output - Claude did not translate"

# A German back-translation proves Codex ran and its answer came back.
printf '%s' "$out" | grep -qi 'pferd' \
    || fail "no back-translation - Codex probably never ran" \
            "Run 02-codex.sh to check Codex on its own."

pass "both agents, Bash tool and agent-to-agent call work"
