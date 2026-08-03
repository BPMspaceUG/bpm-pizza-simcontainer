#!/usr/bin/env bash
# 07-env-count.sh
# Regression coverage for check_env()'s "N entries in ~/.env" line (#15).
#
# check_env() is extracted verbatim out of update.sh (pattern-anchored sed,
# not a line-number slice, so it survives edits elsewhere in the file) and
# run in isolation against disposable HOME/.env fixtures. No apt, no sudo,
# no network, no root-owned STATE_FILE - update.sh itself is never executed.
set -uo pipefail
cd "$(dirname "$0")" && . ./lib.sh

TEST_NAME="07-env-count"
header "check_env() entry counting"

REPO="$(cd "$(dirname "$0")/.." && pwd)"
step() { :; }                          # stub: check_env()'s only external call
eval "$(sed -n '/^check_env() {/,/^}/p' "$REPO/update.sh")"
type check_env >/dev/null 2>&1 || fail "extraction failed" \
    "check_env() no longer matches the sed pattern - has update.sh's shape changed?"

SCRATCH_HOME="$(mktemp -d)"
export HOME="$SCRATCH_HOME"
trap 'rm -rf "$SCRATCH_HOME"' EXIT

expect_entries() {
    STATE_FILE="/nonexistent/env-source"
    if [ "$1" = "__ABSENT__" ]; then
        rm -f "$HOME/.env"
    else
        printf '%s' "$1" > "$HOME/.env"
    fi
    out=$(check_env)
    printf '%s' "$out" | grep -q "^  $2 entries in ~/.env\$" \
        || fail "$3: expected $2 entries" "got: $(printf '%s' "$out" | head -n1)"
}

expect_entries "__ABSENT__" 0 "TC1 absent .env"
expect_entries "" 0 "TC2 empty .env"
expect_entries \
'LITELLM_PIZZA_URL=https://gateway.example
LITELLM_PIZZA_KEY=sk-abc123
CLAUDE_MODEL=claude-sonnet' \
3 "TC3 three well-formed entries"
expect_entries \
'LITELLM_PIZZA_URL=https://gateway.example
BARE_EMPTY=' \
1 "TC4 bare-empty KEY="
expect_entries \
'LITELLM_PIZZA_URL=https://gateway.example
QUOTED_EMPTY=""' \
1 'TC5 quoted-empty KEY=""'
expect_entries \
'  LITELLM_PIZZA_URL=https://gateway.example' \
1 "TC6 leading-whitespace entry"
expect_entries \
'# LITELLM_PIZZA_URL=https://gateway.example' \
0 "TC7 comment-only line"
expect_entries \
'# comment line with a KEY=value shape
LITELLM_PIZZA_URL=https://gateway.example
LITELLM_PIZZA_KEY=sk-abc123
BARE_EMPTY=
QUOTED_EMPTY=""
  INDENTED=val
' \
3 "TC8 mixed file"

printf 'LITELLM_PIZZA_URL=https://gateway.example\n' > "$HOME/.env"
STATE_TMP="$SCRATCH_HOME/state"
printf 'https://cdn.example/pizza.env\nsecond line must not appear\n' > "$STATE_TMP"
STATE_FILE="$STATE_TMP"
out=$(check_env)
printf '%s' "$out" | grep -q '^  source: https://cdn.example/pizza.env$' \
    || fail "TC9 STATE_FILE present" "got: $out"
printf '%s' "$out" | grep -q 'second line must not appear' \
    && fail "TC9 STATE_FILE present" "head -n1 leaked a second line: $out"

STATE_FILE="/nonexistent/env-source"
out=$(check_env)
printf '%s' "$out" | grep -q '^  no source remembered - pass --url once$' \
    || fail "TC10 STATE_FILE absent" "got: $out"

pass "10/10 check_env() fixtures correct"
