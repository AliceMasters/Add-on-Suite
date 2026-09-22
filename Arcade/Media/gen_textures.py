#!/usr/bin/env python3
"""Generate rounded-rectangle TGAs for the 9-slice UI (white; tinted at runtime).
   roundfill.tga  = filled rounded rect (soft edge)
   roundline.tga  = rounded rect outline (for borders)
   roundglow.tga  = filled rounded rect, softer, for the outer 'pop' glow
Run:  python gen_textures.py   (writes the .tga files next to this script)
"""
import os, struct

SIZE = 64
RADIUS = 14
THICK = 3
SS = 3   # supersample for smooth edges

def inside(px, py, radius, inset):
    lo, hi = inset, SIZE - inset
    if px < lo or px > hi or py < lo or py > hi:
        return False
    r = radius
    dx = 0.0; dy = 0.0
    if px < lo + r: dx = (lo + r) - px
    elif px > hi - r: dx = px - (hi - r)
    if py < lo + r: dy = (lo + r) - py
    elif py > hi - r: dy = py - (hi - r)
    return dx * dx + dy * dy <= r * r

def coverage(x, y, radius, inset):
    hits = 0
    for sx in range(SS):
        for sy in range(SS):
            px = x + (sx + 0.5) / SS
            py = y + (sy + 0.5) / SS
            if inside(px, py, radius, inset):
                hits += 1
    return int(255 * hits / (SS * SS))

def alpha_fill(x, y):
    return coverage(x, y, RADIUS, 0)

def alpha_line(x, y):
    outer = coverage(x, y, RADIUS, 0)
    inner = coverage(x, y, RADIUS - THICK, THICK)
    return max(0, outer - inner)

def alpha_glow(x, y):
    return coverage(x, y, RADIUS, 0)

def write_tga(path, fn):
    # 18-byte header: uncompressed true-color, 32bpp, top-left origin
    hdr = bytes([0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0]) + \
        struct.pack("<HH", SIZE, SIZE) + bytes([32, 0x28])
    data = bytearray()
    for y in range(SIZE):
        for x in range(SIZE):
            a = fn(x, y)
            data += bytes([255, 255, 255, a])   # BGRA, white
    with open(path, "wb") as f:
        f.write(hdr); f.write(data)
    print(f"wrote {os.path.basename(path)} ({18 + SIZE*SIZE*4} bytes)")

here = os.path.dirname(os.path.abspath(__file__))
write_tga(os.path.join(here, "roundfill.tga"), alpha_fill)
write_tga(os.path.join(here, "roundline.tga"), alpha_line)
write_tga(os.path.join(here, "roundglow.tga"), alpha_glow)
