'use strict';
/* =========================================================
   Asset studio core: RNG, noise, materials, bevel/emboss lighting,
   shapes (rounded rects, ribbons, stars, gems, element sigils).
   Light always comes from the top-left. No glow anywhere.
   ========================================================= */
const TAU = Math.PI * 2;
const clamp = (v, a = 0, b = 1) => v < a ? a : v > b ? b : v;
const lerp = (a, b, t) => a + (b - a) * t;
const smooth = t => t * t * (3 - 2 * t);
function mulberry(a) { return function () { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; }; }
function hashStr(s) { let h = 2166136261; for (const c of s) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); } return h >>> 0; }
function mk(w, h) { const c = document.createElement('canvas'); c.width = w; c.height = h; return c; }
function layer(w, h, fn) { const c = mk(w, h); const x = c.getContext('2d'); fn(x, c); return c; }
function hex(h) { h = h.replace('#', ''); if (h.length === 3) h = h.split('').map(c => c + c).join(''); return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)]; }
function rgba(h, a) { const [r, g, b] = hex(h); return `rgba(${r},${g},${b},${a})`; }
function mix(h1, h2, t) { const a = hex(h1), b = hex(h2); return '#' + a.map((v, i) => Math.round(lerp(v, b[i], t)).toString(16).padStart(2, '0')).join(''); }
// color ramp: stops = ['#..', '#..', ...] evenly spaced, returns [r,g,b] for t in 0..1
function ramp(stops) {
  const cs = stops.map(hex), n = cs.length - 1;
  return t => { t = clamp(t) * n; const i = Math.min(n - 1, Math.floor(t)), f = t - i; const a = cs[i], b = cs[i + 1]; return [lerp(a[0], b[0], f), lerp(a[1], b[1], f), lerp(a[2], b[2], f)]; };
}
function grad(x, x0, y0, x1, y1, stops) { const g = x.createLinearGradient(x0, y0, x1, y1); stops.forEach((s, i) => Array.isArray(s) ? g.addColorStop(s[0], s[1]) : g.addColorStop(i / (stops.length - 1), s)); return g; }
function rgrad(x, cx, cy, r0, r1, stops, fx, fy) { const g = x.createRadialGradient(fx ?? cx, fy ?? cy, r0, cx, cy, r1); stops.forEach((s, i) => Array.isArray(s) ? g.addColorStop(s[0], s[1]) : g.addColorStop(i / (stops.length - 1), s)); return g; }

/* ---------- value noise (optionally periodic for seamless tiles) ---------- */
function makeNoise(seed) {
  const r = mulberry(seed), N = 512, tab = new Float32Array(N * N);
  for (let i = 0; i < tab.length; i++) tab[i] = r();
  const f = (x, y, P = 0) => {
    const xi = Math.floor(x), yi = Math.floor(y); let fx = x - xi, fy = y - yi;
    fx = fx * fx * (3 - 2 * fx); fy = fy * fy * (3 - 2 * fy);
    let x0 = xi, y0 = yi, x1 = xi + 1, y1 = yi + 1;
    if (P) { x0 = ((x0 % P) + P) % P; x1 = ((x1 % P) + P) % P; y0 = ((y0 % P) + P) % P; y1 = ((y1 % P) + P) % P; }
    x0 &= N - 1; x1 &= N - 1; y0 &= N - 1; y1 &= N - 1;
    const a = tab[y0 * N + x0], b = tab[y0 * N + x1], c = tab[y1 * N + x0], d = tab[y1 * N + x1];
    return lerp(lerp(a, b, fx), lerp(c, d, fx), fy);
  };
  f.fbm = (x, y, oct = 4, P = 0, gain = .5) => { let s = 0, a = 1, t = 0, fr = 1; for (let o = 0; o < oct; o++) { s += a * f(x * fr, y * fr, P * fr); t += a; a *= gain; fr *= 2; } return s / t; };
  return f;
}
// pixel texture: fn(px,py) -> [r,g,b] or [r,g,b,a]
function texture(w, h, fn) {
  const c = mk(w, h), x = c.getContext('2d'), id = x.createImageData(w, h), d = id.data;
  for (let y = 0, i = 0; y < h; y++) for (let X = 0; X < w; X++, i += 4) { const v = fn(X, y); d[i] = v[0]; d[i + 1] = v[1]; d[i + 2] = v[2]; d[i + 3] = v.length > 3 ? v[3] : 255; }
  x.putImageData(id, 0, 0); return c;
}
const TEXCACHE = new Map();
function cached(key, fn) { if (!TEXCACHE.has(key)) TEXCACHE.set(key, fn()); return TEXCACHE.get(key); }

