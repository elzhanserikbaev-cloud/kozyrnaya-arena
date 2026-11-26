'use strict';
/* =========================================================
   Extras: legendary heroes and arena guardians (Godot Data.LEGENDS / Data.MONSTERS).
   Portraits hero_<id>.png 432x312 + cards/frame_legend.png. Loaded after art.js / cards_stone.js.
   Icons not in web/icons.js come from icons_extra.js.
   ========================================================= */
const LEGEND_HEROES = [
  ['frostdragon', 'dragon-head', 'S'], ['phoenix', 'eagle-emblem', 'H'], ['archangel', 'angel-outfit', 'D'],
  ['ancientent', 'evil-tree', 'C'], ['madjester', 'sharp-smile', 'H'],
];
const MONSTER_UNITS = [
  ['m_golem', 'golem-head', 'C'], ['m_slime', 'slime', 'C'], ['m_rat', 'rat', 'C'], ['m_ghoul', 'bone-gnawer', 'H'],
  ['m_harpy', 'harpy', 'D'], ['m_bonedragon', 'wyvern', 'S'], ['m_icegolem', 'ice-golem', 'S'], ['m_spectre', 'spectre', 'S'],
  ['m_banshee', 'ghost', 'D'], ['m_abyss', 'daemon-skull', 'H'], ['m_minotaur', 'minotaur', 'D'], ['m_imp', 'imp', 'H'],
  ['m_sapling', 'sprout', 'C'],
];
// legend figure: element colors in the body, warm gold rim light
const FIG_LEGEND = {
  ice: { cols: ['#ffffff', '#bfe6f2', '#2c6a86'], rim: '#ffe2a0', tint: '#062a3a' },
  fire: { cols: ['#fff6e0', '#f6b468', '#82280e'], rim: '#ffe2a0', tint: '#3a0806' },
  light: { cols: ['#fffcec', '#f6d77a', '#8a5a10'], rim: '#fff0c0', tint: '#3a2204' },
  nature: { cols: ['#f6ffe6', '#bce08a', '#34621c'], rim: '#ffe2a0', tint: '#0c2a08' },
};
// guardian figure: bone/ash body, element-tinted shadows, dull red rim (menacing, no glow)
const FIG_MONSTER = {
  ice: { cols: ['#e6eef2', '#9ab4c0', '#24404e'], rim: '#d07a6a', tint: '#0a1a24' },
  fire: { cols: ['#f2e2d2', '#c08a6a', '#4a160c'], rim: '#e08a5a', tint: '#2a0604' },
  light: { cols: ['#f2ecd8', '#c4ac7a', '#5a3e14'], rim: '#d88a6a', tint: '#2a1a06' },
  nature: { cols: ['#e8eed8', '#9cae7a', '#2c401a'], rim: '#c8805a', tint: '#0c1a08' },
};

// gold filigree frame inside the portrait (beveled metal, painted, no glow)
function legendFiligree(x) {
  const b = 9, W = PW - b * 2, H = PH - b * 2;
  const ring = xx => { xx.beginPath(); rr(xx, b, b, W, H, 14); rr(xx, b + 6, b + 6, W - 12, H - 12, 10, true); };
  put(x, matLayer(ring, GOLD, { w: PW, h: PH, r: 3, depth: 1.8, spec: .7, hammer: .05 }), { sh: .6, blur: 5, ox: 1, oy: 2 });
  const gems = xx => {
    xx.beginPath();
    for (const [cx, cy] of [[b + 3, b + 3], [PW - b - 3, b + 3], [b + 3, PH - b - 3], [PW - b - 3, PH - b - 3]]) {
      xx.moveTo(cx, cy - 13); xx.lineTo(cx + 13, cy); xx.lineTo(cx, cy + 13); xx.lineTo(cx - 13, cy); xx.closePath();
    }
    const cx = PW / 2, cy = b + 2; // small crown notch on the top edge
    xx.moveTo(cx - 34, cy + 6); xx.lineTo(cx - 30, cy - 4); xx.lineTo(cx - 14, cy + 2); xx.lineTo(cx, cy - 8);
    xx.lineTo(cx + 14, cy + 2); xx.lineTo(cx + 30, cy - 4); xx.lineTo(cx + 34, cy + 6); xx.lineTo(cx, cy + 14); xx.closePath();
  };
  put(x, matLayer(gems, GOLD, { w: PW, h: PH, r: 3, depth: 2, spec: .8, hammer: .04 }), { sh: .65, blur: 5, ox: 1, oy: 2 });
}

