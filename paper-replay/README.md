# Replaying a strategy on recorded market data

**Your private key is nowhere: not on our servers, not on the agent's machine, not with anyone.**

The agent trades. It holds nothing.

`lpa paper record` writes Hyperliquid's candles into a tape on your disk. `lpa paper replay`
walks that tape minute by minute with a strategy file, settles every trade it would have taken,
and ends with a verdict. Nothing is signed, nothing is sent, and no position is ever opened.

About five minutes for the first tape.

## 1. Record the market

```sh
lpa paper record --coins BTC,ETH
```

```
Recorded 2 markets into /home/you/.lpa/paper/tape (40166 new rows).

MARKET  1M     5M     1H     4H     FUNDING
BTC     +5000  +5000  +5000  +5000  +83
ETH     +5000  +5000  +5000  +5000  +83

One call reaches about 3.5 days back on the 1 m band: run `lpa paper record` again over days to grow the tape (new rows are appended, the ones already there are kept).
```

Candles at 1 m, 5 m, 1 h and 4 h, plus funding, into `~/.lpa/paper/tape`, files mode 0600.
Without `--coins` it takes the 20 busiest markets of the main dex, BTC always among them.
`--top <n>` and `--min-vlm <usd>` change that choice.

One call reaches about three and a half days back on the 1 m band, which is Hyperliquid's own
limit, not ours. Running it again later appends what is new and keeps what is there, so the
tape grows over days. **That is the point**: a tape of three days is far too short for the
verdict below to mean anything.

## 2. A strategy is a file, never code

[`range-fade.json`](range-fade.json) is the example, copied here from the package:

```json
{
  "version": 1,
  "name": "range-fade",
  "comment": "AN EXAMPLE, NOT ADVICE. ...",
  "when": {
    "markets": { "top": 10 },
    "regime": ["Range"],
    "rsi14": { "min": 30, "max": 70 },
    "rangeWidthPct": { "min": 1, "max": 5 },
    "nearLevel": { "level": "support", "withinPctOfWidth": 25 },
    "minDayVolumeUsd": 5000000
  },
  "order": {
    "side": "fade",
    "sizeUsd": 100,
    "leverage": 2,
    "entry": { "type": "level", "offsetPct": 0.1 },
    "tp": { "rangeShare": 0.5 },
    "sl": { "outsidePct": 1 },
    "ttlHours": 6,
    "cooldownMinutes": 30,
    "maxRiskReward": 3
  }
}
```

Its numbers are round and illustrative. They were picked to show what the schema can say, and
were never measured on any market. The file says so in its own `comment`.

| Field | What it says |
|---|---|
| `when.markets` | A list of markets, or `{ "top": n }` for the busiest. Every recorded market when absent |
| `when.regime` | Any of `StrongBull`, `WeakBull`, `Range`, `WeakBear`, `StrongBear`, as `lpa perps regime` reads them |
| `when.rsi14`, `when.rsi6` | `{ "min", "max" }` between 0 and 100 |
| `when.rangeWidthPct`, `when.nearLevel` | The 4 h range's width, and how close the price is to its support or resistance, as a share of that width |
| `when.volumeRatio`, `when.minDayVolumeUsd` | Volume against its average, and the day's volume floor |
| `order.side` | `long`, `short`, or `fade`: long near the support, short near the resistance |
| `order.sizeUsd`, `order.leverage` | At least $10, the exchange's minimum; leverage 1 to 100 |
| `order.entry` | `{ "type": "market" }`, or a limit resting at the level, `{ "type": "level", "offsetPct": n }` |
| `order.tp`, `order.sl` | A percentage from the entry (`{ "pct": n }`), or tied to the range (`rangeShare`, `outsidePct`) |
| `order.ttlHours`, `order.cooldownMinutes` | How long a limit rests before it is dropped; the pause after a stop |
| `order.maxRiskReward` | The risk to reward ceiling, 3 by default, `"never"` to drop it |

The file is read and never executed. A field the schema does not know is refused by its name, so
a misspelt condition never quietly passes for a true one.

## 3. Replay

```sh
lpa paper replay --strategy range-fade.json
lpa paper replay --strategy range-fade.json --from 7d --coins ETH
```

`--from` and `--to` take a duration back from now (`3d`), a day (`20260925` or `2026-09-25`) or
a timestamp.

## 4. Read the verdict

```
## Verdict

- Settled trades: 7 / 300 needed -> NOT ENOUGH, keep recording
- 95 % lower bound (34.1 %) against the win rate needed in the base scenario (72.7 %) -> BELOW
- Per settled trade, base scenario: -$0.03

**GATE NOT CLEARED**: this strategy is not proven on this tape. The tape grows by running `lpa paper record` again.
```

**GATE NOT CLEARED on a short tape is the normal outcome, not a failure of the strategy and not
a bug.** Two things have to hold at once for the gate to clear:

1. At least 300 settled trades. Three days of two markets gives a handful.
2. The 95 % lower bound of the win rate (Clopper-Pearson) above the win rate the costs require
   in the base scenario.

The replay is deliberately harsh, because the cheap version of this exercise flatters every
strategy:

- a resting limit fills only when a candle goes **through** its price, never on a touch;
- no take-profit on the candle that filled the order;
- a candle that reaches both the take-profit and the stop counts as a **loss**;
- trades cut off by the end of the tape are left out of the win rate;
- real funding from the tape, and the real fees as one total.

The report also gives the costs under three slippage scenarios, what the same strategy would
have done filled on a touch (the adverse-selection counterfactual), why no order was placed,
and each market on its own line. It is written to `~/.lpa/paper/replay-latest.md`, and every
trade to `~/.lpa/paper/trades-latest.jsonl`.

## What a replay is not

**A replay is never a reason to open a real position.** Report it as it is:

- A replay that has not cleared the gate proves nothing, whatever its win rate.
- A replay that has cleared it describes the tape it ran on, which is the past. It says nothing
  about the next trade.
- Tuning a strategy's numbers until the replay passes, then calling it proven, is fitting the
  past. It is the one mistake this whole tool exists to make visible, not to hide.

An agent asked to trade on a replay's result should say all three of those and stop.

## Growing the tape

```sh
lpa paper record --coins BTC,ETH   # run it again tomorrow, and the day after
```

Or leave it to a scheduled job: it appends, never overwrites. A tape of several weeks over ten
or twenty markets is what 300 settled trades usually takes.

## check.sh

```sh
./check.sh
```

It records two markets into a throwaway `LPA_HOME`, replays `range-fade.json` on that tape, and
checks that the report carries a verdict line, that the report file was written, and that a
strategy with a field the schema does not know is refused by that field's name. It deletes the
folder at the end, and places no order of any kind.

```sh
LPA_BIN=/path/to/packages/agentic/bin/lpa.js ./check.sh
```

## Next

[`../range-scalping-paper/`](../range-scalping-paper/) is the live side of the same idea: read
the ranges and the regime now, then place one paper order.
