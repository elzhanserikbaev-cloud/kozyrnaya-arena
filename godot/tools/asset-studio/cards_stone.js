'use strict';
/* =========================================================
   Card frames, "carved stone" style (512x716):
   slate-blue stone outer frame + element-colored inner frame, art window,
   colored banner with an octagonal gem badge, parchment text area,
   top-left corner medallion with element flames, stat medallions.
   All text areas are plain; see CARD_LAYOUT (used by the Godot card scene).
   ========================================================= */
const CARD_LAYOUT = {
  window: [50, 58, 412, 298, 12],      // transparent portrait window (x,y,w,h,r); portraits 432x312 scale to 412 wide
  corner: [66, 74, 38, 29],            // corner medallion center x,y, radius, text radius (rank+suit / magic cost)
  gem: [256, 350, 30, 21],             // banner gem badge center, radius, text radius (hero cost)
  name: [72, 362, 368, 46],            // title text rect on the banner
  parchment: [62, 426, 388, 222],      // parchment plate
  text: [80, 436, 352, 172],           // ability / description text rect (dark brown text)
  atk: [112, 662, 34, 25], mana: [256, 668, 30, 21], hp: [400, 662, 34, 25], // center, radius, number radius
  stars: { y: 33, xs: { 2: [236, 276], 3: [216, 256, 296] }, r: 16 },
  magicArt: [256, 207, 148],           // round hole for magic_<key>.png (300x300) in frame_item/frame_spell
};
const INNER = {
  nature: ['#123c08', '#2c7a16', '#58b42c', '#a6e46a', '#e4ffc0'],
  ice: ['#063a48', '#11819a', '#30c0d6', '#8eecf6', '#e0feff'],
  light: ['#5e3404', '#b87408', '#eeb024', '#fcdc6c', '#fff6c8'],
  fire: ['#4e0a06', '#a8240e', '#e45224', '#f8985a', '#ffd8b0'],
  item: ['#1c2a36', '#3e5468', '#6e8aa2', '#aec4d6', '#eef6fc'],
  spell: ['#2a0c40', '#5a2484', '#8c48c0', '#c492ec', '#f2e0ff'],
};
const SLATE = ['#121822', '#222e40', '#34465e', '#4c627e', '#6c84a0'];
function slateTex(w = CW, h = CH) { return cached(`slate|${w}|${h}`, () => texStone(w, h, SLATE, 101, 1.3)); }
function outline(ctx, pathFn, w = 2.5, col = 'rgba(6,8,14,.85)') { ctx.save(); pathFn(ctx); ctx.lineWidth = w; ctx.lineJoin = 'round'; ctx.strokeStyle = col; ctx.stroke(); ctx.restore(); }
// chipped stone ring layer
function stoneLayer(w, h, pathFn, o = {}) {
  const rnd = mulberry(o.seed || 7);
  const cv = layer(w, h, x => {
    pathFn(x); x.fillStyle = pattern(x, slateTex(w, h)); x.fill(o.rule || 'evenodd');
    // painted top-left light / bottom-right shade
    x.save(); x.globalCompositeOperation = 'source-atop';
    x.fillStyle = grad(x, 0, 0, w, h, [[0, 'rgba(190,215,255,.22)'], [.5, 'rgba(0,0,0,0)'], [1, 'rgba(0,0,10,.3)']]); x.fillRect(0, 0, w, h); x.restore();
    // chips along the outer edge
    if (o.chips) {
      const [X, Y, W, H] = o.chips; x.save(); x.globalCompositeOperation = 'destination-out';
      for (let i = 0; i < (o.nChips || 22); i++) {
        const side = i % 4, t = .12 + rnd() * .76, d = 3 + rnd() * 5, l = 6 + rnd() * 12;
        let px, py, ax, ay; if (side === 0) { px = X + W * t; py = Y; ax = 1; ay = 0; } else if (side === 1) { px = X + W; py = Y + H * t; ax = 0; ay = 1; } else if (side === 2) { px = X + W * t; py = Y + H; ax = 1; ay = 0; } else { px = X; py = Y + H * t; ax = 0; ay = 1; }
        const nx = side === 0 ? 0 : side === 1 ? -1 : side === 2 ? 0 : 1, ny = side === 0 ? 1 : side === 2 ? -1 : 0;
        x.beginPath(); x.moveTo(px - ax * l / 2 - nx * 2, py - ay * l / 2 - ny * 2); x.lineTo(px + nx * d + ax * (rnd() - .5) * 4, py + ny * d + ay * (rnd() - .5) * 4); x.lineTo(px + ax * l / 2 - nx * 2, py + ay * l / 2 - ny * 2); x.closePath(); x.fill();
      }
      x.restore();
    }
  });
  bevel(cv, { r: o.r ?? 9, depth: o.depth ?? 1.9, amb: .42, spec: .18, shin: 14, round: 1.3 });
  // cracks
  if (o.cracks) {
    const x = cv.getContext('2d');
    x.save(); x.globalCompositeOperation = 'source-atop';
    for (let i = 0; i < o.cracks; i++) {
      const [X, Y, W, H] = o.chips; const side = rnd() * 4 | 0; let px = X + rnd() * W, py = Y + rnd() * H;
      if (side === 0) py = Y + 2; else if (side === 1) px = X + W - 2; else if (side === 2) py = Y + H - 2; else px = X + 2;
      const pts = [[px, py]]; let a = side === 0 ? Math.PI / 2 : side === 1 ? Math.PI : side === 2 ? -Math.PI / 2 : 0;
      for (let k = 0; k < 4; k++) { a += (rnd() - .5) * 1.2; px += Math.cos(a) * (4 + rnd() * 6); py += Math.sin(a) * (4 + rnd() * 6); pts.push([px, py]); }
      groove(x, xx => { xx.beginPath(); pts.forEach((p, j) => j ? xx.lineTo(p[0], p[1]) : xx.moveTo(p[0], p[1])); }, 1.4, .7);
    }
    x.restore();
  }
  return cv;
}
function rivets(ctx, pts, r, stops = SILVER) {
  put(ctx, matLayer(xx => { for (const [px, py] of pts) { xx.moveTo(px + r, py); xx.arc(px, py, r, 0, TAU); } }, stops, { r: Math.max(2, r * .6), depth: 2.2, round: 1.6, spec: .6, hammer: .05 }), { sh: .7, blur: 3, ox: 1, oy: 2 });
}
function octPath(cx, cy, r) { return (x, c) => { if (!c) x.beginPath(); for (let i = 0; i < 8; i++) { const a = Math.PI / 8 + i * Math.PI / 4; i ? x.lineTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r) : x.moveTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r); } x.closePath(); }; }
function gemBadge(ctx, cx, cy, r, cols) {
  put(ctx, matLayer(octPath(cx, cy, r + 7), [mix(cols[0], '#000', .3), cols[0], cols[1], cols[2], cols[3]], { r: 4, depth: 2, spec: .5, hammer: .05 }), { sh: .7, blur: 8, oy: 4 });
  outline(ctx, octPath(cx, cy, r + 7), 2.5);
  const inner = shapeLayer(CW, CH, octPath(cx, cy, r), x => rgrad(x, cx, cy, 2, r * 1.2, [cols[3], cols[2], cols[1]], cx - r * .3, cy - r * .4), { bevel: { r: 6, depth: 1.4, spec: .55, round: 1.4 } });
  put(ctx, inner, { sh: 0 });
  // facet lines from the corners (subtle)
  ctx.save(); octPath(cx, cy, r)(ctx); ctx.clip(); ctx.strokeStyle = 'rgba(255,255,255,.12)'; ctx.lineWidth = 1.2;
  for (let i = 0; i < 8; i++) { const a = Math.PI / 8 + i * Math.PI / 4; ctx.beginPath(); ctx.moveTo(cx + Math.cos(a) * r, cy + Math.sin(a) * r); ctx.lineTo(cx + Math.cos(a) * r * .72, cy + Math.sin(a) * r * .72); ctx.stroke(); }
  ctx.restore();
  outline(ctx, octPath(cx, cy, r), 1.5, 'rgba(6,8,14,.55)');
}
function stoneMedal(ctx, cx, cy, R, enamel) {
  put(ctx, stoneLayer(CW, CH, P.circle(cx, cy, R + 8), { r: 5, depth: 2, rule: 'nonzero' }), { sh: .75, blur: 8, oy: 4 });
  outline(ctx, P.circle(cx, cy, R + 8), 2.5);
  const disc = shapeLayer(CW, CH, P.circle(cx, cy, R), x => rgrad(x, cx, cy, 0, R, [[0, enamel[1]], [.7, enamel[0]], [1, mix(enamel[0], '#000', .4)]], cx - R * .3, cy - R * .35), {
    post: x => { x.save(); x.globalCompositeOperation = 'source-atop'; x.beginPath(); x.ellipse(cx - R * .2, cy - R * .5, R * .55, R * .22, -.3, 0, TAU); x.fillStyle = 'rgba(255,255,255,.16)'; x.fill(); x.restore(); },
    bevel: { r: 6, depth: 1.5, spec: .35, round: 1.4 }
  });
  put(ctx, disc, { sh: 0 });
  outline(ctx, P.circle(cx, cy, R), 1.6, 'rgba(6,8,14,.6)');
}
function parchmentPlate(ctx, area, seed) {
  const [px, py, pw, ph] = area;
  const t = cached('parch|' + area, () => texParchment(CW, CH, ['#9c7c4c', '#c8a872', '#e2cc98', '#f2e4bc'], seed));
  const path = P.rr(px, py, pw, ph, 14);
  const pl = shapeLayer(CW, CH, path, x => pattern(x, t), {
    post: x => { x.save(); x.globalCompositeOperation = 'source-atop'; x.fillStyle = rgrad(x, px + pw / 2, py + ph / 2, Math.min(pw, ph) * .35, Math.max(pw, ph) * .62, ['rgba(0,0,0,0)', 'rgba(90,50,14,.38)']); x.fillRect(0, 0, CW, CH); x.restore(); },
    bevel: { r: 5, depth: 1, spec: .08, round: 1.3 }
  });
  put(ctx, pl, { sh: .65, blur: 8, oy: 3 });
  outline(ctx, path, 2.5, 'rgba(40,22,8,.9)');
}
// element flames bursting from the top-left corner behind the medallion
function cornerFlames(ctx, cx, cy, cols) {
  const L = layer(CW, CH, x => {
    const fc = [cols[0], cols[1], cols[2], cols[4]];
    flameTongue(x, cx + 14, cy - 6, -Math.PI * .56, 72, 46, fc);
    flameTongue(x, cx - 8, cy + 14, -Math.PI * .95, 66, 46, fc);
    flameTongue(x, cx - 2, cy - 2, -Math.PI * .75, 100, 76, fc);
  });
  bevel(L, { r: 4, depth: 1.4, spec: .35, amb: .55 });
  put(ctx, L, { sh: .55, blur: 6, oy: 3 });
}
function cornerMedal(ctx, cols, seed) {
  const [cx, cy, R] = CARD_LAYOUT.corner;
  cornerFlames(ctx, cx, cy, cols);
  put(ctx, stoneLayer(CW, CH, P.circle(cx, cy, R + 7), { r: 5, depth: 2, rule: 'nonzero', seed }), { sh: .75, blur: 8, oy: 4 });
  outline(ctx, P.circle(cx, cy, R + 7), 2.5);
  put(ctx, matLayer(P.ring(cx, cy, R - 4, R + 1), cols, { r: 3, depth: 1.8, spec: .5, hammer: .05 }), { sh: .4, blur: 2, oy: 1 });
  const disc = shapeLayer(CW, CH, P.circle(cx, cy, R - 4), x => rgrad(x, cx, cy, 0, R, ['#2a3446', '#121822', '#06080e'], cx - 10, cy - 12), { bevel: { r: 6, inset: true, depth: 1.2, spec: .1 } });
  put(ctx, disc, { sh: 0 });
}