function drawLegendPortrait(id, icon, suit) {
  const E = SUIT_EL[suit], rnd = mulberry(hashStr(id)), F = FIG_LEGEND[E];
  const c = mk(PW, PH), x = c.getContext('2d');
  BG[E](x, PW, PH, rnd);
  // warm gilded wash over the element backdrop
  x.save(); x.globalCompositeOperation = 'multiply'; x.fillStyle = grad(x, 0, 0, 0, PH, [mix(F.tint, '#ffffff', .62), mix('#5a3a10', '#ffffff', .45)]); x.fillRect(0, 0, PW, PH); x.restore();
  x.save(); x.globalCompositeOperation = 'soft-light'; x.fillStyle = rgrad(x, PW / 2, PH * .42, 10, PW * .6, ['rgba(255,220,140,.75)', 'rgba(200,140,50,.35)', 'rgba(60,30,0,.2)']); x.fillRect(0, 0, PW, PH); x.restore();
  // engraved sunburst rays behind the figure (painted, low alpha)
  x.save(); x.translate(PW / 2, PH * .48);
  for (let i = 0; i < 28; i++) {
    const a = i * TAU / 28, s = .05;
    x.beginPath(); x.moveTo(0, 0); x.lineTo(Math.cos(a - s) * 320, Math.sin(a - s) * 320); x.lineTo(Math.cos(a + s) * 320, Math.sin(a + s) * 320); x.closePath();
    x.fillStyle = i % 2 ? 'rgba(255,226,150,.10)' : 'rgba(120,70,10,.10)'; x.fill();
  }
  x.restore();
  // halo ring (beveled gold) behind the figure
  put(x, matLayer(P.ring(PW / 2, PH * .40, 92, 100), GOLD, { w: PW, h: PH, r: 3, depth: 1.6, spec: .6, hammer: .05 }), { sh: .5, blur: 6, oy: 2, alpha: .85 });
  blob(x, PW / 2, PH * .5, 160, F.tint, .35);
  x.save(); x.filter = 'blur(8px)'; x.beginPath(); x.ellipse(PW / 2 + 8, PH - 26, 124, 16, 0, 0, TAU); x.fillStyle = 'rgba(0,0,0,.5)'; x.fill(); x.restore();
  const fig = figureLayer(PW, PH, icon, PW / 2, PH / 2 + 10, 262, F, hashStr(id) + 3);
  put(x, fig, { sh: .6, blur: 14, ox: 12, oy: 10 });
  for (let i = 0; i < 46; i++) { x.beginPath(); x.arc(rnd() * PW, rnd() * PH, .6 + rnd() * 1.6, 0, TAU); x.fillStyle = `rgba(255,228,150,${.35 + rnd() * .45})`; x.fill(); }
  x.fillStyle = rgrad(x, PW / 2, PH / 2, PW * .38, PW * .74, ['rgba(0,0,0,0)', 'rgba(30,14,0,.45)']); x.fillRect(0, 0, PW, PH);
  legendFiligree(x);
  return c;
}

function drawMonsterPortrait(id, icon, suit) {
  const E = SUIT_EL[suit], rnd = mulberry(hashStr(id)), F = FIG_MONSTER[E];
  const c = mk(PW, PH), x = c.getContext('2d');
  BG[E](x, PW, PH, rnd);
  // dim, blood-tinted dusk over the element backdrop
  x.save(); x.globalCompositeOperation = 'multiply'; x.fillStyle = grad(x, 0, 0, 0, PH, [mix(F.tint, '#ffffff', .4), mix('#3a0a08', '#ffffff', .3)]); x.fillRect(0, 0, PW, PH); x.restore();
  // arena floor + torchlight from below
  x.fillStyle = grad(x, 0, PH * .78, 0, PH, ['rgba(20,10,8,0)', 'rgba(20,10,8,.85)']); x.fillRect(0, PH * .7, PW, PH * .3);
  blob(x, PW * .5, PH * .95, 200, '#a8401c', .18);
  // claw marks scratched into the backdrop
  x.save(); x.strokeStyle = 'rgba(0,0,0,.28)'; x.lineCap = 'round';
  for (let k = 0; k < 2; k++) {
    const sx = rnd() < .5 ? PW * (.08 + rnd() * .12) : PW * (.78 + rnd() * .12), sy = PH * (.12 + rnd() * .2);
    for (let i = 0; i < 3; i++) { x.lineWidth = 3 - i * .5; x.beginPath(); x.moveTo(sx + i * 9, sy); x.quadraticCurveTo(sx + i * 9 + 10, sy + 40, sx + i * 9 + 4, sy + 80); x.stroke(); }
  }
  x.restore();
  blob(x, PW / 2, PH * .5, 170, F.tint, .55);
  x.save(); x.filter = 'blur(8px)'; x.beginPath(); x.ellipse(PW / 2 + 8, PH - 26, 124, 16, 0, 0, TAU); x.fillStyle = 'rgba(0,0,0,.55)'; x.fill(); x.restore();
  const fig = figureLayer(PW, PH, icon, PW / 2, PH / 2 + 10, 258, F, hashStr(id) + 3);
  put(x, fig, { sh: .6, blur: 14, ox: 12, oy: 10 });
  for (let i = 0; i < 40; i++) { x.beginPath(); x.arc(rnd() * PW, rnd() * PH, .6 + rnd() * 1.4, 0, TAU); x.fillStyle = `rgba(200,190,180,${.2 + rnd() * .3})`; x.fill(); }
  x.fillStyle = rgrad(x, PW / 2, PH / 2, PW * .3, PW * .7, ['rgba(0,0,0,0)', 'rgba(10,0,0,.55)']); x.fillRect(0, 0, PW, PH);
  return c;
}

