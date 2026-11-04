#!/usr/bin/env node
// Runs tools/e2e.lua's scenarios in the game from a terminal, through one game's VanaCore MCP server: no Claude
// session needed. Node 18 or later, nothing to install.
//
//   node tools/e2e.mjs [--port 47800] run [name ... | all]   queue them, follow them, print the results
//   node tools/e2e.mjs [--port 47800] list | status | report | abort
//
// `run` exits 1 when a scenario failed or erred (skips don't count). The game needs VanaCore's MCP on
// ([mcp] enabled=1 in vanacore.ini, or /vana > Client > AI MCP; each game takes the next free port from 47800) and
// Sidekick loaded. docs/e2e.md has the scenarios and how to write one.

const argv = process.argv.slice(2);
let port = 47800;
if (argv[0] === '--port') { port = Number(argv[1]); argv.splice(0, 2); }
const [verb = 'help', ...names] = argv;
if (!Number.isInteger(port) || port < 1 || port > 65535) {
  console.error(`not a port: ${port}`);
  process.exit(2);
}
for (const n of names) {
  if (!/^[a-z0-9_]+$/.test(n)) {
    console.error(`not a scenario name: ${n}`);
    process.exit(2);
  }
}
const url = `http://127.0.0.1:${port}/mcp`;
let session = null;
let nextId = 1;

async function post(body) {
  const headers = { 'Content-Type': 'application/json', Accept: 'application/json, text/event-stream', Connection: 'close' };
  if (session) headers['Mcp-Session-Id'] = session;
  const res = await fetch(url, { method: 'POST', headers, body: JSON.stringify(body) });
  session = res.headers.get('mcp-session-id') || session;
  const text = await res.text();
  if (!res.ok) throw new Error(`the MCP answered HTTP ${res.status}: ${text.slice(0, 200)}`);
  if (!text) return null;
  if ((res.headers.get('content-type') || '').includes('text/event-stream')) {
    let last = null;
    for (const line of text.split('\n')) if (line.startsWith('data:')) last = JSON.parse(line.slice(5));
    return last;
  }
  return JSON.parse(text);
}

async function tool(name, args) {
  const out = await post({ jsonrpc: '2.0', id: nextId++, method: 'tools/call', params: { name, arguments: args } });
  if (out?.error) throw new Error(`${name}: ${out.error.message}`);
  const text = (out?.result?.content || []).map((c) => c.text || '').join('\n');
  if (out?.result?.isError) throw new Error(`${name}: ${text}`);
  return text;
}

async function connect() {
  try {
    await post({ jsonrpc: '2.0', id: nextId++, method: 'initialize', params: {
      protocolVersion: '2025-03-26', capabilities: {}, clientInfo: { name: 'sidekick-e2e', version: '1.0' } } });
  } catch (e) {
    throw new Error(`no VanaCore MCP at ${url} (${e.cause?.code || e.message}): is the game up with the MCP on?`);
  }
  await post({ jsonrpc: '2.0', method: 'notifications/initialized' });
  await tool('hello', { name: 'Sidekick e2e tests' });
}

// Lua in Sidekick's state; what it prints between @@ marks comes back as JSON.
async function lua(code) {
  const text = await tool('lua', { addon: 'Sidekick', code: `local e2e = require('tools.e2e') ${code}` });
  const m = text.match(/@@([\s\S]*)@@/);
  if (!m) throw new Error(`Sidekick answered:\n${text}`);
  return JSON.parse(m[1]);
}
const json = (expr) => `print('@@' .. vana.json.encode(${expr}) .. '@@') return true`;
// The runner and the GM commands loaded again from their files, unless a scenario is running: edits take effect.
const FRESH = `local was = package.loaded['tools.e2e'] local s = was and was.status()
  if not (s and (s.running or #s.queued > 0)) then
    if was then was.unwatch() end
    package.loaded['tools.e2e'], package.loaded['tools.gm'] = nil, nil
  end`;
// An empty Lua table comes back as {} rather than [].
const count = (v) => (Array.isArray(v) ? v.length : Object.keys(v || {}).length);
const list = (v) => (Array.isArray(v) ? v : []);

