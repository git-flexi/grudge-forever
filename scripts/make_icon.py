# Draws the skull-on-a-red-badge icon as an uncompressed TGA.
# Usage: python3 scripts/make_icon.py Media/icon.tga [size]  (default 64; 512 for the CurseForge logo)
import math, struct, sys
N = int(sys.argv[2]) if len(sys.argv) > 2 else 64; SS = 4 if N <= 64 else 2
SCALE = 64 / N  # the shapes below are drawn on a 64x64 grid
def inside_circle(x, y, cx, cy, r): return (x-cx)**2 + (y-cy)**2 <= r*r
def inside_ellipse(x, y, cx, cy, rx, ry): return ((x-cx)/rx)**2 + ((y-cy)/ry)**2 <= 1
def inside_tri(x, y, a, b, c):
    def s(p, q, r): return (p[0]-r[0])*(q[1]-r[1]) - (q[0]-r[0])*(p[1]-r[1])
    d1, d2, d3 = s((x,y),a,b), s((x,y),b,c), s((x,y),c,a)
    return not ((d1<0 or d2<0 or d3<0) and (d1>0 or d2>0 or d3>0))
def sample(x, y):
    # outside the badge: transparent
    if not inside_circle(x, y, 32, 32, 31): return None
    if not inside_circle(x, y, 32, 32, 28): return (20, 20, 20)        # dark rim
    if not inside_circle(x, y, 32, 32, 26): return (200, 160, 60)      # gold ring
    t = max(0.0, min(1.0, (y - 6) / 52)); col = (int(195 - 60*t), int(32 - 16*t), int(32 - 16*t))  # red field, lighter top
    skull = inside_ellipse(x, y, 32, 28, 15, 14) or (abs(x-32) <= 9 and 34 <= y <= 47)
    if skull:
        col = (240, 236, 225)
        if inside_ellipse(x, y, 26, 30, 4.6, 5.2) or inside_ellipse(x, y, 38, 30, 4.6, 5.2): col = (25, 10, 10)
        if inside_tri(x, y, (32, 34), (29.5, 39), (34.5, 39)): col = (25, 10, 10)
        if y >= 42 and abs(x-32) <= 9 and (int(x) - 23) % 4 == 0: col = (60, 50, 45)   # teeth gaps
    return col
pix = []
for py in range(N):
    for px in range(N):
        r = g = b = a = 0
        for sy in range(SS):
            for sx in range(SS):
                c = sample((px + (sx+.5)/SS) * SCALE, (py + (sy+.5)/SS) * SCALE)
                if c: r += c[0]; g += c[1]; b += c[2]; a += 1
        n = SS*SS
        pix.append((r//a if a else 0, g//a if a else 0, b//a if a else 0, 255*a//n))
out = sys.argv[1]
with open(out, "wb") as f:
    # uncompressed 32-bit TGA, top-left origin (descriptor bit 5) with 8 alpha bits
    f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 0x28))
    for r, g, b, a in pix: f.write(bytes((b, g, r, a)))