/* ---------- shared stone card body ---------- */
function stoneCard(x, cols, o = {}) {
  const [wx, wy, ww, wh, wr] = CARD_LAYOUT.window, seed = o.seed || 11;
  // content backdrop below the art (element-tinted dark)
  x.save(); x.beginPath(); rr(x, 46, 54, 420, 622, 14); x.fillStyle = grad(x, 0, 300, 0, 680, [mix(cols[0], '#0a0c12', .55), mix(cols[0], '#05060a', .8)]); x.fill(); x.restore();
  // stone outer frame
  const outer = P.rr(12, 20, 488, 690, 28), hole = P.rr(40, 48, 432, 634, 16);
  const stonePath = xx => { xx.beginPath(); rr(xx, 12, 20, 488, 690, 28); rr(xx, 40, 48, 432, 634, 16, true); };
  put(x, stoneLayer(CW, CH, stonePath, { chips: [12, 20, 488, 690], cracks: 9, seed }), { sh: .7, blur: 10, oy: 5 });
  outline(x, outer, 3);
  // element inner frame
  const innerPath = xx => { xx.beginPath(); rr(xx, 36, 44, 440, 642, 18); rr(xx, 50, 58, 412, 614, 12, true); };
  put(x, matLayer(innerPath, cols, { r: 5, depth: 2, spec: .5, hammer: .06, sheenA: .35 }), { sh: .7, blur: 6, oy: 3 });
  outline(x, P.rr(36, 44, 440, 642, 18), 2);
  outline(x, P.rr(50, 58, 412, 614, 12), 2);
  if (o.trim) { // star-tier trim line on the inner frame
    put(x, matLayer(xx => { xx.beginPath(); rr(xx, 40, 48, 432, 634, 16); rr(xx, 44, 52, 424, 626, 14, true); }, o.trim, { r: 2, depth: 1.6, spec: .9, hammer: .05 }), { sh: .4, blur: 2, oy: 1 });
  }
  // rivets on the stone
  rivets(x, [[26, 34], [CW - 26, 34], [26, CH - 20], [CW - 26, CH - 20], [24, 360], [CW - 24, 360]], 6, o.rivet || SILVER);
}
function cutWindow(x, pathFn) {
  x.save(); x.globalCompositeOperation = 'destination-out'; pathFn(x); x.fill(); x.restore();
  innerShadow(x, pathFn, { blur: 14, ox: 3, oy: 6, a: .75 });
}
function banner(x, cols) {
  const [nx, ny, nw, nh] = CARD_LAYOUT.name;
  ribbon(x, [mix(cols[0], '#000', .1), cols[1], cols[2]], [nx - 10, ny - 14, nw + 20, nh + 20], null, { tail: 30 });
  const rp = ribbonPaths(nx - 32, nx + nw + 32, ny - 16, nh + 24, 30, 10);
  outline(x, rp.face, 2.5);
  outline(x, xx => { rp.tailL(xx); rp.tailR(xx, true); }, 2);
}

