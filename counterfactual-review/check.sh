#!/usr/bin/env bash
# Opens and closes one paper trade, then runs review.mjs on it, and runs it
# again on a fixture built from Hyperliquid's own candles two hours back, where
# a level is certain to be crossed. Paper only, in throwaway LPA_HOME folders
# removed at the end; your own ~/.lpa is never read or written.
#
#   LPA_BIN   the lpa command to run (default: lpa on the PATH)

set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LPA="${LPA_BIN:-lpa}"
export LPA_BIN="$LPA"
PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; return 0; }
die() { printf '# %d passed, %d failed\n' "$PASS" "$FAIL"; exit 1; }

if ! command -v "$LPA" >/dev/null 2>&1 && ! [ -x "$LPA" ]; then
    printf 'FAIL - lpa not found: %s. Install it, or set LPA_BIN.\n' "$LPA"
    exit 1
fi

WORK="$(mktemp -d)" || exit 1
trap 'rm -rf "$WORK"' EXIT
printf '# work=%s\n' "$WORK"

# review.mjs reads plan.json beside itself. The copy has none, which is how the
# check reaches the refusal the README promises.
cp "$HERE/review.mjs" "$WORK/review.mjs"

# ---------------------------------------------------------------- a real trade
export LPA_HOME="$WORK/live"
mkdir -p "$LPA_HOME" && chmod 700 "$LPA_HOME"

"$LPA" paper init --budget 1000 >/dev/null 2>&1 || { bad "paper init"; die; }
mid=$("$LPA" perps quote --symbol BTC --side long --size 0.001 --leverage 2 --format json 2>&1 | sed -n 's/.*"midPx": *"\([0-9.]*\)".*/\1/p')
[ -n "$mid" ] || { bad "a quote reads the mid of BTC"; die; }
size=$(awk -v m="$mid" 'BEGIN { printf "%.5f", 40 / m }')
TP=$(awk -v m="$mid" 'BEGIN { printf "%.1f", m * 1.004 }')
SL=$(awk -v m="$mid" 'BEGIN { printf "%.1f", m * 0.996 }')

"$LPA" perps open --symbol BTC --side long --size "$size" --leverage 2 --tp "$TP" --sl "$SL" --paper --yes >/dev/null 2>&1 \
    || { bad "the paper order filled"; die; }
"$LPA" perps close --symbol BTC --paper --yes >/dev/null 2>&1 || { bad "the paper position closed"; die; }
ok "a paper trade was opened and closed: BTC long $size, take-profit $TP, stop-loss $SL"

if report=$(node "$WORK/review.mjs" --tp "$TP" --sl "$SL" --minutes 60 2>&1); then
    ok "review.mjs runs on the trade it finds in the journal"
    printf '%s\n' "$report" | sed 's/^/# /'
else
    bad "review.mjs runs on the trade it finds in the journal" "$report"
    die
fi

for phrase in "what it made" "what that gives" "VERDICT:" "candles of 1 min from Hyperliquid"; do
    if printf '%s' "$report" | grep -qF "$phrase"; then
        ok "the report says \"$phrase\""
    else
        bad "the report says \"$phrase\"" "$report"
    fi
done
# One trade is a reading, never an edge: the report has to say so itself.
if printf '%s' "$report" | grep -q 'not an edge'; then
    ok "the report says one trade is not an edge"
else
    bad "the report says one trade is not an edge" "$report"
fi

# The journal keeps the order, not its take-profit and its stop-loss: without
# them, and without a plan.json beside it, the script refuses rather than guess.
if refusal=$(node "$WORK/review.mjs" --minutes 60 2>&1); then
    bad "without levels, review.mjs refuses rather than guess" "it answered: $refusal"
elif printf '%s' "$refusal" | grep -q -- '--tp'; then
    ok "without levels, review.mjs refuses and names --tp and --sl"
else
    bad "without levels, review.mjs refuses and names --tp and --sl" "$refusal"
fi

# Levels that do not frame the entry are refused too.
if wrong=$(node "$WORK/review.mjs" --tp "$SL" --sl "$TP" --minutes 60 2>&1); then
    bad "levels on the wrong side of the entry are refused" "it answered: $wrong"
else
    ok "levels on the wrong side of the entry are refused"
fi

# ------------------------------------------------- a fixture, two hours back
# The walk itself, proven against Hyperliquid's own candles: a trade closed two
# hours ago, with levels inside the range the market actually traded after it,
# so one of them has to be crossed.
export LPA_HOME="$WORK/fixture"
mkdir -p "$LPA_HOME" && chmod 700 "$LPA_HOME"

cat >"$WORK/fixture.mjs" <<'FIXTURE'
// Builds a journal from real candles: an order and a close two hours back, and
// prints the take-profit and the stop-loss that the market crossed afterwards.
import { writeFileSync } from 'node:fs';
import { join } from 'node:path';

const home = process.env.LPA_HOME;
const now = Date.now();
const start = now - 180 * 60_000;
const answer = await fetch('https://api.hyperliquid.xyz/info', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'candleSnapshot', req: { coin: 'BTC', interval: '1m', startTime: start, endTime: now } }),
});
const candles = await answer.json();
if (candles.length < 90) { console.error(`only ${candles.length} candles`); process.exit(1); }

