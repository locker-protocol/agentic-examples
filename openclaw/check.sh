#!/usr/bin/env bash
# Reads openclaw.json, starts the command it names, and checks the server
# answers. Nothing is traded here, so no order and no key: a throwaway LPA_HOME
# is used all the same, and removed at the end.
#
#   LOCKER_MCP_BIN   overrides the command line the config names

set -u -o pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"

HOME_DIR="$(mktemp -d)" || exit 1
export LPA_HOME="$HOME_DIR"
trap 'rm -rf "$HOME_DIR"' EXIT
printf '# LPA_HOME=%s\n' "$LPA_HOME"

node "$HERE/config-check.mjs"
