# Range scalping, on paper

**Your private key is nowhere: not on our servers, not on the agent's machine, not with anyone.**

The agent trades. It holds nothing.

Find the markets that are going sideways, check the one you picked is really in a range, then
place one paper order whose take-profit and stop-loss fit that range instead of being round
numbers. About five minutes, nothing signed, no real order.

Every figure on this page is one run of the real market on 2026-09-29. **None of them is a
recommendation, and none of them came from a strategy that was measured.** They are there to
show the shape of the answers.

## 1. Which markets are in a range

```sh
lpa perps ranges --limit 5
```

```
SYMBOL  RANGE%  VOL%  RANGINESS  SCORE  SUPPORT  RESISTANCE
ZEC     4.43    0.88  5.06       5.06   1378     1439.1
HYPE    2.35    0.48  4.89       4.89   84.759   86.752
ETH     0.89    0.23  3.93       3.93   2677.7   2701.5
BTC     0.44    0.09  4.77       0.00   83334    83697
NEAR    5.99    1.28  4.66       0.00   4.8804   5.1725
In a range now: ZEC, HYPE, ETH (3 of 5 scanned).
```

The last four hours, market by market. `RANGE%` is the width as a percentage of price, `VOL%`
the volatility on the same basis, `RANGINESS` their ratio, and `SCORE` runs from 0 to 10 and
falls to 0 outside a width of 0.5 % to 5 %. The two zeros are the two ways to fail: NEAR is too
wide at 5.99 % to scalp, and BTC too tight at 0.44 %, where the fees eat the whole move.

`SUPPORT` and `RESISTANCE` are the edges the last four hours actually traded between. They are
an observation, not a promise, and neither one holds because it is printed here.

`--limit <n>` scans more markets, `--dex <name>` or `--all-dexes` looks at the HIP-3 dexes.

## 2. Is it really in a range

```sh
lpa perps regime --symbol ETH
```

```
ETH: range, trend score +0.18
  EMA stack     -0.32, leaning down
  structure     uptrend: higher highs and higher lows on the 4 h candles
  momentum      5 m micro -0.34, slope +0.0005 %/min
  RSI           14: 48.6, 6: 43.4
  volatility    ATR 4 h 1.50% of price, contracting (-43.1%); 1 h over 4 h 0.45
  volume        0.57x the 24 h average, rising (+89.4%)
  age           this regime has held 3 h
```

Five states, `StrongBull`, `WeakBull`, `Range`, `WeakBear`, `StrongBear`. `lpa perps ranges`
measures the shape of the last four hours; `lpa perps regime` measures the market. Both have to
agree before a range trade makes any sense.

Two lines are worth more than the verdict:

- **age**: `this regime has held 3 h` is how long the state has lasted. A regime that has just
  turned is the least reliable kind, and a scalp taken on one is a coin flip with fees.
- **volume**: `0.57x the 24 h average` is a thin book. The worst accepted price in the quote is
  where that shows up.

Both commands read the past. Neither is a forecast, and a regime can change while an order is
in flight.

## 3. The levels, and what they make the order

Take ETH above: support 2677.7, resistance 2701.5, width 23.8, price 2685.7. That is the lower
half of the range, so the trade is a long from the support.

| | | How it is built |
|---|---|---|
| entry | 2685.7 | the market |
| take-profit | 2701.5 | the far edge of the range |
| stop-loss | 2671.75 | a quarter of the range beyond the near edge |

The rule is the same from the other side: short from the upper half, target the support, stop a
quarter of the range above the resistance. Both levels come from the range and not from a round
percentage, and the stop sits beyond the level that defines the trade: if the price goes through
it, the reason for the trade is gone.

Putting the stop a quarter of the range beyond the edge, rather than at a fixed percentage, is
also what keeps the risk:reward in bounds on a tight range and a wide one alike.

The quote says what that costs, and what the two levels make of it:

```sh
lpa perps quote --symbol ETH --side long --size 0.018617 --leverage 2 --tp 2701.5 --sl 2671.75
```

```
LONG 0.0186 ETH at 2x (market)
  entry        2685.7   (mid 2685.65, worst accepted 2766.2)
  notional     $49.95   margin $24.98
  fees         0.095% ($0.0475)   (base tier)
  liquidation  1370.2551   (estimate, this order alone, cross margin)
  take profit  2701.5
  stop loss    2671.75
  risk:reward  0.88x   (the stop's distance from the entry, over the take profit's)
```