/* ---------- materials ---------- */
// brushed / hammered metal
function texMetal(w, h, stops, seed = 1, hammer = .25, brush = .22) {
  const n = makeNoise(seed), n2 = makeNoise(seed + 7), R = ramp(stops);
  return texture(w, h, (x, y) => {
    const br = n.fbm(x * .004, y * .3, 3);
    const ham = n2.fbm(x * .03, y * .03, 4);
    const big = n.fbm(x * .006 + 50, y * .006, 3);
    const fine = n2(x * .9, y * .9);
    return R(.5 + (br - .5) * brush + (ham - .5) * hammer * 1.6 + (big - .5) * .35 + (fine - .5) * .05);
  });
}
// wood grain running along x. P>0 => seamless tile of size w x h (w,h multiples of the lattice)
function texWood(w, h, stops, seed = 3, scale = 1, seamless = false) {
  const n = makeNoise(seed), n2 = makeNoise(seed + 11), R = ramp(stops);
  const px = 8, py = 64; // lattice periods for seamless
  return texture(w, h, (x, y) => {
    const u = x / w * px, v = y / h * py;
    const warp = n.fbm(u * 1.0 / scale, v * .06 / scale, 4, seamless ? px / scale : 0) * 6;
    const ring = Math.sin((v / scale + warp) * Math.PI * .5);
    const grain = n2.fbm(u * 6, v * .5, 3, seamless ? px * 6 : 0);
    const knot = n.fbm(u * .5, v * .03, 2, seamless ? px * .5 : 0);
    let t = .5 + ring * .16 + (grain - .5) * .55 + (knot - .5) * .5;
    t += (n2(u * 40, v * 2, seamless ? px * 40 : 0) - .5) * .1;
    return R(t);
  });
}
function texStone(w, h, stops, seed = 5, sc = 1) {
  const n = makeNoise(seed), n2 = makeNoise(seed + 3), R = ramp(stops);
  return texture(w, h, (x, y) => {
    const a = n.fbm(x * .012 * sc, y * .012 * sc, 5), b = n2.fbm(x * .05 * sc, y * .05 * sc, 3);
    const vein = Math.abs(n2.fbm(x * .006 * sc, y * .006 * sc, 4) - .5);
    return R(clamp(.15 + a * .7 + (b - .5) * .3 - (vein < .02 ? .18 : 0)));
  });
}
function texParchment(w, h, stops, seed = 9) {
  const n = makeNoise(seed), n2 = makeNoise(seed + 5), R = ramp(stops);
  return texture(w, h, (x, y) => {
    const a = n.fbm(x * .008, y * .008, 5), f = n2.fbm(x * .15, y * .02, 2);
    const ed = Math.min(x, y, w - 1 - x, h - 1 - y) / Math.min(w, h);
    return R(clamp(.25 + a * .6 + (f - .5) * .12 + Math.min(ed * 2, .25) - .1));
  });
}
function texLeather(w, h, stops, seed = 13) {
  const n = makeNoise(seed), n2 = makeNoise(seed + 9), R = ramp(stops);
  return texture(w, h, (x, y) => {
    const pebble = 1 - Math.abs(n(x * .22, y * .22) - .5) * 2;
    const big = n2.fbm(x * .01, y * .01, 4);
    return R(clamp(big * .75 + pebble * .25 - .05));
  });
}
function pattern(x, tex) { return x.createPattern(tex, 'repeat'); }

