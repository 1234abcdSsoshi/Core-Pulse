"""Generate all shop/weapon/turret/item icons for Twin Core Blasters.
Dark space sci-fi aesthetic: metallic circular frames, colour-coded glows.
"""
from PIL import Image, ImageDraw, ImageFilter
import math
import os

BASE = r"C:\Users\zongs\Development\twin-core-blasters-1.0\assets"

S = 128
cx = cy = S // 2


# ─────────────────────────────────────── helpers ────────────────────────────

def new(size=S):
    return Image.new("RGBA", (size, size), (0, 0, 0, 0))


def over(base, layer):
    return Image.alpha_composite(base, layer)


def glow(img, pos, col, r=20, strength=180):
    g = new(img.width)
    d = ImageDraw.Draw(g)
    px, py = pos
    for ri in range(r, 0, -1):
        t = (1 - ri / r) ** 1.4
        a = int(t * strength)
        d.ellipse([px - ri, py - ri, px + ri, py + ri], fill=(*col, a))
    g = g.filter(ImageFilter.GaussianBlur(3))
    return over(img, g)


def metal_circle(img, col, r=50, ring=10):
    """Dark metallic disc with coloured rim glow."""
    # outer glow halo
    h = new()
    hd = ImageDraw.Draw(h)
    for ri in range(r + 14, r - 2, -1):
        t = (ri - (r - 2)) / 16
        a = int(t * 55)
        hd.ellipse([cx - ri, cy - ri, cx + ri, cy + ri], fill=(*col, a))
    h = h.filter(ImageFilter.GaussianBlur(5))
    img = over(img, h)
    d = ImageDraw.Draw(img)
    # dark plate
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(10, 13, 22, 252))
    # coloured ring
    for i in range(ring, 0, -1):
        t = i / ring
        ri = r - ring + i
        a = int(t * 210)
        col_t = tuple(int(c * (0.4 + 0.6 * t)) for c in col)
        d.ellipse([cx - ri, cy - ri, cx + ri, cy + ri], outline=(*col_t, a), width=1)
    # subtle inner radial gradient
    inner = r - ring
    for ri in range(inner, 2, -4):
        t = 1 - ri / inner
        a = int(t * 16)
        d.ellipse([cx - ri, cy - ri, cx + ri, cy + ri],
                  fill=(col[0] // 6, col[1] // 6, col[2] // 6, a))
    return img


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, "PNG")
    print("  saved:", path)


# ─────────────────────────────────────── crystal (64x64) ────────────────────

def make_item_crystal():
    size = 64
    c = size // 2
    ACC = (0, 220, 255)
    DARK = (0, 60, 130)

    img = new(size)
    img = glow(img, (c, c), ACC, 26, 120)

    d = ImageDraw.Draw(img)
    # 6-sided gem polygon
    verts = [
        (c,      c - 24),  # top
        (c + 14, c - 8),   # upper-right
        (c + 14, c + 10),  # lower-right
        (c,      c + 24),  # bottom
        (c - 14, c + 10),  # lower-left
        (c - 14, c - 8),   # upper-left
    ]
    # dark fill
    d.polygon(verts, fill=(*DARK, 255))
    # bright upper face
    top_face = [verts[0], verts[1], verts[5]]
    d.polygon(top_face, fill=(*ACC, 200))
    # right face mid-tone
    right_face = [verts[1], verts[2], verts[3], verts[0]]
    d.polygon(right_face, fill=(0, 160, 210, 180))
    # white sparkle at top
    d.polygon([(c - 3, c - 22), (c, c - 26), (c + 3, c - 22), (c, c - 18)],
              fill=(255, 255, 255, 230))
    # outline
    d.polygon(verts, outline=(160, 240, 255, 200), width=1)

    img = glow(img, (c, c - 6), ACC, 10, 90)
    return img


# ─────────────────────────────────────── weapons ────────────────────────────

def make_weapon_side_cannon():
    ACC = (0, 170, 255)
    img = new()
    img = metal_circle(img, ACC)
    d = ImageDraw.Draw(img)

    # centre barrel
    d.rectangle([cx - 5, cy - 36, cx + 5, cy + 28], fill=(*ACC, 225))
    d.rectangle([cx - 7, cy - 6, cx + 7, cy + 28],  fill=(*ACC, 170))
    # left barrel
    d.rectangle([cx - 28, cy - 22, cx - 15, cy + 16], fill=(*ACC, 165))
    d.rectangle([cx - 28, cy - 26, cx - 13, cy - 18], fill=(*ACC, 215))
    # right barrel
    d.rectangle([cx + 15, cy - 22, cx + 28, cy + 16], fill=(*ACC, 165))
    d.rectangle([cx + 13, cy - 26, cx + 28, cy - 18], fill=(*ACC, 215))
    # muzzle tips (bright)
    d.rectangle([cx - 6, cy - 40, cx + 6, cy - 34], fill=(200, 235, 255, 235))
    d.rectangle([cx - 29, cy - 30, cx - 12, cy - 22], fill=(180, 220, 255, 205))
    d.rectangle([cx + 12, cy - 30, cx + 29, cy - 22], fill=(180, 220, 255, 205))
    # base mount
    d.rectangle([cx - 20, cy + 28, cx + 20, cy + 40], fill=(*ACC, 165))

    img = glow(img, (cx, cy - 4), ACC, 14, 160)
    return img


def make_weapon_spread_shot():
    ACC = (175, 60, 255)
    img = new()
    img = metal_circle(img, ACC)
    d = ImageDraw.Draw(img)

    # 3 bullets fanning at -30°, 0°, +30°
    for ang_deg in [-30, 0, 30]:
        rad = math.radians(ang_deg)
        ca, sa = math.cos(rad), math.sin(rad)
        bw, bh = 7, 26
        corners = [(-bw/2, -bh/2), (bw/2, -bh/2), (bw/2, bh/2), (-bw/2, bh/2)]
        pts = [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in corners]
        # glow pass
        gl = new()
        gd = ImageDraw.Draw(gl)
        gd.polygon(pts, fill=(*ACC, 90))
        gl = gl.filter(ImageFilter.GaussianBlur(5))
        img = over(img, gl)
        d2 = ImageDraw.Draw(img)
        d2.polygon(pts, fill=(*ACC, 215))
        # nose cap
        nose = [(-bw/2, -bh/2), (bw/2, -bh/2), (0, -bh/2 - 10)]
        nose_pts = [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in nose]
        d2.polygon(nose_pts, fill=(225, 185, 255, 235))
        # highlight stripe
        stripe = [(-1, -bh/2), (1, -bh/2), (1, bh/2), (-1, bh/2)]
        st_pts = [(cx + x * ca - y * sa, cy + x * sa + y * ca) for x, y in stripe]
        d2.polygon(st_pts, fill=(255, 255, 255, 165))

    img = glow(img, (cx, cy - 8), ACC, 18, 140)
    return img


def make_weapon_homing_missile():
    ACC = (255, 140, 0)
    img = new()
    img = metal_circle(img, ACC)
    d = ImageDraw.Draw(img)

    # missile body
    mw, mh = 12, 36
    d.rectangle([cx - mw//2, cy - mh//2, cx + mw//2, cy + mh//2],
                fill=(*ACC, 230))
    # nose
    d.polygon([(cx - mw//2, cy - mh//2),
               (cx + mw//2, cy - mh//2),
               (cx, cy - mh//2 - 14)],
              fill=(255, 220, 90, 245))
    # fins
    for sx in [-1, 1]:
        fin = [(cx + sx * mw//2, cy + mh//4),
               (cx + sx * (mw//2 + 12), cy + mh//2 + 6),
               (cx + sx * mw//2, cy + mh//2)]
        d.polygon(fin, fill=(200, 95, 0, 225))
    # exhaust
    d.polygon([(cx - 5, cy + mh//2), (cx + 5, cy + mh//2),
               (cx + 2, cy + mh//2 + 14), (cx - 2, cy + mh//2 + 14)],
              fill=(255, 80, 0, 155))
    # tracking arcs
    for ri in [28, 33, 38]:
        d.arc([cx - ri, cy - ri, cx + ri, cy + ri],
              start=-55, end=55, fill=(*ACC, 45 + ri * 2), width=2)
    # arrowhead on outermost arc
    tip_x = int(cx + 38 * math.cos(math.radians(0)))
    tip_y = int(cy + 38 * math.sin(math.radians(0)))
    d.polygon([(tip_x + 8, tip_y),
               (tip_x, tip_y - 6),
               (tip_x, tip_y + 6)],
              fill=(*ACC, 210))
    # highlight
    d.rectangle([cx - 2, cy - mh//2, cx + 2, cy + mh//2],
                fill=(255, 255, 255, 165))
    img = glow(img, (cx, cy - 20), (255, 200, 50), 14, 200)
    return img


def make_weapon_twin_laser():
    ACC = (0, 255, 200)
    img = new()
    img = metal_circle(img, ACC)

    gap = 14
    bw, bh = 6, 44
    for sx in [-1, 1]:
        bx = cx + sx * gap // 2
        # beam glow
        bl = new()
        bld = ImageDraw.Draw(bl)
        bld.rectangle([bx - bw - 5, cy - bh//2 - 5, bx + bw + 5, cy + bh//2 + 5],
                      fill=(*ACC, 50))
        bl = bl.filter(ImageFilter.GaussianBlur(6))
        img = over(img, bl)
        d2 = ImageDraw.Draw(img)
        d2.rectangle([bx - bw//2, cy - bh//2, bx + bw//2, cy + bh//2],
                     fill=(*ACC, 225))
        d2.rectangle([bx - 1, cy - bh//2, bx + 1, cy + bh//2],
                     fill=(255, 255, 255, 195))
        # cap glows
        img = glow(img, (bx, cy - bh//2), ACC, 8, 130)
        img = glow(img, (bx, cy + bh//2), ACC, 8, 130)

    d3 = ImageDraw.Draw(img)
    d3.rectangle([cx - gap//2, cy + bh//4, cx + gap//2, cy + bh//2 + 8],
                 fill=(*ACC, 145))
    d3.rectangle([cx - gap - 4, cy + bh//2, cx + gap + 4, cy + bh//2 + 12],
                 fill=(*ACC, 155))
    img = glow(img, (cx, cy), ACC, 16, 100)
    return img


# ─────────────────────────────────────── turrets ────────────────────────────

def make_turret_auto_cannon():
    ACC = (80, 150, 220)
    img = new()
    img = metal_circle(img, ACC)
    d = ImageDraw.Draw(img)

    # base trapezoid
    base = [(cx - 20, cy + 18), (cx + 20, cy + 18),
            (cx + 14, cy + 30), (cx - 14, cy + 30)]
    d.polygon(base, fill=(40, 65, 110, 240))
    d.polygon(base, outline=(*ACC, 200))
    # rotary body
    d.ellipse([cx - 18, cy - 2, cx + 18, cy + 24], fill=(25, 50, 100, 238))
    d.ellipse([cx - 12, cy + 2, cx + 12, cy + 20], fill=(*ACC, 148))
    # barrel
    d.rectangle([cx - 6, cy - 38, cx + 6, cy + 4], fill=(*ACC, 238))
    d.rectangle([cx - 8, cy - 42, cx + 8, cy - 32], fill=(160, 200, 255, 245))
    # muzzle ring
    d.ellipse([cx - 9, cy - 46, cx + 9, cy - 34], fill=(200, 225, 255, 185))
    # fired bullet
    d.ellipse([cx - 4, cy - 54, cx + 4, cy - 46], fill=(255, 255, 200, 235))
    # highlight on barrel
    d.rectangle([cx - 1, cy - 38, cx + 1, cy + 4], fill=(255, 255, 255, 120))

    img = glow(img, (cx, cy - 42), (160, 210, 255), 10, 195)
    return img


def make_turret_laser_tower():
    ACC = (255, 30, 60)
    img = new()
    img = metal_circle(img, ACC)
    d = ImageDraw.Draw(img)

    # tower stand
    d.rectangle([cx - 14, cy + 24, cx + 14, cy + 38], fill=(*ACC, 188))
    d.rectangle([cx - 18, cy + 34, cx + 18, cy + 42], fill=(*ACC, 168))
    # tower body
    d.rectangle([cx - 9, cy - 20, cx + 9, cy + 26], fill=(50, 14, 22, 228))
    d.rectangle([cx - 6, cy - 22, cx + 6, cy + 24], fill=(*ACC, 138))
    # emitter dome
    d.ellipse([cx - 14, cy - 38, cx + 14, cy - 12], fill=(70, 14, 22, 238))
    d.ellipse([cx - 10, cy - 35, cx + 10, cy - 15], fill=(*ACC, 162))
    d.ellipse([cx - 6,  cy - 32, cx + 6,  cy - 18], fill=(255, 185, 195, 228))
    # laser beams (5 rays)
    for ang_deg in [0, 72, 144, 216, 288]:
        rad = math.radians(ang_deg - 90)
        ex = int(cx + 46 * math.cos(rad))
        ey = int(cy - 25 + 46 * math.sin(rad))
        bl = new()
        bld = ImageDraw.Draw(bl)
        bld.line([(cx, cy - 25), (ex, ey)], fill=(*ACC, 155), width=4)
        bl = bl.filter(ImageFilter.GaussianBlur(3))
        img = over(img, bl)
        d2 = ImageDraw.Draw(img)
        d2.line([(cx, cy - 25), (ex, ey)], fill=(*ACC, 225), width=2)

    img = glow(img, (cx, cy - 25), ACC, 18, 210)
    return img


def make_turret_missile_pod():
    ACC = (255, 100, 20)
    img = new()
    img = metal_circle(img, ACC)
    d = ImageDraw.Draw(img)

    # pod housing
    d.ellipse([cx - 22, cy - 8, cx + 22, cy + 30], fill=(42, 20, 6, 238))
    d.ellipse([cx - 18, cy - 4, cx + 18, cy + 26], fill=(*ACC, 108))
    # 3 missiles
    for mx, my in [(-12, 0), (0, -6), (12, 0)]:
        bx, by = cx + mx, cy + my
        d.rectangle([bx - 4, by - 24, bx + 4, by + 18], fill=(*ACC, 235))
        d.polygon([(bx, by - 36), (bx - 4, by - 24), (bx + 4, by - 24)],
                  fill=(255, 200, 95, 240))
        for sx2 in [-1, 1]:
            d.polygon([(bx + sx2 * 4, by + 12),
                       (bx + sx2 * 11, by + 24),
                       (bx + sx2 * 4, by + 18)],
                      fill=(200, 68, 0, 215))
        d.ellipse([bx - 3, by + 17, bx + 3, by + 27], fill=(255, 160, 38, 162))
    img = glow(img, (cx, cy), (255, 160, 40), 18, 148)
    return img


def make_turret_shield_wall():
    ACC = (60, 140, 255)
    img = new()
    img = metal_circle(img, ACC)

    # shield arc (thick polygon)
    sr = 34
    tk = 10
    a_start, a_end = 200, 340
    outer_pts = []
    inner_pts = []
    for a in range(a_start, a_end + 1, 3):
        rad = math.radians(a)
        outer_pts.append((cx + (sr + tk/2) * math.cos(rad),
                          cy + (sr + tk/2) * math.sin(rad)))
        inner_pts.append((cx + (sr - tk/2) * math.cos(rad),
                          cy + (sr - tk/2) * math.sin(rad)))
    arc_poly = outer_pts + list(reversed(inner_pts))

    # glow layer for arc
    gl = new()
    gld = ImageDraw.Draw(gl)
    gld.polygon(arc_poly, fill=(*ACC, 95))
    gl = gl.filter(ImageFilter.GaussianBlur(6))
    img = over(img, gl)

    d = ImageDraw.Draw(img)
    d.polygon(arc_poly, fill=(*ACC, 205), outline=(255, 255, 255, 185))

    # inner fill
    inner_fill = inner_pts + [(cx, cy)]
    gf = new()
    gfd = ImageDraw.Draw(gf)
    gfd.polygon(inner_fill, fill=(*ACC, 35))
    gf = gf.filter(ImageFilter.GaussianBlur(4))
    img = over(img, gf)

    d2 = ImageDraw.Draw(img)
    # base stand
    d2.rectangle([cx - 6, cy + 16, cx + 6, cy + 40], fill=(*ACC, 208))
    d2.rectangle([cx - 14, cy + 36, cx + 14, cy + 44], fill=(*ACC, 188))
    # energy nodes at arc ends + mid
    for ang in [200, 270, 340]:
        rad = math.radians(ang)
        ex = int(cx + sr * math.cos(rad))
        ey = int(cy + sr * math.sin(rad))
        d2.ellipse([ex - 5, ey - 5, ex + 5, ey + 5], fill=(200, 230, 255, 235))

    img = glow(img, (cx, cy - 8), ACC, 26, 112)
    return img


# ─────────────────────────────────────── items ──────────────────────────────

def make_item_crystal_magnet():
    ACC = (220, 50, 255)
    CYN = (0, 220, 255)
    img = new()
    img = metal_circle(img, ACC)
    d = ImageDraw.Draw(img)

    # U-magnet body
    aw = 11
    d.rectangle([cx - 26, cy - 28, cx - 15, cy + 22], fill=(*ACC, 225))
    d.rectangle([cx + 15, cy - 28, cx + 26, cy + 22], fill=(*ACC, 225))
    d.rectangle([cx - 26, cy + 14, cx + 26, cy + 26], fill=(*ACC, 208))
    # dark notch between arms
    d.rectangle([cx - 14, cy - 28, cx + 14, cy + 26], fill=(10, 13, 22, 252))
    # pole tips
    d.rectangle([cx - 26, cy - 36, cx - 15, cy - 26], fill=(55, 0, 115, 238))
    d.rectangle([cx + 15, cy - 36, cx + 26, cy - 26], fill=(115, 0, 55, 238))
    d.rectangle([cx - 26, cy - 44, cx - 15, cy - 34], fill=(215, 158, 255, 225))
    d.rectangle([cx + 15, cy - 44, cx + 26, cy - 34], fill=(255, 158, 215, 225))

    # attracted crystals (4 small diamonds around magnet)
    for kx, ky in [(-40, -20), (40, -20), (-42, 8), (42, 8)]:
        px, py = cx + kx, cy + ky
        pts = [(px, py - 7), (px - 4, py), (px, py + 7), (px + 4, py)]
        cgl = new()
        cgd = ImageDraw.Draw(cgl)
        cgd.polygon(pts, fill=(*CYN, 120))
        cgl = cgl.filter(ImageFilter.GaussianBlur(4))
        img = over(img, cgl)
        d3 = ImageDraw.Draw(img)
        d3.polygon(pts, fill=(*CYN, 218))
        # dotted attraction line
        ex2 = cx - 18 if kx < 0 else cx + 18
        d3.line([(ex2, cy - 4), (px, py)], fill=(*CYN, 72), width=1)

    img = glow(img, (cx, cy - 6), ACC, 14, 128)
    return img


def make_item_emp_burst():
    ACC = (255, 230, 0)
    img = new()
    img = metal_circle(img, ACC)

    # central bolt glow pass
    bolt_pts = [
        (cx + 6,  cy - 38),
        (cx - 4,  cy - 4),
        (cx + 8,  cy - 4),
        (cx - 8,  cy + 38),
        (cx + 4,  cy + 4),
        (cx - 8,  cy + 4),
        (cx + 8,  cy - 38),
    ]
    gl = new()
    gld = ImageDraw.Draw(gl)
    gld.polygon(bolt_pts, fill=(*ACC, 145))
    gl = gl.filter(ImageFilter.GaussianBlur(7))
    img = over(img, gl)

    d = ImageDraw.Draw(img)
    d.polygon(bolt_pts, fill=(*ACC, 235))
    d.polygon(bolt_pts, outline=(255, 255, 190, 205), width=1)

    # radial burst lines (8 directions)
    for i in range(8):
        ang = math.radians(i * 45)
        r1 = 14
        r2 = 42 + (10 if i % 2 == 0 else 0)
        sx2, sy = int(cx + r1 * math.cos(ang)), int(cy + r1 * math.sin(ang))
        ex2, ey = int(cx + r2 * math.cos(ang)), int(cy + r2 * math.sin(ang))
        lw = 3 if i % 2 == 0 else 2
        la = 215 if i % 2 == 0 else 138
        bl = new()
        bld = ImageDraw.Draw(bl)
        bld.line([(sx2, sy), (ex2, ey)], fill=(*ACC, la), width=lw + 3)
        bl = bl.filter(ImageFilter.GaussianBlur(3))
        img = over(img, bl)
        d2 = ImageDraw.Draw(img)
        d2.line([(sx2, sy), (ex2, ey)], fill=(*ACC, la), width=lw)
        d2.ellipse([ex2 - 3, ey - 3, ex2 + 3, ey + 3], fill=(255, 255, 200, 188))

    img = glow(img, (cx, cy), (255, 240, 80), 22, 192)
    return img


# ─────────────────────────────────────── HUD icon (48x48) ───────────────────

def make_ui_shop_icon():
    SIZE2 = 48
    c = SIZE2 // 2
    ACC = (60, 200, 255)
    GOLD = (255, 200, 40)
    img = new(SIZE2)

    # bg halo
    h = new(SIZE2)
    hd = ImageDraw.Draw(h)
    for ri in range(22, 0, -1):
        t = ri / 22
        hd.ellipse([c - ri, c - ri, c + ri, c + ri], fill=(*ACC, int(t * 48)))
    h = h.filter(ImageFilter.GaussianBlur(3))
    img = over(img, h)

    # dark bg circle
    d = ImageDraw.Draw(img)
    d.ellipse([c - 20, c - 20, c + 20, c + 20], fill=(10, 13, 26, 238))
    d.ellipse([c - 20, c - 20, c + 20, c + 20], outline=(*ACC, 188), width=2)

    # shopping bag
    d.rounded_rectangle([c - 10, c - 5, c + 10, c + 13],
                        radius=3, fill=(28, 28, 40, 245),
                        outline=(*GOLD, 225))
    # bag handle arc
    hpts = []
    for a in range(180, 361, 8):
        rad = math.radians(a)
        hpts.append((c + 6 * math.cos(rad), c - 5 + 6 * math.sin(rad)))
    if len(hpts) > 1:
        d.line(hpts, fill=(*GOLD, 235), width=2)
    # sparkle cross on bag
    d.line([(c - 3, c + 4), (c + 3, c + 4)], fill=(*ACC, 205), width=1)
    d.line([(c, c + 1), (c, c + 7)],          fill=(*ACC, 205), width=1)

    return img


# ─────────────────────────────────────── run ────────────────────────────────

created, failed = [], []


def try_save(fn, rel_path):
    path = os.path.join(BASE, rel_path)
    try:
        img = fn()
        save(img, path)
        created.append(path)
    except Exception as exc:
        print(f"  FAILED {path}: {exc}")
        failed.append((path, str(exc)))


try_save(make_item_crystal,          "items/item_crystal.png")
try_save(make_weapon_side_cannon,    "weapons/weapon_side_cannon.png")
try_save(make_weapon_spread_shot,    "weapons/weapon_spread_shot.png")
try_save(make_weapon_homing_missile, "weapons/weapon_homing_missile.png")
try_save(make_weapon_twin_laser,     "weapons/weapon_twin_laser.png")
try_save(make_turret_auto_cannon,    "turrets/turret_auto_cannon.png")
try_save(make_turret_laser_tower,    "turrets/turret_laser_tower.png")
try_save(make_turret_missile_pod,    "turrets/turret_missile_pod.png")
try_save(make_turret_shield_wall,    "turrets/turret_shield_wall.png")
try_save(make_item_crystal_magnet,   "items/item_crystal_magnet.png")
try_save(make_item_emp_burst,        "items/item_emp_burst.png")
try_save(make_ui_shop_icon,          "ui/ui_shop_icon.png")

print(f"\n=== {len(created)} created, {len(failed)} failed ===")
for path, err in failed:
    print(f"  FAIL: {path}  —  {err}")
