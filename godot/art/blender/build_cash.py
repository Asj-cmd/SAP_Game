"""The cash bundle: a banded stack of notes.

Built to FIFTY UNITS across, because that is the cube the greybox draws today
(greybox_main.CASH_SIZE) and the size the pickup range was tuned against. The
model replaces that cube and must not change how big the thing reads.

Its ORIGIN IS THE BOTTOM, not the centre. CarrySystem rests a carriable exactly
on the surface it lands on and treats it as a point, so a model centred on its
own middle buries half of itself in the floor - which is the bug that was fixed
in presentation for the placeholder cube and must not come back with the art.

  blender --background --python build_cash.py
"""

import math
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import _common as C  # noqa: E402

SIZE = 50.0          # matches greybox_main.CASH_SIZE
NOTE_W = SIZE * 0.86
NOTE_D = SIZE * 0.46
NOTE_T = SIZE * 0.055
NOTES = 7


def build():
    C.clear()
    paper = C.material("Note", (0.42, 0.62, 0.38), rough=0.85)
    ink = C.material("Ink", (0.20, 0.38, 0.24), rough=0.85)
    band = C.material("Band", (0.72, 0.18, 0.16), rough=0.7)

    # The stack. Alternating tones so the edge reads as separate notes at a
    # distance rather than one solid brick - this is seen from across a room,
    # in motion, more often than it is seen up close.
    stack = NOTES * NOTE_T
    for i in range(NOTES):
        # A little jitter per note, so the stack looks handled rather than
        # machined. Deterministic, not random: the same bundle every build.
        skew = math.radians(2.2 * math.sin(i * 1.7))
        C.box(
            "note_%d" % i,
            (NOTE_W, NOTE_D, NOTE_T),
            (0.0, 0.0, NOTE_T * 0.5 + i * NOTE_T),
            paper if i % 2 == 0 else ink,
            rot=(0.0, 0.0, skew),
        )

    # The paper band, proud of the stack so it catches light on its own.
    C.box(
        "band",
        (NOTE_W * 0.30, NOTE_D * 1.06, stack * 1.04),
        (0.0, 0.0, stack * 0.5),
        band,
    )
    return stack


def main():
    stack = build()
    # Sit the whole thing on z=0 so the model's origin is its BOTTOM. Godot
    # positions a carriable at the point it rests on, not at its middle.
    for ob in bpy.data.objects:
        ob.location.z -= 0.0  # stack already starts at z=0 by construction
    print("cash bundle: %.1f wide, %.1f deep, %.1f tall (target %.0f)" % (
        NOTE_W, NOTE_D, stack, SIZE))
    C.export("cash.glb")


main()