/* ---------- separable box blur with zero padding ---------- */
function blur1(src, w, h, r) {
  const tmp = new Float32Array(w * h), out = new Float32Array(w * h), k = 1 / (2 * r + 1);
  for (let y = 0; y < h; y++) {
    const o = y * w; let s = 0;
    for (let i = 0; i <= r && i < w; i++) s += src[o + i];
    for (let x = 0; x < w; x++) { tmp[o + x] = s * k; const a = x + r + 1, b = x - r; if (a < w) s += src[o + a]; if (b >= 0) s -= src[o + b]; }
  }
  for (let x = 0; x < w; x++) {
    let s = 0;
    for (let i = 0; i <= r && i < h; i++) s += tmp[i * w + x];
    for (let y = 0; y < h; y++) { out[y * w + x] = s * k; const a = y + r + 1, b = y - r; if (a < h) s += tmp[a * w + x]; if (b >= 0) s -= tmp[b * w + x]; }
  }
  return out;
}
function blurN(a, w, h, r, passes = 3) { const b = Math.max(1, Math.round(r / Math.sqrt(passes) * 1.15)); for (let p = 0; p < passes; p++) a = blur1(a, w, h, b); return a; }

/* ---------- bevel & emboss: lights a layer from its own alpha ----------
   r: bevel width, depth: slope, amb: ambient, spec: specular strength,
   inset: carved instead of raised, round: profile curvature */