/* ---------- hero frame ---------- */
function drawStoneFrame(E, star) {
  const c = mk(CW, CH), x = c.getContext('2d'), cols = INNER[E];
  const trim = star === 3 ? GOLD : star === 2 ? SILVER : null;
  stoneCard(x, cols, { trim, seed: hashStr(E) + star, rivet: star === 3 ? GOLD : SILVER });
  cutWindow(x, P.rr(...CARD_LAYOUT.window));
  banner(x, cols);
  parchmentPlate(x, CARD_LAYOUT.parchment, 33);
  // stat medallions on the parchment's lower edge
  const [ax, ay, ar] = CARD_LAYOUT.atk, [mx, my, mr] = CARD_LAYOUT.mana, [hx, hy, hr] = CARD_LAYOUT.hp;
  put(x, matLayer(xx => { xx.save(); xx.translate(ax, ay); xx.rotate(-Math.PI * .75); xx.scale(.78, .8); swordShape(xx, 168); xx.restore(); }, SILVER, { r: 3, depth: 1.8, spec: .8 }), { sh: .7, blur: 5, oy: 3 });
  stoneMedal(x, ax, ay, ar, ['#6e0d14', '#d0402e']);
  stoneMedal(x, hx, hy, hr, ['#0f4a22', '#46aa4e']);
  stoneMedal(x, mx, my, mr, ['#0e2a66', '#3c78dc']);
  put(x, shapeLayer(CW, CH, xx => { xx.beginPath(); heartPath(xx, hx + 30, hy - 30, 13); }, xx => rgrad(xx, hx + 26, hy - 36, 2, 20, ['#ff8a80', '#c4202e', '#5a0610']), { bevel: { r: 4, depth: 1.8, spec: .7, round: 1.5 } }), { sh: .7, blur: 4, oy: 2 });
  outline(x, xx => { xx.beginPath(); heartPath(xx, hx + 30, hy - 30, 13); }, 1.6);
  const mc = layer(CW, CH, xx => gemDiamond(xx, mx, my - mr - 6, 9, 13, ['#0b2a7a', '#3c7ce0', '#bcd8ff']));
  put(x, bevel(mc, { r: 2, depth: 1.2, spec: .6 }), { sh: .7, blur: 4, oy: 2 });
  // gem badge (cost) and stars
  const [gx, gy, gr] = CARD_LAYOUT.gem; gemBadge(x, gx, gy, gr, cols);
  if (star >= 2) CARD_LAYOUT.stars.xs[star].forEach(sx => { put(x, starLayer(sx, CARD_LAYOUT.stars.y, CARD_LAYOUT.stars.r, trim), { sh: .75, blur: 4, oy: 2 }); outline(x, P.star(sx, CARD_LAYOUT.stars.y, CARD_LAYOUT.stars.r, CARD_LAYOUT.stars.r * .45), 1.5); });
  cornerMedal(x, cols, hashStr(E));
  return c;
}

