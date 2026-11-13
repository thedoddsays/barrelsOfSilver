"""Build the sloop model (hull, deck, guns, mast, bowsprit, standing rigging) and export it
as a .glb for Godot. Everything is generated from the numbers below: no external assets.

Run (Blender 4.2+ / 5.x):
    blender --background --factory-startup --python tools/blender/build_sloop.py -- \
        assets/ships/sloop/sloop.glb [preview_dir]

Coordinates: all geometry is written in GODOT ship-local space (x = starboard, y = up,
z = aft; the bow points to -z) and converted to Blender's Z-up on the way in, so the
exported glTF lands in Godot exactly where ship.gd expects it.

Must match ship.gd / data/ships/sloop.tres: length 16 m (bow z = -10, stern z = +6),
beam 4.6 m, deck at y = 1.1 amidships, waterline about y = -0.42, mast at z = -0.1 L = -1.6,
mast 0.8 L = 12.8 m above the deck, 5 guns a side from z = -4.0 to +3.52.

Sails, booms, gaffs and the flag are NOT in the model: ship.gd builds them because they
animate. The model carries marker empties for them (mast_0, mast_0_head, jib_tack,
jib_head, flag, gun_0..gun_4 = starboard muzzles, bow to stern).
"""
import math
import os
import sys
import tempfile

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = os.path.abspath(argv[0] if argv else "sloop.glb")
PREVIEW = os.path.abspath(argv[1]) if len(argv) > 1 else ""

# ---------------------------------------------------------------------------
# Hull lines (metres, Godot space)
# ---------------------------------------------------------------------------
KEEL = -1.75            # bottom of the planking (keel box hangs below)
HALF_BEAM = 2.3
MAX_BEAM_Z = -1.5       # widest point, a little forward of amidships
STEM_TOP_Z = -10.0
FOREFOOT_Z = -6.8       # where the curved stem meets the keel
POST_FOOT_Z = 5.4       # sternpost at the keel
TRANSOM_TOP_Z = 6.2     # transom raked aft
SHEER_MID = 1.75        # rail height at the lowest point of the sheer
SHEER_LOW_Z = -0.5
SHEER_BOW_RISE = 0.6
SHEER_STERN_RISE = 0.45
BULWARK = 0.65          # rail above deck
BOOT_TOP = -0.30        # top of the white bottom paint (waterline is about -0.42)
WALE = (0.65, 0.35)     # wale band, distance below the deck edge
TRANSOM_HALF = 0.62     # transom half-width as a fraction of the half-beam
TUMBLEHOME = 0.07
BULWARK_THICK = 0.12
CROWN = 0.07            # deck camber at the centreline

MAST_Z = -1.6
MAST_H = 12.8           # deck to truck
LOWER_MAST_H = 9.3      # deck to lower masthead (the gaff hangs just below)
TOPMAST_Z = MAST_Z - 0.38
GUN_Z = [-4.0, -2.12, -0.24, 1.64, 3.52]


def to_bl(p):
    return Vector((p[0], -p[2], p[1]))


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def sheer(z):
    if z < SHEER_LOW_Z:
        s = (z - SHEER_LOW_Z) / (STEM_TOP_Z - SHEER_LOW_Z)
        return SHEER_MID + SHEER_BOW_RISE * s * s
    s = (z - SHEER_LOW_Z) / (TRANSOM_TOP_Z - SHEER_LOW_Z)
    return SHEER_MID + SHEER_STERN_RISE * s * s


def deck(z):
    return sheer(z) - BULWARK


def deck_c(z):
    return deck(z) + CROWN


def z_fore(h):  # stem profile: a curved forefoot
    return FOREFOOT_Z + (STEM_TOP_Z - FOREFOOT_Z) * (1.0 - (1.0 - h) ** 2.2)


def z_aft(h):  # raked sternpost and transom
    return POST_FOOT_Z + (TRANSOM_TOP_Z - POST_FOOT_Z) * h


def half_breadth(h, z):
    """Half-width of the hull at normalised height h (0 keel, 1 rail) and position z."""
    if z <= MAX_BEAM_Z:
        s = min(max((z - MAX_BEAM_Z) / (z_fore(h) - MAX_BEAM_Z), 0.0), 1.0)
        plan = max(1.0 - s ** (1.6 + 0.8 * h), 0.0) ** 0.5  # bluff, rounded bow
    else:
        s = min(max((z - MAX_BEAM_Z) / (z_aft(h) - MAX_BEAM_Z), 0.0), 1.0)
        wt = 0.04 + (TRANSOM_HALF - 0.04) * smoothstep(0.15, 0.7, h)
        plan = 1.0 - (1.0 - wt) * s ** 2.2  # fine run aft into a transom
    hm = 0.6
    if h < hm:
        k = 1.5 + 1.7 * plan  # V-shaped sections at the ends, fuller amidships
        sec = 1.0 - (1.0 - h / hm) ** k
    else:
        sec = 1.0 - TUMBLEHOME * ((h - hm) / (1.0 - hm)) ** 1.5
    return max(0.1, HALF_BEAM * sec * plan)