/* ---------- legendary card frame: gold-trimmed stone, gold inner frame, crown instead of stars ---------- */
const INNER_LEGEND = ['#4a2a04', '#8e5e10', '#c8962a', '#ecd07a', '#fff4c8'];
function drawLegendFrame() {
  const c = mk(CW, CH), x = c.getContext('2d'), cols = INNER_LEGEND;
  stoneCard(x, cols, { trim: GOLD, seed: hashStr('legend'), rivet: GOLD });
  cutWindow(x, P.rr(...CARD_LAYOUT.window));
  banner(x, cols);
  parchmentPlate(x, CARD_LAYOUT.parchment, 37);
  const [ax, ay, ar] = CARD_LAYOUT.atk, [mx, my, mr] = CARD_LAYOUT.mana, [hx, hy, hr] = CARD_LAYOUT.hp;
  put(x, matLayer(xx => { xx.save(); xx.translate(ax, ay); xx.rotate(-Math.PI * .75); xx.scale(.78, .8); swordShape(xx, 168); xx.restore(); }, GOLD, { r: 3, depth: 1.8, spec: .8 }), { sh: .7, blur: 5, oy: 3 });
  stoneMedal(x, ax, ay, ar, ['#6e0d14', '#d0402e']);
  stoneMedal(x, hx, hy, hr, ['#0f4a22', '#46aa4e']);
  stoneMedal(x, mx, my, mr, ['#0e2a66', '#3c78dc']);
  put(x, shapeLayer(CW, CH, xx => { xx.beginPath(); heartPath(xx, hx + 30, hy - 30, 13); }, xx => rgrad(xx, hx + 26, hy - 36, 2, 20, ['#ff8a80', '#c4202e', '#5a0610']), { bevel: { r: 4, depth: 1.8, spec: .7, round: 1.5 } }), { sh: .7, blur: 4, oy: 2 });
  outline(x, xx => { xx.beginPath(); heartPath(xx, hx + 30, hy - 30, 13); }, 1.6);
  const mc = layer(CW, CH, xx => gemDiamond(xx, mx, my - mr - 6, 9, 13, ['#0b2a7a', '#3c7ce0', '#bcd8ff']));
  put(x, bevel(mc, { r: 2, depth: 1.2, spec: .6 }), { sh: .7, blur: 4, oy: 2 });
  const [gx, gy, gr] = CARD_LAYOUT.gem; gemBadge(x, gx, gy, gr, cols);
  // gold crown on the top edge (where ★★/★★★ sit on hero frames)
  const cy = CARD_LAYOUT.stars.y, cx = CW / 2;
  const crown = xx => {
    xx.beginPath();
    xx.moveTo(cx - 46, cy + 12); xx.lineTo(cx - 52, cy - 16); xx.lineTo(cx - 26, cy - 2); xx.lineTo(cx, cy - 26);
    xx.lineTo(cx + 26, cy - 2); xx.lineTo(cx + 52, cy - 16); xx.lineTo(cx + 46, cy + 12); xx.closePath();
  };
  put(x, matLayer(crown, GOLD, { r: 3, depth: 2, spec: .8, hammer: .04 }), { sh: .75, blur: 5, oy: 3 });
  outline(x, crown, 1.8);
  gemSet(x, ['#4e0a06', '#c43a1c', '#ffc0a0'], cx, cy + 2, 7, GOLD);
  cornerMedal(x, cols, hashStr('legend'));
  return c;
}

for (const [id, ic, s] of LEGEND_HEROES) reg(`portraits/hero_${id}.png`, () => drawLegendPortrait(id, ic, s));
for (const [id, ic, s] of MONSTER_UNITS) reg(`portraits/hero_${id}.png`, () => drawMonsterPortrait(id, ic, s));
reg('cards/frame_legend.png', drawLegendFrame);
