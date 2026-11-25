'use strict';
/* =========================================================
   UI kit: panels, buttons, ribbon, gems, emblems, icons, bars, slots, logo, app icon.
   NINE lists 9-patch margins [l,t,r,b] (written to ui_manifest.json).
   ========================================================= */
const NINE = {};
function nine(path, margins, fn) { NINE[path.replace('ui/', '')] = margins; reg(path, fn); }
const M = (w, h, pathFn, stops, o = {}) => matLayer(pathFn, stops, Object.assign({ w, h }, o));

/* ---------- panels (carved stone frame + inset + parchment / dark slate) ---------- */
function drawPanel(dark) {
  const S = dark ? 160 : 192, B = dark ? 24 : 30, c = mk(S, S), x = c.getContext('2d');
  const inT = dark ? texStone(S, S, ['#070a10', '#0e141e', '#151e2a', '#1c2836'], 65, 1.5) : texParchment(S, S, ['#9c7c4c', '#c8a872', '#e2cc98', '#f2e4bc'], 67);
  x.save(); x.beginPath(); rr(x, B - 6, B - 6, S - 2 * B + 12, S - 2 * B + 12, 10); x.fillStyle = pattern(x, inT); x.fill(); x.restore();
  innerShadow(x, P.rr(B, B, S - 2 * B, S - 2 * B, 8), { blur: dark ? 10 : 12, ox: 2, oy: 4, a: dark ? .9 : .5, col: dark ? '0,0,0' : '70,36,10' });
  const frame = x2 => { x2.beginPath(); rr(x2, 2, 2, S - 4, S - 4, 18); rr(x2, B - 6, B - 6, S - 2 * B + 12, S - 2 * B + 12, 10, true); };
  put(x, stoneLayer(S, S, frame, { chips: [2, 2, S - 4, S - 4], nChips: 10, seed: dark ? 5 : 6, r: 7 }), { sh: 0 });
  outline(x, P.rr(2, 2, S - 4, S - 4, 18), 2.5);
  // colored inset (gold on light panel, teal-gold on dark)
  put(x, M(S, S, x2 => { x2.beginPath(); rr(x2, B - 6, B - 6, S - 2 * B + 12, S - 2 * B + 12, 10); rr(x2, B, B, S - 2 * B, S - 2 * B, 7, true); }, dark ? INNER.ice : GOLD, { r: 2, depth: 1.8, spec: .7, hammer: .06 }), { sh: .5, blur: 3, oy: 1 });
  outline(x, P.rr(B, B, S - 2 * B, S - 2 * B, 7), 1.5, 'rgba(10,6,4,.7)');
  rivets(x, [[B / 2 + 1, B / 2 + 1], [S - B / 2 - 1, B / 2 + 1], [B / 2 + 1, S - B / 2 - 1], [S - B / 2 - 1, S - B / 2 - 1]], 4);
  return c;
}
nine('ui/panel.png', [48, 48, 48, 48], () => drawPanel(false));
nine('ui/panel_dark.png', [38, 38, 38, 38], () => drawPanel(true));

