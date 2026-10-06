# Writing a plugin

**Your private key is nowhere: not on our servers, not on the agent's machine, not with anyone.**

The agent trades. It holds nothing.

A plugin adds a command to `lpa` and a tool to the MCP server. This one is two files: a
`package.json` that says what it adds and what it needs, and a `plugin.mjs` of about forty lines
that ranks the markets by funding. It runs in a separate process that reads its own folder and
nothing else, and it asks `lpa` for the markets through the one capability it declared.

About five minutes. Nothing is signed and no order of any kind is placed.

## 1. The manifest

[`lpa-plugin-funding/package.json`](lpa-plugin-funding/package.json):

```json
{
  "name": "lpa-plugin-funding",
  "version": "1.0.0",
  "files": ["plugin.mjs"],
  "lpa": {
    "schemaVersion": 1,
    "name": "funding",
    "main": "plugin.mjs",
    "commands": [
      {
        "name": "scan",
        "summary": "The markets paying the most funding.",
        "capabilities": ["market-read"],
        "options": { "top": "string" }
      }
    ],
    "tools": [
      { "name": "funding_scan", "command": "scan", "description": "The markets paying the most funding, highest first." }
    ]
  }
}
```

| Field | What it says |
|---|---|
| `lpa.name` | The word it is run by: `lpa funding scan` |
| `lpa.commands[].capabilities` | What this command may ask `lpa` for, and nothing more. `market-read` reads prices, candles and order books |
| `lpa.commands[].options` | Its flags, `"string"` or `"boolean"`. `lpa` parses them, and refuses one that is not declared |
| `lpa.tools` | The same command offered to agents through MCP, as `plugin_funding_scan` |

No `dependencies`: where the plugin runs, it cannot read anything outside its own folder, so a
`node_modules` would not load. No `scripts` either: `lpa` never runs them.

## 2. The code

[`lpa-plugin-funding/plugin.mjs`](lpa-plugin-funding/plugin.mjs) reads one JSON object per line
on its standard input and writes one per line on its standard output:

```text
lpa    -> plugin   {"type":"run","command":"scan","args":{"top":"3"}}
plugin -> lpa      {"type":"call","id":1,"capability":"market-read","method":"markets","params":{}}
lpa    -> plugin   {"type":"result","id":1,"result":[{"name":"BTC","funding":"0.0000125",...}]}
plugin -> lpa      {"type":"done","text":"...","data":{"top":[...]}}
```

`text` is what a person reads; `data` is what `--json` and an agent get. A plugin that cannot
answer writes `{"type":"fail","message":"why"}`.

## 3. Install it

```sh
lpa plugins install --from ./lpa-plugin-funding
```

```
Plugin funding (lpa-plugin-funding 1.0.0) adds:
  lpa funding scan  The markets paying the most funding.
and 1 tool for agents: funding_scan.
It asks to:
  - read the markets: prices, candles, order books
It runs in a separate process that reads its own folder only: it cannot read your keys, your settings or your journal files, start a program, or reach the guardian. It can reach the network, and it knows your user name, the name of this computer and its network addresses, which it can send elsewhere. It signs nothing for your real account.
Install the plugin funding? [y/N] y
Plugin funding 1.0.0 installed: lpa funding scan.
```

The folder is packed by npm and unpacked by tar, as a package from the registry would be, and
kept with the fingerprint of every file. Published on npm, the same line takes its name:
`lpa plugins install --from lpa-plugin-funding`.

## 4. Run it

```sh
lpa funding scan --top 3
```

```
xyz:CVX      0.000439127  (384.7% a year)
APEX         0.0002397866  (210.1% a year)
xyz:PURRDAT  0.0001940642  (170.0% a year)
```

```sh
lpa funding scan --top 3 --json
```

```json
{
  "text": "xyz:CVX      0.000439127  (384.7% a year)\n...",
  "data": {
    "top": [
      { "name": "xyz:CVX", "funding": "0.000439127", "yearly": "384.7%" },
      { "name": "APEX", "funding": "0.0002397866", "yearly": "210.1%" },
      { "name": "xyz:PURRDAT", "funding": "0.0001940642", "yearly": "170.0%" }
    ]
  }
}
```

Funding is the hourly rate, read from Hyperliquid at the moment you run it; the yearly figure is
that rate held for a year, which it never is. The MCP server offers the same command as the
tool `plugin_funding_scan` once it restarts.

## 5. What it cannot do

Change one byte of the installed copy and it does not run:

```
Error [BAD_ARGUMENTS]: The plugin funding changed since you approved it: it does not run.
```

Ask for a capability its command did not declare (here the account instead of the markets) and
it is stopped at that call:

```
Error [PLUGIN_REFUSED]: The plugin funding was stopped: it asked for "account-read", which its command scan did not declare.
```

It cannot read your sealed key, your settings or the guardian's token, and it cannot start a
program. It can reach the network: what it reads through its capabilities, it could send
elsewhere. That is why the install screen lists them, and why you read it.

## check.sh

```sh
./check.sh
```

It installs the plugin into a throwaway `LPA_HOME`, runs `lpa funding scan` in text and in JSON,
then checks the refusals: an undeclared flag, a copy changed after its approval, a capability the
command did not declare. It removes the plugin, deletes the folder at the end, and places no order
of any kind.

```sh
LPA_BIN=/path/to/packages/agentic/bin/lpa.js ./check.sh
```

## Next

The capabilities a plugin may ask for, and the calls of each, are listed in the package's README,
section "Write a plugin".
