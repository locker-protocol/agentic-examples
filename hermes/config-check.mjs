// Reads config.yaml, takes the command it names under mcp_servers.locker,
// starts it, and checks it is really the Locker MCP server: `initialize`, then
// `tools/list`. No dependency, nothing but Node.
//
// The YAML reader below is deliberately small: it reads the block this recipe
// writes, and nothing else. A key it does not understand makes it stop rather
// than guess. Hermes itself reads full YAML; this only has to prove that what
// the recipe tells you to paste is the shape Hermes expects, and that the
// command in it answers.
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

/** One scalar of YAML: a flow list, a quoted string, a number, a boolean. */
function scalar(text) {
    const value = text.trim();
    if (value.startsWith('[') && value.endsWith(']')) {
        const inside = value.slice(1, -1).trim();
        return inside === '' ? [] : inside.split(',').map((part) => scalar(part));
    }
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) return value.slice(1, -1);
    if (value === 'true') return true;
    if (value === 'false') return false;
    if (/^-?\d+(\.\d+)?$/.test(value)) return Number(value);
    return value;
}

/**
 * `mcp_servers:` and the two levels under it: one server per name, one
 * `key: value` per line. Tabs, a line that is not `key: value`, or an
 * indentation that is not 2 or 4 spaces, stop the reader.
 */
function readServers(yaml) {
    const servers = {};
    let inBlock = false;
    let current = null;
    let n = 0;
    for (const raw of yaml.split('\n')) {
        n += 1;
        const line = raw.replace(/\s+$/, '');
        if (line === '' || line.trimStart().startsWith('#')) continue;
        if (line.includes('\t')) throw new Error(`line ${n}: a tab (YAML forbids them for indentation)`);
        const indent = line.length - line.trimStart().length;
        const body = line.trim();
        if (indent === 0) {
            inBlock = body === 'mcp_servers:';
            current = null;
            continue;
        }
        if (!inBlock) continue;
        const colon = body.indexOf(':');
        if (colon < 1) throw new Error(`line ${n}: not a "key: value" line`);
        const key = body.slice(0, colon).trim();
        const rest = body.slice(colon + 1).trim();
        if (indent === 2) {
            if (rest !== '') throw new Error(`line ${n}: a server name takes no value on its line`);
            current = {};
            servers[key] = current;
        } else if (indent === 4) {
            if (current === null) throw new Error(`line ${n}: a setting before any server name`);
            current[key] = scalar(rest);
        } else {
            throw new Error(`line ${n}: indented by ${indent}, expected 2 or 4`);
        }
    }
    return servers;
}

// 1. The configuration: the shape Hermes reads under mcp_servers.
const path = new URL('./config.yaml', import.meta.url);
let entry;
try {
    const servers = readServers(readFileSync(path, 'utf8'));
    entry = servers.locker;
    if (!entry) throw new Error(`no mcp_servers.locker (found: ${Object.keys(servers).join(', ') || 'nothing'})`);
    if (entry.command !== 'npx') throw new Error(`command is ${entry.command}, not npx`);
    if (!Array.isArray(entry.args) || !entry.args.includes('-y')) throw new Error('args miss -y');
    if (!entry.args.includes('--ignore-scripts')) throw new Error('args miss --ignore-scripts: npx would run the install scripts of what it fetches');
    if (!entry.args.some((a) => a === '@locker-protocol/agent-wallet-hyperliquid-trader-mcp@latest')) throw new Error('args do not ask for @locker-protocol/agent-wallet-hyperliquid-trader-mcp@latest');
    if (entry.enabled !== true) throw new Error('the server is not enabled');
    ok('config.yaml parses and names mcp_servers.locker, at @latest');
} catch (e) {
    bad('config.yaml parses and names mcp_servers.locker, at @latest', e.message);
    done();
}

// The reader has to be strict, or the check above proves nothing: a tab is a
// YAML error, and it must be reported as one.
try {
    readServers('mcp_servers:\n\tlocker:\n');
    bad('the reader refuses a tab where YAML forbids one');
} catch {
    ok('the reader refuses a tab where YAML forbids one');
}

// 2. The command it names, started the way Hermes starts it.
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
        clientInfo: { name: 'hermes-recipe-check', version: '2.0.0' },
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