/* ---------- buttons: stone rim + colored inset face ---------- */
const BTN = {
  gold: { face: ['#6a4206', '#b47a10', '#e8b030', '#fad870'], text: '#3a2004' },
  red: { face: ['#480a06', '#8e1c10', '#c4361e', '#e46a44'], text: '#fff0d8' },
  blue: { face: ['#082448', '#14508a', '#2a7cc0', '#62aee6'], text: '#f0f8ff' },
  wood: { face: ['#2a160a', '#4e2c14', '#7a4a24', '#9a6436'], text: '#f6e6c8', wood: true },
};
function drawButton(kind, state) {
  const W = 220, H = 72, c = mk(W, H), x = c.getContext('2d'), b = BTN[kind];
  const press = state === 'pressed' ? 3 : 0, fy = 3 + press, fh = 60;
  x.save(); x.filter = 'blur(3px)'; x.beginPath(); rr(x, 6, 10, W - 12, H - 12, 18); x.fillStyle = 'rgba(0,0,0,.55)'; x.fill(); x.restore();
  // stone rim
  put(x, stoneLayer(W, H, P.rr(3, fy, W - 6, fh, 18), { rule: 'nonzero', r: 6, chips: [3, fy, W - 6, fh], nChips: 8, seed: 3 }), { sh: 0 });
  outline(x, P.rr(3, fy, W - 6, fh, 18), 2.5);
  // colored face
  const tex = b.wood ? texWood(W, H, b.face, 71, .5) : texMetal(W, H, b.face, hashStr(kind), .12, .1);
  const fp = P.rr(13, fy + 9, W - 26, fh - 18, 11);
  const face = shapeLayer(W, H, fp, x2 => pattern(x2, tex), {
    post: x2 => {
      x2.save(); x2.globalCompositeOperation = 'source-atop';
      x2.fillStyle = grad(x2, 0, fy + 9, 0, fy + fh - 9, press ? ['rgba(0,0,0,.3)', 'rgba(0,0,0,.08)', 'rgba(0,0,0,.12)'] : [[0, 'rgba(255,245,225,.35)'], [.5, 'rgba(255,255,255,.03)'], [1, 'rgba(0,0,0,.25)']]); x2.fillRect(0, 0, W, H);
      x2.restore();
    }, bevel: { r: 5, depth: 1.6, spec: .45, inset: !!press, round: 1.3 }
  });
  put(x, face, { sh: .6, blur: 4, oy: 2 });
  outline(x, fp, 2, 'rgba(6,8,14,.75)');
  if (press) innerShadow(x, fp, { blur: 7, ox: 0, oy: 3, a: .55 });
  if (state === 'hover') { x.save(); fp(x); x.clip(); x.fillStyle = 'rgba(255,244,220,.16)'; x.fillRect(0, 0, W, H); x.restore(); }
  if (state === 'disabled') { const d = mk(W, H), dx = d.getContext('2d'); dx.filter = 'grayscale(1) brightness(.6) contrast(.85)'; dx.drawImage(c, 0, 0); return d; }
  return c;
}
for (const k of Object.keys(BTN)) for (const s of ['normal', 'hover', 'pressed', 'disabled']) nine(`ui/btn_${k}_${s}.png`, [30, 28, 30, 28], () => drawButton(k, s));

/* ---------- title ribbon (horizontal 9-patch) ---------- */
function drawRibbon() {
  const W = 640, H = 120, c = mk(W, H), x = c.getContext('2d');
  const cols = ['#5a0e10', '#8e1e1a', '#b23a2a'];
  const cloth = texture(W, H, (X, Y) => { const v = .55 + ((X + Y) % 4 < 2 ? .02 : -.02) + Math.sin(Y / H * Math.PI) * .12; return ramp([mix(cols[0], '#000', .3), cols[0], cols[1], cols[2]])(v); });
  // tails (behind), fully inside the side margins
  const tails = shapeLayer(W, H, x2 => { x2.beginPath(); x2.moveTo(118, 34); x2.lineTo(8, 34); x2.lineTo(40, 70); x2.lineTo(8, 106); x2.lineTo(118, 106); x2.closePath(); x2.moveTo(W - 118, 34); x2.lineTo(W - 8, 34); x2.lineTo(W - 40, 70); x2.lineTo(W - 8, 106); x2.lineTo(W - 118, 106); x2.closePath(); }, x2 => pattern(x2, cloth), {
    post: x2 => { x2.save(); x2.globalCompositeOperation = 'source-atop'; x2.fillStyle = 'rgba(0,0,0,.4)'; x2.fillRect(0, 0, W, H); x2.restore(); }, bevel: { r: 4, depth: 1, spec: .1 }
  });
  put(x, tails, { sh: .5, blur: 6, oy: 3 });
  x.beginPath(); x.moveTo(70, 92); x.lineTo(84, 106); x.lineTo(84, 92); x.closePath(); x.moveTo(W - 70, 92); x.lineTo(W - 84, 106); x.lineTo(W - 84, 92); x.closePath(); x.fillStyle = '#2a0606'; x.fill();
  const face = shapeLayer(W, H, P.rr(70, 14, W - 140, 78, 6), x2 => pattern(x2, cloth), {
    post: x2 => {
      x2.save(); x2.globalCompositeOperation = 'source-atop';
      x2.fillStyle = grad(x2, 0, 14, 0, 92, [[0, 'rgba(255,230,210,.25)'], [.35, 'rgba(255,255,255,0)'], [1, 'rgba(0,0,0,.4)']]); x2.fillRect(0, 0, W, H);
      x2.setLineDash([7, 5]); x2.lineWidth = 2; x2.strokeStyle = 'rgba(255,225,170,.45)';
      x2.beginPath(); x2.moveTo(70, 22); x2.lineTo(W - 70, 22); x2.moveTo(70, 84); x2.lineTo(W - 70, 84); x2.stroke(); x2.restore();
    }, bevel: { r: 6, depth: 1, spec: .12 }
  });
  put(x, face, { sh: .6, blur: 8, oy: 4 });
  // gold edge bands
  put(x, M(W, H, x2 => { x2.beginPath(); x2.rect(70, 12, W - 140, 5); x2.rect(70, 89, W - 140, 5); }, GOLD, { r: 2, depth: 1.5, spec: .8 }), { sh: .5, blur: 3, oy: 1 });
  return c;
}
nine('ui/ribbon.png', [120, 0, 120, 0], drawRibbon);