/* ---------- magic frames ---------- */
function drawStoneMagic(kind) {
  const c = mk(CW, CH), x = c.getContext('2d'), cols = INNER[kind], item = kind === 'item';
  stoneCard(x, cols, { seed: hashStr(kind) });
  // painted backdrop in the window around the round art hole
  const [wx, wy, ww, wh, wr] = CARD_LAYOUT.window, [ox, oy, orr] = CARD_LAYOUT.magicArt;
  x.save(); x.beginPath(); rr(x, wx, wy, ww, wh, wr); x.clip();
  x.fillStyle = rgrad(x, ox, oy, 20, 260, item ? ['#3a5a70', '#17283a', '#080e16'] : ['#5a2e80', '#24103a', '#0c0616']); x.fillRect(wx, wy, ww, wh);
  const n = makeNoise(hashStr(kind)), tex = texture(ww, wh, (X, Y) => { const v = n.fbm(X * .02, Y * .02, 4) * 255; return [v, v, v, 255]; });
  x.globalCompositeOperation = 'overlay'; x.globalAlpha = .3; x.drawImage(tex, wx, wy); x.globalAlpha = 1; x.globalCompositeOperation = 'source-over';
  x.strokeStyle = item ? 'rgba(190,220,240,.18)' : 'rgba(220,180,255,.2)'; x.lineWidth = 2.5; x.lineCap = 'round';
  runeRing(x, ox, oy, orr + 24, 16, hashStr(kind) + 5, 9);
  x.restore();
  // ring bezel around the art hole
  put(x, matLayer(P.ring(ox, oy, orr - 2, orr + 9), cols, { r: 4, depth: 2, spec: .5, hammer: .05 }), { sh: .7, blur: 8, oy: 3 });
  outline(x, P.circle(ox, oy, orr + 9), 2);
  cutWindow(x, P.circle(ox, oy, orr - 1));
  banner(x, cols);
  parchmentPlate(x, CARD_LAYOUT.parchment, 35);
  const [gx, gy, gr] = CARD_LAYOUT.gem; gemBadge(x, gx, gy, gr, cols);
  // engraved type glyph in the badge: item = shield, spell = 4-point star
  const gl = layer(CW, CH, xx => { xx.fillStyle = mix(cols[0], '#000', .2); xx.beginPath(); if (item) { xx.moveTo(gx - 12, gy - 13); xx.lineTo(gx + 12, gy - 13); xx.lineTo(gx + 12, gy); xx.quadraticCurveTo(gx + 10, gy + 10, gx, gy + 15); xx.quadraticCurveTo(gx - 10, gy + 10, gx - 12, gy); xx.closePath(); } else P.star(gx, gy, 16, 5, 4)(xx, true); xx.fill(); });
  put(x, bevel(gl, { r: 2, depth: 1.5, inset: true, spec: .2 }), { sh: 0, alpha: .8 });
  cornerMedal(x, cols, hashStr(kind));
  return c;
}

