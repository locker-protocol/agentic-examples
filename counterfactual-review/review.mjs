// What the exit you did not take would have given.
//
// Reads a closed trade from the paper journal, reads Hyperliquid's candles
// from the moment it was closed, and walks them forward against the trade's
// original take-profit and stop-loss. It answers one question: did closing it
// by hand save money, or cost it?
//
//   node review.mjs --tp 2704.8 --sl 2664.7
//   node review.mjs --symbol ETH --tp 2704.8 --sl 2664.7 --minutes 240
//   node review.mjs                       (levels read from plan.json)
//
//   --symbol <S>    the market; the last closed trade of any market otherwise
//   --tp <price>    the take-profit the trade had
//   --sl <price>    the stop-loss it had
//   --since <d>     how far back to read the journal (default 7d)
//   --minutes <n>   how long to follow the market after the close (default 240)
//
// No dependency. It reads, it never writes and it never trades.
//
//   LPA_BIN   the lpa command to run (default: lpa on the PATH)

import { execFile } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { promisify } from 'node:util';

const run = promisify(execFile);
const HL_INFO = 'https://api.hyperliquid.xyz/info';
const LPA = process.env.LPA_BIN ?? 'lpa';

const flags = {};
for (let i = 2; i < process.argv.length; i += 2) flags[process.argv[i].replace(/^--/, '')] = process.argv[i + 1];
const since = flags.since ?? '7d';
const minutes = Number(flags.minutes ?? 240);

const die = (message) => { console.error(message); process.exit(1); };

// 1. The journal: one line per action, paper and real alike.
const { stdout } = await run(LPA, ['journal', '--since', since, '--format', 'json'], { maxBuffer: 16 << 20 })
    .catch((e) => die(`lpa journal failed: ${e.stderr || e.message}`));
const entries = JSON.parse(stdout).entries ?? [];

// 2. The last trade that was opened and then closed: the `close` line, and the
//    `order` line before it on the same market.
const closes = entries.filter((e) => e.kind === 'close' && (!flags.symbol || e.symbol === flags.symbol));
const close = closes[closes.length - 1];
if (!close) die(`No closed trade in the journal over the last ${since}. Open one on paper, close it, and run this again.`);
const opened = entries.filter((e) => e.kind === 'order' && e.symbol === close.symbol && e.ts < close.ts).pop();
if (!opened) die(`Found a close of ${close.symbol} but no order before it.`);

// 3. The levels. The journal keeps the order, not the take-profit and the
//    stop-loss it carried, so they come from where you wrote them down.
let tp = Number(flags.tp);
let sl = Number(flags.sl);
if (!Number.isFinite(tp) || !Number.isFinite(sl)) {
    const plan = await readFile(new URL('./plan.json', import.meta.url), 'utf8').then(JSON.parse).catch(() => null);
    const level = plan?.[close.symbol];
    if (!level) die(`No take-profit and stop-loss for ${close.symbol}. Pass --tp and --sl, or put them in plan.json.`);
    tp = Number(level.tp);
    sl = Number(level.sl);
}

const side = opened.side;               // long or short, the side it was opened on
const size = Number(opened.size);
const entryPx = Number(opened.px);
const exitPx = Number(close.px);
const isLong = side === 'long';
if ((isLong && !(tp > entryPx && sl < entryPx)) || (!isLong && !(tp < entryPx && sl > entryPx))) {
    die(`Those levels do not frame a ${side} entered at ${entryPx}: take-profit ${tp}, stop-loss ${sl}.`);
}

// The fees, as one total, exactly as the journal gives them.
const feePaid = Number(opened.feeUsd ?? 0) + Number(close.feeUsd ?? 0);
const feeRate = Number(opened.feeUsd ?? 0) / Number(opened.notionalUsd ?? 1);
const pnl = (px) => (isLong ? px - entryPx : entryPx - px) * size;
const actualNet = pnl(exitPx) - feePaid;