/* ---------- gems, emblems, small icons ---------- */
function drawGem(E) {
  const S = 96, c = mk(S, S), x = c.getContext('2d');
  gemSet(x, E, 48, 48, 28, E === 'nature' ? GOLD : E === 'ice' ? SILVER : E === 'fire' ? EL.fire.metal : GOLD, { w: S, h: S });
  return c;
}
function drawEmblem(E) {
  const S = 128, c = mk(S, S), x = c.getContext('2d'), e = EL[E];
  const en = shapeLayer(S, S, P.circle(64, 64, 52), x2 => rgrad(x2, 64, 64, 0, 52, [e.ribbon[2], e.ribbon[0], mix(e.ribbon[0], '#000', .55)], 50, 46), { bevel: { r: 6, inset: true, depth: 1, spec: .2 } });
  put(x, en, { sh: 0 });
  put(x, M(S, S, P.ring(64, 64, 50, 62), E === 'nature' ? BRONZE : e.metal, { r: 5, depth: 1.8, spec: .7 }), { sh: .6, blur: 5, oy: 3 });
  const sg = layer(S, S, x2 => { x2.fillStyle = grad(x2, 30, 30, 98, 98, [mix(e.accent, '#ffffff', .4), e.accent, mix(e.accent, '#000', .3)]); sigil(x2, E, 64, 64, 34); });
  put(x, bevel(sg, { r: 3, depth: 1.8, spec: .6 }), { sh: .7, blur: 4, oy: 2 });
  return c;
}
function icon64(fn) { const c = mk(64, 64); fn(c.getContext('2d'), c); return c; }
const ICON64 = {
  coin: x => {
    put(x, M(64, 64, P.circle(32, 32, 27), GOLD, { r: 5, depth: 1.8, spec: .7, hammer: .05, round: 1.4 }), { sh: .6, blur: 4, oy: 2 });
    groove(x, x2 => { x2.beginPath(); x2.arc(32, 32, 21, 0, TAU); }, 1.4, .5);
    const st = layer(64, 64, x2 => { x2.fillStyle = '#d8a838'; P.star(32, 32, 12, 5.5)(x2); x2.fill(); });
    put(x, bevel(st, { r: 2, depth: 1.6, spec: .6 }), { sh: .5, blur: 2, oy: 1 });
  },
  heart: x => put(x, shapeLayer(64, 64, x2 => { x2.beginPath(); heartPath(x2, 32, 33, 26); }, x2 => rgrad(x2, 32, 33, 2, 34, ['#ff9088', '#d42434', '#5e0610'], 22, 20), { bevel: { r: 7, depth: 1.6, spec: .7, round: 1.6 } }), { sh: .6, blur: 4, oy: 2 }),
  sword: x => put(x, M(64, 64, x2 => { x2.save(); x2.translate(32, 32); x2.rotate(-Math.PI / 4); x2.scale(.5, .62); swordShape(x2, 160); x2.restore(); }, SILVER, { r: 2, depth: 1.8, spec: .8 }), { sh: .6, blur: 3, oy: 2 }),
  mana: x => {
    const d = layer(64, 64, x2 => { x2.beginPath(); x2.moveTo(32, 5); x2.bezierCurveTo(40, 20, 52, 30, 52, 42); x2.bezierCurveTo(52, 54, 42, 60, 32, 60); x2.bezierCurveTo(22, 60, 12, 54, 12, 42); x2.bezierCurveTo(12, 30, 24, 20, 32, 5); x2.closePath(); x2.fillStyle = rgrad(x2, 32, 40, 2, 30, ['#a8ccff', '#3a74dc', '#0c2a7a'], 24, 32); x2.fill(); x2.beginPath(); x2.ellipse(24, 40, 4, 8, .3, 0, TAU); x2.fillStyle = 'rgba(255,255,255,.55)'; x2.fill(); });
    put(x, bevel(d, { r: 5, depth: 1.4, spec: .7, round: 1.5 }), { sh: .6, blur: 4, oy: 2 });
  },
  star: x => put(x, M(64, 64, P.star(32, 33, 28, 12), GOLD, { r: 5, depth: 2, spec: .8, round: 1.4, hammer: .05 }), { sh: .6, blur: 4, oy: 2 }),
  xp: x => {
    put(x, shapeLayer(64, 64, P.circle(32, 32, 27), x2 => rgrad(x2, 32, 32, 0, 27, ['#a07ae0', '#5a2ea0', '#24104a'], 24, 22), { bevel: { r: 5, depth: 1.4, spec: .4, round: 1.4 } }), { sh: .6, blur: 4, oy: 2 });
    put(x, M(64, 64, P.ring(32, 32, 24, 29), GOLD, { r: 2, depth: 1.6 }), { sh: .4, blur: 2, oy: 1 });
    put(x, M(64, 64, x2 => { x2.beginPath(); for (const oy of [0, 12]) { x2.moveTo(18, 34 + oy - 4); x2.lineTo(32, 20 + oy - 4); x2.lineTo(46, 34 + oy - 4); x2.lineTo(46, 41 + oy - 4); x2.lineTo(32, 27 + oy - 4); x2.lineTo(18, 41 + oy - 4); x2.closePath(); } }, GOLD, { r: 2, depth: 1.6, spec: .8 }), { sh: .6, blur: 2, oy: 1 });
  },
};
// standalone medallions (128px) matching the card sockets
function drawMedal(kind) {
  const S = 128, c = mk(S, S), x = c.getContext('2d');
  const en = { atk: ['#6e0d14', '#c2362e'], hp: ['#0f4a22', '#3f9a4a'], mana: ['#0e2a66', '#3a6fd0'] }[kind];
  if (kind === 'cost') {
    put(x, M(S, S, P.ring(64, 64, 44, 56), BRONZE, { r: 4, depth: 1.8, spec: .7 }), { sh: .6, blur: 5, oy: 3 });
    x.drawImage(M(S, S, P.circle(64, 64, 45), GOLD, { r: 6, depth: 1.5, spec: .5, round: 1.6, hammer: .05, sheenA: .35 }), 0, 0);
    groove(x, x2 => { x2.beginPath(); x2.arc(64, 64, 38, 0, TAU); }, 1.4, .45);
    return c;
  }
  if (kind === 'atk') put(x, M(S, S, xx => { xx.save(); xx.translate(64, 64); xx.rotate(Math.PI / 4); xx.scale(.72, .72); swordShape(xx, 168); xx.restore(); }, SILVER, { r: 3, depth: 1.6, spec: .8 }), { sh: .7, blur: 5, oy: 3 });
  const disc = shapeLayer(S, S, P.circle(64, 64, 44), xx => rgrad(xx, 64, 64, 0, 44, [[0, en[1]], [.75, en[0]], [1, mix(en[0], '#000', .45)]], 52, 50), { bevel: { r: 7, depth: 1.2, inset: true, spec: .2 } });
  put(x, disc, { sh: 0 });
  groove(x, x2 => { x2.beginPath(); x2.arc(64, 64, 38, 0, TAU); }, 1.5, .35);
  put(x, M(S, S, P.ring(64, 64, 43, 54), GOLD, { r: 5, depth: 1.8, spec: .7 }), { sh: .65, blur: 6, oy: 3 });
  if (kind === 'hp') put(x, shapeLayer(S, S, xx => { xx.beginPath(); heartPath(xx, 64, 11, 13); }, xx => rgrad(xx, 60, 6, 2, 18, ['#ff8a80', '#c4202e', '#5a0610']), { bevel: { r: 4, depth: 1.8, spec: .7, round: 1.5 } }), { sh: .7, blur: 4, oy: 2 });
  if (kind === 'mana') { const mc = layer(S, S, xx => gemDiamond(xx, 64, 12, 10, 13, ['#0b2a7a', '#3c7ce0', '#bcd8ff'])); put(x, bevel(mc, { r: 2, depth: 1.2, spec: .6 }), { sh: .7, blur: 4, oy: 2 }); }
  return c;
}