/* ---------- card back ---------- */
function drawStoneBack() {
  const c = mk(CW, CH), x = c.getContext('2d'), cols = ['#0a2a30', '#145058', '#227a80', '#4aa8a8', '#a8e0dc'];
  // dark teal carved interior
  const inT = cached('back-teal', () => texStone(CW, CH, ['#041214', '#08201f', '#0e302e', '#164440'], 111, 1.1));
  x.save(); x.beginPath(); rr(x, 40, 48, 432, 634, 16); x.fillStyle = pattern(x, inT); x.fill();
  x.fillStyle = rgrad(x, 256, 340, 40, 360, ['rgba(80,160,150,.18)', 'rgba(0,0,0,.45)']); x.fillRect(0, 0, CW, CH); x.restore();
  const stonePath = xx => { xx.beginPath(); rr(xx, 12, 20, 488, 690, 28); rr(xx, 40, 48, 432, 634, 16, true); };
  put(x, stoneLayer(CW, CH, stonePath, { chips: [12, 20, 488, 690], cracks: 10, seed: 909 }), { sh: .7, blur: 10, oy: 5 });
  outline(x, P.rr(12, 20, 488, 690, 28), 3);
  innerShadow(x, P.rr(40, 48, 432, 634, 16), { blur: 18, ox: 3, oy: 7, a: .85 });
  rivets(x, [[26, 34], [CW - 26, 34], [26, CH - 20], [CW - 26, CH - 20], [24, 360], [CW - 24, 360]], 6);
  // carved emblem: ring + four element sigils + center crown gem (carved = inset bevel, teal tinted)
  const CX = 256, CY = 362;
  const carve = layer(CW, CH, xx => {
    xx.fillStyle = '#2a7870'; xx.strokeStyle = '#2a7870';
    xx.lineWidth = 10; xx.beginPath(); xx.arc(CX, CY, 150, 0, TAU); xx.stroke();
    xx.lineWidth = 4; xx.beginPath(); xx.arc(CX, CY, 132, 0, TAU); xx.stroke();
    [['ice', 0, -1], ['fire', 1, 0], ['light', 0, 1], ['nature', -1, 0]].forEach(([E, sx, sy]) => sigil(xx, E, CX + sx * 84, CY + sy * 84, 34));
    // crown in the middle
    xx.beginPath(); xx.moveTo(CX - 36, CY + 20); xx.lineTo(CX - 40, CY - 18); xx.lineTo(CX - 18, CY - 2); xx.lineTo(CX, CY - 30); xx.lineTo(CX + 18, CY - 2); xx.lineTo(CX + 40, CY - 18); xx.lineTo(CX + 36, CY + 20); xx.closePath(); xx.fill();
    xx.fillRect(CX - 38, CY + 24, 76, 10);
    for (let i = 0; i < 4; i++) { const a = Math.PI / 4 + i * Math.PI / 2; xx.beginPath(); xx.moveTo(CX + Math.cos(a) * 110, CY + Math.sin(a) * 110); xx.lineTo(CX + Math.cos(a) * 130, CY + Math.sin(a) * 130); xx.lineWidth = 6; xx.stroke(); }
    xx.lineWidth = 5; xx.beginPath(); xx.moveTo(CX, 90); xx.lineTo(CX, CY - 156); xx.moveTo(CX, CY + 156); xx.lineTo(CX, 640); xx.stroke();
    for (const py of [90, 640]) { xx.beginPath(); xx.moveTo(CX, py - 14); xx.lineTo(CX + 12, py); xx.lineTo(CX, py + 14); xx.lineTo(CX - 12, py); xx.closePath(); xx.fill(); }
  });
  bevel(carve, { r: 4, depth: 1.8, inset: true, spec: .15, amb: .5 });
  x.drawImage(carve, 0, 0);
  x.save(); x.globalAlpha = .3; x.strokeStyle = '#6ac0b8'; x.lineWidth = 2; runeRing(x, CX, CY, 170, 26, 4242, 9); x.restore();
  gemSet(x, ['#06302e', '#1a8a84', '#9ae8e0'], CX, CY + 2, 11, SILVER);
  return c;
}

for (const E of ['ice', 'fire', 'light', 'nature']) for (const s of [1, 2, 3]) reg(`cards/frame_${E}_${s}.png`, () => drawStoneFrame(E, s));
reg('cards/frame_item.png', () => drawStoneMagic('item'));
reg('cards/frame_spell.png', () => drawStoneMagic('spell'));
reg('cards/back.png', drawStoneBack);
