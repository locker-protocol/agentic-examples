// A minimal MCP client: JSON-RPC, one message per line, over the server's
// stdin and stdout. No dependency, nothing but Node. It starts the server the
// way a client would, then plays the conversation the recipe describes.
//
//   LOCKER_MCP_BIN   the command line that starts the server
//                    (default: npx -y --ignore-scripts @locker-protocol/agent-wallet-hyperliquid-trader-mcp@latest)
//   LPA_HOME         the folder the server reads and writes
//
// Paper only: the one order it places is a paper order, and no key is used.

import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';

const EXPECTED_TOOLS = 42;
const line = (process.env.LOCKER_MCP_BIN ?? 'npx -y --ignore-scripts @locker-protocol/agent-wallet-hyperliquid-trader-mcp@latest').trim();
const parts = line.split(/\s+/);
const [command, ...args] = parts;

let passed = 0;
let failed = 0;
const ok = (what) => { passed += 1; console.log(`ok   - ${what}`); };
const bad = (what, detail) => {
    failed += 1;
    console.log(`FAIL - ${what}`);
    if (detail !== undefined) console.log(`       ${String(detail).slice(0, 400).replace(/\n/g, '\n       ')}`);
};

const child = spawn(command, args, { stdio: ['pipe', 'pipe', 'inherit'], env: process.env });
child.on('error', (e) => { bad(`the server starts (${line})`, e.message); process.exit(1); });

const waiting = new Map();
createInterface({ input: child.stdout }).on('line', (text) => {
    if (!text.trim()) return;
    let message;
    try { message = JSON.parse(text); } catch { bad('every line the server writes is JSON', text); return; }
    const resolve = waiting.get(message.id);
    if (resolve) { waiting.delete(message.id); resolve(message); }
});

let nextId = 0;
const timeout = (ms, what) => new Promise((_, reject) => setTimeout(() => reject(new Error(`${what}: no answer in ${ms} ms`)), ms).unref());
const rpc = (method, params) => Promise.race([
    new Promise((resolve) => {
        const id = ++nextId;
        waiting.set(id, resolve);
        child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', id, method, params })}\n`);
    }),
    timeout(90_000, method),
]);
const notify = (method, params) => { child.stdin.write(`${JSON.stringify({ jsonrpc: '2.0', method, params })}\n`); };

/** A tool's answer, parsed: the server puts JSON in one text block. */
const callTool = async (name, args_) => {
    const answer = await rpc('tools/call', { name, arguments: args_ });
    const text = answer?.result?.content?.[0]?.text ?? '';
    let value;
    try { value = JSON.parse(text); } catch { value = text; }
    return { isError: answer?.result?.isError === true, value, raw: text };
};