/* ---------- bars ---------- */
function drawBarFrame() {
  const W = 256, H = 40, c = mk(W, H), x = c.getContext('2d');
  x.beginPath(); rr(x, 5, 5, W - 10, H - 10, 14); x.fillStyle = 'rgba(8,6,6,.85)'; x.fill();
  innerShadow(x, P.rr(5, 5, W - 10, H - 10, 14), { blur: 6, ox: 0, oy: 3, a: .9 });
  put(x, M(W, H, x2 => { x2.beginPath(); rr(x2, 1, 1, W - 2, H - 2, 19); rr(x2, 6, 6, W - 12, H - 12, 13, true); }, GOLD, { r: 3, depth: 1.6, spec: .7 }), { sh: .5, blur: 3, oy: 1 });
  return c;
}
function drawBarFill(col) {
  const W = 128, H = 28, c = mk(W, H), x = c.getContext('2d');
  const f = shapeLayer(W, H, P.rr(0, 0, W, H, 13), x2 => grad(x2, 0, 0, 0, H, [[0, mix(col, '#ffffff', .35)], [.35, col], [1, mix(col, '#000', .45)]]), {
    post: x2 => { x2.save(); x2.globalCompositeOperation = 'source-atop'; x2.fillStyle = 'rgba(255,255,255,.22)'; x2.beginPath(); rr(x2, 6, 3, W - 12, 7, 3.5); x2.fill(); x2.restore(); }, bevel: { r: 4, depth: 1.2, spec: .3, round: 1.3 }
  });
  x.drawImage(f, 0, 0); return c;
}

