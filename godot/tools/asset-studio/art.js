'use strict';
/* =========================================================
   Portraits: hero_<id>.png 432x312 (element backdrop + beveled icon figure)
   and magic_<key>.png 300x300 (round icon art).
   ========================================================= */
const PW = 432, PH = 312;
// id, icon, suit (from web/index.html RAW)
const HEROES = [
  ['cutpurse', 'robber', 'S'], ['leech', 'bat', 'H'], ['spider', 'hanging-spider', 'C'], ['sellsword', 'brutal-helm', 'D'],
  ['cardsharp', 'carnival-mask', 'S'], ['nun', 'nun-face', 'H'], ['gravedigger', 'hasty-grave', 'C'], ['crossbow', 'crossbow', 'D'],
  ['duelist', 'duel', 'S'], ['vampire', 'vampire-dracula', 'H'], ['halberdier', 'pikeman', 'D'], ['bogwitch', 'witch-face', 'C'],
  ['nighthunter', 'hooded-figure', 'S'], ['inquisitor', 'templar-eye', 'D'], ['cultist', 'cultist', 'H'], ['necro', 'raise-zombie', 'C'],
  ['poisoner', 'poison-bottle', 'S'], ['executioner', 'executioner-hood', 'D'], ['bloodpriest', 'chalice-drops', 'H'], ['shadowmaster', 'hooded-assassin', 'S'],
  ['werewolf', 'werewolf', 'C'], ['blackknight', 'black-knight-helm', 'D'], ['plaguedoc', 'plague-doctor-profile', 'C'], ['crimsonwitch', 'warlock-hood', 'H'],
  ['guildkiller', 'cloak-dagger', 'S'], ['cardinal', 'pope-crown', 'D'], ['gargoyle', 'gargoyle', 'C'], ['guildmaster', 'daggers', 'S'],
  ['vampirecount', 'vampire-cape', 'H'], ['deathlord', 'skull-staff', 'C'], ['mercqueen', 'queen-crown', 'D'], ['countess', 'dagger-rose', 'H'],
  ['spadequeen', 'ceremonial-mask', 'S'], ['tyrant', 'throne-king', 'D'], ['plaguelord', 'dread-skull', 'C'], ['reaper', 'grim-reaper', 'S'],
  ['blooddemon', 'devil-mask', 'H'],
];
const MAGICS = [
  ['sword', 'bloody-sword', 'item'], ['armor', 'spiked-armor', 'item'], ['orb', 'crystal-ball', 'item'], ['fang', 'fangs', 'item'],
  ['feather', 'coinflip', 'item'], ['thorns', 'spiked-shield', 'item'], ['joker', 'jester-hat', 'item'],
  ['fireball', 'fireball', 'spell'], ['heal', 'health-potion', 'spell'], ['bless', 'holy-symbol', 'spell'], ['rage', 'mighty-horn', 'spell'],
  ['freeze', 'snowflake-1', 'spell'], ['meteor', 'meteor-impact', 'spell'], ['surge', 'magic-potion', 'spell'], ['pact', 'blood', 'spell'],
  ['curse', 'evil-hand', 'spell'], ['chain', 'chain-lightning', 'spell'], ['revive', 'coffin', 'spell'], ['venom', 'pouring-chalice', 'spell'],
  ['guillotine', 'guillotine', 'spell'],
];
const FIG = {
  ice: { cols: ['#f2fcff', '#8ed4e6', '#235c74'], rim: '#c8f6ff', tint: '#062a3a' },
  fire: { cols: ['#fff2d4', '#f4a050', '#7a240e'], rim: '#ffc890', tint: '#3a0806' },
  light: { cols: ['#fffae0', '#f2c858', '#80520c'], rim: '#fff2b8', tint: '#3a2204' },
  nature: { cols: ['#f2ffdc', '#a6d86a', '#2e5a18'], rim: '#dcffb0', tint: '#0c2a08' },
  item: { cols: ['#ffffff', '#e2ecf0', '#7890a0'], rim: '#b8f4f4' },
  spell: { cols: ['#fff2dc', '#d4b896', '#5e3e34'], rim: '#e6c0ff' },
};

