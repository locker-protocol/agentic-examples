// An example plugin of lpa. It speaks JSON lines on its standard input and
// output, and asks lpa for the markets through the one capability it
// declared, market-read. No dependency: where it runs, it reads its own
// folder and nothing else.
import { createInterface } from 'node:readline';

const waiting = new Map();
let next = 1;
const write = (msg) => process.stdout.write(JSON.stringify(msg) + '\n');
const call = (capability, method, params = {}) => new Promise((resolve, reject) => {
    const id = next++;
    waiting.set(id, { resolve, reject });
    write({ type: 'call', id, capability, method, params });
});

async function scan(args) {
    const top = Number(args.top ?? 5);
    if (!Number.isInteger(top) || top < 1 || top > 50) throw new Error('--top is a whole number from 1 to 50');
    const markets = await call('market-read', 'markets');
    const rows = markets
        .filter((m) => m.funding !== null && m.funding !== undefined)
        .sort((a, b) => Number(b.funding) - Number(a.funding))
        .slice(0, top)
        .map((m) => ({ name: m.name, funding: m.funding, yearly: `${(Number(m.funding) * 24 * 365 * 100).toFixed(1)}%` }));
    const width = Math.max(...rows.map((r) => r.name.length));
    const text = rows.map((r) => `${r.name.padEnd(width)}  ${r.funding}  (${r.yearly} a year)`).join('\n');
    write({ type: 'done', text, data: { top: rows } });
}

createInterface({ input: process.stdin }).on('line', (line) => {
    const msg = JSON.parse(line);
    if (msg.type === 'result' || msg.type === 'error') {
        const w = waiting.get(msg.id);
        if (!w) return;
        waiting.delete(msg.id);
        if (msg.type === 'result') w.resolve(msg.result);
        else w.reject(new Error(msg.error.message));
        return;
    }
    if (msg.type !== 'run') return;
    if (msg.command !== 'scan') return write({ type: 'fail', message: `unknown command ${msg.command}` });
    scan(msg.args).catch((e) => write({ type: 'fail', message: e.message }));
});
