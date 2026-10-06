# Locker Protocol Agentic: examples

**Your private key is nowhere: not on our servers, not on the agent's machine, not with anyone.**

The agent trades. It holds nothing.

**Documentation:** [doc.lockerprotocol.com/agent-wallet](https://doc.lockerprotocol.com/agent-wallet/agent): install, the setup in steps, how it trades and every command. **Website:** [hyperagentictrader.com](https://hyperagentictrader.com).

Eleven recipes to copy. Every one of them starts on paper, runs in about five minutes, and carries
a `check.sh` that replays it and says what broke.

The paper account fills on Hyperliquid's real order book, at the real prices, with the real fees.
It needs no key, no vault and no guardian, and it works before `lpa init`. That is why every
recipe here starts there: you can run the whole repository without owning a single dollar of
USDC.

## The recipes

| Recipe | What it shows | Needs |
|---|---|---|
| [`claude-code-first-trade/`](claude-code-first-trade/) | The skill installed in Claude Code, "open a 3x long on BTC with 50 USDC, on paper", then the journal | `lpa` |
| [`mcp-claude-desktop/`](mcp-claude-desktop/) | The MCP server in Claude Desktop: the JSON, three questions, one paper order | Node 22.13 |
| [`mcp-cursor/`](mcp-cursor/) | The same server in Cursor, per project and globally | Node 22.13 |
| [`sdk-node-bot/`](sdk-node-bot/) | About 60 lines of JavaScript: markets and a quote from the SDK, a paper order through the library | Node 22.13 |
| [`vault-setup/`](vault-setup/) | The `lpa init` ceremony step by step: the local page, the QR codes, the phone | `lpa`, a phone |
| [`paper-replay/`](paper-replay/) | Record the market into a local tape, replay a strategy file on it, read the verdict | `lpa` |
| [`range-scalping-paper/`](range-scalping-paper/) | Read the ranges and the regime, then a paper order whose stop and target fit the range | `lpa` |
| [`counterfactual-review/`](counterfactual-review/) | A closed paper trade reopened: what its own take-profit and stop-loss would have given | `lpa`, Node 22.13 |
| [`openclaw/`](openclaw/) | The MCP server in OpenClaw | Node 22.13 |
| [`hermes/`](hermes/) | The MCP server in Hermes Agent | Node 22.13 |
| [`plugin-funding/`](plugin-funding/) | A plugin of two files: its manifest, its code, installed and run as `lpa funding scan`, and what it is refused | `lpa` |

## Install

```sh
npm install -g @locker-protocol/agent-wallet-hyperliquid-trader@latest
```

Node 22.13 or later. Nothing in this repository ever sends a real order or asks for a real
signature: every trade is a paper trade. The reads (the order book, the candles, the markets) are
the real Hyperliquid.

## Running the checks

```sh
./check-all.sh
```

It runs every recipe's `check.sh` one after another, prints one line per recipe, and exits 1 if
any of them failed. A single recipe:

```sh
cd paper-replay && ./check.sh
```

Every `check.sh` works in a throwaway `LPA_HOME` created by `mktemp -d` and removed when it ends,
so it never reads or writes your own `~/.lpa`. None of them signs anything, and none of them
places a real order.

Two variables point the checks at something other than what is on your `PATH`:

| Variable | Default | What it is |
|---|---|---|
| `LPA_BIN` | `lpa` | The `lpa` command to run |
| `LOCKER_MCP_BIN` | `npx -y --ignore-scripts @locker-protocol/agent-wallet-hyperliquid-trader-mcp@latest` | The MCP server to start, as a command line |

For example, against a checkout instead of the published packages:

```sh
LPA_BIN=/path/to/packages/agentic/bin/lpa.js \
LOCKER_MCP_BIN="node /path/to/packages/mcp/bin/locker-mcp.js" \
  ./check-all.sh
```

`sdk-node-bot/check.sh` also takes `LOCKER_PACKAGES_DIR`, a directory of `.tgz` tarballs (from
`npm pack`) to install instead of the published packages. Its README says how.

The checks read Hyperliquid over the network. Without it they fail, and say so.

## What these recipes never do

- No real order, no real signature. Every trade is on the paper account.
- No write outside a temporary directory. Your `~/.lpa` is not touched, and no running `lpa` is
  stopped.
- No key, no password, no seed phrase anywhere in this repository.

## Fees

Hyperliquid's own trading fees plus Locker's builder fee are shown as one total in every quote
(`fees 0.095% ($0.0476)`) and totalled the same way in `lpa journal`. The paper account counts
that same total, which is why a paper result is comparable to a real one. Never split that total
or quote a part of it.

## Reading a result honestly

A paper trade, a replay and a counterfactual all describe the past. None of them is a reason to
open a real position. Two recipes say so at length, `paper-replay/` and `counterfactual-review/`,
and the rule holds for all of them.

## Licence

LOCKER PROTOCOL PROPRIETARY NON-COMMERCIAL LICENSE. See [`LICENSE`](LICENSE).