def hull_x(y, z):
    h = min(max((y - KEEL) / (sheer(z) - KEEL), 0.0), 1.0)
    return half_breadth(h, z)


# Hull rows, keel to rail. Rows sit exactly on the paint-band edges so the bands are crisp;
# the wale and upper rows follow the sheer like real planking.
ROWS = []
for f in (0.0, 0.03, 0.08, 0.15, 0.24, 0.35, 0.48, 0.62, 0.76, 0.89, 1.0):
    ROWS.append(lambda z, f=f: KEEL + (BOOT_TOP - KEEL) * f)
for f in (1.0 / 3.0, 2.0 / 3.0):
    ROWS.append(lambda z, f=f: BOOT_TOP + ((deck(z) - WALE[0]) - BOOT_TOP) * f)
ROWS.append(lambda z: deck(z) - WALE[0])
ROWS.append(lambda z: deck(z) - WALE[1])
ROWS.append(lambda z: deck(z) - 0.17)
ROWS.append(lambda z: deck(z))
ROWS.append(lambda z: deck(z) + 0.33)
ROWS.append(lambda z: sheer(z))
DECK_ROW = 16

# Materials (index order)
BOTTOM, TOPSIDES, STRAKE, DECK, INNER, SPAR, WOOD, BLACK, IRON = range(9)


def row_mat(r):
    if r < 10:
        return BOTTOM
    if r == 13:
        return BLACK  # wale
    if r >= DECK_ROW:
        return STRAKE
    return TOPSIDES


# ---------------------------------------------------------------------------
# Mesh builder (Godot space)
# ---------------------------------------------------------------------------
class MB:
    def __init__(self):
        self.verts = []
        self.uvs = []
        self.faces = []

    def v(self, p, uv=(0.0, 0.0)):
        self.verts.append(Vector(p))
        self.uvs.append(uv)
        return len(self.verts) - 1

    def normal(self, idx):
        n = Vector((0.0, 0.0, 0.0))
        for i in range(len(idx)):
            a = self.verts[idx[i]]
            b = self.verts[idx[(i + 1) % len(idx)]]
            n.x += (a.y - b.y) * (a.z + b.z)
            n.y += (a.z - b.z) * (a.x + b.x)
            n.z += (a.x - b.x) * (a.y + b.y)
        return n

    def f(self, idx, mat, smooth=False, want=None):
        out = []
        for i in idx:
            if not out or out[-1] != i:
                out.append(i)
        if len(out) > 1 and out[0] == out[-1]:
            out.pop()
        if len(set(out)) < 3:
            return
        if want is not None and self.normal(out).dot(Vector(want)) < 0.0:
            out.reverse()
        self.faces.append((out, mat, smooth))


def box(mb, c, size, mat, basis=None):
    R = basis if basis is not None else Matrix.Identity(3)
    c = Vector(c)
    h = [size[0] / 2.0, size[1] / 2.0, size[2] / 2.0]
    for ax in range(3):
        a1, a2 = [i for i in range(3) if i != ax]
        for s in (-1.0, 1.0):
            idx = []
            for u, w in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                lp = Vector((0.0, 0.0, 0.0))
                lp[ax] = s * h[ax]
                lp[a1] = u * h[a1]
                lp[a2] = w * h[a2]
                idx.append(mb.v(c + R @ lp, (u * h[a1], w * h[a2])))
            n = Vector((0.0, 0.0, 0.0))
            n[ax] = s
            mb.f(idx, mat, False, R @ n)


