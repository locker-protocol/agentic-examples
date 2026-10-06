#!/usr/bin/env bash
# Replays the recipe: the commands the agent runs for "open a 3x long on BTC
# with 50 USDC, on paper". Paper only, in a throwaway LPA_HOME removed at the
# end; your own ~/.lpa is never read or written.
#
#   LPA_BIN   the lpa command to run (default: lpa on the PATH)

set -u -o pipefail

LPA="${LPA_BIN:-lpa}"
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; return 0; }
lpa()  { "$LPA" "$@"; }

if ! command -v "$LPA" >/dev/null 2>&1 && ! [ -x "$LPA" ]; then
    printf 'FAIL - lpa not found: %s. Install it, or set LPA_BIN.\n' "$LPA"
    exit 1
fi

HOME_DIR="$(mktemp -d)" || exit 1
export LPA_HOME="$HOME_DIR"
trap 'rm -rf "$HOME_DIR"' EXIT
printf '# LPA_HOME=%s\n' "$LPA_HOME"

# 1. The paper account: no key, no vault, works before `lpa init`.
if out=$(lpa paper init --budget 1000 2>&1); then
    ok "paper init --budget 1000"
else
    bad "paper init --budget 1000" "$out"
    printf '# 1..%d passed, %d failed\n' "$PASS" "$FAIL"
    exit 1
fi

# 2. The quote: 50 USDC of notional turned into a size in the base asset, from
#    the mid the quote itself reads. Orders are sized in BTC, never in dollars.
probe=$(lpa perps quote --symbol BTC --side long --size 0.001 --leverage 3 --format json 2>&1)
mid=$(printf '%s' "$probe" | sed -n 's/.*"midPx": *"\([0-9.]*\)".*/\1/p')
if [ -n "$mid" ]; then
    ok "quote reads the mid ($mid)"
else
    bad "quote reads the mid" "$probe"
    printf '# 1..%d passed, %d failed\n' "$PASS" "$FAIL"
    exit 1
fi
size=$(awk -v m="$mid" 'BEGIN { printf "%.4f", 50 / m }')

quote=$(lpa perps quote --symbol BTC --side long --size "$size" --leverage 3 --format json 2>&1)
notional=$(printf '%s' "$quote" | sed -n 's/.*"notionalUsd": *"\([0-9.]*\)".*/\1/p')
fee=$(printf '%s' "$quote" | sed -n 's/.*"totalFeeUsd": *"\([0-9.]*\)".*/\1/p')
if [ -n "$notional" ] && awk -v n="$notional" 'BEGIN { exit !(n > 40 && n < 60) }'; then
    ok "quote of $size BTC is about 50 USDC of notional (\$$notional)"
else
    bad "quote of $size BTC is about 50 USDC of notional" "$quote"
fi
# The fees are one total. A quote that does not carry it is a quote we cannot show.
if [ -n "$fee" ]; then
    ok "the quote gives the fees as one total (\$$fee)"
else
    bad "the quote gives the fees as one total" "$quote"
fi

# 3. Without --yes, the order is refused and nothing is filled. The refusal is
#    the intended path: the agent shows the quote and waits for the user.
refusal=$(lpa perps open --symbol BTC --side long --size "$size" --leverage 3 --paper --format json 2>&1)
if printf '%s' "$refusal" | grep -q 'CONFIRMATION_REQUIRED'; then
    ok "open without --yes answers CONFIRMATION_REQUIRED"
else
    bad "open without --yes answers CONFIRMATION_REQUIRED" "$refusal"
fi

# 4. The order, once the user has agreed.
if out=$(lpa perps open --symbol BTC --side long --size "$size" --leverage 3 --paper --yes 2>&1) \
    && printf '%s' "$out" | grep -q 'Paper order filled'; then
    ok "open --paper --yes fills on the paper account"
else
    bad "open --paper --yes fills on the paper account" "$out"
fi

# 5. The paper account holds the position, and only that one.
status=$(lpa paper status --format json 2>&1)
if printf '%s' "$status" | grep -q '"symbol": "BTC"' && printf '%s' "$status" | grep -q '"fills": 1'; then
    ok "paper status shows the BTC position and one fill"
else
    bad "paper status shows the BTC position and one fill" "$status"
fi

# 6. The journal is the answer to "what did you do?": the order, on the paper
#    book, with its fee; and paper fees left out of the period's total.
journal=$(lpa journal --since 24h --format json 2>&1)
if printf '%s' "$journal" | grep -q '"kind": "order"' \
    && printf '%s' "$journal" | grep -q '"paper": true' \
    && printf '%s' "$journal" | grep -q '"symbol": "BTC"'; then
    ok "journal carries the paper order"
else
    bad "journal carries the paper order" "$journal"
fi

# 7. Closing it costs nothing and is always allowed by the policy.
if out=$(lpa perps close --symbol BTC --paper --yes 2>&1); then
    ok "close --paper --yes"
else
    bad "close --paper --yes" "$out"
fi

printf '# %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