const LIGHT = (() => { const v = [-.52, -.62, .58], l = Math.hypot(...v); return v.map(c => c / l); })();
function bevel(cv, o = {}) {
  const { r = 6, depth = 1.2, amb = .42, spec = .35, shin = 18, inset = false, specCol = [255, 248, 230], round = 1, soft = 0 } = o;
  const w = cv.width, h = cv.height, c = cv.getContext('2d'), id = c.getImageData(0, 0, w, h), d = id.data, n = w * h;
  let A = new Float32Array(n); for (let i = 0; i < n; i++) A[i] = d[i * 4 + 3] / 255;
  let H = blurN(A, w, h, r);
  if (round !== 1) for (let i = 0; i < n; i++) H[i] = 1 - Math.pow(1 - H[i], round);
  if (soft) H = blur1(H, w, h, soft);
  const [lx, ly, lz] = LIGHT; let hx = lx, hy = ly, hz = lz + 1; const hl = Math.hypot(hx, hy, hz); hx /= hl; hy /= hl; hz /= hl;
  const s = depth * r * .5 * (inset ? -1 : 1), flatSpec = Math.pow(hz, shin);
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const i = y * w + x, j = i * 4; if (d[j + 3] === 0) continue;
    const xl = x > 0 ? H[i - 1] : 0, xr = x < w - 1 ? H[i + 1] : 0, yu = y > 0 ? H[i - w] : 0, yd = y < h - 1 ? H[i + w] : 0;
    let nx = -(xr - xl) * s, ny = -(yd - yu) * s, nz = 1; const ln = Math.hypot(nx, ny, nz); nx /= ln; ny /= ln; nz /= ln;
    const dif = Math.max(0, nx * lx + ny * ly + nz * lz) / lz;
    const k = amb + (1 - amb) * dif;
    const sp = spec * Math.max(0, Math.pow(Math.max(0, nx * hx + ny * hy + nz * hz), shin) - flatSpec) * 255;
    d[j] = clamp(d[j] * k + sp * specCol[0] / 255, 0, 255); d[j + 1] = clamp(d[j + 1] * k + sp * specCol[1] / 255, 0, 255); d[j + 2] = clamp(d[j + 2] * k + sp * specCol[2] / 255, 0, 255);
  }
  c.putImageData(id, 0, 0); return cv;
}
// draw a layer onto ctx with a soft drop shadow
function put(ctx, lay, o = {}) {
  const { sh = .55, blur = 8, ox = 2, oy = 5, alpha = 1, op = null, x = 0, y = 0, col = '0,0,0' } = o;
  ctx.save(); if (sh) { ctx.shadowColor = `rgba(${col},${sh})`; ctx.shadowBlur = blur; ctx.shadowOffsetX = ox; ctx.shadowOffsetY = oy; }
  ctx.globalAlpha = alpha; if (op) ctx.globalCompositeOperation = op; ctx.drawImage(lay, x, y); ctx.restore();
}
// shape layer: fill pathFn with material (pattern/color/gradient), apply overlay sheen, bevel
function shapeLayer(w, h, pathFn, fill, o = {}) {
  const cv = layer(w, h, x => {
    x.save(); pathFn(x); x.fillStyle = typeof fill === 'function' ? fill(x) : fill; x.fill(o.rule || 'nonzero'); x.restore();
    if (o.sheen) { x.save(); x.globalCompositeOperation = 'source-atop'; x.globalAlpha = o.sheenA ?? .5; x.fillStyle = o.sheen(x); x.fillRect(0, 0, w, h); x.restore(); }
    if (o.post) o.post(x);
  });
  if (o.bevel !== false) bevel(cv, o.bevel || {});
  if (o.after) o.after(cv.getContext('2d'));
  return cv;
}
// inner shadow inside a path (darkens edges along top-left → reads as recessed)
function innerShadow(x, pathFn, { blur = 10, ox = 3, oy = 5, a = .7, col = '0,0,0' } = {}) {
  x.save(); pathFn(x); x.clip();
  x.shadowColor = `rgba(${col},${a})`; x.shadowBlur = blur; x.shadowOffsetX = ox; x.shadowOffsetY = oy;
  x.beginPath(); x.rect(-5000, -5000, 10000, 10000); pathFn(x, true); x.fillStyle = '#000'; x.fill('evenodd');
  x.restore();
}
// carved groove line along a path: dark core + light lower-right lip
function groove(x, pathFn, w = 2, a = .55) {
  x.save(); x.lineJoin = x.lineCap = 'round';
  x.translate(1, 1); pathFn(x); x.strokeStyle = `rgba(255,240,210,${a * .45})`; x.lineWidth = w; x.stroke();
  x.translate(-1.4, -1.4); pathFn(x); x.strokeStyle = `rgba(0,0,0,${a})`; x.lineWidth = w; x.stroke();
  x.restore();
}
function noiseOverlay(x, w, h, seed, a = .08, sc = .5) {
  const n = makeNoise(seed);
  const t = texture(w, h, (X, Y) => { const v = n.fbm(X * sc * .1, Y * sc * .1, 3) * 255; return [v, v, v, 255]; });
  x.save(); x.globalCompositeOperation = 'overlay'; x.globalAlpha = a; x.drawImage(t, 0, 0); x.restore();
}