// 4. The candles after the close, from Hyperliquid itself. Asked from the
//    minute before: in the first instants of a minute Hyperliquid has no
//    candle for it yet, and a close there would find none at all.
const startTime = close.ts - 60_000;
const endTime = close.ts + minutes * 60_000;
const answer = await fetch(HL_INFO, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ type: 'candleSnapshot', req: { coin: close.symbol, interval: '1m', startTime, endTime } }),
});
if (!answer.ok) die(`Hyperliquid answered ${answer.status} for the candles of ${close.symbol}.`);
const all = await answer.json();
if (all.length === 0) die(`Hyperliquid has no candle around ${new Date(close.ts).toISOString()} for ${close.symbol}.`);
// Only the minutes that begin after the close: the candle the close falls
// inside holds prices from before it, and those are not this trade's future.
const candles = all.filter((c) => c.t >= close.ts);

// 5. Walk them. A candle that reaches both counts as the stop: the same
//    pessimistic convention `lpa paper replay` uses, for the same reason.
let hit = null;
for (const c of candles) {
    const high = Number(c.h);
    const low = Number(c.l);
    const tpHit = isLong ? high >= tp : low <= tp;
    const slHit = isLong ? low <= sl : high >= sl;
    if (slHit && tpHit) { hit = { what: 'stop-loss', px: sl, at: c.t, note: 'the same candle reached both, counted as the stop' }; break; }
    if (slHit) { hit = { what: 'stop-loss', px: sl, at: c.t }; break; }
    if (tpHit) { hit = { what: 'take-profit', px: tp, at: c.t }; break; }
}
const last = candles[candles.length - 1] ?? all[all.length - 1];
const outcome = hit ?? {
    what: 'neither',
    px: Number(last.c),
    at: last.t,
    note: candles.length === 0
        ? 'no full minute has closed since, marked at the last price'
        : `still open after ${minutes} min, marked at the last close`,
};
const wouldNet = pnl(outcome.px) - Number(opened.feeUsd ?? 0) - Math.abs(outcome.px * size) * feeRate;
const difference = actualNet - wouldNet;

const money = (n) => `${n < 0 ? '-' : '+'}$${Math.abs(n).toFixed(4)}`;
const plain = (n) => `$${Math.abs(n).toFixed(4)}`;
const when = (ms) => new Date(ms).toISOString().replace('T', ' ').slice(0, 16);
const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;

console.log(`${close.symbol} ${side.toUpperCase()} ${size}, ${opened.paper ? 'paper' : 'real'}`);
console.log('');
console.log(`  opened      ${entryPx}   ${when(opened.ts)}`);
console.log(`  closed      ${exitPx}   ${when(close.ts)}   held ${Math.round((close.ts - opened.ts) / 60000)} min`);
console.log(`  take-profit ${tp}`);
console.log(`  stop-loss   ${sl}`);
console.log(`  fees        $${feePaid.toFixed(4)} in all`);
console.log('');
console.log(`  what it made          ${money(actualNet)}   (net of fees)`);
console.log(`  followed for          ${minutes} min, ${plural(candles.length, 'candle')} of 1 min from Hyperliquid`);
if (outcome.what === 'neither') {
    console.log(`  neither level hit     marked at ${outcome.px} after ${minutes} min`);
} else {
    console.log(`  first level reached   ${outcome.what} at ${outcome.px}, ${when(outcome.at)}`);
}
if (outcome.note) console.log(`                        (${outcome.note})`);
console.log(`  what that gives       ${money(wouldNet)}   (net of fees, exit fee at the entry's rate)`);
console.log('');
console.log(difference >= 0
    ? `VERDICT: closing it by hand saved ${plain(difference)} against leaving those levels in place.`
    : `VERDICT: closing it by hand cost ${plain(difference)} against leaving those levels in place.`);
console.log('');
console.log('One trade, one window. This is a reading of what happened, not an edge and not a');
console.log('reason to change anything. A rule is worth something only over hundreds of trades:');
console.log('that is what `lpa paper replay` is for.');
