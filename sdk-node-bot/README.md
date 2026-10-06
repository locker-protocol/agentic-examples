# A paper bot in about sixty lines

**Your private key is nowhere: not on our servers, not on the agent's machine, not with anyone.**

The agent trades. It holds nothing.

[`bot.mjs`](bot.mjs) reads the markets from `@locker-protocol/agent-wallet-hyperliquid-signer`, builds the quote and
places a paper order through `@locker-protocol/agent-wallet-hyperliquid-trader`, the same library the `lpa` command runs.
No key, no vault, no guardian. About five minutes.

## Run it

```sh
npm install
node bot.mjs
node bot.mjs ETH
```

Node 22.13 or later. `LPA_HOME` picks the folder the paper account lives in; without it, `~/.lpa`.

```
BTC: 24 h volume $2,140,277,131, up to 40x
LONG 0.0006 BTC at 3x (market)
  entry        83424   (mid 83421.5, worst accepted 85924)
  notional     $50.05   margin $16.68
  fees         0.095% ($0.0476)   (base tier)
  liquidation  56320   (estimate, this order alone, cross margin)
Paper order filled.
Paper equity $999.96 (budget $1000.00), fees $0.0475 over 1 fills
  BTC 0.0006 at 83424, mark 83432, PnL $0.00, 3x
Closed BTC on paper.
```

One run of the real market on 2026-09-29. Yours will differ.

## What it uses

`@locker-protocol/agent-wallet-hyperliquid-signer` is the read and signing side, straight from Hyperliquid:

| Export | What it gives |
|---|---|
| `getHlMarkets()` | Every market of the main dex: name, mid, mark, 24 h volume, max leverage, `szDecimals` |
| `getHlMid(coin)` | One market's mid |
| `MIN_ORDER_USD` | Hyperliquid's floor, $10 of notional |

`@locker-protocol/agent-wallet-hyperliquid-trader` is the command library:

| Export | What it gives |
|---|---|
| `lockerHome(env)` | The folder: `LPA_HOME`, or `~/.lpa` |
| `runCommand(argv, ctx)` | Runs one command, exactly as `lpa` would, and returns its result |
| `buildQuote(input, opts)` | The quote: entry and worst price, notional, margin, fees, liquidation |
| `renderQuote(quote)` | That quote as the text the command prints |

The context is the whole setup:

```js
const ctx = { home: lockerHome(process.env), env: process.env };
const { result } = await runCommand(['paper', 'status'], ctx);
```

A context with no `confirm` is a context that cannot be asked. `lpa perps open` then refuses with
`CONFIRMATION_REQUIRED` unless `--yes` is on the line, so a program never opens a position by
accident: the `--yes` in `bot.mjs` is the agreement of whoever typed `node bot.mjs`.

An agent given this library should still quote, show the quote and wait, exactly as it would on
the command line.

## Sizing, and the fees

Orders are sized in the base asset, never in dollars, so the bot reads the mid and divides:
`(50 / mid).toFixed(market.szDecimals)`. Hyperliquid refuses anything under $10 of notional,
which is what `MIN_ORDER_USD` guards.

The fees are one total everywhere: Hyperliquid's own trading fee and Locker's builder fee added
together, in the quote (`fees 0.095% ($0.0476)`) and in what the bot prints back. Never show a
part of that total.

## Going real: the vault signs, not the program

This recipe stays on paper. Real trading splits in two.

**Orders** are signed by the agent key, in the guardian: a process the person starts with
`lpa unlock`, typed by them, which holds the key in memory. No program here ever holds it.

**Everything that moves funds** is signed by Locker Vault, on the phone, through the QR ceremony.
That is the interface the SDK puts where a browser wallet would be: give it a payload, get back a
signature, with a person and a phone in the middle.

```ts
/** What lpa needs of Locker Vault. Nothing else of the account's key is reachable. */
interface UserSigner {
    /** An EIP-712 payload (approveAgent, withdraw3, spotSend, sendAsset...). Returns the 65-byte signature. */
    signTyped(payload: HlTypedPayload, caption: string): Promise<string>;
    /** An EVM transaction (the USDC deposit to Hyperliquid's bridge on Arbitrum). Returns the raw signed transaction. */
    signTransaction(tx: ethers.Transaction, caption: string): Promise<string>;
}
```

`@locker-protocol/agent-wallet-vault` is what implements it, in four calls. This is the body of `signTyped`,
as `lpa` runs it:

```ts
import { buildSignRequest, DataType, parseSignatureUr, assertRequestIdMatches, toRpcSignature } from '@locker-protocol/agent-wallet-vault';

const req = buildSignRequest({
    signDataHex: ethers.hexlify(ethers.toUtf8Bytes(JSON.stringify(payload))),
    dataType: DataType.typedData,
    chainId: payload.domain.chainId,
    address: account.address,   // the vault account, read from its sync QR
    path: account.path,
    xfpHex: account.xfpHex,
    origin: 'Locker Protocol Agentic',
});

ceremony.show(req.frames, caption);                 // the animated QR the phone reads
const answer = await ceremony.scan('eth-signature'); // the phone's answer, read by the webcam
const parsed = parseSignatureUr(answer);
assertRequestIdMatches(parsed, req.requestIdHex);    // the answer belongs to this request
const signature = toRpcSignature(parsed);
```

`sealTransaction(unsignedHex, parsed)` is the transaction counterpart, and it checks that the
signed transaction really comes from the account before anything is broadcast.

**This recipe does not run it.** It needs a phone with Locker Vault in front of a webcam, and it
is a person's ceremony, not a program's: `lpa init`, `lpa perps deposit`, `lpa perps withdraw`,
`lpa perps transfer` and `lpa agent revoke` are the commands that use it.
[`../vault-setup/`](../vault-setup/) walks through it step by step.

## check.sh

```sh
./check.sh
```

It copies `bot.mjs` into a throwaway folder, installs the packages there, runs the bot on a
throwaway `LPA_HOME`, and checks its output: the quote with the fees as one total, the paper fill,
the equity, the close, and a journal with nothing but paper lines. It removes both folders at the
end, and places no real order.

Against a checkout instead of the published packages, the checkout's packages are packed with
`npm pack` into a temporary folder and installed there as tarballs. Nothing is linked globally
and nothing is written inside the checkout:

```sh
LOCKER_MONOREPO=/path/to/locker-agentic ./check.sh
```

or, with the tarballs already made:

```sh
npm pack --pack-destination /tmp/locker-tgz /path/to/packages/hyperliquid
npm pack --pack-destination /tmp/locker-tgz /path/to/packages/vault
npm pack --pack-destination /tmp/locker-tgz /path/to/packages/agentic
LOCKER_PACKAGES_DIR=/tmp/locker-tgz ./check.sh
```

`@locker-protocol/agent-wallet-vault` is packed too: `@locker-protocol/agent-wallet-hyperliquid-trader` depends on it.
