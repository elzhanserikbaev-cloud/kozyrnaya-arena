// Козырная Арена — локальный сервер (без зависимостей).
// Раздаёт игру по HTTP и пересылает сообщения LAN-игры по WebSocket.
// Вся логика лобби — в странице хоста; сервер только передаёт сообщения:
//   клиент -> хост: {"t":"from","id":N,"m":<сообщение>}
//   хост -> клиент: хост шлёт "N|<json>" (одному) или "*|<json>" (всем)
// Можно запустить отдельно: node server.js [папка-с-игрой]
'use strict';
const http = require('http');
const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');

const MAX = 4 * 1024 * 1024;
const FILES = { '/': 'index.html', '/index.html': 'index.html', '/babylon.js': 'babylon.js', '/peerjs.min.js': 'peerjs.min.js', '/icons.js': 'icons.js' };
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8' };

function localIPs() {
  const out = [];
  for (const list of Object.values(os.networkInterfaces())) {
    for (const a of list || []) {
      if (a.family === 'IPv4' && !a.internal && !a.address.startsWith('169.254.')) out.push(a.address);
    }
  }
  return out;
}

function createServer(webDir) {
  const conns = new Map();
  let nextId = 1;
  let host = null;
  let port = 0;

  function frame(c, first, data) {
    const n = data.length;
    let head;
    if (n < 126) head = Buffer.from([first, n]);
    else if (n < 65536) { head = Buffer.alloc(4); head[0] = first; head[1] = 126; head.writeUInt16BE(n, 2); }
    else { head = Buffer.alloc(10); head[0] = first; head[1] = 127; head.writeBigUInt64BE(BigInt(n), 2); }
    try { c.socket.write(Buffer.concat([head, data])); } catch (_) { /* соединение уже закрыто */ }
  }
  const send = (c, text) => frame(c, 0x81, Buffer.from(text, 'utf8'));

  function onMessage(c, msg) {
    if (c === host) {
      const i = msg.indexOf('|');
      if (i < 0) return;
      const tgt = msg.slice(0, i), payload = msg.slice(i + 1);
      if (tgt === '*') { for (const o of conns.values()) if (o !== host) send(o, payload); }
      else { const o = conns.get(Number(tgt)); if (o) send(o, payload); }
      return;
    }
    let obj;
    try { obj = JSON.parse(msg); } catch (_) { return; }
    if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return;
    if (obj.t === 'host') {
      const ok = !host && c.loopback;
      if (ok) host = c;
      send(c, ok ? '{"t":"hostok"}' : '{"t":"hosterr"}');
      return;
    }
    if (!host) { send(c, '{"t":"nohost"}'); return; }
    send(host, '{"t":"from","id":' + c.id + ',"m":' + JSON.stringify(obj) + '}');
  }

  // Возвращает true — кадр разобран, null — ждём данных, false — закрыть соединение
  function parseFrame(c) {
    const b = c.buf;
    if (b.length < 2) return null;
    const fin = b[0] & 0x80, op = b[0] & 0x0f, masked = b[1] & 0x80;
    let len = b[1] & 0x7f, off = 2;
    if (len === 126) { if (b.length < 4) return null; len = b.readUInt16BE(2); off = 4; }
    else if (len === 127) { if (b.length < 10) return null; const big = b.readBigUInt64BE(2); if (big > BigInt(MAX)) return false; len = Number(big); off = 10; }
    if (len > MAX) return false;
    const mo = masked ? 4 : 0;
    if (b.length < off + mo + len) return null;
    const data = Buffer.from(b.subarray(off + mo, off + mo + len));
    if (masked) { const m = b.subarray(off, off + 4); for (let i = 0; i < len; i++) data[i] ^= m[i & 3]; }
    c.buf = b.subarray(off + mo + len);
    if (op === 8) return false;
    if (op === 9) { frame(c, 0x8a, data); return true; }
    if (op === 10) return true;
    c.frag.push(data);
    if (c.frag.reduce((s, x) => s + x.length, 0) > MAX) return false;
    if (fin) { const msg = Buffer.concat(c.frag).toString('utf8'); c.frag = []; onMessage(c, msg); }
    return true;
  }

  function drop(c) {
    if (!conns.delete(c.id)) return;
    try { c.socket.destroy(); } catch (_) { /* уже закрыто */ }
    if (host === c) { host = null; for (const o of conns.values()) send(o, '{"t":"hostgone"}'); }
    else if (host) send(host, '{"t":"leave","id":' + c.id + '}');
  }

  const server = http.createServer((req, res) => {
    const p = (req.url || '/').split('?')[0];
    if (p === '/info') {
      res.writeHead(200, { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-cache' });
      res.end(JSON.stringify({ port, ips: localIPs() }));
      return;
    }
    const name = FILES[p];
    if (!name) { res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' }); res.end('not found'); return; }
    fs.readFile(path.join(webDir, name), (err, body) => {
      if (err) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { 'Content-Type': TYPES[path.extname(name)], 'Cache-Control': 'no-cache' });
      res.end(body);
    });
  });

  server.on('upgrade', (req, socket) => {
    const key = req.headers['sec-websocket-key'];
    if ((req.url || '').split('?')[0] !== '/ws' || !key) { socket.destroy(); return; }
    const acc = crypto.createHash('sha1').update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
    socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ' + acc + '\r\n\r\n');
    socket.setNoDelay(true);
    const ra = socket.remoteAddress || '';
    const c = { id: nextId++, socket, loopback: ra === '127.0.0.1' || ra === '::1' || ra === '::ffff:127.0.0.1', buf: Buffer.alloc(0), frag: [] };
    conns.set(c.id, c);
    send(c, '{"t":"hello","id":' + c.id + '}');
    socket.on('data', d => {
      c.buf = Buffer.concat([c.buf, d]);
      if (c.buf.length > MAX + 16) { drop(c); return; }
      for (;;) { const r = parseFrame(c); if (r === null) break; if (r === false) { drop(c); return; } }
    });
    socket.on('close', () => drop(c));
    socket.on('error', () => drop(c));
  });

  return {
    listen(ports) {
      return new Promise((resolve, reject) => {
        const tryNext = i => {
          if (i >= ports.length) { reject(new Error('Порты заняты: ' + ports.join(', '))); return; }
          const onErr = () => { server.removeListener('listening', onOk); tryNext(i + 1); };
          const onOk = () => { server.removeListener('error', onErr); port = ports[i]; resolve(port); };
          server.once('error', onErr);
          server.once('listening', onOk);
          server.listen(ports[i], '0.0.0.0');
        };
        tryNext(0);
      });
    },
    close() { server.close(); for (const c of conns.values()) drop(c); },
  };
}

function startServer(webDir, ports = [8777, 8778, 8779]) {
  return createServer(webDir).listen(ports);
}

module.exports = { startServer, localIPs };

if (require.main === module) {
  const dir = process.argv[2] || path.join(__dirname, 'web');
  startServer(dir).then(port => {
    console.log('Козырная Арена запущена: http://127.0.0.1:' + port + '/');
    for (const ip of localIPs()) console.log('  Адрес для друзей в сети: ' + ip + '  (http://' + ip + ':' + port + ')');
  }, err => { console.error(err.message); process.exit(1); });
}