/* ---------- board slots, sell zone, tooltip, chip ---------- */
function drawSlot(bench) {
  const W = 256, H = 358, c = mk(W, H), x = c.getContext('2d');
  const p = P.rr(10, 10, W - 20, H - 20, 22);
  x.save(); p(x); x.fillStyle = bench ? 'rgba(30,16,8,.30)' : 'rgba(0,0,0,.20)'; x.fill(); x.restore();
  innerShadow(x, p, { blur: 14, ox: 2, oy: 5, a: .5 });
  // carved double groove
  groove(x, P.rr(10, 10, W - 20, H - 20, 22), 3, .6);
  x.save(); if (bench) x.setLineDash([14, 9]); groove(x, P.rr(22, 22, W - 44, H - 44, 14), 1.8, .45); x.restore();
  // corner diamonds + center sigil ring
  const orn = layer(W, H, x2 => {
    x2.fillStyle = bench ? '#a07040' : '#c8a050';
    for (const [px, py] of [[22, 22], [W - 22, 22], [22, H - 22], [W - 22, H - 22]]) { x2.beginPath(); x2.moveTo(px, py - 9); x2.lineTo(px + 9, py); x2.lineTo(px, py + 9); x2.lineTo(px - 9, py); x2.closePath(); x2.fill(); }
    if (!bench) { x2.lineWidth = 3; x2.strokeStyle = x2.fillStyle; x2.beginPath(); x2.arc(W / 2, H / 2, 36, 0, TAU); x2.stroke(); for (let i = 0; i < 4; i++) { const a = i * Math.PI / 2 - Math.PI / 4; x2.beginPath(); x2.moveTo(W / 2 + Math.cos(a) * 42, H / 2 + Math.sin(a) * 42); x2.lineTo(W / 2 + Math.cos(a) * 54, H / 2 + Math.sin(a) * 54); x2.stroke(); } }
    else { x2.lineWidth = 3; x2.strokeStyle = x2.fillStyle; x2.beginPath(); x2.moveTo(W / 2 - 30, H / 2); x2.lineTo(W / 2 + 30, H / 2); x2.moveTo(W / 2, H / 2 - 30); x2.lineTo(W / 2, H / 2 + 30); x2.stroke(); }
  });
  bevel(orn, { r: 2, depth: 1.6, spec: .5 });
  put(x, orn, { sh: .5, blur: 3, oy: 2, alpha: .55 });
  return c;
}
function drawSell() {
  const S = 256, c = mk(S, S), x = c.getContext('2d');
  put(x, shapeLayer(S, S, P.circle(128, 128, 108), xx => rgrad(xx, 128, 128, 0, 108, ['#5a2a14', '#3a180c', '#1c0a06'], 100, 92), { bevel: { r: 10, inset: true, depth: 1, spec: .1 } }), { sh: .6, blur: 10, oy: 5 });
  put(x, M(S, S, P.ring(128, 128, 104, 120), GOLD, { r: 6, depth: 1.8, spec: .7 }), { sh: .6, blur: 6, oy: 3 });
  // coin stack
  for (let i = 0; i < 4; i++) {
    const cy = 168 - i * 16, cx = 112 + (i % 2) * 4;
    put(x, M(S, S, xx => { xx.beginPath(); xx.ellipse(cx, cy, 46, 16, 0, 0, TAU); xx.rect(cx - 46, cy - 8, 92, 8); xx.ellipse(cx, cy - 8, 46, 16, 0, 0, TAU); }, GOLD, { r: 4, depth: 1.6, spec: .7, hammer: .05 }), { sh: .5, blur: 4, oy: 3 });
  }
  // single coin leaning
  put(x, M(S, S, P.circle(170, 112, 34), GOLD, { r: 5, depth: 1.8, spec: .7, round: 1.4, hammer: .05 }), { sh: .6, blur: 5, oy: 3 });
  const st = layer(S, S, x2 => { x2.fillStyle = '#c89838'; P.star(170, 112, 16, 7)(x2); x2.fill(); });
  put(x, bevel(st, { r: 2, depth: 1.6, spec: .6 }), { sh: .5, blur: 2, oy: 1 });
  return c;
}
function drawTooltip() {
  const S = 96, c = mk(S, S), x = c.getContext('2d');
  const lt = texStone(S, S, ['#080b10', '#10161f', '#18212c', '#1f2a38'], 81, 1.5);
  x.beginPath(); rr(x, 3, 3, S - 6, S - 6, 12); x.fillStyle = pattern(x, lt); x.fill();
  innerShadow(x, P.rr(3, 3, S - 6, S - 6, 12), { blur: 8, ox: 0, oy: 3, a: .6 });
  put(x, M(S, S, x2 => { x2.beginPath(); rr(x2, 1, 1, S - 2, S - 2, 14); rr(x2, 5, 5, S - 10, S - 10, 11, true); }, GOLD, { r: 2, depth: 1.5, spec: .7 }), { sh: 0 });
  put(x, M(S, S, x2 => { for (const [px, py] of [[12, 12], [S - 12, 12], [12, S - 12], [S - 12, S - 12]]) { x2.moveTo(px, py - 5); x2.lineTo(px + 5, py); x2.lineTo(px, py + 5); x2.lineTo(px - 5, py); x2.closePath(); } }, GOLD, { r: 2, depth: 1.6 }), { sh: .4, blur: 2, oy: 1 });
  return c;
}
function drawChip() {
  const W = 96, H = 40, c = mk(W, H), x = c.getContext('2d');
  put(x, shapeLayer(W, H, P.rr(3, 3, W - 6, H - 6, 17), x2 => grad(x2, 0, 3, 0, H - 3, ['#3a4a60', '#1c2636', '#0e141e']), { bevel: { r: 4, depth: 1.2, spec: .2 } }), { sh: 0 });
  put(x, M(W, H, x2 => { x2.beginPath(); rr(x2, 1, 1, W - 2, H - 2, 19); rr(x2, 4, 4, W - 8, H - 8, 16, true); }, BRONZE, { r: 2, depth: 1.5, spec: .6 }), { sh: 0 });
  return c;
}

