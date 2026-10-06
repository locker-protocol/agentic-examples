#!/usr/bin/env bash
# Installs the example plugin from its folder, runs its command, then shows
# the two refusals that matter: a plugin changed after you approved it does
# not run, and a plugin that asks for a capability its command did not
# declare is stopped. Nothing is signed, no order of any kind is placed, and
# the throwaway LPA_HOME is removed at the end; your own ~/.lpa is never read
# or written.
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
export LPA_HOME="$HOME_DIR/lpa"
trap 'rm -rf "$HOME_DIR"' EXIT
printf '# LPA_HOME=%s\n' "$LPA_HOME"

# 1. The package is a plugin lpa installs: an lpa block, no dependency, no
#    script (none would run anyway).
if node -e '
const p = JSON.parse(require("node:fs").readFileSync(process.argv[1], "utf8"));
if (!p.lpa || p.lpa.schemaVersion !== 1) throw new Error("no lpa block of schema 1");
if (p.dependencies && Object.keys(p.dependencies).length) throw new Error("it has dependencies");
if (p.scripts && Object.keys(p.scripts).length) throw new Error("it has scripts");
' "$HERE/lpa-plugin-funding/package.json" 2>"$HOME_DIR/json.err"; then
    ok "package.json carries an lpa block, no dependency, no script"
else
    bad "package.json carries an lpa block, no dependency, no script" "$(cat "$HOME_DIR/json.err")"
fi

# 2. Install from the folder. --yes stands for the person here, in a throwaway
#    home: on your own computer, read the screen and answer it yourself.
if out=$("$LPA" plugins install --from "$HERE/lpa-plugin-funding" --yes 2>&1) && printf '%s' "$out" | grep -q 'installed: lpa funding scan'; then
    ok "plugins install --from ./lpa-plugin-funding"
else
    bad "plugins install --from ./lpa-plugin-funding" "$out"
    printf '# %d passed, %d failed\n' "$PASS" "$FAIL"
    exit 1
fi
if "$LPA" plugins list 2>&1 | grep -q 'funding  lpa-plugin-funding 1.0.0  scan  (market-read)'; then
    ok "plugins list shows it, with the capability it was given"
else
    bad "plugins list shows it, with the capability it was given" "$("$LPA" plugins list 2>&1)"
fi

# 3. Its command, on the real markets.
if out=$("$LPA" funding scan --top 3 2>&1) && [ "$(printf '%s\n' "$out" | grep -c 'a year)')" -eq 3 ]; then
    ok "funding scan --top 3 gives three markets"
    printf '%s\n' "$out" | sed 's/^/# /'
else
    bad "funding scan --top 3 gives three markets" "$out"
fi
if "$LPA" funding scan --top 3 --json 2>&1 | node -e '
let s = ""; process.stdin.on("data", (d) => s += d).on("end", () => {
    const r = JSON.parse(s);
    if (!Array.isArray(r.data?.top) || r.data.top.length !== 3) throw new Error("no data.top of 3");
    if (!r.data.top.every((m) => typeof m.name === "string" && typeof m.funding === "string")) throw new Error("rows without name or funding");
});' 2>"$HOME_DIR/json.err"; then
    ok "funding scan --json gives the plugin's data"
else
    bad "funding scan --json gives the plugin's data" "$(cat "$HOME_DIR/json.err")"
fi

# 4. A flag the plugin did not declare is refused by lpa, before it runs.
if out=$("$LPA" funding scan --tpo 3 2>&1); then
    bad "an undeclared flag is refused" "it was accepted"
else
    ok "an undeclared flag is refused"
fi

# 5. Changed after approval: its files are fingerprinted again before every
#    run, and one byte is enough.
printf '\n' >>"$LPA_HOME/plugins/funding/plugin.mjs"
if out=$("$LPA" funding scan --top 3 2>&1); then
    bad "a plugin changed since its approval does not run" "it ran"
elif printf '%s' "$out" | grep -q 'changed since you approved it'; then
    ok "a plugin changed since its approval does not run"
else
    bad "a plugin changed since its approval does not run" "$out"
fi

# 6. A capability its command did not declare: the same plugin, asking for
#    the account instead of the markets.
mkdir -p "$HOME_DIR/greedy"
cp "$HERE/lpa-plugin-funding/package.json" "$HOME_DIR/greedy/"
sed "s/call('market-read', 'markets')/call('account-read', 'balance')/" "$HERE/lpa-plugin-funding/plugin.mjs" >"$HOME_DIR/greedy/plugin.mjs"
"$LPA" plugins install --from "$HOME_DIR/greedy" --yes >/dev/null 2>&1
if out=$("$LPA" funding scan --top 3 2>&1); then
    bad "a capability the command did not declare stops the plugin" "it ran"
elif printf '%s' "$out" | grep -q 'which its command scan did not declare'; then
    ok "a capability the command did not declare stops the plugin"
else
    bad "a capability the command did not declare stops the plugin" "$out"
fi

# 7. Removed: its files and its approval go, and the word is lpa's again.
if "$LPA" plugins remove --name funding 2>&1 | grep -q 'Plugin funding removed.' && [ ! -e "$LPA_HOME/plugins/funding" ]; then
    ok "plugins remove takes its files and its approval"
else
    bad "plugins remove takes its files and its approval"
fi
if "$LPA" funding scan >/dev/null 2>&1; then
    bad "lpa funding scan is unknown once it is removed" "it ran"
else
    ok "lpa funding scan is unknown once it is removed"
fi

# 8. Nothing was traded.
if [ ! -e "$LPA_HOME/paper/account.json" ] && [ ! -e "$LPA_HOME/journal.jsonl" ]; then
    ok "no account and no journal: the plugin placed no order"
else
    bad "no account and no journal: the plugin placed no order"
fi

printf '# %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
