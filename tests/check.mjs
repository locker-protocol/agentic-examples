#!/usr/bin/env node
// Checks this repository before it is published. No dependency, Node 22 or later.
//
//   node tests/check.mjs
//
// The same gate public/agentic carries, for the recipes: nothing here needs
// `lpa`, a network or a container, so it runs on every pass, unlike
// check-all.sh, which runs the recipes themselves.
//
// What it checks:
//   1. the files this repository promises are there: the README, the licence,
//      check-all.sh, and for every recipe a README.md and an executable
//      check.sh;
//   2. every relative link of every Markdown file resolves;
//   3. no em dash, no en dash, no emoji, nothing outside ASCII, anywhere in
//      the tree (the images apart, which are bytes);
//   4. no version written: every @locker-protocol package a recipe installs or
//      starts asks for @latest, so a release needs no edit of any recipe;
//   5. the recipes of the README table, the folders on disk and the list in
//      check-all.sh are the same set, in the same order;
//   6. nothing of this machine or of anybody's money: no absolute path of a
//      home folder other than the stand-in the sample outputs use, no e-mail
//      address, no seed phrase, no private key, and no account address other
//      than the demonstration ones;
//   7. every count of the server's own tools a recipe states, in its checks
//      and in its prose, is the number packages/mcp/src/tools.ts declares when
//      the build tree sits next to this one, and the same number everywhere
//      when it does not.
//
// Exit 0 when everything passes, 1 with the list of problems otherwise.

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const problems = [];
const notes = [];
const rel = (p) => path.relative(root, p) || '.';
const fail = (where, what) => problems.push(`${where}: ${what}`);

// The tools the server declares, when the build tree is next door.
const TOOLS_SOURCE = path.resolve(root, '..', '..', 'packages', 'mcp', 'src', 'tools.ts');

const REQUIRED_FILES = ['README.md', 'LICENSE', 'check-all.sh'];

/** Files that are bytes, not text: read for their name only. */
const BINARY = /\.(png|jpg|jpeg|gif|webp|ico|pdf)$/i;

/** The home folder the sample outputs stand in: never a real one. */
const SHOWN_PATHS = new Set(['/home/you', '/Users/you']);

/** The addresses these recipes are allowed to show: anvil's account 0, and a demonstration one. */
const SHOWN_ADDRESSES = new Set([
    '0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266',
    '0x9858effd232b4033e47d90003d41ec34ecaeda94',
]);

function walk(dir, out = []) {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        if (e.name === '.git' || e.name === 'node_modules') continue;
        const full = path.join(dir, e.name);
        if (e.isDirectory()) walk(full, out);
        else out.push(full);
    }
    return out;
}

const files = walk(root).sort();
const text = files.filter((f) => !BINARY.test(f));
const markdown = files.filter((f) => f.endsWith('.md')).sort();
const read = (f) => fs.readFileSync(f, 'utf8');

// --- 1. The files this repository promises ----------------------------------

for (const name of REQUIRED_FILES) {
    if (!fs.existsSync(path.join(root, name))) fail(name, 'missing');
}

/** A recipe is a folder of the root holding a check.sh. */
const recipes = fs.readdirSync(root, { withFileTypes: true })
    .filter((e) => e.isDirectory() && e.name !== 'tests' && !e.name.startsWith('.'))
    .map((e) => e.name)
    .sort();
if (recipes.length === 0) fail('tests/check.mjs', 'no recipe was found: the reader is broken');
for (const recipe of recipes) {
    for (const name of ['README.md', 'check.sh']) {
        const file = path.join(root, recipe, name);
        if (!fs.existsSync(file)) { fail(`${recipe}/${name}`, 'missing'); continue; }
        if (name === 'check.sh' && (fs.statSync(file).mode & 0o111) === 0) fail(`${recipe}/check.sh`, 'is not executable, so check-all.sh would skip it');
    }
}
if (fs.existsSync(path.join(root, 'check-all.sh')) && (fs.statSync(path.join(root, 'check-all.sh')).mode & 0o111) === 0) {
    fail('check-all.sh', 'is not executable');
}

// --- 2. Every relative link -------------------------------------------------

