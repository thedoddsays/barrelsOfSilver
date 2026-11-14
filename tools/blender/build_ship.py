"""Build ship models (hull, deck, guns, masts, bowsprit, standing rigging) and export each
as a .glb for Godot. Everything is generated from the numbers in SHIPS: no external assets.

Run (Blender 4.2+ / 5.x), from the repo root:
    blender --background --factory-startup --python tools/blender/build_ship.py -- <id|all> [preview_dir]
writes assets/ships/<id>/<id>.glb for each ship (and Workbench preview renders if a
preview_dir is given). Then run `godot --headless --path . --import`.

Coordinates: all geometry is written in GODOT ship-local space (x = starboard, y = up,
z = aft; the bow points to -z) and converted to Blender's Z-up on the way in, so the
exported glTF lands in Godot exactly where ship.gd expects it.

Every ship is the sloop's lines scaled by its length L, beam B and hull height H from
data/ships/<id>.tres (which MUST match the numbers here), with a few shape knobs. That keeps
the model in step with the physics: deck at y = 0.5 H, waterline about y = -0.19 H, bow at
z = -0.625 L, stern at +0.375 L, guns from z = -0.25 L to +0.22 L (as ship.gd lays them out).

Sails, booms, gaffs, yards and the flag are NOT in the model: ship.gd builds them because
they animate. The model carries marker empties for them:
    mast_N, mast_N_head, mast_N_top   foot, lower masthead (gaff throat), truck
    jib_tack, jib_head                the jibstay the jib rides on
    flag                              truck of the tallest mast
    gun_N                             starboard muzzles, bow to stern
"""
import math
import os
import sys
import tempfile
from types import SimpleNamespace

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# ---------------------------------------------------------------------------
# Ships. Dimensions must match data/ships/<id>.tres. Masts are (kind, z / L, height k):
# kind "gaff" or "square" as in ShipSpec.masts ("trysail" = a snow's thin gaff mast, a
# "gaff" in the spec); height k multiplies mast_frac * L (deck to truck).
# ---------------------------------------------------------------------------
SHIPS = {
    # Open oared boats: no deck (floorboards and rowing benches instead), oarlock markers for
    # ship.gd's oars, swivel guns on the rail. The periagua is a dugout: pointed both ends.
    "periagua": dict(L=12.0, B=2.4, H=1.1, guns=1, mast_frac=0.55,
                     masts=[("gaff", -0.22, 0.85), ("gaff", 0.1, 1.0)],
                     sprit_len=0.0, sprit_angle=0.0, bow_full=1.3, transom=0.04, forefoot=0.5,
                     open=True, double_ended=True, oars=7, gun_span=(-0.42, -0.42),
                     palette={"Bottom": (0.36, 0.26, 0.17), "Inner": (0.44, 0.31, 0.2),
                              "Deck": (0.55, 0.43, 0.29)}),
    "barco_luengo": dict(L=16.0, B=3.4, H=1.5, guns=1, mast_frac=0.45,
                         masts=[("lateen", -0.12, 1.0)],
                         sprit_len=0.0, sprit_angle=0.0, bow_full=1.5, transom=0.36,
                         open=True, oars=9, gun_span=(-0.44, -0.44)),
    "sloop": dict(L=16.0, B=4.6, H=2.2, guns=5, mast_frac=0.8,
                  masts=[("gaff", -0.1, 1.0)],
                  sprit_len=0.54, sprit_angle=12.0),
    "ketch": dict(L=18.0, B=5.4, H=2.5, guns=4, mast_frac=0.78,
                  masts=[("gaff", -0.12, 1.0), ("gaff", 0.24, 0.62)],
                  sprit_len=0.46, sprit_angle=13.0, bow_full=1.9, transom=0.66),
    "schooner": dict(L=20.0, B=5.2, H=2.4, guns=5, mast_frac=0.85,
                     masts=[("gaff", -0.17, 0.95), ("gaff", 0.1, 1.0)],
                     sprit_len=0.5, sprit_angle=10.0, bow_full=1.25, forefoot=0.4, sheer_bow=0.45,
                     transom=0.56),
    "brigantine": dict(L=22.0, B=6.0, H=2.8, guns=7, mast_frac=0.78,
                       masts=[("square", -0.2, 1.0), ("gaff", 0.12, 0.9)],
                       sprit_len=0.5, sprit_angle=14.0),
    "brig": dict(L=24.0, B=6.6, H=3.0, guns=8, mast_frac=0.8,
                 masts=[("square", -0.2, 1.0), ("square", 0.12, 0.95)],
                 sprit_len=0.48, sprit_angle=15.0, bow_full=1.8),
    "snow": dict(L=26.0, B=7.0, H=3.1, guns=8, mast_frac=0.8,
                 masts=[("square", -0.21, 1.0), ("square", 0.1, 0.95), ("trysail", 0.127, 0.55)],
                 sprit_len=0.46, sprit_angle=15.0, bow_full=1.9, transom=0.66),
    # Three-masted ships: raised quarterdeck (qd: where it starts, z / L) and forecastle
    # (fc: where it ends), a wheel instead of a tiller, guns spread further along the side.
    "barque": dict(L=30.0, B=8.0, H=3.5, guns=6, mast_frac=0.78,
                   masts=[("square", -0.27, 0.92), ("square", -0.02, 1.0), ("gaff", 0.22, 0.72)],
                   sprit_len=0.42, sprit_angle=16.0, bow_full=2.0, transom=0.68,
                   qd=0.12, fc=-0.27, gun_span=(-0.22, 0.08)),
    "merchantman": dict(L=30.0, B=8.0, H=3.6, guns=8, mast_frac=0.8,
                        masts=[("square", -0.27, 0.92), ("square", -0.02, 1.0), ("spanker", 0.22, 0.75)],
                        sprit_len=0.42, sprit_angle=17.0, bow_full=2.2, transom=0.7,
                        qd=0.1, fc=-0.27, gun_span=(-0.24, 0.24)),
    "pirate_frigate": dict(L=32.0, B=8.5, H=3.8, guns=16, mast_frac=0.8,
                           masts=[("square", -0.28, 0.92), ("square", -0.02, 1.0), ("spanker", 0.22, 0.75)],
                           sprit_len=0.42, sprit_angle=16.0, bow_full=1.6, transom=0.62,
                           qd=0.1, fc=-0.27, gun_span=(-0.31, 0.29)),
    "east_indiaman": dict(L=40.0, B=10.5, H=4.6, guns=16, mast_frac=0.78,
                          masts=[("square", -0.27, 0.92), ("square", -0.02, 1.0), ("spanker", 0.22, 0.75)],
                          sprit_len=0.4, sprit_angle=17.0, bow_full=2.1, transom=0.7, sheer_bow=0.75,
                          qd=0.08, fc=-0.28, gun_span=(-0.3, 0.29)),
    # Navy sloop-of-war: a small ship-rigged pirate hunter (mixed rig: gaff mizzen), navy paint.
    "navy_sloop": dict(L=28.0, B=7.6, H=3.4, guns=7, mast_frac=0.82,
                       masts=[("square", -0.27, 0.92), ("square", -0.02, 1.0), ("gaff", 0.22, 0.75)],
                       sprit_len=0.44, sprit_angle=15.0, bow_full=1.5, transom=0.6,
                       qd=0.12, fc=-0.3, gun_span=(-0.27, 0.1), navy=True),
    # Fluyt: Dutch bulk carrier. Pear-shaped sections (strong tumblehome, flat floor), a narrow
    # high stern, few guns.
    "fluyt": dict(L=32.0, B=7.2, H=4.4, guns=4, mast_frac=0.8,
                  masts=[("square", -0.28, 0.92), ("square", -0.03, 1.0), ("spanker", 0.2, 0.7)],
                  sprit_len=0.4, sprit_angle=20.0, bow_full=2.4, transom=0.38, tumble=0.32, sec_k=1.2,
                  sheer_stern=0.9, qd=0.16, fc=-0.36, gun_span=(-0.15, 0.1)),
    # Galleon: two gun decks, a towering stern (quarterdeck plus poop), a high forecastle, a
    # long beakhead, and lateen mizzen and bonaventure masts.
    "galleon": dict(L=42.0, B=11.5, H=7.0, guns=20, decks=2, mast_frac=0.74,
                    masts=[("square", -0.3, 0.9), ("square", -0.05, 1.0), ("lateen", 0.2, 0.6),
                           ("lateen", 0.31, 0.45)],
                    sprit_len=0.42, sprit_angle=28.0, bow_full=1.8, transom=0.62, tumble=0.2,
                    sheer_bow=0.9, sheer_stern=0.8, qd=0.06, poop=0.22, fc=-0.33, beak=1.2,
                    gun_span=(-0.3, 0.26)),
    # Ships of the line: two or three gun decks of lidded ports between black wales, navy ochre.
    "fourth_rate": dict(L=45.0, B=12.5, H=8.0, guns=25, decks=2, mast_frac=0.78,
                        masts=[("square", -0.27, 0.92), ("square", -0.02, 1.0), ("spanker", 0.22, 0.75)],
                        sprit_len=0.4, sprit_angle=20.0, bow_full=1.7, transom=0.66, tumble=0.18,
                        qd=0.1, fc=-0.3, beak=0.5, gun_span=(-0.33, 0.3), navy=True),
    "third_rate": dict(L=52.0, B=14.5, H=9.0, guns=37, decks=2, mast_frac=0.78,
                       masts=[("square", -0.27, 0.92), ("square", -0.02, 1.0), ("spanker", 0.22, 0.75)],
                       sprit_len=0.4, sprit_angle=20.0, bow_full=1.7, transom=0.66, tumble=0.18,
                       qd=0.1, fc=-0.3, beak=0.5, gun_span=(-0.36, 0.33), navy=True),
    "second_rate": dict(L=54.0, B=15.0, H=11.4, guns=45, decks=3, mast_frac=0.78,
                        masts=[("square", -0.27, 0.92), ("square", -0.02, 1.0), ("spanker", 0.22, 0.75)],
                        sprit_len=0.4, sprit_angle=21.0, bow_full=1.7, transom=0.66, tumble=0.2,
                        qd=0.08, poop=0.27, fc=-0.3, beak=0.5, gun_span=(-0.36, 0.33), navy=True),
    "first_rate": dict(L=58.0, B=16.0, H=12.0, guns=50, decks=3, mast_frac=0.78,
                       masts=[("square", -0.27, 0.92), ("square", -0.02, 1.0), ("spanker", 0.22, 0.75)],
                       sprit_len=0.4, sprit_angle=21.0, bow_full=1.7, transom=0.66, tumble=0.2,
                       qd=0.08, poop=0.27, fc=-0.3, beak=0.5, gun_span=(-0.37, 0.34), navy=True),
}