try {
    // 1. The handshake, exactly as a client does it.
    const init = await rpc('initialize', {
        protocolVersion: '2025-06-18',
        capabilities: {},
        clientInfo: { name: 'agentic-examples-check', version: '2.0.0' },
    });
    const info = init?.result?.serverInfo;
    if (info?.name === 'locker-protocol-agentic') ok(`initialize: ${info.name} ${info.version}, protocol ${init.result.protocolVersion}`);
    else bad('initialize answers with the Locker server', JSON.stringify(init));
    notify('notifications/initialized', {});

    // 2. The tools. 42 of its own (a plugin you installed adds plugin_* ones),
    // and the ones the recipe names among them.
    const list = await rpc('tools/list', {});
    const tools = list?.result?.tools ?? [];
    const own = tools.filter((t) => !t.name.startsWith('plugin_'));
    if (own.length === EXPECTED_TOOLS) ok(`tools/list gives ${EXPECTED_TOOLS} tools`);
    else bad(`tools/list gives ${EXPECTED_TOOLS} tools`, `got ${own.length}`);

    const names = new Set(tools.map((t) => t.name));
    const wanted = ['perps_markets', 'perps_quote', 'perps_regime', 'perps_open', 'paper_init', 'journal'];
    const missing = wanted.filter((n) => !names.has(n));
    if (missing.length === 0) ok('the tools the recipe uses are all there');
    else bad('the tools the recipe uses are all there', `missing: ${missing.join(', ')}`);

    // An order is marked destructive, so a client asks before calling it.
    const open = tools.find((t) => t.name === 'perps_open');
    if (open?.annotations?.destructiveHint === true && open?.annotations?.readOnlyHint === false) ok('perps_open is marked destructive, so the client asks first');
    else bad('perps_open is marked destructive', JSON.stringify(open?.annotations));

    // 3. Three reads, the three questions of the recipe. What carries a name a third party
    // chose (a market's) comes marked untrusted, under `data`.
    // What Hyperliquid says comes marked untrusted, the data under `data`: market
    // names are chosen by third parties, so a client reads them as data only.
    const markets = await callTool('perps_markets', { limit: 5 });
    const listed = markets.value?.data?.markets;
    if (!markets.isError && markets.value?.untrusted === true && Array.isArray(listed) && listed.length > 0) ok(`perps_markets: ${listed.length} markets, marked untrusted`);
    else bad('perps_markets answers, marked untrusted', markets.raw);

    const regime = await callTool('perps_regime', { symbol: 'BTC' });
    const regimes = ['StrongBull', 'WeakBull', 'Range', 'WeakBear', 'StrongBear'];
    if (!regime.isError && regime.value?.untrusted === true && regimes.includes(regime.value?.data?.regime)) ok(`perps_regime BTC: ${regime.value.data.regime}`);
    else bad('perps_regime answers one of the five regimes', regime.raw);

    const probe = await callTool('perps_quote', { symbol: 'BTC', side: 'long', size: '0.001', leverage: 3 });
    const mid = Number(probe.value?.data?.midPx);
    if (!probe.isError && Number.isFinite(mid) && mid > 0) ok(`perps_quote reads the mid (${mid})`);
    else bad('perps_quote reads the mid', probe.raw);

    // 50 USDC of notional, in the base asset the order is sized in.
    const size = (50 / mid).toFixed(4);
    const quote = await callTool('perps_quote', { symbol: 'BTC', side: 'long', size, leverage: 3 });
    if (!quote.isError && quote.value?.data?.totalFeeUsd !== undefined) ok(`perps_quote gives the fees as one total ($${quote.value.data.totalFeeUsd})`);
    else bad('perps_quote gives the fees as one total', quote.raw);

    // 4. The paper account. paper_init takes `budget`, not `budgetUsd`.
    const paper = await callTool('paper_init', { budget: 1000 });
    if (!paper.isError && paper.value?.budgetUsd === 1000) ok('paper_init opens a $1000 paper account');
    else bad('paper_init opens a $1000 paper account', paper.raw);

    // 5. Without confirm, the quote and the policy check, nothing filled, and
    // the quote_id the go is given with.
    const shown = await callTool('perps_open', { symbol: 'BTC', side: 'long', size, leverage: 3, paper: true });
    const quoteId = shown.value?.quote_id;
    if (!shown.isError && shown.value?.executed === false && typeof quoteId === 'string') ok('perps_open without confirm executes nothing and gives a quote_id');
    else bad('perps_open without confirm executes nothing and gives a quote_id', shown.raw);

    // 6. confirm: true alone is not a go: it needs the quote the user agreed to.
    const bare = await callTool('perps_open', { symbol: 'BTC', side: 'long', size, leverage: 3, paper: true, confirm: true });
    if (bare.isError && bare.value?.error?.code === 'QUOTE_REQUIRED') ok('perps_open with confirm: true and no quote_id is refused');
    else bad('perps_open with confirm: true and no quote_id is refused', bare.raw);

    // 7. With the user's agreement, the paper order goes through.
    const done = await callTool('perps_open', { symbol: 'BTC', side: 'long', size, leverage: 3, paper: true, confirm: true, quote_id: quoteId });
    if (!done.isError && done.value?.executed === true && done.value?.paper === true) ok('perps_open with confirm: true fills on the paper account');
    else bad('perps_open with confirm: true fills on the paper account', done.raw);

    // 8. And the journal carries it, on the paper book.
    const journal = await callTool('journal', { since: '24h' });
    const entry = (journal.value?.data?.entries ?? []).find((e) => e.kind === 'order' && e.paper === true && e.symbol === 'BTC');
    if (entry) ok('journal carries the paper order');
    else bad('journal carries the paper order', journal.raw);
} catch (e) {
    bad('the conversation runs to the end', e.message);
} finally {
    child.stdin.end();
}

console.log(`# ${passed} passed, ${failed} failed`);
process.exit(failed === 0 ? 0 : 1);
