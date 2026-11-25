'use strict';
/* =========================================================
   Card frames 512x716 (hero frames per element & star tier, magic frames, back)
   Text areas are left plain; see CARD_LAYOUT (also exported to the report).
   ========================================================= */
const CW = 512, CH = 716;

function metalTex(stops, w = CW, h = CH, hammer = .22) { return cached(`metal|${stops}|${w}|${h}|${hammer}`, () => texMetal(w, h, stops, hashStr(stops.join()), hammer)); }
function woodTex(stops, w = CW, h = CH) { return cached(`wood|${stops}|${w}|${h}`, () => texWood(w, h, stops, hashStr(stops.join()) + 1, 1)); }
function bodyTex(E, w = CW, h = CH) {
  const b = EL[E].body;
  return cached(`body|${E}|${w}|${h}`, () => E === 'fire' ? texLeather(w, h, [mix(b[0], '#000', .4), b[0], b[1], b[2]], 21)
    : E === 'nature' ? texWood(w, h, [mix(b[0], '#000', .3), b[0], b[1], b[2]], 23, 1.6)
      : E === 'light' ? texLeather(w, h, [mix(b[0], '#000', .3), b[0], b[1], b[2]], 25)
        : texStone(w, h, [mix(b[0], '#000', .3), b[0], b[1], b[2]], 27, 1.2));
}
// a material shape layer: metal (brushed) or wood (for nature)
function matLayer(pathFn, stops, o = {}) {
  const w = o.w || CW, h = o.h || CH;
  const tex = o.wood ? woodTex(stops, w, h) : metalTex(stops, w, h, o.hammer ?? .22);
  const mask = layer(w, h, x => { x.fillStyle = '#fff'; x.strokeStyle = '#fff'; pathFn(x); x.fill(o.rule || 'nonzero'); });
  const cv = layer(w, h, x => {
    x.drawImage(mask, 0, 0);
    x.globalCompositeOperation = 'source-in'; x.fillStyle = pattern(x, tex); x.fillRect(0, 0, w, h);
    x.globalCompositeOperation = 'overlay'; x.globalAlpha = o.sheenA ?? (o.wood ? .25 : .55);
    x.fillStyle = grad(x, 0, 0, w * .7, h, [[0, '#ffffff'], [.3, '#5a5a5a'], [.55, '#d0d0d0'], [.8, '#3a3a3a'], [1, '#909090']]);
    x.fillRect(0, 0, w, h);
    x.globalAlpha = 1; x.globalCompositeOperation = 'destination-in'; x.drawImage(mask, 0, 0);
    x.globalCompositeOperation = 'source-over';
    if (o.post) o.post(x);
  });
  bevel(cv, { r: o.r ?? 6, depth: o.depth ?? 1.6, spec: o.spec ?? (o.wood ? .18 : .6), shin: o.shin ?? 22, amb: o.amb ?? .38, round: o.round ?? 1 });
  if (o.after) o.after(cv.getContext('2d'));
  return cv;
}
function tierMetal(E, star) { return star === 3 ? GOLD : star === 2 ? SILVER : (E === 'nature' ? BRONZE : EL[E].metal); }