/* ---------- backdrops ---------- */
function blob(x, cx, cy, r, col, a) { x.fillStyle = rgrad(x, cx, cy, 0, r, [rgba(col, a), rgba(col, a * .6), rgba(col, 0)]); x.fillRect(cx - r, cy - r, r * 2, r * 2); }
function ridge(x, rnd, y0, amp, step, w) { const pts = [[0, y0]]; let y = y0; for (let px = 0; px <= w + step; px += step * (.6 + rnd() * .8)) { y = y0 + (rnd() - .5) * amp * 2 - (rnd() < .25 ? amp * rnd() : 0); pts.push([px, y]); } return pts; }
function fillRidge(x, pts, h, fill) { x.beginPath(); x.moveTo(0, h); pts.forEach(p => x.lineTo(p[0], p[1])); x.lineTo(PW * 2, h); x.closePath(); x.fillStyle = fill; x.fill(); }

function bgIce(x, w, h, rnd) {
  x.fillStyle = grad(x, 0, 0, 0, h, [[0, '#3f6ea6'], [.35, '#86afd6'], [.62, '#d8e9f6'], [1, '#9fbad6']]); x.fillRect(0, 0, w, h);
  for (let i = 0; i < 7; i++) blob(x, rnd() * w, 20 + rnd() * h * .4, 60 + rnd() * 90, '#ffffff', .18);
  // far range with snow caps
  const far = ridge(x, rnd, h * .52, 34, 38, w);
  fillRidge(x, far, h, grad(x, 0, h * .35, 0, h * .8, ['#b9cfe6', '#7c9cc2']));
  x.save(); fillRidge(x, far, h, '#0000'); x.clip(); x.fillStyle = grad(x, 0, h * .35, 0, h * .62, ['rgba(250,253,255,.95)', 'rgba(250,253,255,0)']); x.fillRect(0, 0, w, h);
  // snow-line light/shadow sides
  for (let i = 1; i < far.length; i++) { const p = far[i - 1], q = far[i]; if (q[1] > p[1]) { x.beginPath(); x.moveTo(p[0], p[1]); x.lineTo(q[0], q[1]); x.lineTo(q[0], h); x.lineTo(p[0] + (q[0] - p[0]) * .3, h); x.closePath(); x.fillStyle = 'rgba(40,70,110,.18)'; x.fill(); } }
  x.restore();
  blob(x, w * .5, h * .62, w * .7, '#eef6ff', .25); // haze
  const near = ridge(x, rnd, h * .7, 22, 60, w);
  fillRidge(x, near, h, grad(x, 0, h * .6, 0, h, ['#5f7fa8', '#2f4668']));
  // snow ground
  x.beginPath(); x.moveTo(0, h * .86); x.bezierCurveTo(w * .3, h * .78, w * .6, h * .92, w, h * .82); x.lineTo(w, h); x.lineTo(0, h); x.closePath();
  x.fillStyle = grad(x, 0, h * .78, 0, h, ['#f2f8ff', '#b4c8e0']); x.fill();
  // snowfall
  for (let i = 0; i < 90; i++) { const r = .6 + rnd() * 2.2; x.beginPath(); x.arc(rnd() * w, rnd() * h, r, 0, TAU); x.fillStyle = `rgba(255,255,255,${.35 + rnd() * .55})`; x.fill(); }
  x.save(); x.filter = 'blur(2px)'; for (let i = 0; i < 10; i++) { x.beginPath(); x.arc(rnd() * w, rnd() * h, 3 + rnd() * 4, 0, TAU); x.fillStyle = 'rgba(255,255,255,.35)'; x.fill(); } x.restore();
  x.save(); x.globalAlpha = .18; x.fillStyle = '#ffffff'; sigil(x, 'ice', w * (.12 + rnd() * .1), h * .25, 22); sigil(x, 'ice', w * (.8 + rnd() * .1), h * .18, 16); x.restore();
}
function bgFire(x, w, h, rnd) {
  x.fillStyle = grad(x, 0, 0, 0, h, [[0, '#2a0a10'], [.3, '#6e1a16'], [.55, '#c4482a'], [.7, '#eea050'], [1, '#5a1a0e']]); x.fillRect(0, 0, w, h);
  const sx = w * (.3 + rnd() * .4);
  x.fillStyle = rgrad(x, sx, h * .66, 0, 120, ['rgba(255,226,150,.95)', 'rgba(255,190,100,.55)', 'rgba(255,150,70,0)']); x.fillRect(0, 0, w, h);
  x.beginPath(); x.arc(sx, h * .66, 34, 0, TAU); x.fillStyle = 'rgba(255,236,180,.85)'; x.fill();
  // smoke banks
  for (let i = 0; i < 9; i++) blob(x, rnd() * w, rnd() * h * .45, 50 + rnd() * 80, rnd() < .5 ? '#1c0a0a' : '#4a1c14', .45);
  for (let i = 0; i < 5; i++) { x.beginPath(); x.ellipse(rnd() * w, h * (.42 + rnd() * .12), 80 + rnd() * 90, 6 + rnd() * 6, 0, 0, TAU); x.fillStyle = 'rgba(120,40,26,.35)'; x.fill(); }
  const far = ridge(x, rnd, h * .68, 18, 46, w);
  fillRidge(x, far, h, '#4a1812');
  const near = ridge(x, rnd, h * .8, 16, 70, w);
  fillRidge(x, near, h, grad(x, 0, h * .7, 0, h, ['#26100c', '#120606']));
  // lava glints along the ridge
  x.save(); x.strokeStyle = 'rgba(255,140,60,.55)'; x.lineWidth = 1.5; x.beginPath(); near.forEach((p, i) => i ? x.lineTo(p[0], p[1]) : x.moveTo(p[0], p[1])); x.stroke(); x.restore();
  for (let i = 0; i < 70; i++) { const ex = rnd() * w, ey = rnd() * h, r = .6 + rnd() * 1.8; x.beginPath(); x.ellipse(ex, ey, r, r * (1 + rnd() * 1.5), -.3, 0, TAU); x.fillStyle = rnd() < .5 ? `rgba(255,200,110,${.5 + rnd() * .5})` : `rgba(255,120,50,${.5 + rnd() * .5})`; x.fill(); }
}
function bgLight(x, w, h, rnd) {
  x.fillStyle = rgrad(x, w / 2, -30, 10, h * 1.25, [[0, '#fff8de'], [.35, '#f4d68e'], [.7, '#c8903e'], [1, '#6a4418']]); x.fillRect(0, 0, w, h);
  x.save(); x.translate(w / 2, -50);
  for (let i = 0; i < 18; i++) { const a = Math.PI * (.1 + .8 * i / 17) + (rnd() - .5) * .05, s = .035 + rnd() * .03; x.beginPath(); x.moveTo(0, 0); x.lineTo(Math.cos(a - s) * 700, Math.sin(a - s) * 700); x.lineTo(Math.cos(a + s) * 700, Math.sin(a + s) * 700); x.closePath(); x.fillStyle = `rgba(255,250,225,${.07 + rnd() * .08})`; x.fill(); }
  x.restore();
  // colonnade
  x.save(); x.globalAlpha = .2; x.fillStyle = '#8a5a24';
  for (let i = 0; i < 7; i++) { const cx = (i + .5) * w / 7 + (rnd() - .5) * 8, top = h * .34 + (Math.abs(i - 3) * 6); x.fillRect(cx - 9, top, 18, h); x.fillRect(cx - 14, top - 8, 28, 8); }
  x.fillRect(0, h * .3, w, 10); x.restore();
  // clouds at the bottom
  for (let i = 0; i < 12; i++) { const cx = rnd() * w, cy = h * (.8 + rnd() * .2), r = 40 + rnd() * 50; x.fillStyle = rgrad(x, cx, cy - r * .3, 0, r, ['rgba(255,250,236,.95)', 'rgba(250,232,196,.75)', 'rgba(240,210,160,0)']); x.beginPath(); x.arc(cx, cy, r, 0, TAU); x.fill(); }
  for (let i = 0; i < 50; i++) { x.beginPath(); x.arc(rnd() * w, rnd() * h * .8, .6 + rnd() * 1.6, 0, TAU); x.fillStyle = `rgba(255,246,210,${.4 + rnd() * .5})`; x.fill(); }
}
function bgNature(x, w, h, rnd) {
  x.fillStyle = grad(x, 0, 0, 0, h, [[0, '#c6dc96'], [.3, '#7fa858'], [.65, '#36582c'], [1, '#14240f']]); x.fillRect(0, 0, w, h);
  // far trunks
  for (let layer = 0; layer < 3; layer++) {
    const col = ['#8fae70', '#56783e', '#2c4422'][layer], n = 6 - layer;
    for (let i = 0; i < n; i++) { const cx = rnd() * w, tw = 10 + layer * 10 + rnd() * 10; x.fillStyle = grad(x, cx - tw, 0, cx + tw, 0, [mix(col, '#000', .25), col, mix(col, '#000', .35)]); x.beginPath(); x.moveTo(cx - tw * .7, 0); x.lineTo(cx + tw * .7, 0); x.lineTo(cx + tw, h); x.lineTo(cx - tw, h); x.closePath(); x.fill(); }
    for (let i = 0; i < 8; i++) blob(x, rnd() * w, rnd() * h * .3, 50 + rnd() * 50, ['#a8c87c', '#5e8a3c', '#2a4a1e'][layer], .5);
  }
  // light shafts
  x.save(); x.globalCompositeOperation = 'screen';
  for (let i = 0; i < 5; i++) { const sx = rnd() * w * 1.2 - 40; x.beginPath(); x.moveTo(sx, -10); x.lineTo(sx + 30 + rnd() * 30, -10); x.lineTo(sx + 160 + rnd() * 60, h); x.lineTo(sx + 100, h); x.closePath(); x.fillStyle = `rgba(250,240,180,${.07 + rnd() * .06})`; x.fill(); }
  x.restore();
  // canopy leaves framing the top corners
  const lc = [['#1e3a16', '#2f5a22', '#4e7e34'], ['#2a4a1c', '#3e6e28', '#6a9a44']];
  for (let i = 0; i < 70; i++) { const side = rnd() < .5, px = side ? rnd() * w * .35 : w - rnd() * w * .35, py = rnd() * h * .3 * (1 - Math.abs(px - w / 2) / w); leaf(x, px, py, rnd() * TAU, 22 + rnd() * 18, 12 + rnd() * 6, lc[i % 2]); }
  // grass
  x.fillStyle = grad(x, 0, h * .82, 0, h, ['#2e4a20', '#16260e']); x.beginPath(); x.moveTo(0, h * .88); x.bezierCurveTo(w * .3, h * .82, w * .7, h * .9, w, h * .84); x.lineTo(w, h); x.lineTo(0, h); x.fill();
  x.lineCap = 'round';
  for (let i = 0; i < 220; i++) { const gx = rnd() * w, gy = h * .86 + rnd() * h * .16, L = 8 + rnd() * 18; x.beginPath(); x.moveTo(gx, gy); x.quadraticCurveTo(gx + (rnd() - .5) * 8, gy - L * .6, gx + (rnd() - .5) * 14, gy - L); x.strokeStyle = rnd() < .5 ? '#4a7a2c' : '#2a4a1a'; x.lineWidth = 1 + rnd() * 1.5; x.stroke(); }
  for (let i = 0; i < 7; i++) leaf(x, rnd() * w, h * (.3 + rnd() * .5), rnd() * TAU, 10 + rnd() * 6, 6, ['#6a5a1c', '#a8862c', '#d8b850']);
}
const BG = { ice: bgIce, fire: bgFire, light: bgLight, nature: bgNature };

