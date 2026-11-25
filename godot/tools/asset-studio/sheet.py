"""Contact sheet of baked assets.
usage: python sheet.py OUT.png SCALE pattern [pattern ...]
patterns are globs relative to godot/assets (e.g. "cards/frame_*.png").
Frames get a sample portrait composited under the window when available."""
import sys, glob, os
from PIL import Image, ImageDraw

ASSETS = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', 'assets')
out, scale, pats = sys.argv[1], float(sys.argv[2]), sys.argv[3:]
files = []
for p in pats:
    files += sorted(glob.glob(os.path.join(ASSETS, p)))
SAMPLE = {'ice': 'hero_cutpurse', 'fire': 'hero_vampire', 'light': 'hero_inquisitor', 'nature': 'hero_werewolf'}
tiles = []
for f in files:
    im = Image.open(f).convert('RGBA')
    name = os.path.basename(f)
    if name.startswith('frame_') and im.size == (512, 716):
        base = Image.new('RGBA', im.size, (0, 0, 0, 0))
        el = name.split('_')[1]
        if el in SAMPLE and os.path.exists(os.path.join(ASSETS, 'portraits', SAMPLE[el] + '.png')):
            base.paste(Image.open(os.path.join(ASSETS, 'portraits', SAMPLE[el] + '.png')).convert('RGBA').resize((412, 298), Image.LANCZOS), (50, 58))
        elif el.split('.')[0] in ('item', 'spell') and os.path.exists(os.path.join(ASSETS, 'portraits', 'magic_fireball.png')):
            el = el.split('.')[0]
            m = Image.open(os.path.join(ASSETS, 'portraits', 'magic_' + ('sword' if el == 'item' else 'fireball') + '.png')).convert('RGBA')
            base.paste(m, (256 - 150, 207 - 150))
        im = Image.alpha_composite(base, im)
    w, h = max(1, int(im.width * scale)), max(1, int(im.height * scale))
    tiles.append((name, im.resize((w, h), Image.LANCZOS)))
cols_w = 1800
x = y = 10; rowh = 0; pos = []
for name, t in tiles:
    if x + t.width > cols_w:
        x = 10; y += rowh + 26; rowh = 0
    pos.append((x, y)); x += t.width + 12; rowh = max(rowh, t.height)
H = y + rowh + 30
sheet = Image.new('RGBA', (cols_w, H), (58, 52, 48, 255))
d = ImageDraw.Draw(sheet)
for (name, t), (px, py) in zip(tiles, pos):
    # checker under transparent assets
    for cy in range(0, t.height, 12):
        for cx in range(0, t.width, 12):
            if (cx // 12 + cy // 12) % 2:
                d.rectangle([px + cx, py + cy, px + min(cx + 11, t.width - 1), py + min(cy + 11, t.height - 1)], fill=(70, 64, 60, 255))
    sheet.alpha_composite(t, (px, py))
    d.text((px, py + t.height + 4), name, fill=(230, 220, 200, 255))
sheet.convert('RGB').save(out)
print(out, sheet.size, len(tiles))
