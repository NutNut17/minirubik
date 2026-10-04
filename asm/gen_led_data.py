#!/usr/bin/env python3
"""Generates led_data.s (the data the LED template needs) and expected_frames.txt, and
proves the data right before writing anything:

  1. a physical model (3D sticker positions, quarter turns of R, B, D) is checked against the
     solver's own move tables (source/twist read from ../solver.c) on random states;
  2. the template's table-driven rendering (the same lookups the assembly does) is compared with
     the physical model's picture of the cube on every frame of the dummy test case.

Run:  python3 gen_led_data.py            (needs only the Python standard library)
"""
import random, re, sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 35, 25                                   # LED matrix size
FW, FH = 4, 3                                   # one facelet is 4 pixels wide, 3 tall
PALETTE = {'W': 0xFFFFFF, 'Y': 0xFFFF00, 'G': 0x00C800, 'B': 0x0000FF, 'O': 0xFF8000, 'R': 0xFF0000}
COLNAMES = ['W', 'Y', 'G', 'B', 'O', 'R']       # colour index used by the assembly

# ---- geometry ---------------------------------------------------------------
# corner positions, labelled as in report.md: 0 FUL, 1 FUR, 2 FDR, 3 FDL, 4 BUR, 5 BDR, 6 BDL, 7 BUL
POS = {0: (-1, 1, 1), 1: (1, 1, 1), 2: (1, -1, 1), 3: (-1, -1, 1),
       4: (1, 1, -1), 5: (1, -1, -1), 6: (-1, -1, -1), 7: (-1, 1, -1)}
COL = {(0, 1, 0): 'W', (0, -1, 0): 'Y', (0, 0, 1): 'G', (0, 0, -1): 'B', (-1, 0, 0): 'O', (1, 0, 0): 'R'}
FACE_OF = {(0, 1, 0): 'U', (0, -1, 0): 'D', (0, 0, 1): 'F', (0, 0, -1): 'B', (-1, 0, 0): 'L', (1, 0, 0): 'R'}
# the unfolded net of report.md: face -> (slot column, slot row, 2x2 grid of position labels)
NET = {'U': (1, 0, [[7, 4], [0, 1]]), 'L': (0, 1, [[7, 0], [6, 3]]), 'F': (1, 1, [[0, 1], [3, 2]]),
       'R': (2, 1, [[1, 4], [2, 5]]), 'B': (3, 1, [[4, 7], [5, 6]]), 'D': (1, 2, [[3, 2], [6, 5]])}

def facelet_xy(face, label):
    """top-left pixel of the facelet that position `label` shows on `face` (4 x 3 pixels)."""
    sc, sr, grid = NET[face]
    for r in range(2):
        for c in range(2):
            if grid[r][c] == label:
                return sc * (2 * FW + 1) + c * FW, sr * (2 * FH + 1) + r * FH
    raise KeyError((face, label))

def rotate(v, axis, q):                         # q = +1: +90 degrees about +axis, -1: -90
    x, y, z = v
    if axis == 0: return (x, -q * z, q * y)
    if axis == 1: return (q * z, y, -q * x)
    return (-q * y, q * x, z)

LAYER = {0: (lambda p: p[0] == 1, 0, -1), 1: (lambda p: p[2] == -1, 2, +1), 2: (lambda p: p[1] == -1, 1, +1)}

def det(a, b, c):
    return a[0]*(b[1]*c[2]-b[2]*c[1]) - a[1]*(b[0]*c[2]-b[2]*c[0]) + a[2]*(b[0]*c[1]-b[1]*c[0])

def cw_order(label):
    """normals of the corner, U/D first, then clockwise seen from outside the cube."""
    x, y, z = POS[label]; u, a, b = (0, y, 0), (x, 0, 0), (0, 0, z)
    return [u, b, a] if det(u, a, b) > 0 else [u, a, b]

# ---- solver tables, read from the source so they cannot drift ---------------
src = open(os.path.join(HERE, '..', 'solver.c')).read()
def grab(name):
    body = re.search(name + r'\[3\]\[CUBIES\] = \{(.*?)\};', src, re.S).group(1)
    return [[int(x) for x in row.split(',')] for row in re.findall(r'\{([^}]*)\}', body)]
SRC, TW = grab('source'), grab('twist')

