// A paper bot in about sixty lines: the market read straight from the SDK, the
// order placed through the same library the `lpa` command runs. No key, no
// vault, no guardian: the paper account fills on Hyperliquid's real order book
// with the real fees, and it works before `lpa init`.
//
//   node bot.mjs            picks the busiest market and opens 50 USDC at 3x
//   node bot.mjs ETH        the same on one market
//
// LPA_HOME points at the folder the paper account lives in.

import { getHlMarkets, getHlMid, MIN_ORDER_USD } from '@locker-protocol/agent-wallet-hyperliquid-signer';
import { runCommand, lockerHome, buildQuote, renderQuote } from '@locker-protocol/agent-wallet-hyperliquid-trader';

const NOTIONAL_USD = 50;
const LEVERAGE = 3;

// Everything the library needs: where the folder is, and the environment.
// No `confirm` here, so an order without `--yes` is refused rather than sent.
const ctx = { home: lockerHome(process.env), env: process.env };
const lpa = async (...argv) => (await runCommand(argv, ctx)).result;

// 1. The markets, from the SDK: Hyperliquid's own list, 24 h volume first.
const markets = (await getHlMarkets()).sort((a, b) => Number(b.dayNtlVlm) - Number(a.dayNtlVlm));
const symbol = process.argv[2] ?? markets[0].name;
const market = markets.find((m) => m.name === symbol);
if (!market) throw new Error(`No market named ${symbol} on the main dex.`);
console.log(`${market.name}: 24 h volume $${Math.round(Number(market.dayNtlVlm)).toLocaleString('en-US')}, up to ${market.maxLeverage}x`);

// 2. The mid, and the size in the base asset: orders are never sized in dollars.
const mid = await getHlMid(symbol);
const size = (NOTIONAL_USD / mid).toFixed(market.szDecimals);
if (Number(size) * mid < MIN_ORDER_USD) throw new Error(`Under Hyperliquid's $${MIN_ORDER_USD} minimum.`);

// 3. The quote, before anything else. The same one the command shows, fees as
//    one total: Hyperliquid's own plus Locker's builder fee, never split.
const quote = await buildQuote(
    { symbol, side: 'long', size, leverage: LEVERAGE, type: 'market', maxSlippageBps: 300 },
    { lockerFeeApplies: true },
);
process.stdout.write(renderQuote(quote));

// 4. The paper account, opened once. `--reset` would start it over.
await lpa('paper', 'init', '--budget', '1000').catch(() => undefined);

// 5. The order. `--paper` sends it to the paper account; `--yes` is the user's
//    agreement, which in a script is the person who typed the command line.
//    Without it the library answers CONFIRMATION_REQUIRED and signs nothing.
const fill = await lpa('perps', 'open', '--symbol', symbol, '--side', 'long', '--size', size, '--leverage', String(LEVERAGE), '--paper', '--yes');
console.log(fill.executed ? 'Paper order filled.' : 'Nothing was executed.');

// 6. What the account holds now, and what it has paid. The fees are one
//    total: Hyperliquid's and Locker's added, the way every quote shows them.
const status = await lpa('paper', 'status');
const feesUsd = status.hlFeesUsd + status.lockerFeesUsd;
console.log(`Paper equity $${status.equityUsd.toFixed(2)} (budget $${status.budgetUsd.toFixed(2)}), fees $${feesUsd.toFixed(4)} over ${status.fills} fills`);
for (const p of status.positions) console.log(`  ${p.symbol} ${p.size} at ${p.entryPx}, mark ${p.markPx ?? '-'}, PnL $${(p.unrealizedPnlUsd ?? 0).toFixed(2)}, ${p.leverage}x`);

// 7. And the way out, so the recipe leaves nothing open.
await lpa('perps', 'close', '--symbol', symbol, '--paper', '--yes');
console.log(`Closed ${symbol} on paper.`);
