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
carries nothing. Big head, small limbs, strong team colour on the torso.

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

# Proportions, as fractions of height. Head is deliberately oversized - it is
# what reads first at distance and it is what makes the tone comic rather than
# military.
HEAD = 0.30
TORSO = 0.34
LEG = 0.30

TEAMS = {
    "a": {
        "skin": (0.85, 0.68, 0.55),
        "shirt": (0.78, 0.22, 0.20),   # matches the team tint in greybox_main
        "trouser": (0.22, 0.24, 0.32),
        "hair": (0.24, 0.16, 0.12),
    },
    "b": {
        "skin": (0.76, 0.60, 0.48),
        "shirt": (0.22, 0.38, 0.75),
        "trouser": (0.24, 0.22, 0.26),
        "hair": (0.16, 0.14, 0.13),
    },
}


def build(team):
    C.clear()
    tone = TEAMS[team]
    skin = C.material("Skin", tone["skin"], rough=0.75)
    shirt = C.material("Shirt", tone["shirt"], rough=0.8)
    trouser = C.material("Trouser", tone["trouser"], rough=0.85)
    hair = C.material("Hair", tone["hair"], rough=0.9)
    eye = C.material("Eye", (0.08, 0.08, 0.10), rough=0.4)

    leg_h = HEIGHT * LEG
    torso_h = HEIGHT * TORSO
    head_h = HEIGHT * HEAD

    # Legs, from the floor up. Two stubby blocks rather than one - the gap is
    # what makes a walk read even without animation.
    for side, x in (("l", -WIDTH * 0.22), ("r", WIDTH * 0.22)):
        C.box("leg_%s" % side, (WIDTH * 0.32, WIDTH * 0.34, leg_h),
              (x, 0.0, leg_h * 0.5), trouser)
        C.box("shoe_%s" % side, (WIDTH * 0.36, WIDTH * 0.52, leg_h * 0.16),
              (x, -WIDTH * 0.08, leg_h * 0.08), hair)

    # Torso: tapered, wider at the shoulder, so the silhouette has a direction.
    torso_z = leg_h + torso_h * 0.5
    C.box("torso", (WIDTH * 0.78, WIDTH * 0.52, torso_h), (0.0, 0.0, torso_z), shirt)

    # Arms, hanging slightly out from the body so they clear the torso in
    # silhouette rather than merging into one blob.
    for side, x in (("l", -WIDTH * 0.48), ("r", WIDTH * 0.48)):
        C.box("arm_%s" % side, (WIDTH * 0.20, WIDTH * 0.22, torso_h * 0.82),
              (x, 0.0, torso_z + torso_h * 0.04), shirt,
              rot=(0.0, math.radians(6 if side == "l" else -6), 0.0))
        C.box("hand_%s" % side, (WIDTH * 0.22, WIDTH * 0.24, WIDTH * 0.20),
              (x, 0.0, torso_z - torso_h * 0.42), skin)

    # Head: the big readable shape.
    head_z = leg_h + torso_h + head_h * 0.45
    C.box("head", (WIDTH * 0.72, WIDTH * 0.66, head_h * 0.86),
          (0.0, 0.0, head_z), skin)
    C.box("hair", (WIDTH * 0.76, WIDTH * 0.70, head_h * 0.26),
          (0.0, 0.0, head_z + head_h * 0.36), hair)

    # Eyes on the -Y face, which is the direction glTF forward points after the
    # Y-up conversion. Whoever is chasing you should be able to tell.
    for x in (-WIDTH * 0.16, WIDTH * 0.16):
        C.box("eye", (WIDTH * 0.10, WIDTH * 0.06, head_h * 0.14),
              (x, -WIDTH * 0.33, head_z + head_h * 0.06), eye)

    # SCALED TO EXACTLY HEIGHT. The proportions above are chosen by eye, and by
    # eye they came out 166 rather than 180 - the head sits lower than the
    # fractions suggest because the hair and skull overlap. Rather than tune the
    # fractions until they happen to sum right, the whole body is scaled to the
    # number the simulation uses. A character that measures wrong makes every
    # rule built on actor_height read as broken: what fits under a crouch gap,
    # what the jump's ceiling cap allows, how tall a body looks beside a door.
    top = head_z + head_h * 0.49
    fix = HEIGHT / top
    for ob in bpy.data.objects:
        ob.scale = (ob.scale[0] * fix, ob.scale[1] * fix, ob.scale[2] * fix)
        ob.location = (ob.location[0] * fix, ob.location[1] * fix,
                       ob.location[2] * fix)
    print("character %s: %.1f tall before fit, scaled by %.3f -> %.1f" % (
        team, top, fix, top * fix))
    return top * fix


def main():
    for team in TEAMS:
        build(team)
        C.export("character_%s.glb" % team)


main()