def cyl(mb, p0, p1, r0, r1, mat, seg=8, caps=True):
    p0 = Vector(p0)
    p1 = Vector(p1)
    ax = p1 - p0
    if ax.length < 1e-6:
        return
    ax.normalize()
    t = ax.orthogonal().normalized()
    b = ax.cross(t)
    dirs = [t * math.cos(2 * math.pi * i / seg) + b * math.sin(2 * math.pi * i / seg) for i in range(seg)]
    r_0 = [mb.v(p0 + d * r0) for d in dirs]
    r_1 = [mb.v(p1 + d * r1) for d in dirs]
    for i in range(seg):
        j = (i + 1) % seg
        mb.f([r_0[i], r_0[j], r_1[j], r_1[i]], mat, True, dirs[i] + dirs[j])
    if caps:
        mb.f([mb.v(p0 + d * r0) for d in dirs], mat, False, -ax)
        mb.f([mb.v(p1 + d * r1) for d in dirs], mat, False, ax)


def prism(mb, pts_yz, half_t, mat, x=0.0):
    """Flat plate: polygon in (y, z), thickness 2 * half_t across x."""
    a = [mb.v((x - half_t, y, z), (z * 0.5, y * 0.5)) for y, z in pts_yz]
    b = [mb.v((x + half_t, y, z), (z * 0.5, y * 0.5)) for y, z in pts_yz]
    mb.f(a, mat, False, (-1, 0, 0))
    mb.f(b, mat, False, (1, 0, 0))
    cy = sum(p[0] for p in pts_yz) / len(pts_yz)
    cz = sum(p[1] for p in pts_yz) / len(pts_yz)
    n = len(pts_yz)
    for i in range(n):
        j = (i + 1) % n
        my = (pts_yz[i][0] + pts_yz[j][0]) * 0.5 - cy
        mz = (pts_yz[i][1] + pts_yz[j][1]) * 0.5 - cz
        mb.f([a[i], a[j], b[j], b[i]], mat, False, (0, my, mz))


# ---------------------------------------------------------------------------
# Hull, bulwarks and deck
# ---------------------------------------------------------------------------
def solve(rowf, t):
    z, h = 0.0, 0.5
    for _ in range(5):
        z = z_aft(h) + (z_fore(h) - z_aft(h)) * t
        y = rowf(z)
        h = min(max((y - KEEL) / (sheer(z) - KEEL), 0.0), 1.0)
    return Vector((half_breadth(h, z), y, z))


