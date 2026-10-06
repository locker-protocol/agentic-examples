#!/usr/bin/env bash
# Runs every recipe's check.sh, one after another, and exits 1 if any of them
# failed. Each one works in a throwaway LPA_HOME it removes itself: your own
# ~/.lpa is never read or written, and no real order is ever placed.
#
#   LPA_BIN               the lpa command (default: lpa on the PATH)
#   LOCKER_MCP_BIN        the MCP server command line
#   LOCKER_MONOREPO       a checkout, for sdk-node-bot
#   LOCKER_PACKAGES_DIR   a folder of .tgz tarballs, for sdk-node-bot
#
# One recipe on its own: cd <recipe> && ./check.sh

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"

RECIPES="
claude-code-first-trade
mcp-claude-desktop
mcp-cursor
sdk-node-bot
vault-setup
paper-replay
range-scalping-paper
counterfactual-review
openclaw
hermes
plugin-funding
"

FAILED=""
PASSED=""
START=$(date +%s)

for recipe in $RECIPES; do
    script="$HERE/$recipe/check.sh"
    if [ ! -x "$script" ]; then
        printf '\n=== %s ===\n' "$recipe"
        printf 'FAIL - %s/check.sh is missing or not executable\n' "$recipe"
        FAILED="$FAILED $recipe"
        continue
    fi
    printf '\n=== %s ===\n' "$recipe"
    began=$(date +%s)
    if (cd "$HERE/$recipe" && ./check.sh); then
        PASSED="$PASSED $recipe"
        printf '%s: passed in %s s\n' "$recipe" "$(( $(date +%s) - began ))"
    else
        FAILED="$FAILED $recipe"
        printf '%s: FAILED in %s s\n' "$recipe" "$(( $(date +%s) - began ))"
    fi
done

count() { set -- $1; echo "$#"; }

printf '\n=== summary ===\n'
printf 'passed (%s):%s\n' "$(count "$PASSED")" "${PASSED:- none}"
if [ -n "$FAILED" ]; then
    printf 'FAILED (%s):%s\n' "$(count "$FAILED")" "$FAILED"
fi
printf 'total %s s\n' "$(( $(date +%s) - START ))"

[ -z "$FAILED" ]