/* ---------- title logo ---------- */
function drawLogo() {
  const W = 1200, H = 360, c = mk(W, H), x = c.getContext('2d');
  // stone plaque behind the lettering
  const stone = slateTex(W, H);
  const plaque = x2 => { x2.beginPath(); x2.moveTo(150, 150); x2.quadraticCurveTo(160, 60, 300, 52); x2.lineTo(900, 52); x2.quadraticCurveTo(1040, 60, 1050, 150); x2.lineTo(1100, 196); x2.lineTo(1050, 242); x2.quadraticCurveTo(1040, 320, 900, 324); x2.lineTo(300, 324); x2.quadraticCurveTo(160, 320, 150, 242); x2.lineTo(100, 196); x2.closePath(); };
  put(x, shapeLayer(W, H, plaque, x2 => pattern(x2, stone), { bevel: { r: 14, depth: 1.4, spec: .15 } }), { sh: .6, blur: 18, oy: 8 });
  put(x, M(W, H, x2 => { plaque(x2); x2.save(); x2.translate(600, 188); x2.scale(.975, .94); x2.translate(-600, -188); x2.beginPath(); x2.restore(); }, GOLD, { r: 3 }), { sh: 0, alpha: 0 });
  // gold border on the plaque (stroke)
  const border = layer(W, H, x2 => { plaque(x2); x2.lineWidth = 10; x2.strokeStyle = '#fff'; x2.lineJoin = 'round'; x2.stroke(); });
  const gb = layer(W, H, x2 => { x2.drawImage(border, 0, 0); x2.globalCompositeOperation = 'source-in'; x2.fillStyle = pattern(x2, metalTex(GOLD, W, H, .1)); x2.fillRect(0, 0, W, H); });
  put(x, bevel(gb, { r: 3, depth: 1.8, spec: .8 }), { sh: .5, blur: 4, oy: 2 });
  // element sigils at the pointed ends
  [['ice', 160, 196], ['fire', 1040, 196]].forEach(() => {});
  const sigs = layer(W, H, x2 => { x2.fillStyle = '#e8c870'; sigil(x2, 'ice', 205, 120, 26); sigil(x2, 'fire', 995, 120, 26); sigil(x2, 'nature', 205, 262, 26); sigil(x2, 'light', 995, 262, 26); });
  put(x, bevel(sigs, { r: 3, depth: 1.8, spec: .6 }), { sh: .6, blur: 4, oy: 2 });
  // lettering
  const txt = (x2, fill) => {
    x2.textAlign = 'center'; x2.textBaseline = 'alphabetic'; x2.fillStyle = fill;
    x2.font = '700 104px Philosopher'; x2.fillText('КОЗЫРНАЯ', 600, 168);
    x2.font = '700 132px Philosopher'; x2.fillText('АРЕНА', 600, 296);
  };
  // dark outline
  const outline = layer(W, H, x2 => { x2.lineJoin = 'round'; x2.textAlign = 'center'; x2.strokeStyle = '#1a0e06'; x2.lineWidth = 16; x2.font = '700 104px Philosopher'; x2.strokeText('КОЗЫРНАЯ', 600, 168); x2.font = '700 132px Philosopher'; x2.strokeText('АРЕНА', 600, 296); });
  put(x, outline, { sh: .7, blur: 12, oy: 6 });
  const letters = layer(W, H, x2 => txt(x2, grad(x2, 0, 70, 0, 300, [[0, '#fff6cc'], [.25, '#f2cc62'], [.42, '#b07818'], [.47, '#fff0b0'], [.6, '#f0c050'], [.85, '#b07818'], [1, '#7a4c0c']])));
  put(x, bevel(letters, { r: 4, depth: 2, spec: .9, shin: 26 }), { sh: 0 });
  // divider between the lines with a gem
  put(x, M(W, H, x2 => { x2.beginPath(); x2.moveTo(330, 186); x2.lineTo(560, 180); x2.lineTo(560, 192); x2.closePath(); x2.moveTo(870, 186); x2.lineTo(640, 180); x2.lineTo(640, 192); x2.closePath(); }, GOLD, { r: 2, depth: 1.6 }), { sh: .5, blur: 3, oy: 2 });
  gemSet(x, 'fire', 600, 186, 11, GOLD, { w: W, h: H });
  return c;
}

