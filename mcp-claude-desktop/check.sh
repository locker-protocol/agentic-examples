#!/usr/bin/env bash
# Checks the recipe: the configuration parses, and the server it names answers
# the conversation the recipe describes. Paper only, in a throwaway LPA_HOME
# removed at the end; your own ~/.lpa is never read or written.
#
#   LOCKER_MCP_BIN   the command line that starts the server
#                    (default: npx -y --ignore-scripts @locker-protocol/agent-wallet-hyperliquid-trader-mcp@latest)

set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PASS=0
FAIL=0
ok()  { PASS=$((PASS + 1)); printf 'ok   - %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf 'FAIL - %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; return 0; }

HOME_DIR="$(mktemp -d)" || exit 1
export LPA_HOME="$HOME_DIR"
trap 'rm -rf "$HOME_DIR"' EXIT
printf '# LPA_HOME=%s\n' "$LPA_HOME"

# The configuration the README tells you to paste must be valid JSON, and must
# name the server under mcpServers.locker at @latest, fetched by npx
# without running any install script.
if node -e '
const fs = require("node:fs");
const c = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
const s = c.mcpServers && c.mcpServers.locker;
if (!s) throw new Error("no mcpServers.locker");
if (s.command !== "npx") throw new Error("command is not npx: " + s.command);
const args = s.args || [];
if (!args.includes("-y")) throw new Error("args miss -y");
if (!args.includes("--ignore-scripts")) throw new Error("args miss --ignore-scripts: npx would run the install scripts of what it fetches");
if (!args.includes("@locker-protocol/agent-wallet-hyperliquid-trader-mcp@latest")) throw new Error("args do not ask for @locker-protocol/agent-wallet-hyperliquid-trader-mcp@latest");
' "$HERE/claude_desktop_config.json" 2>"$HOME_DIR/config.err"; then
    ok "claude_desktop_config.json is JSON and names the server, at @latest"
else
    bad "claude_desktop_config.json is JSON and names the server, at @latest" "$(cat "$HOME_DIR/config.err")"
fi

if node "$HERE/mcp-check.mjs"; then
    ok "the server answers the whole conversation"
else
    bad "the server answers the whole conversation"
fi

printf '# %d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