Orders are sized in the base asset, so 50 USDC of notional is `50 / 2685.7`, and the command
rounds that down to the size the market trades.

The fees are one total: Hyperliquid's own trading fee and Locker's builder fee added. Never a
part of it.

`risk:reward 0.88x` is the stop's distance over the target's. Under 1 you are risking less than
you are reaching for. The policy refuses an order past 3:

```
Error [POLICY_REJECTED]: The policy refuses this order: the stop-loss is 10.1132x further from
the entry than the take-profit (53.6 against 5.3), above the 3x allowed.
Hint: See `lpa policy show`. Closing and cancelling are always allowed.
```

That guard came out of measured losses on a bot that ran for months: the trade that reaches for
a few basis points and risks a full range is the one that quietly eats the account.
`lpa policy set --max-risk-reward <n>|never` changes it.

## 4. The paper order

```sh
lpa paper init --budget 1000
lpa paper on
lpa perps open --symbol ETH --side long --size 0.018617 --leverage 2 --tp 2701.5 --sl 2671.75 --yes
```

The quote again, then:

```
Paper order filled.
```

Then:

```sh
lpa paper status
```

```
Paper equity $999.95 (budget $1000.00, realized $0.00, unrealized -$0.01)
Fees paid: $0.0475 over 1 fills

SYMBOL  SIZE    ENTRY   MARK    PNL     LEV
ETH     0.0186  2685.7  2685.4  -$0.01  2x
```

`lpa perps positions` reads the same account while paper mode is on, and `lpa paper off` puts
the perps commands back on the real one.

## What a paper order does not do, and what to do about it

**A paper order fills at once or not at all.** There is no resting order on the paper account.
Two consequences, both worth knowing before you build anything on this:

A limit that does not cross the book is refused outright:

```
Error [BAD_ARGUMENTS]: The paper account fills at once or not at all: a resting limit order is
not simulated.
Hint: Use a market order, or a limit that crosses the book.
```

And the take-profit and the stop-loss are quoted, checked against the risk:reward guard, and
then **not placed**: no trigger order rests behind a paper position.

```
$ lpa perps orders
No paper order: a paper order fills at once or not at all.
```

On a real account both exist: `lpa perps open` sends the triggers with the order, and
`lpa perps modify --symbol ETH --tp <p> --sl <p>` sets them on a position that is already open.
On paper, you close by hand:

```sh
lpa perps close --symbol ETH --paper --yes
```

So the honest version of this recipe is: **paper shows you the entry and the cost; it does not
show you the exit.** The part this leaves out, a limit resting at the support, a native stop
that fires while you are asleep, and what either would have been worth over days, is exactly
what [`../paper-replay/`](../paper-replay/) is for. Its simulator fills a resting limit only
when a candle goes through the price, counts a candle that hits both the target and the stop as
a loss, and ends on a verdict. That is where a range strategy gets tested, not here.

[`../counterfactual-review/`](../counterfactual-review/) is the other half: once a paper trade
is closed, it reads the candles after the close and says what the original take-profit and
stop-loss would have given.

## What this recipe is not

- Not a strategy. The levels above are one market on one afternoon.
- Not a measured result. No number here comes from a tested edge, and none is presented as one.
- Not a reason to open a real position. A reading of the past says nothing about the next hour.

An agent running this should show the two readings, the quote and the risk:reward together, and
wait for the user. `lpa perps open` without `--yes` answers `CONFIRMATION_REQUIRED` and signs
nothing, which is the intended path.

## check.sh

```sh
./check.sh
```

It runs the whole sequence in a throwaway `LPA_HOME`: `perps ranges`, `perps regime`, then a
market that is in a range now and trading inside it, the side picked by which half of the range
the price sits in, and a quote whose take-profit and stop-loss are built from that market's real
support and resistance by the rule above. Then the paper order, and the two refusals this page
claims, the resting limit and the risk:reward guard. It checks that the order is between
Hyperliquid's $10 floor and the policy's $100 ceiling, that no trigger order rests behind the
paper position, closes it by hand, and deletes the folder. No real order, nothing signed.

```sh
LPA_BIN=/path/to/packages/agentic/bin/lpa.js ./check.sh
```
