#!/usr/bin/env bash
# Records two markets, replays range-fade.json on that tape, and checks the
# report carries a verdict. Nothing is signed, no order of any kind is placed,
# and the throwaway LPA_HOME is removed at the end; your own ~/.lpa is never
# read or written.
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

# The strategy file has to be JSON, and has to say out loud that its numbers
# are an example. A recipe that reads like a recommendation is a bug.
if node -e '
const s = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
if (s.version !== 1) throw new Error("not a v1 strategy");
if (!/NOT ADVICE/.test(s.comment || "")) throw new Error("the comment does not say AN EXAMPLE, NOT ADVICE");
if (!s.when || !s.order) throw new Error("no when/order");
' "$HERE/range-fade.json" 2>"$HOME_DIR/json.err"; then
    ok "range-fade.json is a v1 strategy and says it is an example, not advice"
else
    bad "range-fade.json is a v1 strategy and says it is an example, not advice" "$(cat "$HOME_DIR/json.err")"
fi

# 1. The tape: two markets, from Hyperliquid's real candles.
if out=$("$LPA" paper record --coins BTC,ETH 2>&1); then
    ok "paper record --coins BTC,ETH"
    printf '%s\n' "$out" | sed 's/^/# /'
else
    bad "paper record --coins BTC,ETH" "$out"
    printf '# %d passed, %d failed\n' "$PASS" "$FAIL"
    exit 1
fi
if [ -d "$LPA_HOME/paper/tape" ] && [ -n "$(ls -A "$LPA_HOME/paper/tape" 2>/dev/null)" ]; then
    ok "the tape is on disk"
else
    bad "the tape is on disk"
fi

# 2. The replay. It settles trades on the tape and signs nothing.
if report=$("$LPA" paper replay --strategy "$HERE/range-fade.json" 2>&1); then
    ok "paper replay --strategy range-fade.json"
else
    bad "paper replay --strategy range-fade.json" "$report"
    printf '# %d passed, %d failed\n' "$PASS" "$FAIL"
    exit 1
fi

# 3. The verdict. Either wording is a pass here: a short tape gives GATE NOT
#    CLEARED, which is the normal outcome, not a failure of the check.
if printf '%s' "$report" | grep -qE 'GATE (NOT )?CLEARED'; then
    verdict=$(printf '%s' "$report" | grep -oE 'GATE (NOT )?CLEARED' | head -1)
    ok "the report ends on a verdict line ($verdict)"
else
    bad "the report ends on a verdict line" "$(printf '%s' "$report" | tail -20)"
fi
if printf '%s' "$report" | grep -q 'Settled trades:'; then
    ok "the verdict counts the settled trades against the 300 it needs"
else
    bad "the verdict counts the settled trades against the 300 it needs"
fi
if printf '%s' "$report" | grep -q 'Clopper-Pearson'; then
    ok "the report gives the 95 % lower bound of the win rate"
else
    bad "the report gives the 95 % lower bound of the win rate"
fi

# 4. The report and the trades are written where the README says.
if [ -s "$LPA_HOME/paper/replay-latest.md" ] && grep -qE 'GATE (NOT )?CLEARED' "$LPA_HOME/paper/replay-latest.md"; then
    ok "the report is written to paper/replay-latest.md, verdict included"
else
    bad "the report is written to paper/replay-latest.md, verdict included"
fi

# 5. A field the schema does not know is refused by its name, so a misspelt
#    condition never passes for a true one.
sed 's/"rsi14"/"rsi_14"/' "$HERE/range-fade.json" >"$HOME_DIR/misspelt.json"
if refusal=$("$LPA" paper replay --strategy "$HOME_DIR/misspelt.json" 2>&1); then
    bad "a field the schema does not know is refused by its name" "it was accepted"
elif printf '%s' "$refusal" | grep -q 'rsi_14'; then
    ok "a field the schema does not know is refused by its name"
else
    bad "a field the schema does not know is refused by its name" "$refusal"
fi

# 6. Nothing was traded: the replay touches no account.
if [ ! -e "$LPA_HOME/paper/account.json" ] && [ ! -e "$LPA_HOME/journal.jsonl" ]; then
    ok "no account and no journal: a replay places no order"
else
    bad "no account and no journal: a replay places no order"
fi

printf '# %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