/* ---------- paths ---------- */
function rr(x, X, Y, W, H, r, ccw) {
  if (!ccw) { x.moveTo(X + r, Y); x.arcTo(X + W, Y, X + W, Y + H, r); x.arcTo(X + W, Y + H, X, Y + H, r); x.arcTo(X, Y + H, X, Y, r); x.arcTo(X, Y, X + W, Y, r); x.closePath(); }
  else { x.moveTo(X + r, Y); x.arcTo(X, Y, X, Y + H, r); x.arcTo(X, Y + H, X + W, Y + H, r); x.arcTo(X + W, Y + H, X + W, Y, r); x.arcTo(X + W, Y, X, Y, r); x.closePath(); }
}
const P = {
  rr: (X, Y, W, H, r) => (x, cont) => { if (!cont) x.beginPath(); rr(x, X, Y, W, H, r); },
  circle: (cx, cy, r) => (x, cont) => { if (!cont) x.beginPath(); x.moveTo(cx + r, cy); x.arc(cx, cy, r, 0, TAU); x.closePath(); },
  ring: (cx, cy, r0, r1) => x => { x.beginPath(); x.arc(cx, cy, r1, 0, TAU); x.closePath(); x.moveTo(cx + r0, cy); x.arc(cx, cy, r0, 0, TAU, true); x.closePath(); },
  rrRing: (a, b) => x => { x.beginPath(); rr(x, ...a); rr(x, ...b, true); },
  star: (cx, cy, R, r, n = 5, rot = -Math.PI / 2) => (x, cont) => { if (!cont) x.beginPath(); for (let i = 0; i < n * 2; i++) { const a = rot + i * Math.PI / n, q = i % 2 ? r : R; i ? x.lineTo(cx + Math.cos(a) * q, cy + Math.sin(a) * q) : x.moveTo(cx + Math.cos(a) * q, cy + Math.sin(a) * q); } x.closePath(); },
  poly: pts => (x, cont) => { if (!cont) x.beginPath(); pts.forEach((p, i) => i ? x.lineTo(p[0], p[1]) : x.moveTo(p[0], p[1])); x.closePath(); },
};
// heart centered at cx,cy with half-width s
function heartPath(x, cx, cy, s) {
  x.moveTo(cx, cy + s * .95);
  x.bezierCurveTo(cx - s * .35, cy + s * .6, cx - s * 1.05, cy + s * .15, cx - s, cy - s * .35);
  x.bezierCurveTo(cx - s * .95, cy - s * .95, cx - s * .2, cy - s * 1.05, cx, cy - s * .5);
  x.bezierCurveTo(cx + s * .2, cy - s * 1.05, cx + s * .95, cy - s * .95, cx + s, cy - s * .35);
  x.bezierCurveTo(cx + s * 1.05, cy + s * .15, cx + s * .35, cy + s * .6, cx, cy + s * .95); x.closePath();
}
// banner ribbon with folded tails. (x0..x1) main face, y top, h height, tail width t
function ribbonPaths(x0, x1, y, h, t = 36, drop = 10) {
  const face = x => { x.beginPath(); x.moveTo(x0, y); x.quadraticCurveTo((x0 + x1) / 2, y - 6, x1, y); x.lineTo(x1, y + h); x.quadraticCurveTo((x0 + x1) / 2, y + h - 6, x0, y + h); x.closePath(); };
  const tailL = (x, c) => { if (!c) x.beginPath(); x.moveTo(x0 + 6, y + drop); x.lineTo(x0 - t, y + drop); x.lineTo(x0 - t + t * .45, y + drop + h / 2); x.lineTo(x0 - t, y + drop + h); x.lineTo(x0 + 6, y + drop + h); x.closePath(); };
  const tailR = (x, c) => { if (!c) x.beginPath(); x.moveTo(x1 - 6, y + drop); x.lineTo(x1 + t, y + drop); x.lineTo(x1 + t - t * .45, y + drop + h / 2); x.lineTo(x1 + t, y + drop + h); x.lineTo(x1 - 6, y + drop + h); x.closePath(); };
  const foldL = (x, c) => { if (!c) x.beginPath(); x.moveTo(x0, y + h); x.lineTo(x0 + 8, y + h + drop); x.lineTo(x0 + 8, y + h); x.closePath(); };
  const foldR = (x, c) => { if (!c) x.beginPath(); x.moveTo(x1, y + h); x.lineTo(x1 - 8, y + h + drop); x.lineTo(x1 - 8, y + h); x.closePath(); };
  return { face, tailL, tailR, foldL, foldR };
}

