#!/usr/bin/env node
/*
 * Groups a `adb logcat -v time` capture by netdisk transport route.
 *
 * Answers the question the transport logs were added for
 * (docs/specs/2026-10-18-netdisk-buffering-todo.md): when a 4K remux rebuffers
 * every ~20 s while aggregate transport throughput looks healthy, is the CDN
 * budget going to *one* file read by several connections, or to several files?
 *
 *   adb logcat -v time > cap.txt
 *   node tool/analyze_transport_log.js cap.txt
 *
 * No dependencies. Input lines of interest:
 *   MEDIO-TRANSPORT relay #N route=K active=2 client=PORT range=...
 *   MEDIO-TRANSPORT relay #N CONCURRENT route=K active=2 peers=...
 *   MEDIO-TRANSPORT relay #N done route=K bytes=... mbps=... blocks=... active=...
 *   MEDIO-TRANSPORT block #B 206 bytes=... total=...ms route=K via=serve#N|prefetch
 *   MEDIO-TRANSPORT prefetch cap reached: inFlight=8 route=K servedBlock=B
 *   TvExoPlayer ... state=2|3 pos=MS buf=MS
 */

'use strict';

const fs = require('fs');

const file = process.argv[2] || 'cap.txt';
if (!fs.existsSync(file)) {
  console.error(`capture not found: ${file}`);
  process.exit(1);
}

const tsRe = /^(\d{2})-(\d{2})\s+(\d{2}):(\d{2}):(\d{2})\.(\d{1,3})/;

let lastTod = -1;
let dayOffset = 0;

function stampOf(line) {
  const m = tsRe.exec(line);
  if (!m) return null;
  const tod =
    ((+m[3] * 60 + +m[4]) * 60 + +m[5]) * 1000 + +m[6].padEnd(3, '0');
  if (lastTod >= 0 && tod < lastTod - 1000) dayOffset += 86400000;
  lastTod = tod;
  return dayOffset + tod;
}

const blocks = []; // { t, route, index, bytes, ms, via }
const relays = new Map(); // relayId -> { id, route, start, client, range, done? }
const concurrency = []; // { t, id, route, active, peers }
const caps = []; // { t, route, inFlight, block }
const player = []; // { t, state, pos, buf }