def build_hull(mb):
    T = 64
    ts = [0.5 - 0.5 * math.cos(math.pi * j / (T - 1)) for j in range(T)]  # 0 = stern, 1 = bow
    grid = [[solve(rf, t) for t in ts] for rf in ROWS]
    R = len(ROWS)

    # Outer shell, both sides. UV: u along the length, v around the girth (2 m texture tile).
    S, P = [], []
    for r in range(R):
        S.append([None] * T)
        P.append([None] * T)
    for j in range(T):
        g = 0.0
        for r in range(R):
            p = grid[r][j]
            if r > 0:
                g += (p - grid[r - 1][j]).length
            uv = (-p.z / 2.0, g / 2.0)
            S[r][j] = mb.v((p.x, p.y, p.z), uv)
            P[r][j] = mb.v((-p.x, p.y, p.z), uv)
    for r in range(R - 1):
        m = row_mat(r)
        for j in range(T - 1):
            mb.f([S[r][j], S[r][j + 1], S[r + 1][j + 1], S[r + 1][j]], m, True, (1, 0, 0))
            mb.f([P[r][j], P[r][j + 1], P[r + 1][j + 1], P[r + 1][j]], m, True, (-1, 0, 0))

    # Flat keel strip, stem strip and transom (separate verts: hard edges)
    def strip_pt(r, j, side):
        p = grid[r][j]
        return mb.v((p.x * side, p.y, p.z), (p.x * side / 2.0, p.y / 2.0))

    for j in range(T - 1):
        mb.f([strip_pt(0, j, 1), strip_pt(0, j + 1, 1), strip_pt(0, j + 1, -1), strip_pt(0, j, -1)],
             BOTTOM, False, (0, -1, 0))
    for r in range(R - 1):
        for j, want in ((T - 1, (0, 0, -1)), (0, (0, 0, 1))):
            mb.f([strip_pt(r, j, 1), strip_pt(r + 1, j, 1), strip_pt(r + 1, j, -1), strip_pt(r, j, -1)],
                 row_mat(r) if j == T - 1 else (BOTTOM if r < 10 else (STRAKE if r >= DECK_ROW else TOPSIDES)),
                 False, want)

    # Inner bulwarks, rail cap, deck
    def inner(p):
        return Vector((max(p.x - BULWARK_THICK, 0.03), p.y, p.z))

    for side in (1, -1):
        for r in range(DECK_ROW, R - 1):
            for j in range(T - 1):
                q = [inner(grid[r][j]), inner(grid[r][j + 1]), inner(grid[r + 1][j + 1]), inner(grid[r + 1][j])]
                idx = [mb.v((p.x * side, p.y, p.z), (-p.z / 2.0, p.y / 2.0)) for p in q]
                mb.f(idx, INNER, True, (-side, 0, 0))
        top = R - 1
        for j in range(T - 1):
            o0, o1 = grid[top][j], grid[top][j + 1]
            i0, i1 = inner(o0), inner(o1)
            pts = [(o0.x + 0.04, o0.y + 0.05, o0.z), (o1.x + 0.04, o1.y + 0.05, o1.z),
                   (i1.x - 0.02, i1.y + 0.05, i1.z), (i0.x - 0.02, i0.y + 0.05, i0.z)]
            mb.f([mb.v((p[0] * side, p[1], p[2])) for p in pts], BLACK, False, (0, 1, 0))
            lip = [(o0.x + 0.04, o0.y + 0.05, o0.z), (o1.x + 0.04, o1.y + 0.05, o1.z),
                   (o1.x + 0.04, o1.y - 0.07, o1.z), (o0.x + 0.04, o0.y - 0.07, o0.z)]
            mb.f([mb.v((p[0] * side, p[1], p[2])) for p in lip], BLACK, False, (side, 0, 0))
    # Transom: inner face of the stern bulwark and its rail cap
    for r in range(DECK_ROW, R - 1):
        a, b = inner(grid[r][0]), inner(grid[r + 1][0])
        mb.f([mb.v((a.x, a.y, a.z)), mb.v((b.x, b.y, b.z)), mb.v((-b.x, b.y, b.z)), mb.v((-a.x, a.y, a.z))],
             INNER, False, (0, 0, -1))
    o, i = grid[R - 1][0], inner(grid[R - 1][0])
    mb.f([mb.v((o.x + 0.04, o.y + 0.05, o.z + 0.04)), mb.v((-o.x - 0.04, o.y + 0.05, o.z + 0.04)),
          mb.v((-i.x, i.y + 0.05, i.z - 0.1)), mb.v((i.x, i.y + 0.05, i.z - 0.1))], BLACK, False, (0, 1, 0))

    # Deck with camber, planks running fore and aft
    K = 8
    cols = []
    for j in range(T):
        e = inner(grid[DECK_ROW][j])
        col = []
        for k in range(K + 1):
            s = -1.0 + 2.0 * k / K
            x = e.x * s
            y = e.y + CROWN * (1.0 - s * s)
            col.append(mb.v((x, y, e.z), (-e.z / 2.0, x / 2.0)))
        cols.append(col)
    for j in range(T - 1):
        for k in range(K):
            mb.f([cols[j][k], cols[j + 1][k], cols[j + 1][k + 1], cols[j][k + 1]], DECK, True, (0, 1, 0))

    # Keel
    box(mb, (0.0, KEEL - 0.1, (FOREFOOT_Z + 0.4 + POST_FOOT_Z) / 2.0),
        (0.2, 0.24, POST_FOOT_Z - FOREFOOT_Z - 0.4), BOTTOM)

    # Cutwater: a fin ahead of the stem, black, from the waterline up to the bowsprit
    stem = [grid[r][T - 1] for r in range(9, R)]
    y0, y1 = stem[0].y, stem[-1].y
    pts = [(p.y, p.z) for p in stem]
    for p in reversed(stem):
        s = (p.y - y0) / (y1 - y0)
        pts.append((p.y - 0.05 * s, p.z - 0.6 * s ** 0.8 - 0.02))
    prism(mb, pts, 0.09, BLACK)

    # Stern windows on the transom (just proud of it)
    for y in (deck(6.0) - 0.48,):
        for xa, xb in ((0.3, 0.75), (0.95, 1.3)):
            for side in (1, -1):
                ya, yb = y, y + 0.32
                za = z_aft((ya - KEEL) / (sheer(6.0) - KEEL)) + 0.03
                zb = z_aft((yb - KEEL) / (sheer(6.0) - KEEL)) + 0.03
                q = [(xa * side, ya, za), (xb * side, ya, za), (xb * side, yb, zb), (xa * side, yb, zb)]
                mb.f([mb.v(p) for p in q], BLACK, False, (0, 0, 1))
    return grid


# ---------------------------------------------------------------------------
# Fittings, guns, mast and rigging
# ---------------------------------------------------------------------------
def rot_x(deg):
    return Matrix.Rotation(math.radians(deg), 3, 'X')


def rot_z(deg):
    return Matrix.Rotation(math.radians(deg), 3, 'Z')


