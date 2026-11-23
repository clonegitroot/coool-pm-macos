#!/usr/bin/env python3
"""Render the installer artwork at 1x/2x without embedding source metadata."""
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

output = Path(sys.argv[1])
output.mkdir(parents=True, exist_ok=True)
for scale in (1, 2):
    width, height = 760 * scale, 520 * scale
    image = Image.new('RGB', (width, height))
    draw = ImageDraw.Draw(image)
    for y in range(height):
        t = y / max(1, height - 1)
        color = tuple(round(a + (b-a)*t) for a,b in zip((248,250,248),(235,243,237)))
        draw.line((0,y,width,y), fill=color)
    def box(value): return tuple(round(v*scale) for v in value)
    def font(size, bold=False):
        path = '/System/Library/Fonts/Supplemental/Arial' + (' Bold' if bold else '') + '.ttf'
        return ImageFont.truetype(path, round(size*scale))
    ink, green, muted = '#183b2e', '#27705a', '#61776b'
    def text(x,y,value,size,color=ink,bold=False,anchor=None):
        draw.text((x*scale,y*scale),value,font=font(size,bold),fill=color,anchor=anchor)
    text(48,32,'Coool PM',40,bold=True)
    text(49,89,'A calmer home for creative projects.',17,color=muted)
    draw.line(box((48,137,712,137)),fill='#d7e4dc',width=scale)
    shadow = Image.new('RGBA',(width,height))
    sd = ImageDraw.Draw(shadow)
    for x in (120,460):
        sd.rounded_rectangle(box((x,180,x+180,352)),radius=25*scale,fill=(31,75,48,16))
    shadow = shadow.filter(ImageFilter.GaussianBlur(10*scale))
    image = Image.alpha_composite(image.convert('RGBA'),shadow).convert('RGB')
    draw = ImageDraw.Draw(image)
    for x in (120,460):
        draw.rounded_rectangle(box((x,174,x+180,346)),radius=24*scale,fill='#ffffff',outline='#d8e5dc',width=scale)
    draw.line(box((350,250,409,250)),fill=green,width=3*scale)
    draw.line(box((393,234,409,250,393,266)),fill=green,width=3*scale,joint='curve')
    text(380,282,'drag',12,color=muted,anchor='mt')
    text(380,380,'Drag Coool PM into Applications.',22,bold=True,anchor='mt')
    text(380,416,'Then open it from your Applications folder.',15,color=muted,anchor='mt')
    text(380,458,'First launch blocked? Privacy & Security → Open Anyway.',13,color=ink,anchor='mt')
    text(380,493,'APPLE SILICON  ·  macOS 14+  ·  TESTER BUILD',11,color=muted,anchor='mt')
    name = 'background.png' if scale == 1 else 'background@2x.png'
    image.save(output/name,format='PNG')