/* ---------- element motifs (drawn flat, beveled later) ---------- */
function crystal(x, bx, by, ang, len, wid, cols) {
  x.save(); x.translate(bx, by); x.rotate(ang);
  const tip = len, sh = len * .78;
  // left facet (lit) and right facet (shade)
  x.beginPath(); x.moveTo(0, -wid / 2); x.lineTo(sh, -wid / 2); x.lineTo(tip, 0); x.lineTo(0, 0); x.closePath();
  x.fillStyle = grad(x, 0, -wid / 2, 0, 0, [cols[2], cols[1]]); x.fill();
  x.beginPath(); x.moveTo(0, 0); x.lineTo(tip, 0); x.lineTo(sh, wid / 2); x.lineTo(0, wid / 2); x.closePath();
  x.fillStyle = grad(x, 0, 0, 0, wid / 2, [cols[1], cols[0]]); x.fill();
  x.beginPath(); x.moveTo(0, 0); x.lineTo(tip, 0); x.strokeStyle = rgba('#ffffff', .55); x.lineWidth = 1.2; x.stroke();
  x.restore();
}
function flameTongue(x, bx, by, ang, len, wid, cols) {
  // layered flame pointing along ang; len = height, wid = width
  x.save(); x.translate(bx + Math.cos(ang) * len * .48, by + Math.sin(ang) * len * .48); x.rotate(ang + Math.PI / 2);
  const sx = wid / 160, sy = len / 200;
  x.save(); x.scale(sx, sy); flamePath(x); x.fillStyle = grad(x, 0, 100, 0, -100, [cols[0], cols[1], mix(cols[1], cols[2], .4)]); x.fill(); x.restore();
  x.save(); x.translate(0, len * .14); x.scale(sx * .62, sy * .62); flamePath(x); x.fillStyle = grad(x, 0, 100, 0, -100, [cols[1], cols[2]]); x.fill(); x.restore();
  x.save(); x.translate(0, len * .26); x.scale(sx * .3, sy * .32); flamePath(x); x.fillStyle = cols[3] || cols[2]; x.fill(); x.restore();
  x.restore();
}
function leaf(x, bx, by, ang, len, wid, cols) {
  x.save(); x.translate(bx, by); x.rotate(ang);
  x.beginPath(); x.moveTo(0, 0); x.bezierCurveTo(len * .3, -wid * .65, len * .75, -wid * .55, len, 0); x.bezierCurveTo(len * .75, wid * .55, len * .3, wid * .65, 0, 0); x.closePath();
  x.fillStyle = grad(x, 0, -wid / 2, 0, wid / 2, [cols[2], cols[1], cols[0]]); x.fill();
  x.beginPath(); x.moveTo(len * .08, 0); x.lineTo(len * .9, 0); x.strokeStyle = rgba(cols[0], .8); x.lineWidth = Math.max(1, wid * .08); x.stroke();
  x.restore();
}
function ray(x, bx, by, ang, len, wid, cols) {
  x.save(); x.translate(bx, by); x.rotate(ang);
  x.beginPath(); x.moveTo(0, -wid / 2); x.lineTo(len, 0); x.lineTo(0, wid / 2); x.closePath();
  x.fillStyle = grad(x, 0, -wid / 2, 0, wid / 2, [cols[2], cols[1], cols[0]]); x.fill();
  x.beginPath(); x.moveTo(0, 0); x.lineTo(len, 0); x.strokeStyle = rgba(cols[0], .45); x.lineWidth = 1; x.stroke();
  x.restore();
}
// a fan of motif units around (cx,cy) pointing at angle a0 spreading 'spread' radians
function motifFan(x, E, cx, cy, a0, spread, n, len, wid, r0 = 0) {
  const e = EL[E];
  for (let i = 0; i < n; i++) {
    const t = n === 1 ? .5 : i / (n - 1), a = a0 - spread / 2 + spread * t;
    const L = len * (1 - Math.abs(t - .5) * .55);
    const bx = cx + Math.cos(a) * r0, by = cy + Math.sin(a) * r0;
    if (E === 'ice') crystal(x, bx, by, a, L, wid, e.crystal);
    else if (E === 'fire') flameTongue(x, bx, by, a, L, wid, e.flame);
    else if (E === 'nature') leaf(x, bx, by, a, L, wid, e.leaf);
    else ray(x, bx, by, a, L, wid, [e.metal[1], e.metal[3], e.metal[4]]);
  }
}
function motifLayer(E, draws, o = {}) {
  const c = layer(o.w || CW, o.h || CH, x => draws(x));
  return bevel(c, { r: o.r ?? 3, depth: o.depth ?? 1.4, spec: E === 'ice' ? .8 : E === 'light' ? .6 : E === 'fire' ? .45 : .25, shin: 26, amb: .5 });
}
// vine with leaves along a path of points
function vine(x, pts, cols, seed) {
  const r = mulberry(seed);
  x.save(); x.lineCap = 'round'; x.strokeStyle = '#4a3016'; x.lineWidth = 5;
  x.beginPath(); x.moveTo(pts[0][0], pts[0][1]);
  for (let i = 1; i < pts.length - 1; i++) { const mx = (pts[i][0] + pts[i + 1][0]) / 2, my = (pts[i][1] + pts[i + 1][1]) / 2; x.quadraticCurveTo(pts[i][0], pts[i][1], mx, my); }
  x.lineTo(pts[pts.length - 1][0], pts[pts.length - 1][1]); x.stroke(); x.restore();
  for (let i = 1; i < pts.length; i++) { const p = pts[i], q = pts[i - 1], a = Math.atan2(p[1] - q[1], p[0] - q[0]); const side = i % 2 ? 1 : -1; leaf(x, p[0], p[1], a + side * (.9 + r() * .4), 20 + r() * 8, 11 + r() * 3, cols); }
}

