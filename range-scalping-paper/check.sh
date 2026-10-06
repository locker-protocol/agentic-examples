#!/usr/bin/env bash
# Runs the recipe against the real market: the ranges, the regime, a quote
# whose take-profit and stop-loss come from the real support and resistance, a
# paper order, and the two refusals the README claims. Paper only, in a
# throwaway LPA_HOME removed at the end; your own ~/.lpa is never touched.
#
#   LPA_BIN   the lpa command to run (default: lpa on the PATH)

set -u -o pipefail

LPA="${LPA_BIN:-lpa}"
PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; return 0; }
die() { printf '# %d passed, %d failed\n' "$PASS" "$FAIL"; exit 1; }

if ! command -v "$LPA" >/dev/null 2>&1 && ! [ -x "$LPA" ]; then
    printf 'FAIL - lpa not found: %s. Install it, or set LPA_BIN.\n' "$LPA"
    exit 1
fi

HOME_DIR="$(mktemp -d)" || exit 1
export LPA_HOME="$HOME_DIR"
trap 'rm -rf "$HOME_DIR"' EXIT
printf '# LPA_HOME=%s\n' "$LPA_HOME"

# 1. The markets in a range now, with their support and resistance, and their
#    prices. The trade is the one the README describes: from the edge the price
#    is nearest, target the opposite edge, stop a quarter of the range beyond
#    the near edge.
ranges=$("$LPA" perps ranges --limit 10 --format json 2>&1) || { bad "perps ranges" "$ranges"; die; }
prices=$("$LPA" perps markets --limit 100 --format json 2>&1) || { bad "perps markets" "$prices"; die; }
printf '%s' "$ranges" >"$HOME_DIR/ranges.json"
printf '%s' "$prices" >"$HOME_DIR/markets.json"

pick=$(node -e '
const fs = require("node:fs");
const ranges = JSON.parse(fs.readFileSync(process.argv[1], "utf8")).markets || [];
const prices = new Map((JSON.parse(fs.readFileSync(process.argv[2], "utf8")).markets || []).map((m) => [m.symbol, Number(m.markPx)]));
for (const r of ranges) {
    if (!(r.score > 0) || !(r.support > 0) || !(r.resistance > r.support)) continue;
    const mid = prices.get(r.symbol);
    if (!Number.isFinite(mid) || mid <= r.support || mid >= r.resistance) continue;
    const width = r.resistance - r.support;
    const low = mid < (r.support + r.resistance) / 2;
    const side = low ? "long" : "short";
    const tp = low ? r.resistance : r.support;                       // the far edge
    const sl = low ? r.support - width / 4 : r.resistance + width / 4; // beyond the near edge
    const riskReward = Math.abs(mid - sl) / Math.abs(tp - mid);
    if (!(riskReward > 0 && riskReward <= 2.5)) continue;
    process.stdout.write([r.symbol, side, r.support, r.resistance, r.width.toFixed(2), mid, tp, sl, riskReward.toFixed(2)].join(" "));
    process.exit(0);
}
console.error("no market of the scan is trading inside its own range right now");
process.exit(1);
' "$HOME_DIR/ranges.json" "$HOME_DIR/markets.json") || { bad "perps ranges names a market trading inside its range" "$ranges"; die; }

set -- $pick
SYMBOL="$1"; SIDE="$2"; SUPPORT="$3"; RESISTANCE="$4"; WIDTH="$5"; MID="$6"; TP="$7"; SL="$8"; RR="$9"
ok "perps ranges: $SYMBOL in a range, support $SUPPORT, resistance $RESISTANCE (width ${WIDTH}%)"

# 2. The regime of that market, one of the five states.
regime=$("$LPA" perps regime --symbol "$SYMBOL" --format json 2>&1) || { bad "perps regime --symbol $SYMBOL" "$regime"; die; }
state=$(printf '%s' "$regime" | sed -n 's/.*"regime": *"\([A-Za-z]*\)".*/\1/p')
case "$state" in
    StrongBull|WeakBull|Range|WeakBear|StrongBear) ok "perps regime --symbol $SYMBOL: $state" ;;
    *) bad "perps regime answers one of the five states" "$regime" ;;
esac
# The reading has to carry what it is built on, not just a verdict.
for field in trendScore rsi14 atr4hPct volumeRatio trendAgeHours; do
    printf '%s' "$regime" | grep -q "\"$field\"" || bad "perps regime gives $field" "$regime"
done
ok "perps regime gives the figures behind the state"

# 3. The quote. $50 of notional, well above Hyperliquid's $10 floor and under
#    the policy's $100 ceiling. A size with more digits than the market trades
#    is rounded down by the command itself, so the notional is checked below.
SIZE=$(awk -v mid="$MID" 'BEGIN { printf "%.6f", 50 / mid }')
ok "levels from the range: $SYMBOL $SIDE at $MID, size $SIZE, take-profit $TP, stop-loss $SL (risk:reward ${RR}x)"