/* ---------- icon paths from icons.js (game-icons.net, CC BY 3.0) ---------- */
const ICONP = new Map();
function iconPath(name) { if (!ICONP.has(name)) ICONP.set(name, new Path2D(ICONS[name] || '')); return ICONP.get(name); }
function iconFill(x, name, cx, cy, size, fill) { x.save(); x.translate(cx - size / 2, cy - size / 2); x.scale(size / 512, size / 512); x.fillStyle = fill; x.fill(iconPath(name)); x.restore(); }

/* ---------- element sigils (procedural, original) ---------- */
function flamePath(x) { // unit flame, base at y=96, tip at y=-104
  x.beginPath();
  x.moveTo(0, 96);
  x.bezierCurveTo(-52, 96, -80, 62, -78, 22); x.bezierCurveTo(-76, -16, -52, -36, -46, -74);
  x.bezierCurveTo(-26, -52, -22, -30, -24, -14); x.bezierCurveTo(-14, -46, 2, -70, -6, -104);
  x.bezierCurveTo(30, -82, 50, -48, 44, -10); x.bezierCurveTo(54, -24, 58, -40, 56, -54);
  x.bezierCurveTo(78, -26, 84, 8, 78, 34); x.bezierCurveTo(70, 72, 42, 96, 0, 96); x.closePath();
}
// draws a filled sigil with current fillStyle centered at cx,cy radius r
function sigil(x, el, cx, cy, r) {
  x.save(); x.translate(cx, cy); x.scale(r / 100, r / 100);
  if (el === 'ice') {
    x.lineCap = 'round'; x.lineJoin = 'round'; x.strokeStyle = x.fillStyle;
    for (let i = 0; i < 6; i++) {
      x.save(); x.rotate(i * TAU / 6);
      x.beginPath(); x.moveTo(0, 0); x.lineTo(0, -92); x.lineWidth = 15; x.stroke();
      x.beginPath(); x.moveTo(0, -38); x.lineTo(-24, -60); x.moveTo(0, -38); x.lineTo(24, -60);
      x.moveTo(0, -64); x.lineTo(-16, -80); x.moveTo(0, -64); x.lineTo(16, -80); x.lineWidth = 11; x.stroke();
      x.restore();
    }
    x.beginPath(); for (let i = 0; i < 6; i++) { const a = i * TAU / 6 - Math.PI / 2; x.lineTo(Math.cos(a) * 26, Math.sin(a) * 26); } x.closePath(); x.fill();
  } else if (el === 'fire') {
    flamePath(x); x.fill();
    x.globalCompositeOperation = 'destination-out';
    x.beginPath(); x.moveTo(0, 80); x.bezierCurveTo(-30, 80, -42, 56, -36, 32); x.bezierCurveTo(-30, 12, -12, 4, -8, -18);
    x.bezierCurveTo(10, 0, 18, 18, 14, 34); x.bezierCurveTo(24, 28, 28, 18, 28, 8); x.bezierCurveTo(42, 30, 40, 58, 26, 70); x.bezierCurveTo(18, 77, 10, 80, 0, 80); x.closePath(); x.fill();
    x.globalCompositeOperation = 'source-over';
    x.beginPath(); x.moveTo(0, 72); x.bezierCurveTo(-16, 72, -22, 58, -18, 46); x.bezierCurveTo(-14, 34, -4, 30, -2, 16); x.bezierCurveTo(10, 28, 18, 40, 16, 52); x.bezierCurveTo(14, 64, 8, 72, 0, 72); x.closePath(); x.fill();
  } else if (el === 'light') {
    x.beginPath(); x.arc(0, 0, 40, 0, TAU); x.fill();
    for (let i = 0; i < 16; i++) {
      const a = i * TAU / 16, L = i % 2 ? 72 : 98, wd = i % 2 ? .1 : .13;
      x.beginPath(); x.moveTo(Math.cos(a - wd) * 50, Math.sin(a - wd) * 50); x.lineTo(Math.cos(a) * L, Math.sin(a) * L); x.lineTo(Math.cos(a + wd) * 50, Math.sin(a + wd) * 50); x.closePath(); x.fill();
    }
    x.globalCompositeOperation = 'destination-out'; x.beginPath(); x.arc(0, 0, 40, 0, TAU); x.arc(0, 0, 30, 0, TAU, true); x.fill();
    x.globalCompositeOperation = 'source-over';
  } else if (el === 'nature') {
    x.rotate(-.5);
    x.beginPath(); x.moveTo(0, -100); x.bezierCurveTo(60, -62, 66, 24, 0, 84); x.bezierCurveTo(-66, 24, -60, -62, 0, -100); x.closePath(); x.fill();
    x.fillRect(-5, 70, 10, 34);
    x.globalCompositeOperation = 'destination-out'; x.lineCap = 'round'; x.strokeStyle = '#000';
    x.lineWidth = 7; x.beginPath(); x.moveTo(0, -76); x.lineTo(0, 70); x.stroke();
    x.lineWidth = 5; x.beginPath();
    for (let i = 0; i < 4; i++) { const y = -46 + i * 28; x.moveTo(0, y + 14); x.lineTo(-30 + i * 3, y - 6); x.moveTo(0, y + 14); x.lineTo(30 - i * 3, y - 6); }
    x.stroke(); x.globalCompositeOperation = 'source-over';
  }
  x.restore();
}

