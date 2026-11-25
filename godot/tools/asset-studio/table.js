'use strict';
/* =========================================================
   Table & environment textures: felt.png (round slate arena, 2048),
   wood.png (warm wood strip, horizontally tileable), stone_rim.png,
   floor.png (seamless flagstones), ui/bg_wall.png (seamless dungeon wall).
   ========================================================= */
const FELT = {
  N: 2048,
  lanes: { enemy: [600, 860], player: [1188, 1448], bench: [1570, 1760] }, // y ranges in texture px (top = far/enemy side)
  emblem: [1024, 1024, 140],
};
// periodic stone texture (seamless when P divides the tile in both axes)
function tileStone(w, h, stops, seed, P = 8, tile = w) {
  const n = makeNoise(seed), n2 = makeNoise(seed + 1), R = ramp(stops);
  return texture(w, h, (X, Y) => {
    const u = X / tile * P, v = Y / tile * P;
    const a = n.fbm(u, v, 5, P), b = n2.fbm(u * 4, v * 4, 3, P * 4);
    return R(clamp(.1 + a * .8 + (b - .5) * .35));
  });
}
// seamless brick / flagstone tile: draws onto a padded canvas then crops
function brickTile(S, rowH, brickW, stops, seed, o = {}) {
  const pad = 48, W = S + pad * 2, rnd = mulberry(seed);
  const base = tileStone(S, S, stops, seed, 8);
  const mask = layer(W, W, x => {
    for (let r = 0; r * rowH < S; r++) {
      const off = (r % 2) * brickW / 2 + (o.jitter ? (rnd() - .5) * brickW * .3 : 0);
      let bx = -off; const end = S - off, bws = [];
      while (bx < end - 1) { let bw = brickW * (o.jitter ? .7 + rnd() * .6 : 1); if (end - (bx + bw) < brickW * .4) bw = end - bx; bws.push([bx, bw]); bx += bw; }
      for (const [x0, bw] of bws) for (const dx of [-S, 0, S]) for (const dy of [-S, 0, S]) {
        const gx = pad + x0 + dx + 4, gy = pad + r * rowH + dy + 4;
        x.beginPath(); rr(x, gx, gy, bw - 8, rowH - 8, o.round ?? 10); x.fillStyle = `hsl(0,0%,${70 + rnd() * 30}%)`; x.fill();
      }
    }
  });
  // tint each brick by the mask lightness, fill with stone
  const tex = layer(W, W, x => { const p = x.createPattern(base, 'repeat'); x.save(); x.translate(pad, pad); x.fillStyle = p; x.fillRect(-pad, -pad, W, W); x.restore(); x.globalCompositeOperation = 'multiply'; x.drawImage(mask, 0, 0); x.globalCompositeOperation = 'destination-in'; x.drawImage(mask, 0, 0); });
  bevel(tex, { r: o.bevel ?? 8, depth: 1.8, amb: .45, spec: .12, round: 1.3 });
  const out = mk(S, S), x = out.getContext('2d');
  x.fillStyle = o.mortar || '#06080c'; x.fillRect(0, 0, S, S);
  x.drawImage(tex, -pad, -pad);
  return out;
}