const at = candles[30];                       // the trade closed here
const after = candles.slice(31);
const entry = Number(at.c);
const high = Math.max(...after.map((c) => Number(c.h)));
const low = Math.min(...after.map((c) => Number(c.l)));
if (!(high > entry) || !(low < entry)) { console.error('the market did not move both ways after that candle'); process.exit(1); }

// Halfway to each extreme: both are crossed, so a level has to be hit.
const tp = entry + (high - entry) / 2;
const sl = entry - (entry - low) / 2;

// And one candle that reaches both levels at once: the first candle after the
// close that straddles the entry and goes further either way than every
// candle before it, so no earlier candle can be reached first. Its own high
// and low are the two levels.
let bothTp = 0;
let bothSl = 0;
let maxSoFar = -Infinity;
let minSoFar = Infinity;
for (const c of after) {
    const h = Number(c.h);
    const l = Number(c.l);
    if (h > entry && l < entry && h > maxSoFar && l < minSoFar) { bothTp = h; bothSl = l; break; }
    maxSoFar = Math.max(maxSoFar, h);
    minSoFar = Math.min(minSoFar, l);
}
if (bothTp === 0) { console.error('no candle straddles the entry before another exceeds it'); process.exit(1); }

const size = 0.0005;
const notional = (entry * size).toFixed(2);
const fee = (entry * size * 0.00095).toFixed(4);
// The close lands exactly on the start of the first candle of `after`, so the
// walk begins there and the candle the trade was closed inside is left out.
const lines = [
    { ts: at.t, kind: 'order', paper: true, symbol: 'BTC', side: 'long', size: String(size), px: String(entry), notionalUsd: notional, hlFeeUsd: fee, lockerFeeUsd: '0' },
    { ts: after[0].t, kind: 'close', paper: true, symbol: 'BTC', side: 'short', size: String(size), px: String(entry), notionalUsd: notional, hlFeeUsd: fee, lockerFeeUsd: '0' },
];
writeFileSync(join(home, 'journal.jsonl'), lines.map((l) => JSON.stringify(l)).join('\n') + '\n', { mode: 0o600 });
process.stdout.write(`${tp.toFixed(2)} ${sl.toFixed(2)} ${entry.toFixed(2)} ${bothTp.toFixed(2)} ${bothSl.toFixed(2)}`);
FIXTURE

if levels=$(node "$WORK/fixture.mjs" 2>&1); then
    set -- $levels
    FTP="$1"; FSL="$2"; FENTRY="$3"; BOTH_TP="$4"; BOTH_SL="$5"
    ok "fixture built from real candles: entry $FENTRY, take-profit $FTP, stop-loss $FSL"
else
    bad "fixture built from real candles" "$levels"
    die
fi

if walked=$(node "$WORK/review.mjs" --tp "$FTP" --sl "$FSL" --minutes 150 2>&1); then
    ok "review.mjs walks the candles of the fixture"
    printf '%s\n' "$walked" | sed 's/^/# /'
else
    bad "review.mjs walks the candles of the fixture" "$walked"
    die
fi
if printf '%s' "$walked" | grep -qE 'first level reached'; then
    hitline=$(printf '%s' "$walked" | grep -E 'first level reached' | head -1 | sed 's/^ *//')
    ok "a level is reported as hit ($hitline)"
else
    bad "a level is reported as hit: the levels were inside the range the market traded" "$walked"
fi

# A candle that reaches both levels counts as the stop, never as the target.
# The fixture's two levels are one candle's own high and low, and no earlier
# candle goes as far either way, so that candle is where the walk stops.
if both=$(node "$WORK/review.mjs" --tp "$BOTH_TP" --sl "$BOTH_SL" --minutes 150 2>&1) \
    && printf '%s' "$both" | grep -q 'first level reached   stop-loss' \
    && printf '%s' "$both" | grep -q 'reached both'; then
    ok "a candle that reaches both levels counts as the stop (take-profit $BOTH_TP, stop-loss $BOTH_SL)"
else
    bad "a candle that reaches both levels counts as the stop" "$both"
fi

# And levels the market never came near are reported as never hit, rather than
# quietly counted as a win.
FAR_TP=$(awk -v e="$FENTRY" 'BEGIN { printf "%.2f", e * 1.5 }')
FAR_SL=$(awk -v e="$FENTRY" 'BEGIN { printf "%.2f", e * 0.5 }')
if far=$(node "$WORK/review.mjs" --tp "$FAR_TP" --sl "$FAR_SL" --minutes 150 2>&1) \
    && printf '%s' "$far" | grep -q 'neither level hit'; then
    ok "levels the market never reached are reported as neither hit"
else
    bad "levels the market never reached are reported as neither hit" "$far"
fi

# Nothing real anywhere in this recipe.
if ! grep -rq '"paper":false' "$WORK"/*/journal.jsonl 2>/dev/null; then
    ok "every journal line of this check is a paper line"
else
    bad "every journal line of this check is a paper line"
fi

printf '# %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