# ---- physical model ------------------------------------------------------------
def physical(p, o):
    """sticker -> (corner position vector, outward normal) for solver state (p, o).
    rule verified against the solver's tables below: sticker j of a cubie lands in slot (j - t) mod 3."""
    st = {(0, n): (POS[0], n) for n in cw_order(0)}
    for i in range(7):
        cub = p[i] + 1; slots = cw_order(i + 1)
        for j, n in enumerate(cw_order(cub)):
            st[(cub, n)] = (POS[i + 1], slots[(j - o[i]) % 3])
    return st

def phys_turn(st, f):
    inl, ax, q = LAYER[f]
    return {k: ((rotate(pp, ax, q), rotate(n, ax, q)) if inl(pp) else (pp, n)) for k, (pp, n) in st.items()}

def phys_read(st):
    p = [0] * 7; o = [0] * 7
    for i in range(7):
        here = {k[0] for k, (pp, _) in st.items() if pp == POS[i + 1]}
        assert len(here) == 1
        cub = here.pop(); slots = cw_order(i + 1)
        y = [n for (c, n0), (pp, n) in st.items() if c == cub and n0[1] != 0][0]
        p[i] = cub - 1; o[i] = (-slots.index(y)) % 3
    return p, o

def phys_picture(st):
    """pixel -> colour word, drawn straight from the physical stickers."""
    fb = [[0] * W for _ in range(H)]
    for (cub, n0), (pp, n) in st.items():
        label = [l for l, v in POS.items() if v == pp][0]
        x0, y0 = facelet_xy(FACE_OF[n], label)
        for y in range(FH):
            for x in range(FW):
                fb[y0 + y][x0 + x] = PALETTE[COL[n0]]
    return fb

# ---- tables the assembly uses -----------------------------------------------------
def color_table():           # COLOR[(cubie*3 + twist)*3 + slot] = colour index, cubie 0..6 = report cubies 1..7
    t = []
    for k in range(7):
        home = cw_order(k + 1)
        for tw in range(3):
            for s in range(3):
                t.append(COLNAMES.index(COL[home[(s + tw) % 3]]))
    return t

def pix_table():             # PIX[idx*3 + slot] = byte offset (y*W + x)*4 of the facelet at position idx+1
    t = []
    for i in range(7):
        for n in cw_order(i + 1):
            x, y = facelet_xy(FACE_OF[n], i + 1); t.append((y * W + x) * 4)
    return t

def fixed_entries():         # the fixed corner never moves: (offset, colour index) x 3
    return [((lambda xy: (xy[1] * W + xy[0]) * 4)(facelet_xy(FACE_OF[n], 0)), COLNAMES.index(COL[n])) for n in cw_order(0)]

COLOR, PIX, FIXED = color_table(), pix_table(), fixed_entries()

def table_picture(p, o):     # exactly what draw_cube does with the tables
    fb = [[0] * W for _ in range(H)]
    for off, c in FIXED: block(fb, off, PALETTE[COLNAMES[c]])
    for i in range(7):
        for s in range(3):
            block(fb, PIX[i * 3 + s], PALETTE[COLNAMES[COLOR[(p[i] * 3 + o[i]) * 3 + s]]])
    return fb