def build_fittings(mb, markers):
    # Hatches with dark gratings, cabin skylight, windlass and bitts
    for z, w, l in ((-4.9, 1.0, 1.0), (0.6, 1.5, 1.4)):
        y = deck_c(z)
        box(mb, (0, y + 0.1, z), (w, 0.22, l), WOOD)
        box(mb, (0, y + 0.2, z), (w - 0.16, 0.04, l - 0.16), BLACK)
        for k in range(1, 5):  # grating bars
            box(mb, (0, y + 0.225, z - l / 2 + 0.08 + k * (l - 0.16) / 5), (w - 0.16, 0.03, 0.05), WOOD)
    zc = 3.6
    box(mb, (0, deck_c(zc) + 0.22, zc), (1.2, 0.44, 1.3), WOOD)
    box(mb, (0, deck_c(zc) + 0.46, zc), (1.3, 0.06, 1.4), BLACK)
    zw = -6.9
    cyl(mb, (-0.85, deck_c(zw) + 0.38, zw), (0.85, deck_c(zw) + 0.38, zw), 0.2, 0.2, WOOD, 10)
    for x in (-1.0, 1.0):
        box(mb, (x, deck_c(zw) + 0.35, zw), (0.16, 0.7, 0.5), WOOD)
    for x in (-0.3, 0.3):
        box(mb, (x, deck_c(-7.9) + 0.35, -7.9), (0.2, 0.7, 0.2), WOOD)

    # Ship's boat on chocks over the main hatch
    build_boat(mb, zc=0.9, y0=deck_c(0.9) + 0.42)
    for z in (0.1, 1.7):
        box(mb, (0, deck_c(z) + 0.2, z), (1.0, 0.2, 0.18), WOOD)

    # Guns: carriage on deck, barrel out through an open port (no lids: from the high
    # camera they read as stray tabs)
    for gi, z in enumerate(GUN_Z):
        yp = deck(z) + 0.33
        xo = hull_x(yp, z)
        xi = max(xo - BULWARK_THICK, 0.3)
        for side in (1, -1):
            box(mb, (side * xo, yp, z), (0.08, 0.36, 0.46), BLACK)  # port opening
            box(mb, (side * (xi - 0.42), deck(z) + 0.2, z), (0.7, 0.3, 0.46), WOOD)  # carriage
            cyl(mb, (side * (xi - 0.85), yp + 0.03, z), (side * (xo + 0.2), yp, z), 0.12, 0.085, IRON, 8)
            cyl(mb, (side * (xo + 0.12), yp, z), (side * (xo + 0.22), yp, z), 0.105, 0.105, IRON, 8)
        markers["gun_%d" % gi] = (xo + 0.25, yp, z)

    # Rudder (outboard, on the sternpost) and tiller over the taffrail
    ys = sheer(TRANSOM_TOP_Z)
    top = ys + 0.15

    def le(y):
        return POST_FOOT_Z + 0.05 + (TRANSOM_TOP_Z + 0.08 - POST_FOOT_Z - 0.05) * (y - (KEEL - 0.15)) / (top - (KEEL - 0.15))
    rud = [(KEEL - 0.15, le(KEEL - 0.15)), (KEEL - 0.15, le(KEEL - 0.15) + 1.0), (0.3, le(0.3) + 0.95),
           (1.1, le(1.1) + 0.32), (top, le(top) + 0.24), (top, le(top))]
    prism(mb, rud, 0.08, TOPSIDES)
    cyl(mb, (0, top - 0.05, le(top) + 0.12), (0, deck_c(4.3) + 0.8, 4.3), 0.07, 0.05, WOOD, 6)

    # Taffrail lantern
    cyl(mb, (0, ys + 0.05, TRANSOM_TOP_Z - 0.1), (0, ys + 0.7, TRANSOM_TOP_Z - 0.1), 0.04, 0.04, BLACK, 6)
    box(mb, (0, ys + 0.85, TRANSOM_TOP_Z - 0.1), (0.24, 0.32, 0.24), BLACK)

    # Mast: lower mast, cap, trestle/crosstrees, topmast, truck
    yd = deck_c(MAST_Z)
    head = yd + LOWER_MAST_H
    cyl(mb, (0, yd - 0.05, MAST_Z), (0, head + 0.5, MAST_Z), 0.21, 0.15, SPAR, 12)
    box(mb, (0, head + 0.6, MAST_Z - 0.19), (0.36, 0.2, 0.82), BLACK)  # cap
    for x in (-0.16, 0.16):
        box(mb, (x, head - 0.25, MAST_Z - 0.1), (0.08, 0.12, 1.1), SPAR)  # trestletrees
    for dz in (-0.45, 0.25):
        box(mb, (0, head - 0.17, MAST_Z + dz), (1.9, 0.07, 0.08), SPAR)  # crosstrees
    truck = yd + MAST_H
    cyl(mb, (0, head - 0.9, TOPMAST_Z), (0, truck, TOPMAST_Z), 0.12, 0.07, SPAR, 10)
    cyl(mb, (0, truck, TOPMAST_Z), (0, truck + 0.08, TOPMAST_Z), 0.11, 0.11, BLACK, 8)
    markers["mast_0"] = (0.0, yd, MAST_Z)
    markers["mast_0_head"] = (0.0, head - 0.15, MAST_Z)
    markers["flag"] = (0.0, truck + 0.1, TOPMAST_Z)

    # Bowsprit, rising 12 degrees from its heel between the bitts
    a = math.radians(12.0)
    heel = Vector((0.0, deck_c(-7.7) + 0.25, -7.7))
    d = Vector((0.0, math.sin(a), -math.cos(a)))
    tip = heel + d * 8.6
    cyl(mb, heel, tip, 0.19, 0.1, SPAR, 10)
    cyl(mb, tip - d * 0.3, tip + d * 0.05, 0.11, 0.11, BLACK, 8)

    # Standing rigging
    rope = BLACK
    jib_head = Vector((0.0, yd + 11.0, TOPMAST_Z))
    jib_tack = tip - d * 0.35
    cyl(mb, jib_head, jib_tack, 0.03, 0.03, rope, 4, False)  # jibstay (the jib rides on it)
    cyl(mb, (0, head - 0.1, MAST_Z - 0.2), (0, sheer(-9.7) + 0.05, -9.7), 0.04, 0.04, rope, 4, False)  # forestay
    bob = Vector((0.0, -0.1, z_fore((-0.1 - KEEL) / (sheer(-8.5) - KEEL)) - 0.4))
    cyl(mb, tip - d * 0.6, bob, 0.035, 0.035, rope, 4, False)  # bobstay
    markers["jib_tack"] = tuple(jib_tack)
    markers["jib_head"] = tuple(jib_head)

    for side in (1, -1):
        # Channel, deadeyes, chainplates and three shrouds with ratlines
        zc_ch = MAST_Z + 0.75
        ych = sheer(zc_ch) - 0.25
        xo = hull_x(ych, zc_ch)
        box(mb, (side * (xo + 0.17), ych, zc_ch), (0.34, 0.07, 1.7), BLACK)
        lows, highs = [], []
        for k, dz in enumerate((-0.6, 0.0, 0.6)):
            z = zc_ch + dz
            xo_k = hull_x(ych, z)
            dead = Vector((side * (xo_k + 0.3), ych + 0.18, z))
            cyl(mb, dead - Vector((0, 0.1, 0)), dead + Vector((0, 0.1, 0)), 0.09, 0.09, BLACK, 6)
            box(mb, (side * (xo_k + 0.02), ych - 0.35, z), (0.03, 0.7, 0.06), BLACK)
            hi = Vector((side * 0.2, head - 0.35, MAST_Z + 0.05 * k))
            cyl(mb, dead + Vector((0, 0.1, 0)), hi, 0.03, 0.03, rope, 4, False)
            lows.append(dead + Vector((0, 0.1, 0)))
            highs.append(hi)
        n = 18
        for i in range(1, n):
            s = i / n
            if s > 0.86:
                break
            p0 = lows[0].lerp(highs[0], s)
            p2 = lows[2].lerp(highs[2], s)
            cyl(mb, p0, p2, 0.012, 0.012, rope, 3, False)
        # Topmast shroud and backstay
        cyl(mb, (side * 0.9, head - 0.17, MAST_Z - 0.1), (side * 0.06, yd + 11.6, TOPMAST_Z), 0.02, 0.02, rope, 4, False)
        zb = 2.6
        cyl(mb, (side * 0.05, yd + 12.2, TOPMAST_Z), (side * (hull_x(sheer(zb), zb) + 0.15), sheer(zb), zb),
            0.025, 0.025, rope, 4, False)


