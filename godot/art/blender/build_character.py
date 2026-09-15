"""The two families, as one script with a colour per team.

SIZED TO THE SIMULATION, not to taste. The body is 180 units tall and 40 across
(TuningDef.actor_height, actor_radius * 2), because those are the numbers every
rule in the game is built on: what fits under a crouch gap, what the jump's
ceiling cap measures against, how close two bodies can stand. A character that
looks right but measures wrong would make all of that read as broken.

ORIGIN AT THE FEET. The simulation's position is a body centre one radius above
the floor, and greybox_main lifts the mesh to match; a model whose origin is its
middle would sink, exactly as the cash bundle did.

STYLE: chunky and readable at distance. This is a chase game seen from a
third-person camera across a room - silhouette carries everything, detail
carries nothing. Big head, strong team colour on the torso.

PARTS OVERLAP AT EVERY JOINT. The first version butted them edge to edge, and
from two metres away the arms hung visibly detached from the shoulders and the
hands floated under the sleeves. Nothing here is welded or boolean'd - these are
separate boxes - so the only thing holding the figure together is that each part
starts INSIDE the one it grows from. Overlap is cheap; a floating limb is not.

  blender --background --python build_character.py
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import _common as C  # noqa: E402

HEIGHT = 180.0   # TuningDef.actor_height
WIDTH = 40.0     # actor_radius * 2

TEAMS = {
    "a": {
        "skin": (0.88, 0.71, 0.57),
        "shirt": (0.78, 0.22, 0.20),   # the team tint greybox_main already uses
        "cuff": (0.62, 0.16, 0.15),
        "trouser": (0.25, 0.28, 0.38),
        "hair": (0.28, 0.18, 0.11),
        "shoe": (0.16, 0.13, 0.12),
    },
    "b": {
        "skin": (0.79, 0.62, 0.49),
        "shirt": (0.22, 0.38, 0.75),
        "cuff": (0.16, 0.28, 0.58),
        "trouser": (0.26, 0.24, 0.28),
        "hair": (0.14, 0.12, 0.11),
        "shoe": (0.14, 0.13, 0.14),
    },
}


def build(team):
    C.clear()
    t = TEAMS[team]
    skin = C.material("Skin", t["skin"], rough=0.75)
    shirt = C.material("Shirt", t["shirt"], rough=0.8)
    cuff = C.material("Cuff", t["cuff"], rough=0.8)
    trouser = C.material("Trouser", t["trouser"], rough=0.85)
    hair = C.material("Hair", t["hair"], rough=0.9)
    shoe = C.material("Shoe", t["shoe"], rough=0.6)
    eye = C.material("Eye", (0.07, 0.07, 0.09), rough=0.3)

    # EVERYTHING BELOW IS IN SIMULATION UNITS, summing to HEIGHT. An earlier
    # version wrote the vertical budget as fractions of 1.0 while writing the
    # horizontal positions as `fraction * WIDTH`, then scaled the result to fit
    # - so the two axes were in different units and the fit-up multiplied the
    # whole figure by 181. It exploded. One unit, everywhere, and no rescale.
    shoe_h = HEIGHT * 0.055
    leg_h = HEIGHT * 0.300
    torso_h = HEIGHT * 0.345
    neck_h = HEIGHT * 0.035
    head_h = HEIGHT * 0.265

    z_shoe = shoe_h
    z_leg = z_shoe + leg_h
    z_torso = z_leg + torso_h
    z_neck = z_torso + neck_h

    # --- legs -------------------------------------------------------------
    # Each leg starts BELOW the hip line and the shoe starts below the ankle,
    # so there is no seam to see through at any angle.
    for side, x in (("l", -0.24), ("r", 0.24)):
        C.box("leg_%s" % side, (WIDTH * 0.38, WIDTH * 0.36, leg_h + HEIGHT * 0.05),
              (x * WIDTH, 0.0, z_shoe + leg_h * 0.5 - HEIGHT * 0.02), trouser)
        # Shoe: longer than it is wide, pushed forward, so the figure has a
        # facing even when it is standing still.
        C.box("shoe_%s" % side, (WIDTH * 0.40, WIDTH * 0.54, shoe_h * 1.6),
              (x * WIDTH, -0.07 * WIDTH, shoe_h * 0.55), shoe)

    # --- torso ------------------------------------------------------------
    # Two stacked blocks rather than one slab: a wider chest over a narrower
    # waist reads as a body instead of a fridge, and costs one box.
    waist_z = z_leg + torso_h * 0.28
    chest_z = z_leg + torso_h * 0.72
    C.box("waist", (WIDTH * 0.78, WIDTH * 0.50, torso_h * 0.60),
          (0.0, 0.0, waist_z), shirt)
    C.box("chest", (WIDTH * 0.96, WIDTH * 0.58, torso_h * 0.58),
          (0.0, 0.0, chest_z), shirt)

    # --- arms -------------------------------------------------------------
    # The sleeve starts INSIDE the chest (x is inboard of the chest's edge) and
    # hangs past the waist; the hand starts inside the sleeve. That overlap is
    # what stopped them floating.
    arm_top = z_torso - torso_h * 0.06
    arm_len = torso_h * 0.86
    for side, x in (("l", -0.44), ("r", 0.44)):
        C.box("sleeve_%s" % side, (WIDTH * 0.24, WIDTH * 0.28, arm_len),
              (x * WIDTH, 0.0, arm_top - arm_len * 0.5), shirt)
        C.box("cuff_%s" % side, (WIDTH * 0.25, WIDTH * 0.29, arm_len * 0.18),
              (x * WIDTH, 0.0, arm_top - arm_len * 0.88), cuff)
        C.box("hand_%s" % side, (WIDTH * 0.26, WIDTH * 0.30, HEIGHT * 0.085),
              (x * WIDTH, 0.0, arm_top - arm_len * 0.98), skin)

    # --- neck and head ----------------------------------------------------
    # The neck sinks into both the chest and the skull, so neither joint shows.
    C.box("neck", (WIDTH * 0.34, WIDTH * 0.30, neck_h + HEIGHT * 0.04),
          (0.0, 0.0, z_torso + neck_h * 0.5 - HEIGHT * 0.01), skin)
    head_z = z_neck + head_h * 0.48
    C.box("head", (WIDTH * 0.80, WIDTH * 0.70, head_h * 0.92), (0.0, 0.0, head_z), skin)

    # Hair as a cap with sides, not a lid: a crown box plus a thin band round
    # the back and sides, which is what stops it reading as a flat plate.
    C.box("hair_top", (WIDTH * 0.84, WIDTH * 0.74, head_h * 0.30),
          (0.0, 0.0, head_z + head_h * 0.34), hair)
    C.box("hair_back", (WIDTH * 0.84, WIDTH * 0.26, head_h * 0.62),
          (0.0, 0.23 * WIDTH, head_z + head_h * 0.04), hair)

    # Eyes on the -Y face, which is forward after the glTF Y-up conversion.
    # Slightly proud of the face so they never z-fight with it.
    for x in (-0.18, 0.18):
        C.box("eye", (WIDTH * 0.12, WIDTH * 0.05, head_h * 0.15),
              (x * WIDTH, -0.355 * WIDTH, head_z + head_h * 0.07), eye)

    # No rescale. The budget above already sums to HEIGHT, so the figure is the
    # right size by construction - which is the only way to keep it that way
    # when a proportion is later nudged by eye.
    top = head_z + head_h * 0.49
    print("character %s: %.1f tall, %.1f wide (targets %.0f / %.0f)" % (
        team, top, WIDTH * 0.96, HEIGHT, WIDTH))


def main():
    for team in TEAMS:
        build(team)
        C.export("character_%s.glb" % team)


main()