def block(fb, off, word):
    x0, y0 = (off // 4) % W, (off // 4) // W
    for y in range(FH):
        for x in range(FW): fb[y0 + y][x0 + x] = word

def checksum(fb):            # the template's selftest: s = rotl(s,1) ^ word over all 875 words, row-major
    s = 0
    for row in fb:
        for w in row: s = (((s << 1) | (s >> 31)) & 0xFFFFFFFF) ^ w
    return s

def ascii_net(fb):
    inv = {v: k for k, v in PALETTE.items()}
    return '\n'.join(''.join(inv.get(fb[y][x], '.') for x in range(W)) for y in range(20))

# ---- proofs -----------------------------------------------------------------------
def apply_table(p, o, m):
    f, turns = m // 3, m % 3 + 1
    for _ in range(turns):
        p, o = [p[SRC[f][i]] for i in range(7)], [(o[SRC[f][i]] + TW[f][i]) % 3 for i in range(7)]
    return p, o

random.seed(7)
for _ in range(300):                                     # 1. physical model == solver tables
    p = list(range(7)); random.shuffle(p); o = [random.randrange(3) for _ in range(6)]; o.append((-sum(o)) % 3)
    for f in range(3):
        assert phys_read(phys_turn(physical(p, o), f)) == ([p[SRC[f][i]] for i in range(7)],
                                                          [(o[SRC[f][i]] + TW[f][i]) % 3 for i in range(7)]), (p, o, f)
assert all(phys_picture(physical(list(range(7)), [0] * 7)) == table_picture(list(range(7)), [0] * 7) for _ in [0])

# ---- the dummy test case ----------------------------------------------------------------
STATE = '21345671111111'                                  # distance 11, hw2.md's sample vector
PATH = [0, 5, 7, 2, 3, 2, 5, 0, 7, 0, 3]                  # R B' D2 R' B R' B' R D2 R B  (face*3 + turns - 1)
NAMES = ['R', 'R2', "R'", 'B', 'B2', "B'", 'D', 'D2', "D'"]
p = [int(c) - 1 for c in STATE[:7]]; o = [int(c) - 1 for c in STATE[7:]]
frames = [(None, p[:], o[:])]
for m in PATH:
    p, o = apply_table(p, o, m); frames.append((m, p[:], o[:]))
assert p == list(range(7)) and o == [0] * 7, "dummy path must solve the dummy state"

# walk the physical cube too (a move is 1-3 quarter turns) and compare every frame
st = physical([int(c) - 1 for c in STATE[:7]], [int(c) - 1 for c in STATE[7:]])
sums = []
for k, (m, fp, fo) in enumerate(frames):
    if k > 0:
        for _ in range(m % 3 + 1): st = phys_turn(st, m // 3)
    a, b = table_picture(fp, fo), phys_picture(st)
    assert a == b, "frame %d: table picture differs from the physical cube" % k
    sums.append(checksum(a))
print("physical model == solver move tables (900 random turns), and %d frames match the physical cube" % len(frames))

# ---- write the outputs ---------------------------------------------------------------------
def rows(label, values, directive, per=12):
    out = [label + ':']
    for i in range(0, len(values), per):
        out.append('    %s %s' % (directive, ','.join(str(v) for v in values[i:i + per])))
    return '\n'.join(out)

with open(os.path.join(HERE, 'led_data.s'), 'w') as f:
    f.write('# generated by gen_led_data.py (do not edit); proofs run at generation time\n    .data\n')
    f.write('# palette: colour index -> 0x00RRGGBB, order %s\n' % ' '.join(COLNAMES))
    f.write('PALETTE:\n    .word %s\n' % ','.join('0x%06X' % PALETTE[c] for c in COLNAMES))
    f.write('# COLOR[(cubie*3 + twist)*3 + slot]: colour index of the sticker in `slot` of a position\n')
    f.write(rows('COLOR', COLOR, '.byte') + '\n')
    f.write('# PIX[idx*3 + slot]: byte offset ((y*35 + x)*4) of the 4x3 facelet block, idx = position - 1\n')
    f.write(rows('PIX', PIX, '.half', 9) + '\n')
    f.write('# FIXED: the fixed corner (offset .half, colour .half) x 3, drawn once\n')
    f.write('FIXED:\n    .half %s\n' % ','.join('%d,%d' % e for e in FIXED))
    f.write('# move tables of solver.c: SRC[face*7 + i], TW[face*7 + i]; move m = face*3 + turns - 1\n')
    f.write(rows('SRC', [v for r in SRC for v in r], '.byte') + '\n')
    f.write(rows('TW', [v for r in TW for v in r], '.byte') + '\n')
    f.write('MOVEF:\n    .byte 0,0,0,1,1,1,2,2,2\nMOVET:\n    .byte 1,2,3,1,2,3,1,2,3\n')
    f.write('# dummy test case\nSTATE:\n    .asciz "%s"\nDUMMYPATH:\n    .byte %s\n    .align 2\n' % (STATE, ','.join(map(str, PATH))))
    f.write('EXPECT_SUMS:\n    .word %s\n' % ','.join('0x%08X' % s for s in sums))
with open(os.path.join(HERE, 'expected_frames.txt'), 'w') as f:
    f.write('Expected picture for the dummy test case %s, solved by: %s\n' % (STATE, ' '.join(NAMES[m] for m in PATH)))
    f.write('(W white U, Y yellow D, G green F, B blue B, O orange L, R red R; "." = off; only the top 20 of 25 rows are used)\n')
    for k, (m, fp, fo) in enumerate(frames):
        f.write('\nframe %d  %s   checksum 0x%08X\n%s\n' % (k, 'scrambled state' if m is None else 'after ' + NAMES[m], sums[k], ascii_net(table_picture(fp, fo))))
print("wrote led_data.s and expected_frames.txt;  frame checksums:", ' '.join('%08X' % s for s in sums[:3]), '...')
