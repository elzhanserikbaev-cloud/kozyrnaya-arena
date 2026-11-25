// Asset studio baker: serves the repo over HTTP, opens studio.html in headless Chrome
// and writes every asset canvas as PNG into godot/assets/.
//   node bake.mjs                 -> bake everything
//   node bake.mjs cards/frame_ice  -> bake assets whose path contains the filter(s)
// Env: CHROME (path), BAKE_PORT (debug port, default 9531), BAKE_PROFILE (user-data-dir)
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '../../..');            // kozyrnaya-arena/
const ASSETS = path.resolve(HERE, '../../assets');      // godot/assets/
const CHROME = process.env.CHROME || 'C:/Program Files/Google/Chrome/Application/chrome.exe';
const DPORT = +(process.env.BAKE_PORT || 9531);
const PROFILE = process.env.BAKE_PROFILE || path.join(os.tmpdir(), 'kozyr-asset-studio-profile');
const filters = process.argv.slice(2);

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.ttf': 'font/ttf', '.png': 'image/png', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  const p = path.join(REPO, decodeURIComponent(req.url.split('?')[0]));
  if (!p.startsWith(REPO) || !fs.existsSync(p) || fs.statSync(p).isDirectory()) { res.writeHead(404); res.end(); return; }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(p)] || 'application/octet-stream' });
  fs.createReadStream(p).pipe(res);
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const HPORT = server.address().port;

const chrome = spawn(CHROME, ['--headless=new', '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
  `--remote-debugging-port=${DPORT}`, `--user-data-dir=${PROFILE}`, '--no-first-run', '--hide-scrollbars', 'about:blank'], { stdio: 'ignore' });
const sleep = ms => new Promise(r => setTimeout(r, ms));
let ws;
try {
  let targets;
  for (let i = 0; i < 60; i++) { try { targets = await (await fetch(`http://127.0.0.1:${DPORT}/json/list`)).json(); if (targets.find(t => t.type === 'page')) break; } catch {} await sleep(250); }
  const page = targets.find(t => t.type === 'page');
  ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise((r, j) => { ws.onopen = r; ws.onerror = j; });
  let id = 0; const pending = new Map();
  ws.onmessage = ev => { const m = JSON.parse(ev.data); if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); } else if (m.method === 'Runtime.consoleAPICalled') console.log('[page]', m.params.args.map(a => a.value ?? a.description).join(' ')); else if (m.method === 'Runtime.exceptionThrown') console.log('[page error]', JSON.stringify(m.params.exceptionDetails).slice(0, 600)); };
  const send = (method, params = {}) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
  const evaluate = async expr => { const m = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true }); if (m.result.exceptionDetails) throw new Error(JSON.stringify(m.result.exceptionDetails).slice(0, 800)); return m.result.result.value; };
  await send('Runtime.enable');
  await send('Page.enable');
  await send('Page.navigate', { url: `http://127.0.0.1:${HPORT}/godot/tools/asset-studio/studio.html` });
  for (let i = 0; i < 200; i++) { await sleep(150); try { if (await evaluate('!!(window.STUDIO && window.STUDIO.ready)')) break; } catch {} }
  const list = await evaluate('STUDIO.list()');
  const todo = list.filter(p => !filters.length || filters.some(f => p.includes(f)));
  console.log(`baking ${todo.length}/${list.length} assets`);
  const t0 = Date.now();
  for (const p of todo) {
    const t = Date.now();
    const b64 = await evaluate(`STUDIO.render(${JSON.stringify(p)})`);
    const out = path.join(ASSETS, p);
    fs.mkdirSync(path.dirname(out), { recursive: true });
    fs.writeFileSync(out, Buffer.from(b64, 'base64'));
    console.log(`  ${p}  ${(fs.statSync(out).size / 1024).toFixed(0)} KB  ${Date.now() - t} ms`);
  }
  console.log(`done in ${((Date.now() - t0) / 1000).toFixed(1)} s`);
} finally {
  try { ws && ws.close(); } catch {}
  chrome.kill();
  server.close();
}