function seconds(s) { return s === undefined ? '' : `${Number(s).toFixed(2)}s`; }

function show(r) {
  const timings = Object.entries(r.timings || {}).map(([k, v]) => `${k} ${seconds(v)}`).join(', ');
  console.log(`${r.result.toUpperCase().padEnd(5)} ${r.name.padEnd(14)} ${String(r.seconds).padStart(5)}s  ${timings}`);
  if (r.why) console.log(`      ${r.why.split('\n')[0]}`);
  for (const n of list(r.notes)) console.log(`      - ${n}`);
  if (r.result === 'pass' || r.result === 'skip') return;
  if (r.sidekick) console.log(`      Sidekick: running ${r.sidekick.running}, ${r.sidekick.why || ''}${r.sidekick.intent ? `, next ${r.sidekick.intent}` : ''}`);
  for (const e of list(r.trail)) {
    const { type, at, seq, ...rest } = e;
    const fields = Object.entries(rest).map(([k, v]) =>
      `${k}=${typeof v === 'object' ? JSON.stringify(v) : String(v).replace(/----== SystemMessage ==----\n/, '').replace(/\n/g, ' / ')}`);
    console.log(`        ${type} ${fields.join(' ')}`.slice(0, 200));
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  if (verb === 'help' || verb === '--help') {
    console.log('node tools/e2e.mjs [--port 47800] run [name ... | all] | list | status | report | abort');
    return 0;
  }
  await connect();
  if (verb === 'list') {
    await tool('lua', { addon: 'Sidekick', code: FRESH });
    for (const s of list(await lua(json('e2e.list()')))) console.log(`${s.name.padEnd(14)} ${s.about}`);
  } else if (verb === 'status') {
    console.log(JSON.stringify(await lua(json('e2e.status()')), null, 2));
  } else if (verb === 'abort') {
    await lua(`e2e.abort() ${json('e2e.status()')}`);
    console.log('aborted: the scenario running stops at its next wait, and cleans up');
  } else if (verb === 'report') {
    for (const r of list(await lua(json('e2e.report()')))) show(r);
  } else if (verb === 'run') {
    const wanted = names.length ? names : ['all'];
    await tool('lua', { addon: 'Sidekick', code: FRESH });
    const before = (await lua(json('e2e.status()'))).finished;
    await lua(`e2e.run(${wanted.map((n) => `'${n}'`).join(', ')}) ${json('e2e.status()')}`);
    let shown = before;
    let last = '';
    for (;;) {
      await sleep(2000);
      const s = await lua(json('e2e.status()'));
      // Results gone, or nothing running, queued or finished: Sidekick (or the runner) loaded again mid-run.
      if (s.finished < shown || (!s.running && count(s.queued) === 0 && s.finished <= before)) {
        throw new Error('the run is gone: Sidekick (or the runner) was loaded again mid-run');
      }
      if (s.finished > shown) {
        for (const r of list(await lua(json(`e2e.report(${shown + 1})`)))) show(r);
        shown = s.finished;
      }
      const now = s.running ? `${s.running}${s.cleaning ? ' (cleaning up)' : ''}` : '';
      if (now && now !== last) console.log(`  ... ${now}`);
      last = now;
      if (!s.running && count(s.queued) === 0 && s.finished > before) break;
    }
    const results = list(await lua(json(`e2e.report(${before + 1})`)));
    const tally = (k) => results.filter((r) => r.result === k).length;
    console.log(`\n${tally('pass')} passed, ${tally('fail')} failed, ${tally('error')} errors, ${tally('skip')} skipped`);
    return tally('fail') + tally('error') > 0 ? 1 : 0;
  } else {
    throw new Error(`unknown: ${verb} (run, list, status, report, abort)`);
  }
  return 0;
}

// Exit codes set, not process.exit(): Node on Windows can abort exiting while a closed socket is still being torn down.
main().then((code) => { process.exitCode = code; }).catch((e) => { console.error(e.message); process.exitCode = 2; });