def build_boat(mb, zc, y0):
    """A small open boat, pointed at both ends: a simple lofted shell plus floorboards."""
    L, Bh, D = 3.4, 0.65, 0.5
    T, R = 18, 6
    grid = []
    for r in range(R):
        h = r / (R - 1)
        row = []
        for j in range(T):
            t = j / (T - 1)
            plan = math.sin(math.pi * t) ** 0.6
            x = max(Bh * plan * (1.0 - (1.0 - h) ** 2.2), 0.03)
            z = zc + L / 2.0 * (1.0 - 2.0 * t) * (0.86 + 0.14 * h)
            row.append(Vector((x, y0 - D + D * h + 0.08 * abs(1 - 2 * t) ** 3, z)))
        grid.append(row)
    for side in (1, -1):
        idx = [[mb.v((p.x * side, p.y, p.z)) for p in row] for row in grid]
        for r in range(R - 1):
            for j in range(T - 1):
                mb.f([idx[r][j], idx[r][j + 1], idx[r + 1][j + 1], idx[r + 1][j]], BOTTOM, True, (side, 0, 0))
        top = grid[R - 1]
        for j in range(T - 1):
            a, b = top[j], top[j + 1]
            mb.f([mb.v((a.x * side, a.y + 0.03, a.z)), mb.v((b.x * side, b.y + 0.03, b.z)),
                  mb.v(((b.x - 0.06) * side, b.y + 0.03, b.z)), mb.v(((a.x - 0.06) * side, a.y + 0.03, a.z))],
                 BLACK, False, (0, 1, 0))
    # Floorboards and thwarts
    fr = 3
    floor = [Vector((max(p.x - 0.06, 0.02), p.y, p.z)) for p in grid[fr]]
    for j in range(T - 1):
        a, b = floor[j], floor[j + 1]
        mb.f([mb.v((a.x, a.y, a.z)), mb.v((b.x, b.y, b.z)), mb.v((-b.x, b.y, b.z)), mb.v((-a.x, a.y, a.z))],
             INNER, False, (0, 1, 0))
    for dz in (-0.9, 0.0, 0.9):
        box(mb, (0, y0 - 0.12, zc + dz), (1.1, 0.05, 0.22), WOOD)


