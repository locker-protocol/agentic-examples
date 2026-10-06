#!/usr/bin/env bash
# Runs bot.mjs against the paper account, in a throwaway copy of the recipe and
# a throwaway LPA_HOME, both removed at the end. Your own ~/.lpa is never read
# or written, and no real order is placed.
#
# Where the packages come from, first one that is set:
#   LOCKER_PACKAGES_DIR   a folder of .tgz tarballs (from `npm pack`)
#   LOCKER_MONOREPO       a checkout: its packages are packed into a temp folder
#   neither               the published packages, at the versions package.json pins

set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; return 0; }

WORK="$(mktemp -d)" || exit 1
export LPA_HOME="$WORK/lpa-home"
mkdir -p "$LPA_HOME" && chmod 700 "$LPA_HOME"
trap 'rm -rf "$WORK"' EXIT
printf '# work=%s\n' "$WORK"

APP="$WORK/app"
mkdir -p "$APP"
cp "$HERE/bot.mjs" "$APP/bot.mjs"

# The recipe is written for the published packages. To run it today against a
# checkout, its packages are packed and installed as tarballs: nothing is
# linked globally and nothing is written inside the checkout.
PACKAGES_DIR="${LOCKER_PACKAGES_DIR:-}"
if [ -z "$PACKAGES_DIR" ] && [ -n "${LOCKER_MONOREPO:-}" ]; then
    PACKAGES_DIR="$WORK/tarballs"
    mkdir -p "$PACKAGES_DIR"
    for p in hyperliquid vault agentic; do
        if ! npm pack --silent --pack-destination "$PACKAGES_DIR" "$LOCKER_MONOREPO/packages/$p" >/dev/null 2>"$WORK/pack.err"; then
            bad "npm pack $p" "$(cat "$WORK/pack.err")"
            printf '# %d passed, %d failed\n' "$PASS" "$FAIL"
            exit 1
        fi
    done
    ok "packed hyperliquid, vault and agentic from $LOCKER_MONOREPO"
fi

if [ -n "$PACKAGES_DIR" ]; then
    # A package.json of its own, so npm resolves the three names to the three
    # tarballs instead of asking the registry for them.
    printf '{ "name": "locker-sdk-node-bot-check", "version": "0.0.0", "private": true, "type": "module" }\n' >"$APP/package.json"
    set --
    for t in "$PACKAGES_DIR"/*.tgz; do set -- "$@" "$t"; done
    if [ "$#" -eq 0 ]; then
        bad "tarballs found in $PACKAGES_DIR"
        printf '# %d passed, %d failed\n' "$PASS" "$FAIL"
        exit 1
    fi
    if (cd "$APP" && npm install --no-audit --no-fund --loglevel=error "$@" >/dev/null 2>"$WORK/npm.err"); then
        ok "installed $# tarballs into the throwaway copy"
    else
        bad "installed the tarballs into the throwaway copy" "$(cat "$WORK/npm.err")"
        printf '# %d passed, %d failed\n' "$PASS" "$FAIL"
        exit 1
    fi
else
    cp "$HERE/package.json" "$APP/package.json"
    if (cd "$APP" && npm install --no-audit --no-fund --loglevel=error >/dev/null 2>"$WORK/npm.err"); then
        ok "installed the published packages"
    else
        bad "installed the published packages" "$(cat "$WORK/npm.err")"
        printf '# %d passed, %d failed\n' "$PASS" "$FAIL"
        exit 1
    fi
fi

# The two packages the recipe imports, and the three exports it names.
if (cd "$APP" && node -e '
import("@locker-protocol/agent-wallet-hyperliquid-signer").then((hl) => {
    for (const n of ["getHlMarkets", "getHlMid", "MIN_ORDER_USD"]) if (hl[n] === undefined) throw new Error("@locker-protocol/agent-wallet-hyperliquid-signer has no " + n);
    return import("@locker-protocol/agent-wallet-hyperliquid-trader");
}).then((a) => {
    for (const n of ["runCommand", "lockerHome", "buildQuote", "renderQuote"]) if (a[n] === undefined) throw new Error("@locker-protocol/agent-wallet-hyperliquid-trader has no " + n);
}).catch((e) => { console.error(e.message); process.exit(1); });
' 2>"$WORK/imports.err"); then
    ok "the packages export what bot.mjs imports"
else
    bad "the packages export what bot.mjs imports" "$(cat "$WORK/imports.err")"
fi

# The bot itself, on the paper account.
if (cd "$APP" && node bot.mjs >"$WORK/out.txt" 2>"$WORK/err.txt"); then
    ok "bot.mjs runs"
else
    bad "bot.mjs runs" "$(tail -20 "$WORK/err.txt")"
fi
sed 's/^/# /' "$WORK/out.txt"

out="$(cat "$WORK/out.txt")"
# One total for the fees in the quote it printed, never a part of it.
if printf '%s' "$out" | grep -qE '^  fees +[0-9.]+% \(\$[0-9.]+\)( +\(base tier\))?$'; then
    ok "the quote shows the fees as one total"
else
    bad "the quote shows the fees as one total" "$out"
fi
if printf '%s' "$out" | grep -q 'Paper order filled.'; then
    ok "the order filled on the paper account"
else
    bad "the order filled on the paper account" "$out"
fi
if printf '%s' "$out" | grep -q 'Paper equity \$'; then
    ok "the paper account answers with its equity and its fees"
else
    bad "the paper account answers with its equity and its fees" "$out"
fi
if printf '%s' "$out" | grep -q 'Closed .* on paper.'; then
    ok "the position is closed again, so the recipe leaves nothing open"
else
    bad "the position is closed again" "$out"
fi

# Nothing signed, nothing real: the journal knows only paper.
if [ -f "$LPA_HOME/journal.jsonl" ] && ! grep -q '"paper":false' "$LPA_HOME/journal.jsonl"; then
    ok "every line of the journal is a paper line"
else
    bad "every line of the journal is a paper line" "$(cat "$LPA_HOME/journal.jsonl" 2>&1)"
fi

printf '# %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