/* ---------- reusable card pieces ---------- */
function cardRimPath(x) { x.beginPath(); rr(x, 0, 0, CW, CH, 30); rr(x, 20, 20, CW - 40, CH - 40, 20, true); }
function bodyLayer(E, texOverride) {
  return shapeLayer(CW, CH, P.rr(0, 0, CW, CH, 30), x => pattern(x, texOverride || bodyTex(E)), {
    post: x => {
      // soft painted light falling from the top-left, darker at the bottom
      x.save(); x.globalCompositeOperation = 'source-atop';
      x.fillStyle = rgrad(x, 140, 120, 40, 820, [[0, 'rgba(255,240,210,.10)'], [.6, 'rgba(0,0,0,0)'], [1, 'rgba(0,0,0,.35)']]); x.fillRect(0, 0, CW, CH); x.restore();
    }, bevel: { r: 3, depth: 1, spec: .1 },
  });
}
function recessed(ctx, pathFn, fillCol, o = {}) {
  ctx.save(); pathFn(ctx); ctx.fillStyle = fillCol; ctx.fill(); ctx.restore();
  innerShadow(ctx, pathFn, { blur: o.blur ?? 8, ox: 2, oy: 4, a: o.a ?? .8 });
  // lower lip highlight
  ctx.save(); pathFn(ctx); ctx.clip(); ctx.translate(-1, -1.5); pathFn(ctx); ctx.lineWidth = 2; ctx.strokeStyle = 'rgba(255,235,200,.10)'; ctx.stroke(); ctx.restore();
}
function starLayer(cx, cy, R, stops) {
  return matLayer(P.star(cx, cy, R, R * .45), stops, { r: Math.max(3, R * .3), depth: 2.2, spec: .8, round: 1.4, hammer: .05 });
}
function gemSet(ctx, E, cx, cy, r, stops, o = {}) {
  // metal bezel with prongs
  const bez = matLayer(x => { x.beginPath(); x.ellipse(cx, cy, r + 7, r * 1.18 + 7, 0, 0, TAU); for (let i = 0; i < 4; i++) { const a = Math.PI / 4 + i * Math.PI / 2; x.moveTo(cx + Math.cos(a) * (r + 12), cy + Math.sin(a) * (r * 1.18 + 12)); x.arc(cx + Math.cos(a) * (r + 9), cy + Math.sin(a) * (r * 1.18 + 9), 4, 0, TAU); } }, stops, { r: 4, depth: 1.8, w: o.w, h: o.h });
  put(ctx, bez, { sh: .6, blur: 6, oy: 3 });
  ctx.save(); ctx.beginPath(); ctx.ellipse(cx, cy, r + 1, r * 1.18 + 1, 0, 0, TAU); ctx.fillStyle = 'rgba(0,0,0,.6)'; ctx.fill(); ctx.restore();
  ctx.drawImage(gemLayer(o.w || CW, o.h || CH, cx, cy, r, EL[E] ? EL[E].gem : E, 'oval', r * 1.18), 0, 0);
}
// round stat medallion: metal ring + enamel disc; motif drawn by caller
function medallion(ctx, cx, cy, R, ring, enamel) {
  const ringL = matLayer(P.ring(cx, cy, R - 11, R), ring, { r: 5, depth: 1.8, spec: .7 });
  const disc = shapeLayer(CW, CH, P.circle(cx, cy, R - 10), x => rgrad(x, cx, cy, 0, R - 10, [[0, enamel[1]], [.75, enamel[0]], [1, mix(enamel[0], '#000', .45)]], cx - R * .25, cy - R * .3), {
    post: x => { // enamel sheen band, subtle
      x.save(); x.globalCompositeOperation = 'source-atop'; x.fillStyle = rgrad(x, cx - R * .3, cy - R * .45, 0, R * .7, ['rgba(255,255,255,.22)', 'rgba(255,255,255,0)']); x.fillRect(0, 0, CW, CH); x.restore();
    }, bevel: { r: 7, depth: 1.2, inset: true, spec: .2 }
  });
  put(ctx, disc, { sh: 0 });
  // engraved fine ring inside the enamel
  groove(ctx, x => { x.beginPath(); x.arc(cx, cy, R - 16, 0, TAU); }, 1.5, .35);
  put(ctx, ringL, { sh: .65, blur: 8, oy: 4 });
}
function swordShape(x, len) { // pointing +x, centered at 0
  const h = len / 2;
  x.beginPath();
  x.moveTo(h, 0); x.lineTo(h - 22, -7); x.lineTo(-h + 40, -7); x.lineTo(-h + 40, 7); x.lineTo(h - 22, 7); x.closePath(); // blade
  x.rect(-h + 34, -20, 9, 40); // guard
  x.rect(-h + 10, -4.5, 25, 9); // grip
  x.moveTo(-h + 12, 0); x.arc(-h + 8, 0, 8, 0, TAU); // pommel
}

