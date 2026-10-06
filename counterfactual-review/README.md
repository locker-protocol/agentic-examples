# The exit you did not take

**Your private key is nowhere: not on our servers, not on the agent's machine, not with anyone.**

The agent trades. It holds nothing.

You closed a position by hand, or something else closed it for you. Would leaving the original
take-profit and stop-loss in place have been better? [`review.mjs`](review.mjs) reads the closed
trade from the journal, reads Hyperliquid's candles from the moment of the close, and walks them
forward until one of the two levels is crossed.

One file, no dependency, about 130 lines. It reads, it never writes, and it never trades.

## Run it

```sh
lpa paper init --budget 1000
lpa perps open --symbol BTC --side long --size 0.0006 --leverage 3 --tp 83862.6 --sl 83194.4 --paper --yes
# ... some time later, you close it by hand
lpa perps close --symbol BTC --paper --yes

node review.mjs --tp 83862.6 --sl 83194.4 --minutes 150
```

```
BTC LONG 0.0005, paper

  opened      83556   2026-09-29 19:33
  closed      83556   2026-09-29 19:34   held 1 min
  take-profit 83591.5
  stop-loss   83445
  fees        $0.0794 in all

  what it made          -$0.0794   (net of fees)
  followed for          150 min, 151 candles of 1 min from Hyperliquid
  first level reached   stop-loss at 83445, 2026-09-29 19:44
  what that gives       -$0.1348   (net of fees, exit fee at the entry's rate)

VERDICT: closing it by hand saved $0.0554 against leaving those levels in place.
```

| Flag | What it does |
|---|---|
| `--symbol <S>` | The market. The last closed trade of any market otherwise |
| `--tp <price>` | The take-profit the trade had |
| `--sl <price>` | The stop-loss it had |
| `--since <d>` | How far back to read the journal. `7d` by default |
| `--minutes <n>` | How long to follow the market after the close. 240 by default |

`LPA_BIN` points it at another `lpa`.

## Where the levels come from

**The journal records the order, not the take-profit and the stop-loss it carried.** A `lpa
journal --format json` line holds the time, the market, the side, the size, the price, the
notional and the fees, and nothing about the two levels. So they have to come from you:

```sh
node review.mjs --tp 83862.6 --sl 83194.4
```

or from [`plan.json`](plan.json) beside the script, which is the version worth keeping if you do
this more than once. The numbers in the file are the levels of one run and mean nothing on your
trade: replace them with yours, one entry per market.

```json
{
  "ETH": { "tp": 2704.8, "sl": 2664.7 },
  "BTC": { "tp": 83779, "sl": 82634.75 }
}
```

Without either, the script refuses and says so. It never guesses a level, and levels that do not
frame the entry (a take-profit below a long's entry, say) are refused too.

## How it decides

It asks Hyperliquid for the 1 m candles from the close onwards, and walks them in order:

- only the minutes that **begin** after the close. The candle the close falls inside holds
  prices from before it, and those are not this trade's future;
- for a long, the take-profit is reached when a candle's high touches it and the stop-loss when
  its low does; for a short, the other way round;
- a candle that reaches **both** counts as the stop. That is the same pessimistic convention
  `lpa paper replay` uses, and for the same reason: from a 1 m candle you cannot tell which came
  first, and assuming the good one is how a backtest lies to you;
- if neither is reached inside the window, the trade is marked at the last close and the report
  says it was still open.

The fees are one total throughout: what the journal charged on the entry and the real exit, and
for the exit that did not happen, the entry's own fee rate applied to that exit's notional.

## What this is, and what it is not

This is the review of **one** trade. It answers "what would that exit have given", and nothing
else. It is not:

- a measure of a rule. "Closing by hand saved money" on one trade says nothing about closing by
  hand. Twenty of these all pointing the same way is a hypothesis, not a result;
- a backtest. It looks at one window after one close, with the levels you already had;
- a reason to change a strategy, and certainly not a reason to open a real position.

The version of this that means something is [`../paper-replay/`](../paper-replay/): the same
question over hundreds of trades on a recorded tape, with a gate that stays closed until there
are 300 settled trades and the lower bound of the win rate clears the costs. Use this recipe to
understand a trade; use the replay to judge a rule.

The output says the same thing in its last three lines, so an agent reading it out loud says it
too.

## Where the idea comes from

An earlier range-scalping bot of ours closed positions on a breakout detector rather than on
their own stop. Reviewing a session trade by trade, one close at a time, against the prices that
followed, showed that the detector saved a large loss on one trade and cost two winners on two
others. No single trade would have shown that; the trade-by-trade review over a session did.
This recipe is that review, for `lpa`.

## check.sh

```sh
./check.sh
```

It opens and closes one paper trade and runs `review.mjs` on it, then runs it again on a fixture
built from Hyperliquid's own candles two hours back, with levels set inside the range the market
actually traded, so a level has to be crossed and the walk is proven rather than asserted. It
also checks the two refusals: no levels, and levels on the wrong side of the entry. Throwaway
folders, deleted at the end, no real order.

```sh
LPA_BIN=/path/to/packages/agentic/bin/lpa.js ./check.sh
```
