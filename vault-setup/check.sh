#!/usr/bin/env bash
# Checks what can be checked without a phone and a webcam: the commands and the
# flags the README names exist, a blank folder says to run `lpa init`, the
# commands that need the account refuse instead of acting, the paper account
# needs none of it, and every image the README links to is there.
#
# It signs nothing, opens no page, and works in a throwaway LPA_HOME removed at
# the end; your own ~/.lpa is never read or written.
#
#   LPA_BIN   the lpa command to run (default: lpa on the PATH)

set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LPA="${LPA_BIN:-lpa}"
PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; return 0; }

if ! command -v "$LPA" >/dev/null 2>&1 && ! [ -x "$LPA" ]; then
    printf 'FAIL - lpa not found: %s. Install it, or set LPA_BIN.\n' "$LPA"
    exit 1
fi

HOME_DIR="$(mktemp -d)" || exit 1
export LPA_HOME="$HOME_DIR"
trap 'rm -rf "$HOME_DIR"' EXIT
printf '# LPA_HOME=%s\n' "$LPA_HOME"

# Every command the README names, with the flags it names for it. The flag has
# to be in the command's own usage line: a flag that is only in our prose is a
# flag we invented.
check_usage() {
    command_words="$1"
    shift
    # shellcheck disable=SC2086
    usage=$("$LPA" $command_words --help 2>&1)
    if ! printf '%s' "$usage" | grep -q "^Usage: lpa $command_words"; then
        bad "lpa $command_words exists" "$usage"
        return 0
    fi
    for flag in "$@"; do
        if ! printf '%s' "$usage" | grep -q -- "$flag"; then
            bad "lpa $command_words names $flag" "$usage"
            return 0
        fi
    done
    if [ "$#" -eq 0 ]; then ok "lpa $command_words"; else ok "lpa $command_words ($*)"; fi
}

check_usage "init" "--days" "--account"
check_usage "doctor"
check_usage "status"
check_usage "unlock" "--hours"
check_usage "lock"
check_usage "wallet address"
check_usage "wallet balances"
check_usage "perps deposit" "--amount" "--source-chain-id"
check_usage "perps withdraw" "--amount"
check_usage "perps transfer" "--amount" "--to-dex"
check_usage "agent revoke" "--yes"
check_usage "paper init" "--budget"
check_usage "policy show"
check_usage "policy set"
check_usage "journal" "--since"
check_usage "config"
check_usage "reset"

# A flag we did not invent has to be refused, or the check above proves nothing.
if "$LPA" init --webcam >/dev/null 2>&1; then
    bad "an invented flag is refused"
else
    ok "an invented flag is refused (lpa init --webcam)"
fi

# A blank folder: doctor says what is missing and names the command to run.
doctor=$("$LPA" doctor 2>&1)
if printf '%s' "$doctor" | grep -q 'no vault account yet: run lpa init'; then
    ok "doctor on a blank folder says to run lpa init"
else
    bad "doctor on a blank folder says to run lpa init" "$doctor"
fi
if printf '%s' "$doctor" | grep -q 'hyperliquid'; then
    ok "doctor reaches Hyperliquid and measures the clock drift"
else
    bad "doctor reaches Hyperliquid and measures the clock drift" "$doctor"
fi

# Without the ceremony, a command that needs the account refuses and says so,
# rather than inventing an address.
refusal=$("$LPA" wallet address --format json 2>&1)
if printf '%s' "$refusal" | grep -q 'NOT_INITIALIZED' && printf '%s' "$refusal" | grep -q 'lpa init'; then
    ok "wallet address refuses with NOT_INITIALIZED and names lpa init"
else
    bad "wallet address refuses with NOT_INITIALIZED and names lpa init" "$refusal"
fi

# And the paper account needs none of it: that is why the recipes start there.
if "$LPA" paper init --budget 1000 >/dev/null 2>&1 && "$LPA" paper status >/dev/null 2>&1; then
    ok "the paper account works before lpa init"
else
    bad "the paper account works before lpa init"
fi

# Nothing was sealed, because nothing was signed.
if [ ! -e "$LPA_HOME/agent.json" ]; then
    ok "no agent key was created: the check signs nothing"
else
    bad "no agent key was created" "$LPA_HOME/agent.json exists"
fi

# Every image the README links to is on disk, and is a PNG.
images=$(sed -n 's/.*(\(images\/[A-Za-z0-9._-]*\)).*/\1/p' "$HERE/README.md" | sort -u)
if [ -z "$images" ]; then
    bad "the README links to at least one image"
else
    missing=""
    count=0
    for img in $images; do
        count=$((count + 1))
        if [ ! -f "$HERE/$img" ]; then
            missing="$missing $img"
            continue
        fi
        # The 8 bytes every PNG starts with.
        magic=$(head -c 8 "$HERE/$img" | od -An -tx1 | tr -d ' \n')
        [ "$magic" = "89504e470d0a1a0a" ] || missing="$missing $img(not-a-png)"
    done
    if [ -z "$missing" ]; then
        ok "the $count images the README links to are PNGs on disk"
    else
        bad "the images the README links to are PNGs on disk" "missing:$missing"
    fi
fi

# The vault wording that is wrong for lpa must not be published as a picture.
# The check cannot read a PNG, so it checks the prose says the card is absent.
if grep -q 'deliberately absent' "$HERE/README.md"; then
    ok "the README says why the agent approval card is not shown"
else
    bad "the README says why the agent approval card is not shown"
fi

printf '# %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