/* ---------- gems (faceted, painted; no glow) ---------- */
// cols: [dark, mid, light]
function gemLayer(w, h, cx, cy, r, cols, shape = 'oval', ry) {
  ry = ry || r;
  const c = layer(w, h, x => {
    const n = shape === 'round' ? 12 : 10, pts = [], inner = [];
    for (let i = 0; i < n; i++) { const a = -Math.PI / 2 + i * TAU / n; pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * ry]); inner.push([cx + Math.cos(a) * r * .52 - r * .08, cy + Math.sin(a) * ry * .52 - ry * .1]); }
    // base body
    x.beginPath(); x.ellipse(cx, cy, r, ry, 0, 0, TAU); x.fillStyle = rgrad(x, cx - r * .2, cy - ry * .25, 0, r * 1.1, [cols[2], cols[1], cols[0]]); x.fill();
    // crown facets
    for (let i = 0; i < n; i++) {
      const a0 = -Math.PI / 2 + i * TAU / n, a1 = a0 + TAU / n;
      const p0 = [cx + Math.cos(a0) * r, cy + Math.sin(a0) * ry], p1 = [cx + Math.cos(a1) * r, cy + Math.sin(a1) * ry];
      const q0 = inner[i], q1 = inner[(i + 1) % n];
      const am = (a0 + a1) / 2, lit = (-Math.cos(am) * .55 - Math.sin(am) * .65 + 1) / 2; // facing light
      x.beginPath(); x.moveTo(p0[0], p0[1]); x.lineTo(p1[0], p1[1]); x.lineTo(q1[0], q1[1]); x.lineTo(q0[0], q0[1]); x.closePath();
      const col = lit > .6 ? mix(cols[1], cols[2], (lit - .6) * 2.2) : mix(cols[0], cols[1], lit / .6);
      x.fillStyle = rgba(col, .85); x.fill();
      x.strokeStyle = rgba(cols[0], .5); x.lineWidth = Math.max(.8, r / 30); x.stroke();
    }
    // table
    x.beginPath(); inner.forEach((p, i) => i ? x.lineTo(p[0], p[1]) : x.moveTo(p[0], p[1])); x.closePath();
    x.fillStyle = grad(x, cx - r * .5, cy - ry * .5, cx + r * .4, cy + ry * .4, [mix(cols[2], '#ffffff', .25), cols[1], mix(cols[1], cols[0], .5)]); x.fill();
    x.strokeStyle = rgba(mix(cols[2], '#ffffff', .4), .6); x.lineWidth = Math.max(.8, r / 34); x.stroke();
    // inner depth
    x.beginPath(); x.ellipse(cx + r * .15, cy + ry * .2, r * .45, ry * .4, 0, 0, TAU); x.fillStyle = rgba(cols[0], .25); x.fill();
    // specular: small soft highlight + sharp sparkle
    x.beginPath(); x.ellipse(cx - r * .38, cy - ry * .42, r * .22, ry * .12, -.6, 0, TAU); x.fillStyle = 'rgba(255,255,255,.75)'; x.fill();
    x.beginPath(); x.arc(cx - r * .12, cy - ry * .55, Math.max(1, r * .05), 0, TAU); x.fillStyle = 'rgba(255,255,255,.8)'; x.fill();
    // lower reflected light
    x.beginPath(); x.ellipse(cx + r * .3, cy + ry * .55, r * .3, ry * .12, -.5, 0, TAU); x.fillStyle = rgba(cols[2], .35); x.fill();
    // outline
    x.beginPath(); x.ellipse(cx, cy, r, ry, 0, 0, TAU); x.strokeStyle = rgba(cols[0], .9); x.lineWidth = Math.max(1, r / 18); x.stroke();
  });
  return c;
}