# ---------------------------------------------------------------------------
# Textures (generated: planks with seams, butt joints and grain)
# ---------------------------------------------------------------------------
SIZE = 512
TEX_METRES = 2.0
PLANK_W = 0.25


def plank_maps(seed, base_srgb, variation, seam_dark, grain):
    rng = np.random.default_rng(seed)
    n_rows = int(TEX_METRES / PLANK_W)
    px = SIZE // n_rows
    v = np.arange(SIZE)
    row = v // px
    in_row = v % px
    albedo = np.ones((SIZE, SIZE))
    height = np.ones((SIZE, SIZE))
    # Grain: streaks along u, made periodic so the texture tiles
    coarse = rng.random((SIZE, 16))
    u = np.linspace(0, 16, SIZE, endpoint=False)
    i0 = np.floor(u).astype(int) % 16
    i1 = (i0 + 1) % 16
    fu = u - np.floor(u)
    streak = coarse[:, i0] * (1 - fu) + coarse[:, i1] * fu
    streak = (streak + np.roll(streak, 1, axis=0) + np.roll(streak, -1, axis=0)) / 3.0
    albedo *= 1.0 + (streak - 0.5) * grain
    for r in range(n_rows):
        rows = row == r
        butt = int(rng.integers(0, SIZE))
        k1 = 1.0 + (rng.random() - 0.5) * variation
        k2 = 1.0 + (rng.random() - 0.5) * variation
        cols = np.arange(SIZE)
        first = ((cols - butt) % SIZE) < SIZE // 2
        tone = np.where(first, k1, k2)
        albedo[rows, :] *= tone[None, :]
        for c in (butt % SIZE, (butt + 1) % SIZE, (butt + SIZE // 2) % SIZE, (butt + SIZE // 2 + 1) % SIZE):
            albedo[rows, c] *= seam_dark
            height[rows, c] = 0.0
    seam_rows = (in_row == 0) | (in_row == 1)
    albedo[seam_rows, :] *= seam_dark
    height[seam_rows, :] = 0.0
    rgb = np.clip(albedo[..., None] * np.array(base_srgb)[None, None, :], 0.0, 1.0)
    # Normal map from the seam grooves (OpenGL convention, as glTF expects)
    hx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
    hy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    n = np.dstack((-hx * 1.5, -hy * 1.5, np.ones_like(height)))
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    return rgb, n * 0.5 + 0.5


TEX_DIR = os.path.join(tempfile.gettempdir(), "bos_ship_textures")
os.makedirs(TEX_DIR, exist_ok=True)


def save_image(name, rgb, non_color=False):
    img = bpy.data.images.new(name, SIZE, SIZE, alpha=False)
    rgba = np.dstack((rgb, np.ones((SIZE, SIZE)))).astype(np.float32)
    img.pixels.foreach_set(rgba.ravel())
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    img.filepath_raw = os.path.join(TEX_DIR, name + ".png")
    img.file_format = "PNG"
    img.save()
    return img


def make_material(name, srgb, rough, metal=0.0, albedo_img=None, normal_img=None):
    m = bpy.data.materials.new(name)
    try:
        m.use_nodes = True
    except Exception:
        pass
    lin = [c ** 2.2 for c in srgb]
    m.diffuse_color = (lin[0], lin[1], lin[2], 1.0)
    nt = m.node_tree
    bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (lin[0], lin[1], lin[2], 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if albedo_img is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = albedo_img
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    if normal_img is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = normal_img
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.inputs["Strength"].default_value = 1.0
        nt.links.new(tex.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    return m


def build_materials():
    # Topsides texture is neutral: ship.gd tints it with Ship.hull_color.
    specs = [
        ("Bottom", (0.80, 0.76, 0.66), 0.08, 0.80, 0.25, 0.85),
        ("Topsides", (0.86, 0.86, 0.86), 0.10, 0.70, 0.30, 0.6),
        ("Strake", (0.76, 0.55, 0.20), 0.06, 0.75, 0.20, 0.6),
        ("Deck", (0.80, 0.67, 0.48), 0.14, 0.55, 0.35, 0.85),
        ("Inner", (0.60, 0.22, 0.13), 0.06, 0.75, 0.20, 0.7),
    ]
    mats = []
    normal = None
    for i, (name, col, var, seam, grain, rough) in enumerate(specs):
        rgb, nrm = plank_maps(11 + i, col, var, seam, grain)
        if normal is None:
            normal = save_image("planks_normal", nrm, True)
        mats.append(make_material(name, col, rough, 0.0, save_image(name.lower() + "_albedo", rgb), normal))
    mats.append(make_material("Spar", (0.58, 0.43, 0.27), 0.7))
    mats.append(make_material("Wood", (0.36, 0.24, 0.15), 0.8))
    mats.append(make_material("Black", (0.05, 0.045, 0.04), 0.6))
    mats.append(make_material("Iron", (0.09, 0.09, 0.095), 0.45, 0.6))
    return mats


# ---------------------------------------------------------------------------
# Assemble, export, preview
# ---------------------------------------------------------------------------
def to_object(mb, name, mats):
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    bv = [bm.verts.new(to_bl(p)) for p in mb.verts]
    uvl = bm.loops.layers.uv.new("UVMap")
    for idx, mat, smooth in mb.faces:
        try:
            f = bm.faces.new([bv[i] for i in idx])
        except ValueError:
            continue
        f.material_index = mat
        f.smooth = smooth
        for k, loop in enumerate(f.loops):
            loop[uvl].uv = mb.uvs[idx[k]]
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    return ob


def preview(ob, out_dir):
    scene = bpy.context.scene
    try:
        scene.render.engine = "BLENDER_WORKBENCH"
    except TypeError:
        scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.world = bpy.data.worlds.new("w") if scene.world is None else scene.world
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    target = to_bl((0.0, 3.0, -2.5))
    views = {
        "side": (to_bl((30.0, 4.0, -2.5)), 32.0),
        "three_quarter": (to_bl((20.0, 14.0, -22.0)), 35.0),
        "top": (to_bl((0.5, 60.0, -2.5)), 30.0),
        "stern": (to_bl((9.0, 6.0, 22.0)), 35.0),
    }
    for name, (pos, lens_fov) in views.items():
        cam.location = pos
        direction = target - pos
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        cam_data.angle = math.radians(lens_fov)
        scene.render.filepath = os.path.join(out_dir, "sloop_%s.png" % name)
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    mats = build_materials()
    mb = MB()
    markers = {}
    build_hull(mb)
    build_fittings(mb, markers)
    ob = to_object(mb, "hull", mats)
    for name, p in markers.items():
        e = bpy.data.objects.new(name, None)
        e.location = to_bl(p)
        e.empty_display_size = 0.3
        bpy.context.scene.collection.objects.link(e)
    print("sloop: %d verts, %d faces, %d materials" % (len(mb.verts), len(mb.faces), len(mats)))
    if PREVIEW:
        os.makedirs(PREVIEW, exist_ok=True)
        preview(ob, PREVIEW)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=False)
    print("exported", OUT)


main()