function gemDiamond(x, cx, cy, w, h, cols) {
  x.beginPath(); x.moveTo(cx, cy - h); x.lineTo(cx + w, cy); x.lineTo(cx, cy + h); x.lineTo(cx - w, cy); x.closePath(); x.fillStyle = cols[1]; x.fill();
  x.beginPath(); x.moveTo(cx, cy - h); x.lineTo(cx - w, cy); x.lineTo(cx, cy); x.closePath(); x.fillStyle = cols[2]; x.fill();
  x.beginPath(); x.moveTo(cx, cy - h); x.lineTo(cx + w, cy); x.lineTo(cx, cy); x.closePath(); x.fillStyle = mix(cols[1], cols[2], .4); x.fill();
  x.beginPath(); x.moveTo(cx, cy + h); x.lineTo(cx - w, cy); x.lineTo(cx, cy); x.closePath(); x.fillStyle = mix(cols[1], cols[0], .3); x.fill();
  x.beginPath(); x.moveTo(cx, cy + h); x.lineTo(cx + w, cy); x.lineTo(cx, cy); x.closePath(); x.fillStyle = cols[0]; x.fill();
}
// name ribbon: area = [x,y,w,h] of the face
function ribbon(ctx, cols, area, trimStops, o = {}) {
  const [rx, ry, rw, rh] = area, W = o.w || CW, H = o.h || CH;
  const x0 = rx - 22, x1 = rx + rw + 22, rp = ribbonPaths(x0, x1, ry - 2, rh + 4, o.tail ?? 34, 10);
  const cloth = cached(`cloth|${cols}|${W}|${H}`, () => { const n = makeNoise(hashStr(cols.join())); const R = ramp([mix(cols[0], '#000', .3), cols[0], cols[1], cols[2]]); return texture(W, H, (X, Y) => { const v = .55 + (n(X * .5, Y * .5) - .5) * .06 + (n.fbm(X * .01, Y * .04, 3) - .5) * .3 + ((X + Y) % 4 < 2 ? .025 : -.025) + ((X - Y) % 4 < 2 ? .015 : -.015); return R(v); }); });
  const tailFill = xx => { const g = pattern(xx, cloth); return g; };
  const tails = shapeLayer(W, H, xx => { rp.tailL(xx); rp.tailR(xx, true); }, tailFill, {
    post: xx => { xx.save(); xx.globalCompositeOperation = 'source-atop'; xx.fillStyle = 'rgba(0,0,0,.42)'; xx.fillRect(0, 0, W, H); xx.restore(); }, bevel: { r: 4, depth: .9, spec: .1 }
  });
  // make tailR its own subpath: redraw both explicitly
  put(ctx, tails, { sh: .55, blur: 6, oy: 3 });
  const folds = layer(W, H, xx => { rp.foldL(xx); xx.fillStyle = mix(cols[0], '#000', .6); xx.fill(); rp.foldR(xx); xx.fill(); });
  ctx.drawImage(folds, 0, 0);
  const face = shapeLayer(W, H, rp.face, xx => pattern(xx, cloth), {
    post: xx => {
      xx.save(); xx.globalCompositeOperation = 'source-atop';
      xx.fillStyle = grad(xx, 0, ry - 4, 0, ry + rh, [[0, 'rgba(0,0,0,.25)'], [.12, 'rgba(255,235,215,.16)'], [.3, 'rgba(255,255,255,0)'], [.7, 'rgba(0,0,0,.12)'], [1, 'rgba(0,0,0,.5)']]); xx.fillRect(0, 0, W, H);
      // stitching
      xx.setLineDash([6, 5]); xx.lineWidth = 1.6; xx.strokeStyle = 'rgba(255,235,200,.38)';
      xx.beginPath(); xx.moveTo(x0 + 6, ry + 5); xx.quadraticCurveTo((x0 + x1) / 2, ry - 1, x1 - 6, ry + 5); xx.stroke();
      xx.beginPath(); xx.moveTo(x0 + 6, ry + rh - 3); xx.quadraticCurveTo((x0 + x1) / 2, ry + rh - 9, x1 - 6, ry + rh - 3); xx.stroke();
      xx.restore();
    }, bevel: { r: 5, depth: .9, spec: .12, round: 1.3 }
  });
  put(ctx, face, { sh: .65, blur: 9, oy: 4 });
  // metal end caps
  if (trimStops) put(ctx, matLayer(xx => { xx.beginPath(); rr(xx, x0 - 3, ry - 4, 9, rh + 6, 3); rr(xx, x1 - 6, ry - 4, 9, rh + 6, 3); }, trimStops, { r: 2, depth: 1.6, w: W, h: H }), { sh: .5, blur: 3, oy: 2 });
}

function runeRing(x, cx, cy, r, n, seed, sz) {
  const rnd = mulberry(seed);
  for (let i = 0; i < n; i++) {
    const a = i * TAU / n; x.save(); x.translate(cx + Math.cos(a) * r, cy + Math.sin(a) * r); x.rotate(a + Math.PI / 2); rune(x, rnd, sz); x.restore();
  }
}
function rune(x, rnd, s) { // angular glyph from a 3x4 grid
  x.beginPath(); const k = 2 + (rnd() * 3 | 0); let px = (rnd() * 3 | 0) - 1, py = (rnd() * 4 | 0) - 1.5; x.moveTo(px * s * .5, py * s * .5);
  x.lineTo(0, -s * .9); x.lineTo(0, s * .9);
  for (let i = 0; i < k; i++) { const qx = (rnd() * 3 | 0) - 1, qy = (rnd() * 4 | 0) - 1.5; x.moveTo(0, qy * s * .5); x.lineTo(qx * s * .5, (qy + (rnd() < .5 ? -1 : 1)) * s * .5); }
  x.stroke();
}