DECK_GAP = 2.3  # metres between gun decks (people and guns don't scale with the ship)

# Sloop baseline these ratios come from: L 16, B 4.6, H 2.2.
BASE_L, BASE_B, BASE_H = 16.0, 4.6, 2.2

C = SimpleNamespace()  # the ship being built


def setup(ship_id):
    s = SHIPS[ship_id]
    L, B, H = s["L"], s["B"], s["H"]
    sl, sb, sh = L / BASE_L, B / BASE_B, H / BASE_H
    C.id = ship_id
    C.L, C.B, C.H, C.sl, C.sb, C.sh = L, B, H, sl, sb, sh
    C.thick = math.sqrt(sh)  # rails, bulwarks: people don't scale with the ship
    C.KEEL = -1.75 * sh
    C.HALF_BEAM = B / 2.0
    C.MAX_BEAM_Z = -0.094 * L
    C.STEM_TOP_Z = -0.625 * L
    C.FOREFOOT_Z = -s.get("forefoot", 0.425) * L
    C.POST_FOOT_Z = 0.3375 * L
    C.TRANSOM_TOP_Z = 0.3875 * L
    C.BULWARK = 0.65 * C.thick
    C.SHEER_MID = 0.5 * H + C.BULWARK
    C.SHEER_LOW_Z = -0.031 * L
    C.SHEER_BOW_RISE = s.get("sheer_bow", 0.6) * sh
    C.SHEER_STERN_RISE = s.get("sheer_stern", 0.45) * sh
    C.BOOT_TOP = -0.30 * sh
    C.WALE = (0.65 * sh, 0.35 * sh)
    C.TRANSOM_HALF = s.get("transom", 0.62)
    C.BOW_FULL = s.get("bow_full", 1.6)
    C.TUMBLEHOME = s.get("tumble", 0.07)
    C.SEC_K = s.get("sec_k", 0.0)  # fuller, flatter-floored sections
    C.BULWARK_THICK = 0.12 * C.thick
    C.CROWN = 0.07 * sb
    C.MAST_FRAC = s["mast_frac"]
    C.MASTS = s["masts"]
    C.SPRIT_LEN = s["sprit_len"] * L
    C.SPRIT_ANGLE = s["sprit_angle"]
    g0, g1 = s.get("gun_span", (-0.25, 0.22))  # ship.gd's spec layout uses -0.25 .. 0.22
    C.DECKS = s.get("decks", 1)
    C.NAVY = s.get("navy", False)
    C.BEAK = s.get("beak", 0.0)
    # Guns per row, lowest gun deck first (the lower rows take any odd guns). Row k's floor
    # is k * DECK_GAP below the weather deck.
    total = s["guns"]
    counts = [total // C.DECKS + (1 if r < total % C.DECKS else 0) for r in range(C.DECKS)]
    C.GUN_ROWS = []
    for r, n in enumerate(counts):
        zs = [(g0 + ((g1 - g0) * i / (n - 1) if n > 1 else (g1 - g0) / 2)) * L for i in range(n)]
        C.GUN_ROWS.append((C.DECKS - 1 - r, zs))
    C.GUN_Z = C.GUN_ROWS[-1][1]  # weather deck row
    C.OPEN = s.get("open", False)
    C.DOUBLE = s.get("double_ended", False)
    C.OARS = s.get("oars", 0)
    C.PALETTE = s.get("palette", {})
    if C.OPEN:
        C.BULWARK = 0.12 * C.thick  # the gunwale stands just above the 'deck' line
        C.SHEER_MID = 0.5 * H + C.BULWARK
    C.QD = s["qd"] * L if "qd" in s else None
    C.FC = s["fc"] * L if "fc" in s else None
    C.POOP = s["poop"] * L if "poop" in s else None  # a second step up, aft of the quarterdeck
    C.RAISE = min(1.4 * C.thick, 2.2)  # quarterdeck / forecastle height above the main deck
    C.ROWS, C.ROW_MATS, C.DECK_ROW = make_rows()


def to_bl(p):
    return Vector((p[0], -p[2], p[1]))


def smoothstep(a, b, x):
    t = min(max((x - a) / (b - a), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------------------
# Hull lines
# ---------------------------------------------------------------------------
def sheer(z):
    if z < C.SHEER_LOW_Z:
        s = (z - C.SHEER_LOW_Z) / (C.STEM_TOP_Z - C.SHEER_LOW_Z)
        return C.SHEER_MID + C.SHEER_BOW_RISE * s * s
    s = (z - C.SHEER_LOW_Z) / (C.TRANSOM_TOP_Z - C.SHEER_LOW_Z)
    return C.SHEER_MID + C.SHEER_STERN_RISE * s * s


def deck(z):
    return sheer(z) - C.BULWARK


def deck_c(z):
    return deck(z) + C.CROWN


RAMP = 0.3  # half-length of the step up to a raised deck


def raise_at(z):
    """Height of the raised deck (quarterdeck or forecastle) above the main deck at z."""
    r = 0.0
    if C.QD is not None:
        r += C.RAISE * smoothstep(C.QD - RAMP, C.QD + RAMP, z)
    if C.FC is not None:
        r += C.RAISE * (1.0 - smoothstep(C.FC - RAMP, C.FC + RAMP, z))
    if C.POOP is not None:
        r += C.RAISE * smoothstep(C.POOP - RAMP, C.POOP + RAMP, z)
    return r


def floor_k(z, k):
    """Floor of gun deck k (0 = the weather deck, 1 = the one below...) at z."""
    return deck(z) - k * DECK_GAP


def sheer_top(z):  # top of the rail, stepping up over the quarterdeck and forecastle
    return sheer(z) + raise_at(z)


def deck_top_c(z):  # the deck you'd stand on at z (centreline)
    return deck_c(z) + raise_at(z)


def z_fore(h):  # stem profile: a curved forefoot
    return C.FOREFOOT_Z + (C.STEM_TOP_Z - C.FOREFOOT_Z) * (1.0 - (1.0 - h) ** 2.2)


def z_aft(h):  # raked sternpost and transom (or a second curved stem on a double-ender)
    if C.DOUBLE:
        return C.POST_FOOT_Z + (C.TRANSOM_TOP_Z - C.POST_FOOT_Z) * (1.0 - (1.0 - h) ** 2.2)
    return C.POST_FOOT_Z + (C.TRANSOM_TOP_Z - C.POST_FOOT_Z) * h


def half_breadth(h, z):
    """Half-width of the hull at normalised height h (0 keel, 1 rail) and position z."""
    if z <= C.MAX_BEAM_Z:
        s = min(max((z - C.MAX_BEAM_Z) / (z_fore(h) - C.MAX_BEAM_Z), 0.0), 1.0)
        plan = max(1.0 - s ** (C.BOW_FULL + 0.8 * h), 0.0) ** 0.5  # rounded bow
    else:
        s = min(max((z - C.MAX_BEAM_Z) / (z_aft(h) - C.MAX_BEAM_Z), 0.0), 1.0)
        wt = 0.04 + (C.TRANSOM_HALF - 0.04) * smoothstep(0.15, 0.7, h)
        plan = 1.0 - (1.0 - wt) * s ** 2.2  # fine run aft into a transom
    hm = 0.6
    if h < hm:
        k = 1.5 + (1.7 + C.SEC_K) * plan  # V-shaped sections at the ends, fuller amidships
        sec = 1.0 - (1.0 - h / hm) ** k
    else:
        sec = 1.0 - C.TUMBLEHOME * ((h - hm) / (1.0 - hm)) ** 1.5
    return max(0.1 * C.thick, C.HALF_BEAM * sec * plan)


def hull_x(y, z):
    h = min(max((y - C.KEEL) / (sheer(z) - C.KEEL), 0.0), 1.0)
    return half_breadth(h, z)


def make_rows():
    """Hull rows, keel to rail, and the material of the band above each row. Rows sit
    exactly on the paint-band edges so the bands are crisp; the wale and upper rows follow
    the sheer like real planking. Returns (rows, mats, deck_row)."""
    rows, mats = [], []

    def add(fn, mat):
        rows.append(fn)
        mats.append(mat)

    for i, f in enumerate((0.0, 0.03, 0.08, 0.15, 0.24, 0.35, 0.48, 0.62, 0.76, 0.89, 1.0)):
        add(lambda z, f=f: C.KEEL + (C.BOOT_TOP - C.KEEL) * f, BOTTOM if i < 10 else TOPSIDES)
    if C.OPEN:
        g = GUNWALE * C.thick
        add(lambda z: floor_y(), TOPSIDES)  # FLOOR_ROW
        add(lambda z: (floor_y() + sheer(z) - g) / 2.0, TOPSIDES)
        add(lambda z: sheer(z) - g, BLACK)  # gunwale
        add(lambda z: sheer(z), TOPSIDES)
        return rows, mats, None
    if C.DECKS > 1:
        # A black wale just under each gun deck; the ports sit in the band above it (navy
        # ochre on warships).
        band = STRAKE if C.NAVY else TOPSIDES
        for k in range(C.DECKS - 1, -1, -1):
            add(lambda z, k=k: floor_k(z, k) - 0.45, BLACK)
            add(lambda z, k=k: floor_k(z, k) - 0.1, band)
    else:
        for f in (1.0 / 3.0, 2.0 / 3.0):
            add(lambda z, f=f: C.BOOT_TOP + ((deck(z) - C.WALE[0]) - C.BOOT_TOP) * f, TOPSIDES)
        add(lambda z: deck(z) - C.WALE[0], BLACK)
        add(lambda z: deck(z) - C.WALE[1], TOPSIDES)
        add(lambda z: deck(z) - 0.17 * C.sh, TOPSIDES)
    deck_row = len(rows)
    add(lambda z: deck(z), STRAKE)
    add(lambda z: deck(z) + 0.5 * C.BULWARK, STRAKE)
    add(lambda z: sheer(z), TOPSIDES)  # raised bulwarks over the quarterdeck/forecastle
    add(lambda z: sheer_top(z) + 0.0001, TOPSIDES)  # (flat elsewhere)
    return rows, mats, deck_row


# Materials (index order)
BOTTOM, TOPSIDES, STRAKE, DECK, INNER, SPAR, WOOD, BLACK, IRON = range(9)


GUNWALE = 0.14  # open boats: dark band along the top of the side
FLOOR_ROW = 11  # open boats: floorboards at this row (see floor_y)


def floor_y():
    """Open boats: floorboards a quarter of the hull depth above the waterline (about
    -0.19 H, set by ship.gd's buoyancy). The ocean is one opaque surface, so anything inside
    the hull below the waterline would show water straight through it."""
    return -0.19 * C.H + 0.25 * C.H


def row_mat(r):
    return C.ROW_MATS[r]


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


def rope(mb, a, b, r=0.03, seg=4):
    cyl(mb, a, b, r, r, BLACK, seg, False)


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
    z, h, y = 0.0, 0.5, 0.0
    for _ in range(5):
        z = z_aft(h) + (z_fore(h) - z_aft(h)) * t
        y = rowf(z)
        h = min(max((y - C.KEEL) / (sheer(z) - C.KEEL), 0.0), 1.0)
    return Vector((half_breadth(h, z), y, z))


def build_hull(mb):
    T = 64 if C.L < 24 else 80
    ts = [0.5 - 0.5 * math.cos(math.pi * j / (T - 1)) for j in range(T)]  # 0 = stern, 1 = bow
    grid = [[solve(rf, t) for t in ts] for rf in C.ROWS]
    R = len(C.ROWS)
    DR = C.DECK_ROW

    # Outer shell, both sides. UV: u along the length, v around the girth (2 m texture tile).
    S = [[None] * T for _ in range(R)]
    P = [[None] * T for _ in range(R)]
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
                 row_mat(r) if j == T - 1 else (TOPSIDES if row_mat(r) == BLACK else row_mat(r)),
                 False, want)

    if C.OPEN:
        build_open_inside(mb, grid, T, R)
        return grid

    # Inner bulwarks, rail cap, deck
    bt = C.BULWARK_THICK
    rc = C.thick

    def inner(p):
        return Vector((max(p.x - bt, 0.03), p.y, p.z))

    for side in (1, -1):
        for r in range(DR, R - 1):
            for j in range(T - 1):
                q = [inner(grid[r][j]), inner(grid[r][j + 1]), inner(grid[r + 1][j + 1]), inner(grid[r + 1][j])]
                idx = [mb.v((p.x * side, p.y, p.z), (-p.z / 2.0, p.y / 2.0)) for p in q]
                mb.f(idx, INNER, True, (-side, 0, 0))
        top = R - 1
        for j in range(T - 1):
            o0, o1 = grid[top][j], grid[top][j + 1]
            i0, i1 = inner(o0), inner(o1)
            pts = [(o0.x + 0.04 * rc, o0.y + 0.05 * rc, o0.z), (o1.x + 0.04 * rc, o1.y + 0.05 * rc, o1.z),
                   (i1.x - 0.02 * rc, i1.y + 0.05 * rc, i1.z), (i0.x - 0.02 * rc, i0.y + 0.05 * rc, i0.z)]
            mb.f([mb.v((p[0] * side, p[1], p[2])) for p in pts], BLACK, False, (0, 1, 0))
            lip = [(o0.x + 0.04 * rc, o0.y + 0.05 * rc, o0.z), (o1.x + 0.04 * rc, o1.y + 0.05 * rc, o1.z),
                   (o1.x + 0.04 * rc, o1.y - 0.07 * rc, o1.z), (o0.x + 0.04 * rc, o0.y - 0.07 * rc, o0.z)]
            mb.f([mb.v((p[0] * side, p[1], p[2])) for p in lip], BLACK, False, (side, 0, 0))
    # Transom: inner face of the stern bulwark and its rail cap
    for r in range(DR, R - 1):
        a, b = inner(grid[r][0]), inner(grid[r + 1][0])
        mb.f([mb.v((a.x, a.y, a.z)), mb.v((b.x, b.y, b.z)), mb.v((-b.x, b.y, b.z)), mb.v((-a.x, a.y, a.z))],
             INNER, False, (0, 0, -1))
    o, i = grid[R - 1][0], inner(grid[R - 1][0])
    mb.f([mb.v((o.x + 0.04 * rc, o.y + 0.05 * rc, o.z + 0.04 * rc)), mb.v((-o.x - 0.04 * rc, o.y + 0.05 * rc, o.z + 0.04 * rc)),
          mb.v((-i.x, i.y + 0.05 * rc, i.z - 0.1 * rc)), mb.v((i.x, i.y + 0.05 * rc, i.z - 0.1 * rc))],
         BLACK, False, (0, 1, 0))

    # Deck with camber, planks running fore and aft
    K = 8
    cols = []
    for j in range(T):
        e = inner(grid[DR][j])
        col = []
        for k in range(K + 1):
            s = -1.0 + 2.0 * k / K
            x = e.x * s
            y = e.y + C.CROWN * (1.0 - s * s)
            col.append(mb.v((x, y, e.z), (-e.z / 2.0, x / 2.0)))
        cols.append(col)
    for j in range(T - 1):
        for k in range(K):
            mb.f([cols[j][k], cols[j + 1][k], cols[j + 1][k + 1], cols[j][k + 1]], DECK, True, (0, 1, 0))

    # Quarterdeck and forecastle: a raised deck inside the stepped-up bulwarks, with a red
    # breast facing the waist and a rail along its edge.
    for kind in ("qd", "fc"):
        zb = C.QD if kind == "qd" else C.FC
        if zb is None:
            continue
        edge = zb + RAMP if kind == "qd" else zb - RAMP
        js = [j for j in range(T) if (grid[R - 1][j].z >= edge if kind == "qd" else grid[R - 1][j].z <= edge)]
        if len(js) < 2:
            continue
        js.sort(key=lambda j: grid[R - 1][j].z)
        pcols = []
        for j in js:
            o = grid[R - 1][j]
            xe = max(o.x - bt + 0.03, 0.05)
            y = deck(o.z) + raise_at(o.z)
            col = []
            for k in range(K + 1):
                s = -1.0 + 2.0 * k / K
                col.append(mb.v((xe * s, y + C.CROWN * (1.0 - s * s), o.z), (-o.z / 2.0, xe * s / 2.0)))
            pcols.append((o, xe, y, col))
        for a in range(len(pcols) - 1):
            ca, cb = pcols[a][3], pcols[a + 1][3]
            for k in range(K):
                mb.f([ca[k], cb[k], cb[k + 1], ca[k + 1]], DECK, True, (0, 1, 0))
        o, xe, y, _ = pcols[0] if kind == "qd" else pcols[-1]
        breast(mb, o.z, deck(o.z), y, xe, -1.0 if kind == "qd" else 1.0)  # faces the waist
    if C.POOP is not None:
        zp = C.POOP - RAMP
        xe = max(hull_x(sheer(zp), zp) - bt + 0.03, 0.05)
        breast(mb, zp, deck(zp) + C.RAISE, deck(zp) + 2.0 * C.RAISE, xe, -1.0)

    # Keel
    k0 = C.FOREFOOT_Z + 0.025 * C.L
    box(mb, (0.0, C.KEEL - 0.1 * C.sh, (k0 + C.POST_FOOT_Z) / 2.0),
        (0.2 * C.thick, 0.24 * C.sh, C.POST_FOOT_Z - k0), BOTTOM)

    # Cutwater: a fin ahead of the stem, black, from the waterline up to the bowsprit. On a
    # galleon or a ship of the line it runs out into a beakhead with head rails.
    stem = [grid[r][T - 1] for r in range(9, R)]
    y0, y1 = stem[0].y, stem[-1].y
    reach = (0.6 + C.BEAK) * C.sl
    pts = [(p.y, p.z) for p in stem]
    for p in reversed(stem):
        s = (p.y - y0) / (y1 - y0)
        pts.append((p.y - 0.05 * C.sh * s, p.z - reach * s ** 0.8 - 0.02))
    prism(mb, pts, 0.09 * C.thick, BLACK)
    if C.BEAK > 0.0:
        top = stem[-1]
        tip = Vector((0.0, top.y - 0.05 * C.sh - 0.6, top.z - reach * 0.92))
        zr = C.STEM_TOP_Z + 0.07 * C.L
        for side in (1, -1):
            for dy in (0.0, -0.9):
                yr = deck(zr) + dy
                cyl(mb, tip + Vector((0, dy * 0.6, 0.2)), (side * hull_x(yr, zr), yr, zr), 0.08, 0.08, WOOD, 6)
        yp = tip.y - 1.1
        zp0 = z_fore(min(max((yp - C.KEEL) / (sheer(C.STEM_TOP_Z) - C.KEEL), 0.0), 1.0))
        box(mb, (0, yp, (tip.z + zp0) / 2.0), (1.4, 0.12, abs(zp0 - tip.z)), WOOD)  # beakhead grating

    # Stern windows on the raked lower transom (just proud of it): a small row on single-deck
    # ships, a wide gallery row for the deck below the weather deck on bigger ones.
    zt = 0.375 * C.L
    if C.DECKS == 1:
        n_win = 2 if C.B < 5.5 else 3
        half = hull_x(deck(zt) - 0.3 * C.sh, zt) * 0.62
        w = half * 2.0 / (n_win * 2 + 1)
        ya, yb = deck(zt) - 0.48 * C.sh, deck(zt) - 0.16 * C.sh
        za = z_aft((ya - C.KEEL) / (sheer(zt) - C.KEEL)) + 0.03
        zb = z_aft((yb - C.KEEL) / (sheer(zt) - C.KEEL)) + 0.03
        for k in range(n_win):
            xa = 0.3 * C.sb + k * (w * 1.4)
            xb = xa + w
            for side in (1, -1):
                q = [(xa * side, ya, za), (xb * side, ya, za), (xb * side, yb, zb), (xa * side, yb, zb)]
                mb.f([mb.v(p) for p in q], BLACK, False, (0, 0, 1))
    else:
        for k in range(1, max(2, C.DECKS - 1)):
            ya, yb = floor_k(zt, k) + 0.6, floor_k(zt, k) + 1.6
            za = z_aft((ya - C.KEEL) / (sheer(zt) - C.KEEL)) + 0.03
            zb = z_aft((yb - C.KEEL) / (sheer(zt) - C.KEEL)) + 0.03
            xt = hull_x(yb, zt) * C.TRANSOM_HALF * 1.2
            nw = 7
            for i in range(nw):
                x0 = -xt + (2 * xt) * (i + 0.18) / nw
                x1 = -xt + (2 * xt) * (i + 0.82) / nw
                mb.f([mb.v((x0, ya, za)), mb.v((x1, ya, za)), mb.v((x1, yb, zb)), mb.v((x0, yb, zb))],
                     BLACK, False, (0, 0, 1))
            box(mb, (0, ya - 0.15, za + 0.2), (2 * xt + 0.4, 0.14, 0.5), STRAKE)  # gallery
    if C.QD is not None:
        # Great-cabin windows under the quarterdeck (and the poop): rows across the upright
        # upper transom
        zw = z_aft(1.0) + 0.03
        xt = hull_x(sheer(zt), zt) * C.TRANSOM_HALF * 1.4
        nw = 7 if C.B > 12 else (5 if C.B > 9 else 4)
        for lvl in range(2 if C.POOP is not None else 1):
            base = deck(zt) + lvl * C.RAISE
            ya, yb = base + 0.3 * C.RAISE, base + 0.75 * C.RAISE
            for k in range(nw):
                x0 = -xt + (2 * xt) * (k + 0.15) / nw
                x1 = -xt + (2 * xt) * (k + 0.85) / nw
                mb.f([mb.v((x0, ya, zw)), mb.v((x1, ya, zw)), mb.v((x1, yb, zw)), mb.v((x0, yb, zw))], BLACK, False, (0, 0, 1))
            box(mb, (0, base + C.RAISE - 0.1, zw + 0.05), (2 * xt + 0.4, 0.12, 0.12), STRAKE)  # trim
    return grid


def breast(mb, z, y_low, y, xe, face):
    """The red front of a raised deck (from y_low up to its deck at y), with a rail of
    balusters along its edge and two ladders down. face = -1 looks forward, +1 aft."""
    mb.f([mb.v((-xe, y_low - 0.05, z)), mb.v((xe, y_low - 0.05, z)), mb.v((xe, y + C.CROWN, z)),
          mb.v((-xe, y + C.CROWN, z))], INNER, False, (0, 0, face))
    zr = z + face * 0.05
    box(mb, (0, y + C.CROWN + 0.9, zr), (2 * xe, 0.08, 0.12), BLACK)  # breast rail
    nb = max(4, int(2 * xe / 0.5))
    for k in range(nb + 1):
        x = -xe + 2 * xe * k / nb
        box(mb, (x, y + C.CROWN + 0.45, zr), (0.06, 0.9, 0.06), WOOD)  # balusters
    steps = max(5, int((y - y_low) / 0.3))
    for x in (-xe * 0.55, xe * 0.55):  # ladders
        for k in range(steps):
            f = (k + 0.5) / steps
            box(mb, (x, y_low + C.CROWN + (y - y_low) * f, z + face * ((y - y_low) * 0.65 * (1.0 - f) + 0.1)),
                (0.7, 0.05, 0.22), WOOD)


def build_open_inside(mb, grid, T, R):
    """Open boat: inner skin, floorboards, gunwale cap, keel, rowing benches."""
    t = 0.08 * C.thick

    def inner(p):
        return Vector((max(p.x - t, 0.02), p.y, p.z))

    for side in (1, -1):
        for r in range(FLOOR_ROW, R - 1):
            for j in range(T - 1):
                q = [inner(grid[r][j]), inner(grid[r][j + 1]), inner(grid[r + 1][j + 1]), inner(grid[r + 1][j])]
                mb.f([mb.v((p.x * side, p.y, p.z), (-p.z / 2.0, p.y / 2.0)) for p in q], INNER, True, (-side, 0, 0))
        for j in range(T - 1):
            o0, o1 = grid[R - 1][j], grid[R - 1][j + 1]
            i0, i1 = inner(o0), inner(o1)
            pts = [(o0.x + 0.02, o0.y + 0.03, o0.z), (o1.x + 0.02, o1.y + 0.03, o1.z),
                   (i1.x - 0.01, i1.y + 0.03, i1.z), (i0.x - 0.01, i0.y + 0.03, i0.z)]
            mb.f([mb.v((q[0] * side, q[1], q[2])) for q in pts], BLACK, False, (0, 1, 0))
    for j in range(T - 1):  # floorboards
        a, b = inner(grid[FLOOR_ROW][j]), inner(grid[FLOOR_ROW][j + 1])
        mb.f([mb.v((a.x, a.y, a.z), (-a.z / 2, a.x / 2)), mb.v((b.x, b.y, b.z), (-b.z / 2, b.x / 2)),
              mb.v((-b.x, b.y, b.z), (-b.z / 2, -b.x / 2)), mb.v((-a.x, a.y, a.z), (-a.z / 2, -a.x / 2))],
             DECK, False, (0, 1, 0))
    for end in (0, T - 1):  # close the ends of the inner skin above the floor
        for r in range(FLOOR_ROW, R - 1):
            a, b = inner(grid[r][end]), inner(grid[r + 1][end])
            mb.f([mb.v((a.x, a.y, a.z)), mb.v((b.x, b.y, b.z)), mb.v((-b.x, b.y, b.z)), mb.v((-a.x, a.y, a.z))],
                 INNER, False, (0, 0, -1 if end == 0 else 1))
    k0 = C.FOREFOOT_Z + 0.025 * C.L
    k1 = C.POST_FOOT_Z - (0.025 * C.L if C.DOUBLE else 0.0)
    box(mb, (0.0, C.KEEL - 0.06 * C.sh, (k0 + k1) / 2.0), (0.14 * C.thick, 0.14 * C.sh, k1 - k0), BOTTOM)


def oar_stations():
    n = C.OARS
    return [(-0.3 + 0.55 * i / max(n - 1, 1)) * C.L for i in range(n)]


def build_open_fittings(mb, markers):
    sl, sh = C.sl, C.sh
    # Rowing benches with an oarlock (thole pin) at each end; the oars are drawn by ship.gd
    for i, z in enumerate(oar_stations()):
        yb = sheer(z) - 0.3 * C.thick
        xb = hull_x(yb, z) - 0.08 * C.thick
        box(mb, (0, yb, z), (2 * xb, 0.06, 0.28), WOOD)
        xo = hull_x(sheer(z), z)
        for side in (1, -1):
            box(mb, (side * xo, sheer(z) + 0.1, z), (0.05, 0.16, 0.05), BLACK)
        markers["oar_%d" % i] = (xo + 0.02, sheer(z) + 0.06, z)
    # Swivel guns on posts at the rail
    for gi, z in enumerate(C.GUN_Z):
        y = sheer(z) + 0.3
        xo = hull_x(sheer(z), z)
        for side in (1, -1):
            cyl(mb, (side * (xo - 0.05), sheer(z) - 0.1, z), (side * (xo - 0.05), y - 0.04, z), 0.05, 0.05, WOOD, 6)
            cyl(mb, (side * (xo - 0.45), y, z), (side * (xo + 0.35), y, z), 0.07, 0.05, IRON, 8)
        markers["gun_%d" % gi] = (xo + 0.4, y, z)
    build_rudder(mb, tiller=True)


def build_open_rig(mb, markers):
    rs = max(C.sh ** 0.8, 0.6)
    masts = mast_list()
    tallest = max(range(len(masts)), key=lambda i: masts[i][2])
    for i, (kind, z, h) in enumerate(masts):
        yf = deck_c(z) - 0.25 * C.thick  # foot marker: just below the gunwale
        floor = floor_y()
        top = yf + h
        cyl(mb, (0, floor, z), (0, top, z), 0.1 * rs, 0.065 * rs, SPAR, 8)
        cyl(mb, (0, top, z), (0, top + 0.06, z), 0.08 * rs, 0.08 * rs, BLACK, 6)
        head = top - (0.25 if kind == "lateen" else 0.35) * C.thick
        markers["mast_%d" % i] = (0.0, yf, z)
        markers["mast_%d_head" % i] = (0.0, head, z)
        markers["mast_%d_top" % i] = (0.0, top, z)
        if i == tallest:
            markers["flag"] = (0.0, top + 0.1, z)
        if kind == "lateen":  # a pair of shrouds a side, and a stay to the stem head
            for side in (1, -1):
                for dz in (-0.3, 0.5):
                    zz = z + dz * C.sl
                    rope(mb, (side * hull_x(sheer(zz), zz), sheer(zz), zz), (side * 0.08, head - 0.2, z), 0.02)
            zs = C.STEM_TOP_Z + 0.4
            rope(mb, (0, sheer(zs) + 0.05, zs), (0, head - 0.1, z), 0.02)


# ---------------------------------------------------------------------------
# Fittings and guns
# ---------------------------------------------------------------------------
def mast_list():
    """[(kind, z, total height)] bow to stern."""
    out = []
    for kind, zf, k in C.MASTS:
        out.append((kind, zf * C.L, k * C.MAST_FRAC * C.L))
    return out


def hatch(mb, z, w, l):
    y = deck_c(z)
    box(mb, (0, y + 0.1, z), (w, 0.22, l), WOOD)
    box(mb, (0, y + 0.2, z), (w - 0.16, 0.04, l - 0.16), BLACK)
    bars = max(3, int(l / 0.28))
    for k in range(1, bars):  # grating bars
        box(mb, (0, y + 0.225, z - l / 2 + 0.08 + k * (l - 0.16) / bars), (w - 0.16, 0.03, 0.05), WOOD)


def build_fittings(mb, markers):
    L, sl, sb, sh = C.L, C.sl, C.sb, C.sh
    masts = mast_list()
    mz = [m[1] for m in masts if m[0] != "trysail"]

    # Windlass and bowsprit bitts at the bow
    zw = -0.431 * L
    xw = 0.85 * sb
    cyl(mb, (-xw, deck_top_c(zw) + 0.38, zw), (xw, deck_top_c(zw) + 0.38, zw), 0.2 * C.thick, 0.2 * C.thick, WOOD, 10)
    for x in (-xw - 0.15, xw + 0.15):
        box(mb, (x, deck_top_c(zw) + 0.35, zw), (0.16, 0.7, 0.5), WOOD)
    zb = -0.494 * L
    for x in (-0.3, 0.3):
        box(mb, (x * C.thick, deck_top_c(zb) + 0.35, zb), (0.2 * C.thick, 0.7, 0.2 * C.thick), WOOD)

    # Hatches: fore hatch between the windlass and the foremast, main hatch with the boat
    # on it (between the first two masts, or just aft of a single mast)
    zf = (zw + mz[0]) / 2.0
    if mz[0] - zw > 3.0 and raise_at(zf) == 0.0:
        hatch(mb, zf, 1.0 * sb, min(1.0 * sl, (mz[0] - zw) - 2.0))
    if C.QD is not None and len(mz) > 1 and C.QD - mz[1] > 3.0:
        hatch(mb, (mz[1] + C.QD) / 2.0, 1.2 * sb, min(1.2 * sl, C.QD - mz[1] - 2.0))  # after hatch
    zc = (mz[0] + mz[1]) / 2.0 if len(mz) > 1 else 0.056 * L
    gap = (mz[1] - mz[0]) if len(mz) > 1 else 6.0
    blen = min(3.4 * math.sqrt(sl), gap - 1.6)
    hatch(mb, zc - 0.3 * sl, 1.5 * sb, 1.4 * sl)
    # The boat rests on two chocks with its keel clear of the hatch grating (top ~0.25 above
    # the deck) and of the deck's sheer along its length.
    # Its size follows its length (sloop: 3.4 m long, 1.3 m wide, 0.5 m deep), so a big
    # ship's longboat is a real boat, not a sloop's dinghy.
    yk = max(deck_c(zc + t * blen / 2.0) for t in (-1.0, -0.5, 0.0, 0.5, 1.0)) + 0.34
    bh, bd = 0.19 * blen, 0.147 * blen
    build_boat(mb, zc, yk + bd, blen, bh, bd)
    for dz in (-0.4, 0.4):
        z = zc + dz * blen * 0.6
        y_floor = deck(z)
        box(mb, (0, (y_floor + yk + 0.03) / 2.0, z), (1.5 * bh, yk + 0.03 - y_floor, 0.18), WOOD)

    # Cabin skylight/companion aft, clear of any mast (on the quarterdeck if there is one)
    zk = 0.225 * L
    if C.QD is not None and len(mz) > 2:
        zk = (C.QD + mz[2]) / 2.0 if mz[2] - C.QD > 3.0 else mz[2] + 1.6
    for m in mz:
        if abs(m - zk) < 1.2:
            zk = m + 1.4
    box(mb, (0, deck_top_c(zk) + 0.22, zk), (1.2 * min(sb, 1.4), 0.44, 1.3), WOOD)
    box(mb, (0, deck_top_c(zk) + 0.46, zk), (1.3 * min(sb, 1.4), 0.06, 1.4), BLACK)

    # Guns, lowest gun deck first (markers gun_N in that order, bow to stern in each row).
    # Lower decks: a port with its red lid hinged up and the muzzle run out. Weather deck:
    # carriage on deck, barrel out through an open port in the bulwark.
    g = min(1.25, math.sqrt(sh))
    gi = 0
    for k, zs in C.GUN_ROWS:
        for z in zs:
            if k > 0:
                yp = floor_k(z, k) + 0.6
                xo = hull_x(yp, z)
                ph, pw = 0.62, 0.7
                for side in (1, -1):
                    box(mb, (side * xo, yp, z), (0.1, ph, pw), BLACK)
                    a = math.radians(115.0)  # lid swung up and out
                    d = Vector((side * math.sin(a), -math.cos(a), 0.0))
                    n = Vector((d.y, -d.x, 0.0))
                    hinge = Vector((side * (xo + 0.04), yp + ph / 2.0, z))
                    R = Matrix(((n.x, d.x, 0.0), (n.y, d.y, 0.0), (0.0, 0.0, 1.0)))
                    box(mb, hinge + d * (ph / 2.0), (0.06, ph, pw), INNER, R)
                    cyl(mb, (side * (xo - 0.3), yp - 0.05, z), (side * (xo + 0.45), yp - 0.05, z), 0.15, 0.12, IRON, 8)
                markers["gun_%d" % gi] = (xo + 0.5, yp - 0.05, z)
            else:
                yp = deck(z) + 0.33 * g
                xo = hull_x(yp, z)
                xi = max(xo - C.BULWARK_THICK, 0.3)
                for side in (1, -1):
                    box(mb, (side * xo, yp, z), (0.08, 0.36 * g, 0.46 * g), BLACK)  # port opening
                    box(mb, (side * (xi - 0.42 * g), deck(z) + 0.2 * g, z), (0.7 * g, 0.3 * g, 0.46 * g), WOOD)
                    cyl(mb, (side * (xi - 0.85 * g), yp + 0.03, z), (side * (xo + 0.2), yp, z), 0.12 * g, 0.085 * g, IRON, 8)
                    cyl(mb, (side * (xo + 0.12), yp, z), (side * (xo + 0.22), yp, z), 0.105 * g, 0.105 * g, IRON, 8)
                markers["gun_%d" % gi] = (xo + 0.25, yp, z)
            gi += 1

    ys = build_rudder(mb, tiller=C.QD is None)
    if C.QD is not None:
        # Ship's wheel on the quarterdeck, between the mizzen and the taffrail
        zh = mz[-1] + (C.TRANSOM_TOP_Z - mz[-1]) * 0.45
        yh = deck_top_c(zh) + 1.0
        for x in (-0.35, 0.35):
            box(mb, (x, deck_top_c(zh) + 0.55, zh), (0.12, 1.1, 0.2), WOOD)
        cyl(mb, (-0.35, yh, zh), (0.35, yh, zh), 0.06, 0.06, WOOD, 6)  # axle
        cyl(mb, (0.22, yh, zh), (0.3, yh, zh), 0.7, 0.7, WOOD, 16)  # wheel rim (a disc)
        for k in range(8):
            a = math.pi * k / 4.0
            cyl(mb, (0.26, yh, zh), (0.26, yh + 0.85 * math.sin(a), zh + 0.85 * math.cos(a)), 0.03, 0.03, WOOD, 4)

    # Taffrail lantern
    zl = C.TRANSOM_TOP_Z - 0.1
    cyl(mb, (0, ys + 0.05, zl), (0, ys + 0.7, zl), 0.04, 0.04, BLACK, 6)
    box(mb, (0, ys + 0.85, zl), (0.24, 0.32, 0.24), BLACK)


def build_rudder(mb, tiller):
    """Outboard rudder on the sternpost, with a tiller over the taffrail. Returns the rail
    height at the stern."""
    L, sl, sh = C.L, C.sl, C.sh
    ys = sheer_top(C.TRANSOM_TOP_Z)
    top = ys + 0.15 * sh
    kb = C.KEEL - 0.15 * sh

    def le(y):
        return C.POST_FOOT_Z + 0.05 + (C.TRANSOM_TOP_Z + 0.08 - C.POST_FOOT_Z - 0.05) * (y - kb) / (top - kb)
    rud = [(kb, le(kb)), (kb, le(kb) + 1.0 * sl), (0.3 * sh, le(0.3 * sh) + 0.95 * sl),
           (1.1 * sh, le(1.1 * sh) + 0.32 * sl), (top, le(top) + 0.24 * sl), (top, le(top))]
    prism(mb, rud, 0.08 * C.thick, TOPSIDES)
    if tiller:
        zt = 0.27 * L
        cyl(mb, (0, top - 0.05, le(top) + 0.12), (0, deck_c(zt) + 0.8 * C.thick, zt), 0.07, 0.05, WOOD, 6)
    return ys


def build_boat(mb, zc, y0, L, Bh, D=0.5):
    """A small open boat, pointed at both ends: a simple lofted shell plus floorboards.
    y0 = gunwale height, D = depth (keel at y0 - D)."""
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
    floor = [Vector((max(p.x - 0.06, 0.02), p.y, p.z)) for p in grid[3]]
    for j in range(T - 1):
        a, b = floor[j], floor[j + 1]
        mb.f([mb.v((a.x, a.y, a.z)), mb.v((b.x, b.y, b.z)), mb.v((-b.x, b.y, b.z)), mb.v((-a.x, a.y, a.z))],
             INNER, False, (0, 1, 0))
    for dz in (-0.27, 0.0, 0.27):
        box(mb, (0, y0 - 0.12, zc + dz * L), (Bh * 1.7, 0.05, 0.22), WOOD)


# ---------------------------------------------------------------------------
# Masts, bowsprit and standing rigging
# ---------------------------------------------------------------------------
def build_rig(mb, markers):
    L, sl, sb, sh = C.L, C.sl, C.sb, C.sh
    rs = sh ** 0.8  # spar thickness scale
    masts = mast_list()
    heads, tops, feet, topmast_z = [], [], [], []
    tallest = max(range(len(masts)), key=lambda i: masts[i][2])

    for i, (kind, z, h) in enumerate(masts):
        yd = deck_top_c(z)
        feet.append(Vector((0.0, yd, z)))
        if kind == "trysail":
            # A snow's trysail mast: a thin pole just abaft the mainmast, up to its top.
            top = yd + h
            cyl(mb, (0, yd - 0.05, z), (0, top, z), 0.11 * rs, 0.09 * rs, SPAR, 8)
            heads.append(Vector((0.0, top - 0.3, z)))
            tops.append(Vector((0.0, top, z)))
            topmast_z.append(z)
            markers["mast_%d" % i] = (0.0, yd, z)
            markers["mast_%d_head" % i] = (0.0, top - 0.3, z)
            markers["mast_%d_top" % i] = (0.0, top, z)
            continue
        lower = {"gaff": 0.727, "spanker": 0.66}.get(kind, 0.62) * h  # gaff masts: tall lower mast
        head = yd + lower
        tz = z - 0.38 * rs
        cyl(mb, (0, yd - 0.05, z), (0, head + 0.5 * rs, z), 0.21 * rs, 0.15 * rs, SPAR, 12)
        box(mb, (0, head + 0.6 * rs, z - 0.19 * rs), (0.36 * rs, 0.2 * rs, 0.82 * rs), BLACK)  # cap
        for x in (-0.16, 0.16):
            box(mb, (x * rs, head - 0.25 * rs, z - 0.1 * rs), (0.08 * rs, 0.12 * rs, 1.1 * rs), SPAR)
        cw = 1.9 * sb if kind == "gaff" else 2.6 * sb
        if C.L > 28:
            cw = min(cw, 6.4)
        for dz in (-0.45, 0.25):
            box(mb, (0, head - 0.17 * rs, z + dz * rs), (cw, 0.07 * rs, 0.08 * rs), SPAR)  # crosstrees
        if kind != "gaff":
            box(mb, (0, head - 0.12 * rs, z - 0.1 * rs), (1.4 * sb, 0.06, 1.3 * rs), WOOD)  # fighting top
        truck = yd + h
        cyl(mb, (0, head - 0.9 * rs, tz), (0, truck, tz), 0.12 * rs, 0.07 * rs, SPAR, 10)
        cyl(mb, (0, truck, tz), (0, truck + 0.08, tz), 0.11 * rs, 0.11 * rs, BLACK, 8)
        heads.append(Vector((0.0, head, z)))
        tops.append(Vector((0.0, truck, tz)))
        topmast_z.append(tz)
        markers["mast_%d" % i] = (0.0, yd, z)
        markers["mast_%d_head" % i] = (0.0, head - 0.15 * rs, z)
        markers["mast_%d_top" % i] = (0.0, truck, z)
    markers["flag"] = tuple(tops[tallest] + Vector((0.0, 0.1, 0.0)))

    # Bowsprit (with a jib-boom look on longer ones: a thinner second section)
    a = math.radians(C.SPRIT_ANGLE)
    zh = -0.481 * L
    heel = Vector((0.0, deck_top_c(zh) + 0.25 * sh, zh))
    d = Vector((0.0, math.sin(a), -math.cos(a)))
    tip = heel + d * C.SPRIT_LEN
    if C.L >= 20:
        mid = heel + d * C.SPRIT_LEN * 0.62
        cyl(mb, heel, mid + d * 0.6, 0.19 * rs, 0.13 * rs, SPAR, 10)
        cyl(mb, mid - d * 0.8, tip, 0.1 * rs, 0.07 * rs, SPAR, 8)
        cyl(mb, mid - d * 0.1, mid + d * 0.3, 0.17 * rs, 0.17 * rs, BLACK, 8)  # cap
    else:
        cyl(mb, heel, tip, 0.19 * rs, 0.1 * rs, SPAR, 10)
    cyl(mb, tip - d * 0.3, tip + d * 0.05, 0.11 * rs, 0.11 * rs, BLACK, 8)

    # Headstays: jibstay from the fore topmast to the bowsprit tip (the jib rides on it),
    # forestay from the fore masthead to the stem head, bobstay under the bowsprit.
    fore_kind, fz, fh = masts[0]
    jib_head = Vector((0.0, feet[0].y + 0.86 * fh, topmast_z[0]))
    jib_tack = tip - d * 0.35
    rope(mb, jib_head, jib_tack)
    zs = -0.606 * L
    rope(mb, heads[0] + Vector((0, -0.1, -0.2 * rs)), (0, sheer_top(zs) + 0.05, zs), 0.04 * rs)
    zbob = -0.53 * L
    bob = Vector((0.0, -0.1 * sh, z_fore((-0.1 * sh - C.KEEL) / (sheer(zbob) - C.KEEL)) - 0.4 * sl))
    rope(mb, tip - d * 0.6, bob, 0.035 * rs)
    markers["jib_tack"] = tuple(jib_tack)
    markers["jib_head"] = tuple(jib_head)

    # Stays between masts: each mast's masthead and topmast are stayed to the mast ahead.
    for i in range(1, len(masts)):
        if masts[i][0] == "trysail":
            continue
        rope(mb, heads[i] + Vector((0, -0.1, 0)), feet[i - 1] + Vector((0, 1.6 * sh, 0)), 0.04 * rs)
        rope(mb, tops[i] + Vector((0, -0.5, 0)), heads[i - 1] + Vector((0, 0.3, 0)), 0.03 * rs)

    # Shrouds with ratlines, channels, deadeyes and chainplates; topmast shrouds; backstays
    n_shrouds = 3 if L < 20 else (4 if L < 28 else (5 if L < 44 else 6))
    for i, (kind, z, h) in enumerate(masts):
        if kind == "trysail":
            continue
        head = heads[i]
        for side in (1, -1):
            span = 0.6 * min(sl, 2.5) * (n_shrouds - 1)
            # Channel just abaft the mast, kept clear of the stern (a galleon's bonaventure)
            zc_ch = min(z + 0.75 * sl, C.TRANSOM_TOP_Z - 0.8 - (span + 0.5 * sl) / 2.0)
            ych = sheer_top(zc_ch) - 0.25 * sh
            xo = hull_x(ych, zc_ch)
            box(mb, (side * (xo + 0.17 * C.thick), ych, zc_ch), (0.34 * C.thick, 0.07, span + 0.5 * sl), BLACK)
            lows, highs = [], []
            for k in range(n_shrouds):
                zk = zc_ch - span / 2 + span * k / max(n_shrouds - 1, 1)
                xo_k = hull_x(ych, zk)
                dead = Vector((side * (xo_k + 0.3 * C.thick), ych + 0.18, zk))
                cyl(mb, dead - Vector((0, 0.1, 0)), dead + Vector((0, 0.1, 0)), 0.09, 0.09, BLACK, 6)
                box(mb, (side * (xo_k + 0.02), ych - 0.35 * sh, zk), (0.03, 0.7 * sh, 0.06), BLACK)
                hi = Vector((side * 0.2 * rs, head.y - 0.35 * rs, z + 0.05 * k))
                rope(mb, dead + Vector((0, 0.1, 0)), hi, 0.03 * rs)
                lows.append(dead + Vector((0, 0.1, 0)))
                highs.append(hi)
            n = int(18 * (head.y - feet[i].y) / 9.3)
            for r in range(1, n):
                s = r / n
                if s > 0.86:
                    break
                rope(mb, lows[0].lerp(highs[0], s), lows[-1].lerp(highs[-1], s), 0.012, 3)
            cw = (1.9 * sb if kind == "gaff" else 2.6 * sb) / 2.0
            if C.L > 28:
                cw = min(cw, 3.2)
            rope(mb, (side * (cw - 0.05), head.y - 0.17 * rs, z - 0.1 * rs),
                 (side * 0.06, feet[i].y + 0.9 * h, topmast_z[i]), 0.02 * rs)
            zb = z + 4.2 * sl
            if zb < C.TRANSOM_TOP_Z - 0.5:
                rope(mb, (side * 0.05, feet[i].y + 0.95 * h, topmast_z[i]),
                     (side * (hull_x(sheer(zb), zb) + 0.15), sheer_top(zb), zb), 0.025 * rs)


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


def save_image(name, rgb, non_color=False):
    os.makedirs(TEX_DIR, exist_ok=True)
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
    if not m.node_tree:
        m.use_nodes = True
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
        col = C.PALETTE.get(name, col)
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


def preview(out_dir):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "MATERIAL"
    scene.display.shading.show_shadows = True
    scene.display.shading.show_cavity = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    cam_data = bpy.data.cameras.new("cam")
    cam = bpy.data.objects.new("cam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    k = C.L / BASE_L
    target = to_bl((0.0, 3.5 * k, -0.15 * C.L))
    views = {
        "side": (to_bl((40.0 * k, 6.0 * k, -0.15 * C.L)), 34.0),
        "three_quarter": (to_bl((22.0 * k, 16.0 * k, -24.0 * k)), 38.0),
        "top": (to_bl((0.5, 70.0 * k, -0.1 * C.L)), 30.0),
    }
    for name, (pos, fov) in views.items():
        cam.location = pos
        cam.rotation_euler = (target - pos).to_track_quat("-Z", "Y").to_euler()
        cam_data.angle = math.radians(fov)
        scene.render.filepath = os.path.join(out_dir, "%s_%s.png" % (C.id, name))
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def build(ship_id, preview_dir):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    setup(ship_id)
    mats = build_materials()
    mb = MB()
    markers = {}
    build_hull(mb)
    if C.OPEN:
        build_open_fittings(mb, markers)
        build_open_rig(mb, markers)
    else:
        build_fittings(mb, markers)
        build_rig(mb, markers)
    to_object(mb, "hull", mats)
    for name, p in markers.items():
        e = bpy.data.objects.new(name, None)
        e.location = to_bl(p)
        e.empty_display_size = 0.3
        bpy.context.scene.collection.objects.link(e)
    print("%s: %d verts, %d faces" % (ship_id, len(mb.verts), len(mb.faces)))
    if preview_dir:
        os.makedirs(preview_dir, exist_ok=True)
        preview(preview_dir)
    out = os.path.join(REPO, "assets", "ships", ship_id, ship_id + ".glb")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=out, export_format="GLB", use_selection=False)
    print("exported", out)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    which = argv[0] if argv else "all"
    preview_dir = os.path.abspath(argv[1]) if len(argv) > 1 else ""
    ids = list(SHIPS) if which == "all" else which.split(",")
    for ship_id in ids:
        build(ship_id, preview_dir)


main()
