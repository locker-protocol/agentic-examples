// Reads openclaw.json the way OpenClaw does (mcp.servers.<name>), takes the
// command it names, starts it, and checks it is really the Locker MCP server:
// `initialize`, then `tools/list`. No dependency, nothing but Node.
//
// OpenClaw's config is JSON5. The example here is written as plain JSON, which
// is a subset of JSON5, so this reader needs nothing but JSON.parse.
//
//   LOCKER_MCP_BIN   overrides the command line the config names
//                    (so the check can run against a checkout)

import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { readFileSync } from 'node:fs';

let passed = 0;
let failed = 0;
const ok = (what) => { passed += 1; console.log(`ok   - ${what}`); };
const bad = (what, detail) => {
    failed += 1;
    console.log(`FAIL - ${what}`);
    if (detail !== undefined) console.log(`       ${String(detail).slice(0, 400).replace(/\n/g, '\n       ')}`);
};
const done = () => { console.log(`# ${passed} passed, ${failed} failed`); process.exit(failed === 0 ? 0 : 1); };

// 1. The configuration: the shape OpenClaw reads.
const path = new URL('./openclaw.json', import.meta.url);
let entry;
try {
    const config = JSON.parse(readFileSync(path, 'utf8'));
    entry = config?.mcp?.servers?.locker;
    if (!entry) throw new Error('no mcp.servers.locker');
    if (entry.transport !== 'stdio') throw new Error(`transport is ${entry.transport}, not stdio`);
    if (entry.command !== 'npx') throw new Error(`command is ${entry.command}, not npx`);
    if (!Array.isArray(entry.args) || !entry.args.includes('-y')) throw new Error('args miss -y');
    if (!entry.args.includes('--ignore-scripts')) throw new Error('args miss --ignore-scripts: npx would run the install scripts of what it fetches');
    if (!entry.args.some((a) => a === '@locker-protocol/agent-wallet-hyperliquid-trader-mcp@latest')) throw new Error('args do not ask for @locker-protocol/agent-wallet-hyperliquid-trader-mcp@latest');
    if (entry.enabled !== true) throw new Error('the server is not enabled');
    ok('openclaw.json parses and names mcp.servers.locker over stdio, at @latest');
} catch (e) {
    bad('openclaw.json parses and names mcp.servers.locker over stdio, at @latest', e.message);
    done();
}

// 2. The command it names, started the way OpenClaw starts it.
const override = process.env.LOCKER_MCP_BIN;
const parts = override ? override.trim().split(/\s+/) : [entry.command, ...entry.args];
const [command, ...args] = parts;
console.log(`# starting: ${parts.join(' ')}`);

const child = spawn(command, args, { stdio: ['pipe', 'pipe', 'inherit'], env: process.env });
child.on('error', (e) => { bad(`the command the config names starts (${parts.join(' ')})`, e.message); done(); });

const waiting = new Map();
createInterface({ input: child.stdout }).on('line', (text) => {
    if (!text.trim()) return;
    let message;
    try { message = JSON.parse(text); } catch { return; }
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

try {
    const init = await rpc('initialize', {
        protocolVersion: '2025-06-18',
        capabilities: {},
        clientInfo: { name: 'openclaw-recipe-check', version: '2.0.0' },
    });
    const info = init?.result?.serverInfo;
    if (info?.name === 'locker-protocol-agentic') ok(`initialize: ${info.name} ${info.version}, protocol ${init.result.protocolVersion}`);
    else bad('initialize answers with the Locker server', JSON.stringify(init));

    const list = await rpc('tools/list', {});
    const tools = list?.result?.tools ?? [];
    // Its own tools; a plugin you installed adds plugin_* ones.
    const own = tools.filter((t) => !t.name.startsWith('plugin_'));
    if (own.length === 42) ok('tools/list gives 42 tools');
    else bad('tools/list gives 42 tools', `got ${own.length}`);
} catch (e) {
    bad('the server answers initialize and tools/list', e.message);
} finally {
    child.stdin.end();
}

done();