/* ---------- app icon ---------- */
function drawAppIcon() {
  const S = 512, c = mk(S, S), x = c.getContext('2d');
  const felt = texStone(S, S, ['#0a1018', '#142030', '#1e3048', '#2a4260'], 95, 1.2);
  put(x, shapeLayer(S, S, P.rr(16, 16, S - 32, S - 32, 96), x2 => pattern(x2, felt), { post: x2 => { x2.save(); x2.globalCompositeOperation = 'source-atop'; x2.fillStyle = rgrad(x2, 256, 230, 40, 340, ['rgba(255,255,230,.18)', 'rgba(0,0,0,.45)']); x2.fillRect(0, 0, S, S); x2.restore(); }, bevel: { r: 8 } }), { sh: 0 });
  put(x, M(S, S, x2 => { x2.beginPath(); rr(x2, 16, 16, S - 32, S - 32, 96); rr(x2, 36, 36, S - 72, S - 72, 78, true); }, GOLD, { r: 6, depth: 1.8, spec: .7 }), { sh: .6, blur: 6, oy: 3 });
  // two fanned cards
  const card = (ang, E) => {
    const L = layer(S, S, x2 => { x2.translate(256, 300); x2.rotate(ang); x2.translate(-256, -300); x2.beginPath(); rr(x2, 166, 120, 180, 252, 18); x2.fillStyle = '#fff'; x2.fill(); });
    const m = layer(S, S, x2 => { x2.drawImage(L, 0, 0); x2.globalCompositeOperation = 'source-in'; x2.fillStyle = pattern(x2, metalTex(E === 'fire' ? EL.fire.metal : SILVER, S, S, .1)); x2.fillRect(0, 0, S, S); });
    bevel(m, { r: 6, depth: 1.6, spec: .6 });
    const inner = layer(S, S, x2 => { x2.translate(256, 300); x2.rotate(ang); x2.translate(-256, -300); x2.beginPath(); rr(x2, 180, 134, 152, 224, 10); x2.fillStyle = grad(x2, 0, 134, 0, 358, E === 'fire' ? ['#8a2018', '#3a0a0a'] : ['#2a5a9e', '#0c1c3a']); x2.fill(); const sg = layer(S, S, x3 => { x3.translate(256, 300); x3.rotate(ang); x3.translate(-256, -300); x3.fillStyle = E === 'fire' ? '#f2b070' : '#cfe6ff'; sigil(x3, E, 256, 246, 50); }); x2.setTransform(1, 0, 0, 1, 0, 0); x2.drawImage(sg, 0, 0); });
    bevel(inner, { r: 3, depth: 1.4, spec: .4 });
    const mx = m.getContext('2d'); mx.drawImage(inner, 0, 0);
    put(x, m, { sh: .6, blur: 12, ox: 4, oy: 8 });
  };
  card(-.26, 'ice'); card(.22, 'fire');
  // big letter K on a shield at the bottom
  const shield = x2 => { x2.beginPath(); x2.moveTo(186, 330); x2.lineTo(326, 330); x2.lineTo(326, 392); x2.quadraticCurveTo(320, 440, 256, 468); x2.quadraticCurveTo(192, 440, 186, 392); x2.closePath(); };
  put(x, M(S, S, shield, GOLD, { r: 7, depth: 1.8, spec: .7 }), { sh: .7, blur: 10, oy: 5 });
  const inner = shapeLayer(S, S, x2 => { x2.beginPath(); x2.moveTo(196, 340); x2.lineTo(316, 340); x2.lineTo(316, 390); x2.quadraticCurveTo(310, 432, 256, 456); x2.quadraticCurveTo(202, 432, 196, 390); x2.closePath(); }, x2 => grad(x2, 0, 340, 0, 456, ['#7a1414', '#3a0608']), { bevel: { r: 5, inset: true, depth: 1, spec: .2 } });
  x.drawImage(inner, 0, 0);
  const k = layer(S, S, x2 => { x2.font = '700 112px Philosopher'; x2.textAlign = 'center'; x2.fillStyle = '#f0cc70'; x2.fillText('К', 256, 434); });
  put(x, bevel(k, { r: 3, depth: 2, spec: .8 }), { sh: .7, blur: 4, oy: 3 });
  return c;
}

