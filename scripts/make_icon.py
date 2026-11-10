# Draws the GrudgeForever icon (two crossed swords on a steel badge) as an uncompressed TGA.
# Usage: python3 scripts/make_icon.py Media/icon.tga [size]  (default 64; 512 for the CurseForge logo)
import math, struct, sys

N = int(sys.argv[2]) if len(sys.argv) > 2 else 64
SS = 4 if N <= 64 else 2  # supersampling per axis
SCALE = 64 / N            # the shapes below are drawn on a 64x64 grid

GOLD, RIM = (205, 165, 70), (18, 18, 20)


def circ(x, y, cx, cy, r):
    return (x - cx) ** 2 + (y - cy) ** 2 <= r * r


def poly(x, y, pts):
    inside, j = False, len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def rot(x, y, cx, cy, deg):
    a = math.radians(deg)
    dx, dy = x - cx, y - cy
    return cx + dx * math.cos(a) + dy * math.sin(a), cy - dx * math.sin(a) + dy * math.cos(a)


def grad(y, top, bottom, y0=4, y1=60):
    t = max(0.0, min(1.0, (y - y0) / (y1 - y0)))
    return tuple(int(a + (b - a) * t) for a, b in zip(top, bottom))


def sword(x, y, deg):
    u, v = rot(x, y, 32, 31, deg)
    if poly(u, v, [(32, 6), (34.6, 11), (34.6, 40), (29.4, 40), (29.4, 11)]):  # blade, lit from the left
        return (225, 230, 236) if u < 32 else (160, 168, 180)
    if abs(v - 41.5) <= 1.6 and abs(u - 32) <= 7.5:  # guard
        return GOLD
    if 43 <= v <= 51 and abs(u - 32) <= 1.9:  # grip
        return (110, 62, 32)
    if circ(u, v, 32, 53, 2.6):  # pommel
        return GOLD
    return None


def sample(x, y):
    if not circ(x, y, 32, 32, 31):
        return None  # transparent outside the badge
    if not circ(x, y, 32, 32, 28):
        return RIM
    if not circ(x, y, 32, 32, 26):
        return GOLD
    return sword(x, y, 38) or sword(x, y, -38) or grad(y, (70, 82, 100), (30, 36, 48))


with open(sys.argv[1], "wb") as f:
    # 32-bit TGA, top-left origin (descriptor bit 5) with 8 alpha bits
    f.write(struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, N, N, 32, 0x28))
    for py in range(N):
        for px in range(N):
            r = g = b = a = 0
            for sy in range(SS):
                for sx in range(SS):
                    c = sample((px + (sx + 0.5) / SS) * SCALE, (py + (sy + 0.5) / SS) * SCALE)
                    if c:
                        r += c[0]; g += c[1]; b += c[2]; a += 1
            f.write(bytes((b // a if a else 0, g // a if a else 0, r // a if a else 0, 255 * a // (SS * SS))))