for (const line of fs
  .readFileSync(file, 'utf8')
  // PowerShell's `>` may write UTF-16: NULs would hide every line.
  .replace(/\0/g, '')
  .split(/\r?\n/)) {
  const t = stampOf(line);
  if (t === null) continue;
  let m;

  if ((m = /MEDIO-TRANSPORT block #(\d+) 206 bytes=(\d+) total=(\d+)ms route=(\S+)(?: rid=(\d+))?(?: via=(\S+))?/.exec(line))) {
    blocks.push({
      t,
      index: +m[1],
      bytes: +m[2],
      ms: +m[3],
      route: m[4],
      rid: m[5] || '-',
      via: m[6] || '?',
    });
  } else if ((m = /MEDIO-TRANSPORT relay #(\d+)(?: rid=(\d+))? route=(\S+)(?: active=(\d+) client=(\d+))? range=(\S+)(?: ua=(.*))?$/.exec(line))) {
    relays.set(+m[1], {
      id: +m[1],
      rid: m[2] || '-',
      route: m[3],
      activeAtStart: +(m[4] || 0),
      client: +(m[5] || 0),
      range: m[6],
      ua: (m[7] || '').trim(),
      start: t,
    });
  } else if ((m = /MEDIO-TRANSPORT relay #(\d+) CONCURRENT route=(\S+) active=(\d+) peers=(.*)$/.exec(line))) {
    concurrency.push({ t, id: +m[1], route: m[2], active: +m[3], peers: m[4].trim() });
  } else if ((m = /MEDIO-TRANSPORT relay #(\d+) done route=(\S+) bytes=(\d+) seconds=([\d.]+) mbps=([\d.]+) blocks=(\d+) cacheHits=(\d+) client=(\d+) active=(\d+)/.exec(line))) {
    const r = relays.get(+m[1]) || { id: +m[1], route: m[2], start: t, client: +m[8] };
    Object.assign(r, {
      route: m[2],
      bytes: +m[3],
      seconds: +m[4],
      mbps: +m[5],
      servedBlocks: +m[6],
      cacheHits: +m[7],
      client: +m[8],
      done: t,
    });
    relays.set(+m[1], r);
  } else if ((m = /MEDIO-TRANSPORT prefetch cap reached: inFlight=(\d+) route=(\S+) servedBlock=(\d+)/.exec(line))) {
    caps.push({ t, inFlight: +m[1], route: m[2], block: +m[3] });
  } else if ((m = /TvExoPlayer.*\bstate=(\d+)\s+pos=(-?\d+)\s+buf=(-?\d+)/.exec(line))) {
    player.push({ t, state: +m[1], pos: +m[2], buf: +m[3] });
  }
}

if (blocks.length === 0 && player.length === 0) {
  console.error('no MEDIO-TRANSPORT / TvExoPlayer lines found — check the -v time format and the "TvExoPlayer" tag (not "TvExoPlayer:")');
  process.exit(1);
}

const allT = [...blocks.map((b) => b.t), ...player.map((p) => p.t)];
const t0 = Math.min(...allT);
const t1 = Math.max(...allT);
const spanS = Math.max((t1 - t0) / 1000, 0.001);

const sec = (t) => ((t - t0) / 1000).toFixed(1);
const mb = (bytes) => (bytes / 1048576).toFixed(1);
const mbps = (bytes, ms) => (ms > 0 ? (bytes * 8) / (ms * 1000) : 0).toFixed(1);

function pad(s, n) {
  s = String(s);
  return s.length >= n ? s : s + ' '.repeat(n - s.length);
}

// ── Per route ────────────────────────────────────────────────────────────────
const routes = new Map();
for (const b of blocks) {
  let r = routes.get(b.route);
  if (!r) {
    r = { key: b.route, blocks: [], byIndex: new Map() };
    routes.set(b.route, r);
  }
  r.blocks.push(b);
  r.byIndex.set(b.index, (r.byIndex.get(b.index) || 0) + 1);
}

console.log(`capture: ${file}`);
console.log(
  `window : ${sec(t0)}s .. ${sec(t1)}s  (${spanS.toFixed(0)}s), ` +
    `${blocks.length} block fetches, ${relays.size} relays, ` +
    `${player.length} player states, ${routes.size} route(s)`,
);
console.log('');

console.log('== routes (one line per file) ==');
console.log(
  pad('route', 34) + pad('relays', 7) + pad('blocks', 7) + pad('dup', 5) +
    pad('bytes', 9) + pad('Mbps', 7) + pad('block#span', 16) + 'peakActive',
);
for (const r of [...routes.values()].sort((a, b) => b.blocks.length - a.blocks.length)) {
  const bytes = r.blocks.reduce((s, b) => s + b.bytes, 0);
  const first = Math.min(...r.blocks.map((b) => b.t));
  const last = Math.max(...r.blocks.map((b) => b.t));
  const idx = r.blocks.map((b) => b.index);
  const dup = [...r.byIndex.values()].filter((n) => n > 1).length;
  const relayCount = [...relays.values()].filter((x) => x.route === r.key).length;
  const peak = Math.max(
    0,
    ...[...relays.values()].filter((x) => x.route === r.key).map((x) => x.activeAtStart || 0),
  );
  console.log(
    pad(r.key.slice(0, 33), 34) + pad(relayCount, 7) + pad(r.blocks.length, 7) +
      pad(dup || '-', 5) + pad(mb(bytes), 9) +
      pad(mbps(bytes, last - first), 7) +
      pad(`${Math.min(...idx)}..${Math.max(...idx)}`, 16) + peak,
  );
}
console.log('');

// ── Relays: one line per client connection ───────────────────────────────────
console.log('== relays (client connections, in start order) ==');
console.log(
  pad('relay', 7) + pad('rid', 5) + pad('client', 8) + pad('start(s)', 9) +
    pad('alive(s)', 9) + pad('MB', 7) + pad('blocks', 7) + pad('range', 30) + 'ua',
);
const seenUa = new Set();
for (const r of [...relays.values()].sort((a, b) => a.start - b.start)) {
  const end = r.done ?? Math.max(...blocks.map((b) => b.t), r.start);
  const range = (r.range || '-').replace(/^bytes=/, '');
  console.log(
    pad(`#${r.id}`, 7) + pad(r.rid || '-', 5) + pad(r.client || '-', 8) +
      pad(sec(r.start), 9) + pad(((end - r.start) / 1000).toFixed(1), 9) +
      pad(r.bytes ? mb(r.bytes) : '-', 7) +
      pad(r.servedBlocks ?? '-', 7) +
      pad(range.slice(0, 29), 30) + (r.ua || '-'),
  );
  if (r.ua) seenUa.add(r.ua);
}
if (seenUa.size > 1) {
  console.log(`  (${seenUa.size} distinct user agents: ${[...seenUa].join(' | ')})`);
}
console.log('');

// ── Per route: contiguous block runs (= one reader advancing) ────────────────
console.log('== reader runs per route (blocks fetched in index order) ==');
console.log(
  pad('route', 20) + pad('run', 5) + pad('blocks', 7) + pad('block#span', 16) +
    pad('t(s)', 15) + pad('Mbps', 7) + 'via(serve/prefetch)',
);
for (const r of routes.values()) {
  const sorted = [...r.blocks].sort((a, b) => a.t - b.t);
  let run = [];
  let n = 0;
  const flush = () => {
    if (run.length === 0) return;
    n++;
    const bytes = run.reduce((s, b) => s + b.bytes, 0);
    const first = run[0];
    const last = run[run.length - 1];
    const dt = last.t - first.t;
    const serve = run.filter((b) => b.via.startsWith('serve')).length;
    console.log(
      pad(r.key.slice(0, 19), 20) + pad(n, 5) + pad(run.length, 7) +
        pad(`${first.index}..${last.index}`, 16) +
        pad(`${sec(first.t)}..${sec(last.t)}`, 15) +
        pad(mbps(bytes, dt), 7) + `${serve}/${run.length - serve}`,
    );
    run = [];
  };
  for (const b of sorted) {
    if (run.length && b.index !== run[run.length - 1].index + 1) flush();
    run.push(b);
  }
  flush();
}
console.log('');

// ── Concurrency ──────────────────────────────────────────────────────────────
console.log('== concurrent relays on the same file ==');
if (concurrency.length === 0) {
  console.log('none: every relay on a route ran alone (no duplicate reader)');
} else {
  for (const c of concurrency.slice(0, 40)) {
    console.log(`  t=${sec(c.t)}s  relay #${c.id} route=${c.route} active=${c.active} peers=${c.peers}`);
  }
  if (concurrency.length > 40) console.log(`  ... ${concurrency.length - 40} more`);
  const sustained = new Map();
  for (const c of concurrency) sustained.set(c.route, (sustained.get(c.route) || 0) + 1);
  console.log(`  per route: ${[...sustained].map(([k, v]) => `${k}=${v}`).join(' ')}`);
}
console.log('');

if (caps.length) {
  console.log(`== prefetch cap throttling (${caps.length}) ==`);
  const byRoute = new Map();
  for (const c of caps) byRoute.set(c.route, (byRoute.get(c.route) || 0) + 1);
  console.log(`  ${[...byRoute].map(([k, v]) => `${k}=${v}`).join(' ')}`);
  console.log(`  first at t=${sec(caps[0].t)}s block=${caps[0].block}`);
  console.log('');
}

// ── Player side ──────────────────────────────────────────────────────────────
const buffering = [];
for (let i = 1; i < player.length; i++) {
  if (player[i].state === 2 && player[i - 1].state !== 2) {
    buffering.push({ t: player[i].t, pos: player[i].pos, buf: player[i].buf });
  }
}
const ready = player.filter((p) => p.state === 3);
console.log('== player ==');
console.log(
  `states=${player.length} READY=${ready.length} BUFFERING episodes=${buffering.length}`,
);
for (const b of buffering.slice(0, 40)) {
  console.log(`  t=${sec(b.t)}s pos=${(b.pos / 1000).toFixed(1)}s buf-ahead=${((b.buf - b.pos) / 1000).toFixed(1)}s`);
}
if (buffering.length > 40) console.log(`  ... ${buffering.length - 40} more`);

const ahead = ready
  .map((p) => ({ t: p.t, ahead: (p.buf - p.pos) / 1000 }))
  .filter((p) => p.ahead >= 0);
if (ahead.length) {
  const peak = Math.max(...ahead.map((a) => a.ahead));
  // Slope while READY: negative = buffer draining faster than it fills.
  let drain = 0;
  let n = 0;
  for (let i = 1; i < ahead.length; i++) {
    const dt = (ahead[i].t - ahead[i - 1].t) / 1000;
    if (dt <= 0 || dt > 5) continue;
    drain += (ahead[i].ahead - ahead[i - 1].ahead) / dt;
    n++;
  }
  console.log(
    `READY buffer-ahead: peak=${peak.toFixed(1)}s last=${ahead[ahead.length - 1].ahead.toFixed(1)}s ` +
      `mean-slope=${(n ? drain / n : 0).toFixed(3)}s/s (>0 filling, <0 draining)`,
  );
}
console.log('');

// ── 10 s buckets: who gets the bandwidth ─────────────────────────────────────
const bucketS = 10;
const buckets = new Map();
for (const b of blocks) {
  const k = Math.floor((b.t - t0) / (bucketS * 1000));
  if (!buckets.has(k)) buckets.set(k, new Map());
  const m = buckets.get(k);
  m.set(b.route, (m.get(b.route) || 0) + b.bytes);
}
const keys = [...routes.keys()];
console.log(`== ${bucketS}s buckets (Mbps per route) ==`);
console.log(pad('t(s)', 8) + pad('total', 8) + keys.map((k) => pad(k.slice(0, 20), 22)).join('') + pad('playstate', 10) + 'buf-ahead');
for (const k of [...buckets.keys()].sort((a, b) => a - b)) {
  const m = buckets.get(k);
  const total = [...m.values()].reduce((s, v) => s + v, 0);
  const bucketEnd = t0 + (k + 1) * bucketS * 1000;
  const lastPlayer = [...player].reverse().find((p) => p.t <= bucketEnd);
  const state = !lastPlayer ? '-' : lastPlayer.state === 3 ? 'READY' : lastPlayer.state === 2 ? 'BUFFER' : lastPlayer.state === 4 ? 'ENDED' : 'IDLE';
  const aheadS = lastPlayer && lastPlayer.state === 3 ? ((lastPlayer.buf - lastPlayer.pos) / 1000).toFixed(1) : '-';
  console.log(
    pad(`${k * bucketS}`, 8) + pad(((total * 8) / (bucketS * 1000000)).toFixed(1), 8) +
      keys.map((key) => pad(((m.get(key) || 0) * 8 / (bucketS * 1000000)).toFixed(1), 22)).join('') +
      pad(state, 10) + aheadS,
  );
}