function drawFelt() {
  const N = FELT.N, c = mk(N, N), x = c.getContext('2d'), C = N / 2;
  const slate = texStone(N, N, ['#0c1118', '#141c27', '#1c2734', '#253344', '#2e3e52'], 121, .5);
  x.drawImage(slate, 0, 0);
  // painted light pool in the middle, darker toward the edge
  x.fillStyle = rgrad(x, C, C * .95, 100, C, ['rgba(140,170,210,.10)', 'rgba(0,0,0,0)', 'rgba(0,0,0,.45)']); x.fillRect(0, 0, N, N);
  // outer carved border ring
  const ring = layer(N, N, xx => { xx.beginPath(); xx.arc(C, C, 1010, 0, TAU); xx.arc(C, C, 930, 0, TAU, true); xx.fillStyle = pattern(xx, slate); xx.fill(); xx.globalCompositeOperation = 'source-atop'; xx.fillStyle = 'rgba(120,150,190,.12)'; xx.fillRect(0, 0, N, N); });
  put(x, bevel(ring, { r: 12, depth: 1.6, spec: .12, round: 1.3 }), { sh: .7, blur: 18, oy: 8 });
  groove(x, xx => { xx.beginPath(); xx.arc(C, C, 970, 0, TAU); }, 4, .7);
  groove(x, xx => { xx.beginPath(); xx.arc(C, C, 900, 0, TAU); }, 3, .5);
  // runes in the border
  x.save(); x.globalAlpha = .55; x.strokeStyle = '#05070a'; x.lineWidth = 6; x.lineCap = 'round'; runeRing(x, C, C, 970, 72, 333, 22); x.restore();
  x.save(); x.globalAlpha = .18; x.strokeStyle = '#a8c0dc'; x.lineWidth = 3; x.lineCap = 'round'; x.translate(2, 2); runeRing(x, C, C, 970, 72, 333, 22); x.restore();
  // four element sigils at the cardinal points of the border (inlaid, muted colors)
  const sig = [['ice', 0, -1, '#5fb8c8'], ['fire', 1, 0, '#c8603a'], ['light', 0, 1, '#d4a83a'], ['nature', -1, 0, '#6aa840']];
  for (const [E, sx, sy, col] of sig) {
    const px = C + sx * 958, py = C + sy * 958;
    put(x, stoneLayer(N, N, P.circle(px, py, 58), { rule: 'nonzero', r: 8 }), { sh: .7, blur: 10, oy: 5 });
    const s = layer(N, N, xx => { xx.fillStyle = col; sigil(xx, E, px, py, 38); });
    put(x, bevel(s, { r: 4, depth: 1.6, inset: true, spec: .2 }), { sh: 0, alpha: .85 });
  }
  // lanes: carved rounded bands (keep subtle)
  const laneRect = ([y0, y1]) => { const yc = (y0 + y1) / 2, half = Math.sqrt(Math.max(0, 880 * 880 - (Math.abs(yc - C) + (y1 - y0) / 2) ** 2)); return [C - half, y0, half * 2, y1 - y0]; };
  for (const k of ['enemy', 'player', 'bench']) {
    const [lx, ly, lw, lh] = laneRect(FELT.lanes[k]);
    x.save(); x.beginPath(); rr(x, lx, ly, lw, lh, 36); x.fillStyle = k === 'enemy' ? 'rgba(60,10,10,.10)' : k === 'player' ? 'rgba(10,40,70,.10)' : 'rgba(0,0,0,.14)'; x.fill(); x.restore();
    if (k === 'bench') x.setLineDash([28, 18]);
    groove(x, xx => { xx.beginPath(); rr(xx, lx, ly, lw, lh, 36); }, 4, .55);
    x.setLineDash([]);
    // small diamonds at the lane ends
    for (const ex of [lx + 30, lx + lw - 30]) groove(x, xx => { xx.beginPath(); xx.moveTo(ex, ly + lh / 2 - 18); xx.lineTo(ex + 14, ly + lh / 2); xx.lineTo(ex, ly + lh / 2 + 18); xx.lineTo(ex - 14, ly + lh / 2); xx.closePath(); }, 3, .5);
  }
  // center emblem: carved disc with four sigils and a crossed divider
  const [ex, ey, er] = FELT.emblem;
  put(x, stoneLayer(N, N, P.ring(ex, ey, er - 26, er), { r: 8, chips: null }), { sh: .7, blur: 12, oy: 6 });
  x.save(); x.beginPath(); x.arc(ex, ey, er - 26, 0, TAU); x.fillStyle = 'rgba(0,0,0,.25)'; x.fill(); x.restore();
  innerShadow(x, P.circle(ex, ey, er - 26), { blur: 16, ox: 3, oy: 6, a: .7 });
  for (const [E, sx, sy, col] of [['ice', -1, -1, '#5fb8c8'], ['fire', 1, -1, '#c8603a'], ['nature', -1, 1, '#6aa840'], ['light', 1, 1, '#d4a83a']]) {
    const s = layer(N, N, xx => { xx.fillStyle = col; sigil(xx, E, ex + sx * 44, ey + sy * 44, 30); });
    put(x, bevel(s, { r: 3, depth: 1.6, inset: true, spec: .2 }), { sh: 0, alpha: .8 });
  }
  groove(x, xx => { xx.beginPath(); xx.moveTo(ex - 100, ey); xx.lineTo(ex + 100, ey); xx.moveTo(ex, ey - 100); xx.lineTo(ex, ey + 100); }, 3, .5);
  // midline from the emblem to the border
  groove(x, xx => { xx.beginPath(); xx.moveTo(C - 880, C); xx.lineTo(ex - er - 10, C); xx.moveTo(ex + er + 10, C); xx.lineTo(C + 880, C); }, 3, .35);
  return c;
}
function drawWood() {
  const c = texWood(1024, 256, ['#1e1008', '#3a2010', '#5a3418', '#7a4c26', '#946036'], 131, 1, true);
  const x = c.getContext('2d');
  x.fillStyle = grad(x, 0, 0, 0, 256, ['rgba(255,230,190,.10)', 'rgba(0,0,0,0)', 'rgba(0,0,0,.25)']); x.fillRect(0, 0, 1024, 256);
  return c;
}
function drawStoneRim() { // carved slate blocks, tileable horizontally
  const S = 1024, t = brickTile(S, S / 4, 256, SLATE, 141, { round: 14, bevel: 12 });
  const c = mk(1024, 256), x = c.getContext('2d'); x.drawImage(t, 0, 0);
  groove(x, xx => { xx.beginPath(); xx.moveTo(0, 40); xx.lineTo(1024, 40); }, 3, .4);
  return c;
}
function drawFloor() { return brickTile(1024, 256, 256, ['#0a0d12', '#151b24', '#1e2733', '#283444', '#323f52'], 151, { jitter: true, round: 16, bevel: 12, mortar: '#040507' }); }
function drawWall() { return brickTile(1024, 128, 256, ['#0e1420', '#172236', '#203048', '#2a3e5a', '#344a6a'], 161, { round: 12, bevel: 10, mortar: '#05070c' }); }

reg('table/felt.png', drawFelt);
reg('table/wood.png', drawWood);
reg('table/stone_rim.png', drawStoneRim);
reg('table/floor.png', drawFloor);
reg('ui/bg_wall.png', drawWall);

// layout metadata for the Godot scenes (card text areas, felt lanes)
reg('cards/card_layout.json', () => ({ toDataURL: () => 'data:application/json;base64,' + btoa(JSON.stringify({ size: [512, 716], card: CARD_LAYOUT, felt: FELT }, null, 1)) }));
