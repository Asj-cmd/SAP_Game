"""The cash bundle: a banded stack of notes.

Built to FIFTY UNITS across, because that is the cube the greybox drew
(greybox_main.CASH_SIZE) and the size the pickup range was tuned against. The
model replaces that cube and must not change how big the thing reads.

Its ORIGIN IS THE BOTTOM, not the centre. CarrySystem rests a carriable exactly
on the surface it lands on and treats it as a point, so a model centred on its
own middle buries half of itself in the floor.

THE NOTES DO NOT FAN. The first version rotated each note a couple of degrees to
look "handled", and from across a room that read as a splayed deck of cards
rather than a bundle of money - the edges caught light individually and the
silhouette went ragged. A bundle is a BLOCK: tight stack, one band round it,
crisp rectangular outline. Money reads by colour and shape, not by detail.

  blender --background --python build_cash.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import _common as C  # noqa: E402

SIZE = 50.0          # greybox_main.CASH_SIZE
NOTE_W = SIZE * 0.88
NOTE_D = SIZE * 0.44
NOTES = 6
NOTE_T = SIZE * 0.052
STACK = NOTES * NOTE_T


def build():
    C.clear()
    # Two greens a shade apart. The banding is what makes the side of the stack
    # read as separate notes; it does not need geometry to do it.
    pale = C.material("NotePale", (0.47, 0.64, 0.42), rough=0.9)
    deep = C.material("NoteDeep", (0.33, 0.50, 0.33), rough=0.9)
    band = C.material("Band", (0.74, 0.19, 0.17), rough=0.65)
    seal = C.material("Seal", (0.86, 0.74, 0.30), rough=0.45, metal=0.3)

    # The stack: square, aligned, no rotation.
    for i in range(NOTES):
        C.box("note_%d" % i, (NOTE_W, NOTE_D, NOTE_T),
              (0.0, 0.0, NOTE_T * 0.5 + i * NOTE_T),
              pale if i % 2 == 0 else deep)

    # The band WRAPS: a strip across the top and down both faces, built as
    # three thin boxes rather than one plate. A single plate through the middle
    # was invisible from above, which is the angle this is usually seen from.
    band_w = NOTE_W * 0.26
    over = NOTE_T * 0.6
    C.box("band_top", (band_w, NOTE_D * 1.04, over),
          (0.0, 0.0, STACK + over * 0.35), band)
    for side, y in (("f", -1.0), ("b", 1.0)):
        C.box("band_%s" % side, (band_w, over, STACK * 1.02),
              (0.0, y * (NOTE_D * 0.5 + over * 0.3), STACK * 0.5), band)

    # A small seal on the band, so there is one warm accent to catch the eye
    # when the bundle is lying on a dark floor.
    C.box("seal", (band_w * 0.42, band_w * 0.42, over * 0.7),
          (0.0, -(NOTE_D * 0.5 + over * 0.45), STACK * 0.55), seal)

    print("cash: %.1f x %.1f x %.1f (target %.0f across)" % (
        NOTE_W, NOTE_D, STACK + over, SIZE))


build()
C.export("cash.glb")
