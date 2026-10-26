# Генерация иконок из static/icons/icon-512.png (зуб на зелёном фоне #16695a)
import os, sys
from PIL import Image, ImageFilter, ImageDraw
src = Image.open(sys.argv[1]).convert('L')
bbox = src.point(lambda v: 255 if v > 128 else 0).getbbox()
crop = src.crop(bbox)
W, H = crop.width * 8, crop.height * 8
big = crop.resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(22)).point(lambda v: 255 if v > 128 else 0)
GREEN = (22, 105, 90)
FRAC = (bbox[2] - bbox[0]) / src.width

def tooth(size, frac=FRAC, bg=GREEN):
    S = size * 4
    c = Image.new('RGBA', (S, S), bg + (255,) if bg else (0, 0, 0, 0))
    tw = int(S * frac); th = int(tw * H / W)
    c.paste(Image.new('RGBA', (tw, th), (255, 255, 255, 255)), ((S - tw) // 2, (S - th) // 2), big.resize((tw, th), Image.LANCZOS))
    return c.resize((size, size), Image.LANCZOS)

tooth(1024).convert('RGB').save('ios/AIDentist/Assets.xcassets/AppIcon.appiconset/icon-1024.png')
tooth(256).save('shared/launcher/icon.png')
res = 'android/app/src/main/res'
for d, s in dict(mdpi=48, hdpi=72, xhdpi=96, xxhdpi=144, xxxhdpi=192).items():
    os.makedirs(f'{res}/mipmap-{d}', exist_ok=True)
    tooth(s).save(f'{res}/mipmap-{d}/ic_launcher.png')
    t = tooth(s * 4); m = Image.new('L', t.size, 0); ImageDraw.Draw(m).ellipse((0, 0, t.width - 1, t.height - 1), fill=255)
    r = Image.new('RGBA', t.size, (0, 0, 0, 0)); r.paste(t, (0, 0), m); r.resize((s, s), Image.LANCZOS).save(f'{res}/mipmap-{d}/ic_launcher_round.png')
    tooth(int(s * 108 / 48), 0.40, bg=None).save(f'{res}/mipmap-{d}/ic_launcher_foreground.png')