/* ---------- beveled icon figure ---------- */
function figureLayer(w, h, icon, cx, cy, size, palette, seed) {
  const f = layer(w, h, x => {
    iconFill(x, icon, cx, cy, size, grad(x, cx - size * .3, cy - size * .5, cx + size * .25, cy + size * .5, palette.cols));
    // material grain
    const n = makeNoise(seed);
    const t = texture(w, h, (X, Y) => { const v = n.fbm(X * .05, Y * .05, 4) * 255; return [v, v, v, 255]; });
    x.save(); x.globalCompositeOperation = 'source-atop'; x.globalAlpha = .16; x.globalCompositeOperation = 'overlay'; x.drawImage(t, 0, 0); x.restore();
    x.save(); x.globalCompositeOperation = 'destination-in'; iconFill(x, icon, cx, cy, size, '#fff'); x.restore();
  });
  bevel(f, { r: Math.max(3, size / 60), depth: 1.6, spec: .45, shin: 20, amb: .45 });
  // rim light on the bottom-right edges (element color), clipped to the figure
  const rim = layer(w, h, x => {
    x.drawImage(f, 0, 0); x.globalCompositeOperation = 'source-in'; x.fillStyle = palette.rim; x.fillRect(0, 0, w, h);
    x.globalCompositeOperation = 'destination-out'; x.drawImage(f, -3, -3);
  });
  const fx = f.getContext('2d');
  fx.save(); fx.globalCompositeOperation = 'source-atop'; fx.globalAlpha = .75; fx.filter = 'blur(.6px)'; fx.drawImage(rim, 0, 0); fx.restore();
  // ambient occlusion toward the bottom
  fx.save(); fx.globalCompositeOperation = 'source-atop'; fx.fillStyle = grad(fx, 0, cy - size * .5, 0, cy + size * .5, ['rgba(0,0,0,0)', 'rgba(0,0,0,0)', 'rgba(0,0,0,.28)']); fx.fillRect(0, 0, w, h); fx.restore();
  return f;
}
function drawPortrait(id, icon, suit) {
  const E = SUIT_EL[suit], rnd = mulberry(hashStr(id));
  const c = mk(PW, PH), x = c.getContext('2d');
  BG[E](x, PW, PH, rnd);
  // darken into the element tint so the light figure reads (matches the dark card art windows)
  x.save(); x.globalCompositeOperation = 'multiply'; x.fillStyle = grad(x, 0, 0, 0, PH, [mix(FIG[E].tint, '#ffffff', .55), mix(FIG[E].tint, '#ffffff', .35)]); x.fillRect(0, 0, PW, PH); x.restore();
  // depth haze behind the figure
  blob(x, PW / 2, PH * .5, 170, FIG[E].tint, .5);
  // contact shadow
  x.save(); x.filter = 'blur(8px)'; x.beginPath(); x.ellipse(PW / 2 + 8, PH - 26, 120, 16, 0, 0, TAU); x.fillStyle = 'rgba(0,0,0,.45)'; x.fill(); x.restore();
  const fig = figureLayer(PW, PH, icon, PW / 2, PH / 2 + 8, 250, FIG[E], hashStr(id) + 3);
  put(x, fig, { sh: .55, blur: 14, ox: 12, oy: 10 });
  // vignette
  x.fillStyle = rgrad(x, PW / 2, PH / 2, PW * .35, PW * .72, ['rgba(0,0,0,0)', 'rgba(0,0,0,.42)']); x.fillRect(0, 0, PW, PH);
  return c;
}
function drawMagicArt(key, icon, kind) {
  const S = 300, c = mk(S, S), x = c.getContext('2d'), rnd = mulberry(hashStr(key)), item = kind === 'item';
  x.save(); x.beginPath(); x.arc(S / 2, S / 2, S / 2, 0, TAU); x.clip();
  x.fillStyle = rgrad(x, S / 2, S / 2, 0, S / 2, item ? ['#5e8e9c', '#2a5260', '#0e2430', '#050e14'] : ['#c49ae6', '#7444a6', '#341656', '#140822'], S * .4, S * .32); x.fillRect(0, 0, S, S);
  // texture
  const tex = item ? texMetal(S, S, ['#000000', '#7f7f7f', '#ffffff'], hashStr(key), .4) : texParchment(S, S, ['#000000', '#808080', '#ffffff'], hashStr(key));
  x.save(); x.globalCompositeOperation = 'overlay'; x.globalAlpha = .35; x.drawImage(tex, 0, 0); x.restore();
  // engraved circles + runes / ticks
  x.lineWidth = 2; x.strokeStyle = item ? 'rgba(220,250,250,.22)' : 'rgba(236,210,255,.24)';
  for (const r of [128, 112]) { x.beginPath(); x.arc(S / 2, S / 2, r, 0, TAU); x.stroke(); }
  if (item) { for (let i = 0; i < 48; i++) { const a = i * TAU / 48; x.beginPath(); x.moveTo(S / 2 + Math.cos(a) * 114, S / 2 + Math.sin(a) * 114); x.lineTo(S / 2 + Math.cos(a) * (i % 4 ? 122 : 127), S / 2 + Math.sin(a) * (i % 4 ? 122 : 127)); x.stroke(); } }
  else { x.lineWidth = 2; runeRing(x, S / 2, S / 2, 120, 18, hashStr(key), 8); }
  // soft light behind the icon (painted, low alpha)
  blob(x, S / 2 - 10, S / 2 - 14, 110, item ? '#e6ffff' : '#f6e6ff', .22);
  x.save(); x.filter = 'blur(6px)'; x.beginPath(); x.ellipse(S / 2 + 6, S / 2 + 92, 80, 12, 0, 0, TAU); x.fillStyle = 'rgba(0,0,0,.4)'; x.fill(); x.restore();
  const fig = figureLayer(S, S, icon, S / 2, S / 2 + 2, 190, FIG[kind], hashStr(key) + 1);
  put(x, fig, { sh: .55, blur: 10, ox: 8, oy: 8 });
  x.fillStyle = rgrad(x, S / 2, S / 2, S * .28, S * .5, ['rgba(0,0,0,0)', 'rgba(0,0,0,.5)']); x.fillRect(0, 0, S, S);
  x.restore();
  return c;
}
for (const [id, ic, s] of HEROES) reg(`portraits/hero_${id}.png`, () => drawPortrait(id, ic, s));
for (const [k, ic, kind] of MAGICS) reg(`portraits/magic_${k}.png`, () => drawMagicArt(k, ic, kind));
