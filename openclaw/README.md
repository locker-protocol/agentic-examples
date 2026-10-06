# The MCP server in OpenClaw

**Your private key is nowhere: not on our servers, not on the agent's machine, not with anyone.**

The agent trades. It holds nothing.

OpenClaw starts the server on your computer, over stdio. Forty-one tools: markets, quotes,
positions, the market regime, the paper account, copies of other traders, the policy, the
mandate, the journal. About five minutes, all of it on paper.

## The configuration

OpenClaw reads an optional JSON5 config from `$OPENCLAW_CONFIG_PATH`, which defaults to
`~/.openclaw/openclaw.json`. MCP servers live under `mcp.servers`, one entry per server.

Add the `locker` entry to yours, from [`openclaw.json`](openclaw.json):

```json5
{
  mcp: {
    servers: {
      locker: {
        transport: "stdio",
        command: "npx",
        args: ["-y", "--ignore-scripts", "@locker-protocol/agent-wallet-hyperliquid-trader-mcp@latest"],
        enabled: true,
      },
    },
  },
}
```

The file in this folder is written as plain JSON, which JSON5 accepts as it is, so you can paste
it either way. JSON5 also allows comments and trailing commas if you prefer the form above.

| Field | What it is |
|---|---|
| `command` | The executable. Required |
| `args` | Its arguments |
| `transport` | `"stdio"`. An explicit `transport: "stdio"` needs a non-empty `command` |
| `enabled` | `false` turns the server off without removing it |
| `cwd` | A working directory for the process. Not needed here |
| `connectionTimeoutMs`, `requestTimeoutMs` | How long to wait when starting, and per call |

It asks for `@latest`, so each start runs the newest release. Node 22.13 or later.

There is also an `openclaw mcp` command group: `openclaw mcp add`, and `list`, `show`, `set` and
`unset`, which read and write the same OpenClaw-managed `mcp.servers` entries. The documentation
page for it does not spell out the flags for a stdio server, so run `openclaw mcp add --help`
rather than trust a line copied from here. Editing the config file directly works in any case:
the gateway watches it and applies the change.

`openclaw config schema` prints the live JSON Schema, which is the last word on the fields
above.

**Where these came from:** [docs.openclaw.ai/tools/mcp](https://docs.openclaw.ai/tools/mcp),
[docs.openclaw.ai/gateway/config-extensions](https://docs.openclaw.ai/gateway/config-extensions)
and
[docs.openclaw.ai/gateway/configuration-reference](https://docs.openclaw.ai/gateway/configuration-reference),
all read on 2026-09-29. If the shape has changed since, the check below is what will tell you.

## Try it

Three reads and one paper order, the same as the other MCP recipes:

> What are the busiest Hyperliquid perps markets right now?

> Is BTC trending or in a range?

> What would a 3x long on BTC with 50 USDC cost me?

> Open a paper account with 1000 dollars, then take that long on paper.

The order goes in two steps, always: `perps_open` with `paper: true` and no `confirm` answers
the quote and the policy check with a `quote_id` and executes nothing; only after you agree
does `confirm: true`, with that `quote_id`, fill it. `perps_open` carries `destructiveHint`, so a client that honours annotations asks
first. Do not put these tools on any auto-approve list.

[`../mcp-claude-desktop/`](../mcp-claude-desktop/) walks through the same conversation in more
detail.

## What this server cannot do

- It has no key. `lpa init` (the phone approves the agent) and `lpa unlock` (the password opens
  the agent key) are typed by a person in their own terminal. The paper account needs neither.
- `perps_deposit`, `perps_withdraw` and `perps_transfer` move funds, so they are signed on the
  phone: those tools answer the exact line for you to type, and stop there.
- It cannot get around the policy, checked before every order and again before a real one is
  signed.

## check.sh

```sh
./check.sh
```

It reads `openclaw.json` with nothing but `JSON.parse` (JSON5 accepts plain JSON, so no
dependency is needed), checks it names `mcp.servers.locker` over stdio at `@latest`,
then starts the command it names and checks the answer to `initialize` really is the Locker
server, with its 42 tools. It trades nothing.

```sh
LOCKER_MCP_BIN="node /path/to/packages/mcp/bin/locker-mcp.js" ./check.sh
```