let linksSeen = 0;
for (const f of markdown) {
    for (const m of read(f).matchAll(/\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g)) {
        const href = m[1];
        if (/^(https?:|mailto:|#)/.test(href)) continue;
        linksSeen++;
        const target = decodeURI(href.split('#')[0]);
        if (!target) continue;
        if (!fs.existsSync(path.resolve(path.dirname(f), target))) fail(rel(f), `link ${href} does not resolve`);
    }
}
if (linksSeen === 0) fail('tests/check.mjs', 'no relative link was found: the reader is broken');

// --- 3. ASCII only: no em dash, no en dash, no emoji ------------------------

const EM_DASH = 0x2014;
const EN_DASH = 0x2013;
const isEmoji = (cp) =>
    (cp >= 0x1f000 && cp <= 0x1faff) || // pictographs, faces, symbols, objects
    (cp >= 0x2600 && cp <= 0x27bf) || // miscellaneous symbols and dingbats
    cp === 0xfe0f || // variation selector 16, the one that makes a glyph an emoji
    (cp >= 0x1f1e6 && cp <= 0x1f1ff); // regional indicators, the flags
const name = (cp) => {
    if (cp === EM_DASH) return 'an em dash';
    if (cp === EN_DASH) return 'an en dash';
    if (isEmoji(cp)) return 'an emoji';
    return 'a character outside ASCII';
};

for (const f of text) {
    let line = 1;
    const seen = new Set();
    for (const ch of read(f)) {
        if (ch === '\n') { line++; continue; }
        const cp = ch.codePointAt(0);
        if (cp < 0x80) continue;
        const key = `${cp}:${line}`;
        if (seen.has(key)) continue;
        seen.add(key);
        fail(rel(f), `line ${line} holds ${name(cp)} (U+${cp.toString(16).toUpperCase().padStart(4, '0')})`);
    }
}

// --- 4. One version everywhere ----------------------------------------------

const latest = [];
for (const f of [...markdown, ...text.filter((t) => t.endsWith('.json') || t.endsWith('.sh') || t.endsWith('.mjs') || t.endsWith('.yaml'))]) {
    for (const m of read(f).matchAll(/@locker-protocol\/[a-z-]+@([^\s"'`)\],]+)/g)) {
        if (m[1] === 'latest') latest.push(rel(f));
        else problems.push(`${rel(f)}: ${m[0]} names a version: write @latest`);
    }
}
if (latest.length === 0) fail('tests/check.mjs', 'no package at @latest was found: the reader is broken');

// --- 5. The recipes: the README, the folders and check-all.sh agree ---------

const readme = fs.existsSync(path.join(root, 'README.md')) ? read(path.join(root, 'README.md')) : '';
const listed = [...readme.matchAll(/\[`([a-z0-9-]+)\/`\]\(\1\/\)/g)].map((m) => m[1]);
if (listed.length === 0) fail('README.md', 'no recipe is listed in the table');
const inScript = fs.existsSync(path.join(root, 'check-all.sh'))
    ? (/RECIPES="\n([^"]*)"/.exec(read(path.join(root, 'check-all.sh')))?.[1] ?? '').split('\n').filter((l) => l !== '')
    : [];
if ([...listed].sort().join(',') !== recipes.join(',')) {
    fail('README.md', `the recipes listed (${listed.join(', ')}) are not the folders on disk (${recipes.join(', ')})`);
}
if (listed.join(',') !== inScript.join(',')) {
    fail('check-all.sh', `it runs (${inScript.join(', ')}), the README lists (${listed.join(', ')}): same recipes, same order`);
}

// --- 6. Nothing of this machine, and nobody's money -------------------------

const LEAKS = [
    { what: 'a path of somebody\'s home folder', re: /(?<![A-Za-z0-9])\/(?:Users|home)\/[A-Za-z0-9._-]+/g },
    { what: 'an e-mail address', re: /[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}/g },
    { what: 'a private key', re: /\b0x[0-9a-fA-F]{64}\b/g },
    { what: 'a seed phrase', re: /\b(?:abandon|zoo)(?:\s+[a-z]+){11,}/g },
];
for (const f of text) {
    const body = read(f);
    for (const { what, re } of LEAKS) {
        for (const m of body.matchAll(re)) {
            const hit = m[0].trim();
            if (SHOWN_PATHS.has(hit)) continue;
            fail(rel(f), `line ${body.slice(0, m.index).split('\n').length} holds ${what}: ${hit}`);
        }
    }
    for (const m of body.matchAll(/\b0x[0-9a-fA-F]{40}\b/g)) {
        if (SHOWN_ADDRESSES.has(m[0].toLowerCase())) continue;
        fail(rel(f), `line ${body.slice(0, m.index).split('\n').length} holds an account address that is not one of the demonstration ones: ${m[0]}`);
    }
}

// --- 7. The number of tools a recipe states ---------------------------------

// A count may break across a line in prose ("(42\ntools"), so the whole body is read.
const TOOL_COUNTS = /EXPECTED_TOOLS = (\d+)|own\.length === (\d+)|\b(\d+)\s+tools\b|\b(\d+) of its own\b/g;
const stated = [];
for (const f of text.filter((t) => !rel(t).startsWith('tests/'))) {
    const body = read(f);
    for (const m of body.matchAll(TOOL_COUNTS)) {
        stated.push({ file: rel(f), line: body.slice(0, m.index).split('\n').length, count: Number(m[1] ?? m[2] ?? m[3] ?? m[4]) });
    }
}
if (stated.length === 0) fail('tests/check.mjs', 'no count of tools was found: the reader is broken');
let TOOL_COUNT = null;
if (!fs.existsSync(TOOLS_SOURCE)) {
    notes.push(`The count of tools was not compared with the server: ${path.relative(root, TOOLS_SOURCE)} is not there, which is normal in a clone of this repository alone.`);
    TOOL_COUNT = stated[0]?.count ?? null;
} else {
    const source = read(TOOLS_SOURCE);
    const list = source.slice(source.indexOf('export const TOOLS'));
    TOOL_COUNT = new Set([...list.slice(0, list.indexOf('\n];')).matchAll(/\bname: '([a-z_]+)'/g)].map((m) => m[1])).size;
    if (TOOL_COUNT === 0) fail('tests/check.mjs', `no tool was read from ${path.relative(root, TOOLS_SOURCE)}: the reader is broken`);
}
for (const wrong of new Set(stated.filter((x) => x.count !== TOOL_COUNT).map((s) => `${s.file}: line ${s.line} states ${s.count} tools, the server has ${TOOL_COUNT}`))) {
    problems.push(wrong);
}

// --- Report ------------------------------------------------------------------

for (const n of notes) console.log(`note: ${n}`);

if (problems.length) {
    console.error(`\ncheck failed, ${problems.length} problem${problems.length > 1 ? 's' : ''}:`);
    for (const p of problems) console.error(`- ${p}`);
    process.exit(1);
}

console.log(`check: ok (${files.length} files, ${markdown.length} Markdown, ${recipes.length} recipes, ${linksSeen} relative links, ${latest.length} packages at @latest, ${stated.length} counts of ${TOOL_COUNT} tools)`);