/* ---------- palettes ---------- */
const EL = {
  ice: {
    metal: ['#1e2836', '#4d5e74', '#8fa2ba', '#d4deea', '#f6f9fd'], accent: '#bfe3ff',
    gem: ['#081d55', '#2357c4', '#9cc4ff'], body: ['#0b1522', '#14253a', '#1f3552'],
    ribbon: ['#163768', '#2a5a9e', '#4f80c2'], rim: '#9fd4ff', tone: '#2a5a9e', name: 'Лёд',
    crystal: ['#5d8fc4', '#a9d2f2', '#eef8ff'],
  },
  fire: {
    metal: ['#250a05', '#62200f', '#a4482a', '#d8885c', '#f8cfa8'], accent: '#f08a3c',
    gem: ['#3e0510', '#b0142c', '#ff8a7a'], body: ['#1c0c0a', '#2e1410', '#45201a'],
    ribbon: ['#651010', '#9c2418', '#c8482a'], rim: '#ff9a4c', tone: '#a8281e', name: 'Огонь',
    flame: ['#6a1408', '#b8401a', '#ec8a34', '#f8cc6a'],
  },
  light: {
    metal: ['#3e2a06', '#8a6418', '#c9a040', '#ecd07a', '#fff4c8'], accent: '#f3e6c0',
    gem: ['#5a3204', '#d4860e', '#ffe08a'], body: ['#20170c', '#33251a', '#3e2e18'],
    ribbon: ['#7a4e0e', '#a87416', '#cf9a30'], rim: '#ffd890', tone: '#b07a20', name: 'Свет',
    ivory: ['#b8aa88', '#e2d8bc', '#f8f2e2'],
  },
  nature: {
    metal: ['#1e1108', '#46290f', '#76491f', '#a77a45', '#d2aa72'], accent: '#8cc060',
    gem: ['#03321a', '#0f8a48', '#8af0b0'], body: ['#0e160c', '#172414', '#22331c'],
    ribbon: ['#1a4a22', '#2a6e34', '#4a9450'], rim: '#a8e07c', tone: '#2f7a3a', name: 'Природа',
    leaf: ['#1d4416', '#3e7a28', '#8cbc56'],
  },
};
const SILVER = ['#2c3038', '#646c7a', '#a9b1bf', '#e2e6ee', '#ffffff'];
const GOLD = ['#3a2604', '#86601a', '#c8982e', '#efd27a', '#fff6cc'];
const BRONZE = ['#2a1a0a', '#5e3e1c', '#9a7040', '#d0aa70', '#f4dcb0'];
const SUIT_EL = { S: 'ice', H: 'fire', D: 'light', C: 'nature' };

/* ---------- registry ---------- */
const REG = [];
function reg(path, fn) { REG.push({ path, fn }); }