/* ---------- registrations ---------- */
for (const E of ['ice', 'fire', 'light', 'nature']) { reg(`ui/gem_${E}.png`, () => drawGem(E)); reg(`ui/element_${E}.png`, () => drawEmblem(E)); }
for (const k of Object.keys(ICON64)) reg(`ui/${k}.png`, () => icon64(ICON64[k]));
for (const k of ['atk', 'hp', 'mana', 'cost']) reg(`ui/medal_${k}.png`, () => drawMedal(k));
nine('ui/bar_frame.png', [22, 18, 22, 18], drawBarFrame);
nine('ui/bar_fill_hp.png', [13, 13, 13, 13], () => drawBarFill('#3c9a3a'));
nine('ui/bar_fill_foe.png', [13, 13, 13, 13], () => drawBarFill('#b8282a'));
nine('ui/bar_fill_mana.png', [13, 13, 13, 13], () => drawBarFill('#2f68c8'));
nine('ui/bar_fill_xp.png', [13, 13, 13, 13], () => drawBarFill('#7a48c0'));
nine('ui/slot.png', [40, 40, 40, 40], () => drawSlot(false));
nine('ui/slot_bench.png', [40, 40, 40, 40], () => drawSlot(true));
reg('ui/sell.png', drawSell);
nine('ui/tooltip.png', [22, 22, 22, 22], drawTooltip);
nine('ui/chip.png', [20, 18, 20, 18], drawChip);
reg('ui/title_logo.png', drawLogo);
reg('ui/icon.png', drawAppIcon);
reg('icon.png', drawAppIcon);
reg('ui/ui_manifest.json', () => ({ toDataURL: () => 'data:application/json;base64,' + btoa(JSON.stringify(Object.entries(NINE).map(([file, margins]) => ({ file, margins })), null, 1)) }));
