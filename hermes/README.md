# The MCP server in Hermes Agent

**Your private key is nowhere: not on our servers, not on the agent's machine, not with anyone.**

The agent trades. It holds nothing.

Hermes Agent, from Nous Research, starts the server on your computer, over stdio. Forty-one
tools: markets, quotes, positions, the market regime, the paper account, copies of other
traders, the policy, the mandate, the journal. About five minutes, all of it on paper.

## The configuration

Hermes keeps its settings in `~/.hermes/config.yaml`, and reads MCP servers from the
`mcp_servers` block of that file. Add the `locker` entry to yours, from
[`config.yaml`](config.yaml):

```yaml
mcp_servers:
  locker:
    command: "npx"
    args: ["-y", "--ignore-scripts", "@locker-protocol/agent-wallet-hyperliquid-trader-mcp@latest"]
    enabled: true
    timeout: 120
    connect_timeout: 60
```

| Field | What it is |
|---|---|
| `command` | The executable to launch |
| `args` | Its arguments, as a list |
| `env` | Environment variables for the subprocess. Not needed here |
| `enabled` | `false` skips the server entirely |
| `timeout` | Tool call timeout, in seconds |
| `connect_timeout` | Initial connection timeout, in seconds |
| `supports_parallel_tool_calls` | Concurrent calls from this server |
| `tools.include`, `tools.exclude` | Narrow the tools this server offers |

It asks for `@latest`, so each start runs the newest release. Node 22.13 or later.

After editing the file, `/reload-mcp` picks the change up without restarting Hermes.

There is also a `hermes mcp` command group (`hermes mcp add`, `hermes mcp list`). The exact
flags of `hermes mcp add` for a stdio server are not spelled out on the pages read below, so
run `hermes mcp add --help` rather than trust a line copied from here. The YAML above is the
path this recipe checks, and it needs no CLI.

**Where these came from:**
[hermes-agent.nousresearch.com/docs/user-guide/features/mcp](https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp),
[.../docs/user-guide/configuration](https://hermes-agent.nousresearch.com/docs/user-guide/configuration)
and
[.../docs/reference/mcp-config-reference](https://hermes-agent.nousresearch.com/docs/reference/mcp-config-reference),
all read on 2026-09-29. Two of those pages name `~/.hermes/config.yaml` and the `mcp_servers`
block in it; the reference page gives the schema without naming a file, so the path above is
the one the other two agree on. If yours differs, the block is the same either way, and the
check below is what will tell you.

The configuration page also notes that Cursor and Claude style MCP configs work unchanged in
the `mcp_servers` block, so [`../mcp-cursor/mcp.json`](../mcp-cursor/mcp.json) is a starting
point too.

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

It reads `config.yaml` with a YAML reader of about forty lines written for this one block, no
dependency: a tab, a line that is not `key: value`, or an indentation that is not 2 or 4 spaces
stops it rather than being guessed at. It checks the block names `mcp_servers.locker` at
`@latest`, then starts the command it names and checks the answer to `initialize` really
is the Locker server, with its 42 tools. It trades nothing.

```sh
LOCKER_MCP_BIN="node /path/to/packages/mcp/bin/locker-mcp.js" ./check.sh
```
