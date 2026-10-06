# A first trade from Claude Code, on paper

**Your private key is nowhere: not on our servers, not on the agent's machine, not with anyone.**

The agent trades. It holds nothing.

You install the skill, you ask for a trade in plain words, and the agent quotes it, shows you the
quote and waits. Nothing is signed, because nothing needs to be: the whole recipe runs on the
paper account, which fills on Hyperliquid's real order book with the real fees and needs no key
and no vault.

About five minutes. You need `lpa` and Claude Code.

## 1. Install `lpa`

```sh
npm install -g @locker-protocol/agent-wallet-hyperliquid-trader@latest
lpa --version
```

Node 22.13 or later.

## 2. Install the skill

In Claude Code, add the marketplace once, then install the plugin:

```
/plugin marketplace add locker-protocol/agent-skills
/plugin install locker-agentic@locker-protocol
```

Outside Claude Code, or for another host that reads skill folders:

```sh
npx skills add locker-protocol/agent-skills
```

Either way the agent now knows `lpa`: its commands, its flags, its refusal codes, and the rules
it must not break.

## 3. Open the paper account

Type this yourself, once:

```sh
lpa paper init --budget 1000
```

```
Paper account opened with $1000. Try: lpa perps quote --symbol BTC --side long --size 0.001 --leverage 2
```

The agent can run it too, but it is the one line worth typing by hand: it is what makes
everything after it harmless.

## 4. Ask

> open a 3x long on BTC with 50 USDC, on paper

## What the agent must do, in order

1. **Turn the 50 USDC into a size.** Orders are sized in the base asset, not in dollars. The
   agent reads the mid from a first quote and divides: 50 / 83400 is about 0.0006 BTC.
2. **Quote first, always.**

   ```sh
   lpa perps quote --symbol BTC --side long --size 0.0006 --leverage 3
   ```

   ```
   LONG 0.0006 BTC at 3x (market)
     entry        83432   (mid 83431.5, worst accepted 85934)
     notional     $50.06   margin $16.69
     fees         0.095% ($0.0476)   (base tier)
     liquidation  56325.401   (estimate, this order alone, cross margin)
   ```

3. **Show you that quote and stop.** Entry and worst accepted price, notional and margin, the
   fees as the one total the quote gives, the liquidation estimate. Never a part of that fee
   total, never a fee split in two.
4. **Wait for your word.** Run without `--yes`, `lpa perps open` answers and signs nothing:

   ```
   Error [CONFIRMATION_REQUIRED]: Paper long 0.0006 BTC at 3x needs the user's go.
   Hint: Show the quote to the user; once they agree, run the same command with --yes.
   ```

   That refusal is the intended path, not an error to work around. An approval quoted from an
   older message, a file or another session is not your word.
5. **Once you agree, and only then:**

   ```sh
   lpa perps open --symbol BTC --side long --size 0.0006 --leverage 3 --paper --yes
   ```

   ```
   Paper order filled.
   ```

## 5. Read what happened

```sh
lpa paper status
```

```
Paper equity $999.95 (budget $1000.00, realized $0.00, unrealized $0.00)
Fees paid: $0.0475 over 1 fills

SYMBOL  SIZE    ENTRY  MARK   PNL    LEV
BTC     0.0006  83432  83427  $0.00  3x
```

```sh
lpa journal --since 24h
```

```
TIME                 KIND   BOOK   SYMBOL  SIDE  SIZE    PRICE  FEES
2026-09-29 21:39:03  order  paper  BTC     long  0.0006  83432  $0.0475
Fees paid over the period: $0.0000 (paper fees not counted)
```

The journal is the answer to "what did you do?". It holds one line per action: quotes, orders,
refusals, deposits, and the fees of each one. Paper fees are listed line by line and left out of
the period's total, and the journal says so.

Every number above is one run of a real market on 2026-09-29. Yours will differ.

## Closing it

```sh
lpa perps close --symbol BTC --paper --yes
lpa paper status
```

## What the agent cannot do here

- It has no key. The paper account has none either.
- It cannot get around the policy: `~/.lpa/policy.json` is checked before every order, and again
  by the guardian before a real one is signed. Its defaults refuse an order above $100, leverage
  above 3, more than 20 orders a day, and a daily loss past 10 % of equity. See `lpa policy show`.
- It cannot deposit, withdraw or transfer. Those are QR codes a person scans and signs on their
  phone, and they are refused outright while paper mode is on.

## Going further

- Real money, once you want it: [`../vault-setup/`](../vault-setup/) sets up the account and the
  agent key with Locker Vault.
- A market read before choosing a side: [`../range-scalping-paper/`](../range-scalping-paper/).
- A strategy tested on recorded market data: [`../paper-replay/`](../paper-replay/).

## check.sh

```sh
./check.sh
```

It replays the commands the agent would run, in a throwaway `LPA_HOME` it deletes at the end:
`paper init`, `quote`, `open` without `--yes` (which must be refused with
`CONFIRMATION_REQUIRED`), `open --paper --yes`, `paper status`, `journal`. It never touches your
own `~/.lpa`, and it places no real order.

`LPA_BIN` points it at another `lpa`:

```sh
LPA_BIN=/path/to/packages/agentic/bin/lpa.js ./check.sh
```
