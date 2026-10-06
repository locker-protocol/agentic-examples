# The MCP server in Claude Desktop

**Your private key is nowhere: not on our servers, not on the agent's machine, not with anyone.**

The agent trades. It holds nothing.

Claude Desktop starts the server on your computer, over stdio. Forty-one tools: markets,
quotes, positions, the market regime, the paper account, copies of other traders, the policy,
the mandate, the journal. About five minutes, all of it on paper.

## 1. The configuration

Settings, Developer, Edit Config, then paste [`claude_desktop_config.json`](claude_desktop_config.json):

```json
{
  "mcpServers": {
    "locker": {
      "command": "npx",
      "args": ["-y", "--ignore-scripts", "@locker-protocol/agent-wallet-hyperliquid-trader-mcp@latest"]
    }
  }
}
```

The file lives at:

| System | Path |
|---|---|
| macOS | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Windows | `%APPDATA%\Claude\claude_desktop_config.json` |

If you already have other servers there, add the `locker` entry beside them instead of replacing
the file.

It asks for `@latest`, so each start runs the newest release. Node 22.13 or later. Restart Claude Desktop
and the server appears in the tools list.

## 2. Three questions

Ask them in order. Each one is a read: nothing is signed, nothing is placed.

> What are the busiest Hyperliquid perps markets right now?

`perps_markets` with `limit`. Volume over 24 hours, largest first, halted markets marked.

> Is BTC trending or in a range?

`perps_regime` with `symbol: "BTC"`. One of five states, `StrongBull`, `WeakBull`, `Range`,
`WeakBear`, `StrongBear`, with the figures behind it: the EMA stack, the structure of the 4 h
candles, RSI 14 and RSI 6, the ATR and its slope, the volume against its average, and how long
the state has held. It describes the past. It is not a forecast, and the agent should say so.

> What would a 3x long on BTC with 50 USDC cost me?

`perps_quote`. Orders are sized in the base asset, so the agent turns 50 USDC into a size with
the mid the quote gives. The answer carries the entry and the worst accepted price, notional and
margin, the fees as one total, and a liquidation estimate.

## 3. One paper order

> Open a paper account with 1000 dollars, then take that 3x long on BTC, on paper.

What has to happen, in this order:

1. `paper_init` with `{ "budget": 1000 }`. The argument is `budget`; `budgetUsd` is refused by
   name, and the refusal says which arguments the tool takes.
2. `perps_open` with `paper: true` and **no** `confirm`. The tool answers the quote and the
   policy check and executes nothing (`"executed": false`), with a `quote_id` that lasts ten
   minutes. That is the answer to show you.
3. Only after you agree, `perps_open` again with the same arguments, `confirm: true` and that
   `quote_id`. The paper account fills on Hyperliquid's real book, with the real fees. A
   `confirm: true` without it is refused (`QUOTE_REQUIRED`), and so is one whose order changed
   since the quote (`QUOTE_STALE`, with a new quote to show you).

`perps_open` carries `destructiveHint`, so Claude Desktop asks you before every call, including
the one that only quotes.

Then:

> What did you do, and what did it cost?

`journal` with `{ "since": "24h" }`: one line per action, with the fees of each. Paper fees are
listed and left out of the period's total, and the answer says so.

## What this server cannot do

- It has no key. `lpa init` (the phone approves the agent) and `lpa unlock` (the password opens
  the agent key) are typed by a person in their own terminal. The paper account needs neither.
- `perps_deposit`, `perps_withdraw` and `perps_transfer` move funds, so they are signed on the
  phone: those tools answer the exact line for you to type, and stop there.
- It cannot get around the policy. `policy_show` lists the limits; they are checked before every
  order and again by the guardian before a real one is signed.

The server reads the same folder as `lpa` (`~/.lpa`, or `LPA_HOME`): the settings, the sealed
agent key, the paper account and the journal. No account with us, no analytics, no telemetry.

## check.sh

```sh
./check.sh
```

It checks that `claude_desktop_config.json` is valid JSON naming the server at `@latest`,
then plays the whole conversation against the real server with a client of about a hundred
lines and no dependency ([`mcp-check.mjs`](mcp-check.mjs)): `initialize`, `tools/list` (42
tools, `perps_open` marked destructive), three reads, `paper_init`, `perps_open` without
`confirm` (nothing executed), a `confirm: true` without its `quote_id` refused, then with both,
and the journal that carries it.

It works in a throwaway `LPA_HOME` it deletes at the end, and places no real order.

```sh
LOCKER_MCP_BIN="node /path/to/packages/mcp/bin/locker-mcp.js" ./check.sh
```