quote=$("$LPA" perps quote --symbol "$SYMBOL" --side "$SIDE" --size "$SIZE" --leverage 2 --tp "$TP" --sl "$SL" 2>&1) || { bad "perps quote with the levels" "$quote"; die; }
json=$("$LPA" perps quote --symbol "$SYMBOL" --side "$SIDE" --size "$SIZE" --leverage 2 --tp "$TP" --sl "$SL" --format json 2>&1)
notional=$(printf '%s' "$json" | sed -n 's/.*"notionalUsd": *"\([0-9.]*\)".*/\1/p')
if [ -n "$notional" ] && awk -v n="$notional" 'BEGIN { exit !(n >= 10 && n <= 100) }'; then
    ok "the order is \$$notional of notional: above Hyperliquid's \$10 floor, under the policy's \$100"
else
    bad "the order is between Hyperliquid's \$10 floor and the policy's \$100" "$json"
    die
fi
if printf '%s' "$quote" | grep -qE '^  fees +[0-9.]+% \(\$[0-9.]+\)( +\(base tier\))?$'; then
    ok "the quote shows the fees as one total"
else
    bad "the quote shows the fees as one total" "$quote"
fi
if printf '%s' "$quote" | grep -q 'risk:reward'; then
    ok "the quote gives the risk:reward of those two levels"
else
    bad "the quote gives the risk:reward of those two levels" "$quote"
fi

# 4. The paper account, and the order.
"$LPA" paper init --budget 1000 >/dev/null 2>&1 || { bad "paper init"; die; }
"$LPA" paper on >/dev/null 2>&1 || { bad "paper on"; die; }
if out=$("$LPA" perps open --symbol "$SYMBOL" --side "$SIDE" --size "$SIZE" --leverage 2 --tp "$TP" --sl "$SL" --yes 2>&1) \
    && printf '%s' "$out" | grep -q 'Paper order filled'; then
    ok "the paper order filled"
else
    bad "the paper order filled" "$out"
fi

# 5. What the README claims about paper mode, checked rather than asserted:
#    no trigger order rests behind the position.
orders=$("$LPA" perps orders 2>&1)
if printf '%s' "$orders" | grep -q 'fills at once or not at all'; then
    ok "no trigger rests behind a paper position, and the command says why"
else
    bad "no trigger rests behind a paper position" "$orders"
fi
positions=$("$LPA" perps positions 2>&1)
if printf '%s' "$positions" | grep -q "$SYMBOL"; then
    ok "the paper position is there"
else
    bad "the paper position is there" "$positions"
fi

# 6. A resting limit is refused, not silently turned into something else.
RESTING=$(awk -v mid="$MID" -v side="$SIDE" 'BEGIN { printf "%.6f", (side == "long" ? mid * 0.9 : mid * 1.1) }')
if refusal=$("$LPA" perps open --symbol "$SYMBOL" --side "$SIDE" --size "$SIZE" --leverage 2 --type limit --limit-px "$RESTING" --yes 2>&1); then
    bad "a resting limit is refused on paper" "it was accepted: $refusal"
elif printf '%s' "$refusal" | grep -q 'fills at once or not at all'; then
    ok "a resting limit is refused on paper, with the reason"
else
    bad "a resting limit is refused on paper" "$refusal"
fi

# 7. The risk:reward guard: a stop far past the target is refused by the policy.
BADSL=$(awk -v mid="$MID" -v side="$SIDE" 'BEGIN { printf "%.6f", (side == "long" ? mid * 0.95 : mid * 1.05) }')
NEARTP=$(awk -v mid="$MID" -v side="$SIDE" 'BEGIN { printf "%.6f", (side == "long" ? mid * 1.001 : mid * 0.999) }')
if refusal=$("$LPA" perps open --symbol "$SYMBOL" --side "$SIDE" --size "$SIZE" --leverage 2 --tp "$NEARTP" --sl "$BADSL" --yes --format json 2>&1); then
    bad "the risk:reward guard refuses a stop far past the target" "it was accepted: $refusal"
elif printf '%s' "$refusal" | grep -q 'POLICY_REJECTED' && printf '%s' "$refusal" | grep -q 'further from the entry'; then
    ok "the risk:reward guard refuses a stop far past the target"
else
    bad "the risk:reward guard refuses a stop far past the target" "$refusal"
fi

# 8. Closed by hand, because paper has no stop to close it.
if "$LPA" perps close --symbol "$SYMBOL" --yes >/dev/null 2>&1; then
    ok "the paper position is closed by hand"
else
    bad "the paper position is closed by hand"
fi
"$LPA" paper off >/dev/null 2>&1

# Nothing real: every journal line is a paper line.
if [ -f "$LPA_HOME/journal.jsonl" ] && ! grep -q '"paper":false' "$LPA_HOME/journal.jsonl"; then
    ok "every line of the journal is a paper line"
else
    bad "every line of the journal is a paper line"
fi

printf '# %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
