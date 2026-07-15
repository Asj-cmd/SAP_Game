"""Builds the Cash Grab FAMILY (father/mother/son/daughter) in Blender (via the
`bpy` pip module, headless - no GUI/display needed) and exports each as a
rigged, animated glTF. Replaces the single gingerbread `character.glb` with
four cartoonish family members while reusing every hard-won pattern from
build_character.py:

  - make_material() sets BOTH diffuse_color and the Principled BSDF Base
    Color (glTF export reads the node's Base Color for baseColorFactor - the
    diffuse_color field only drives viewport solid shading, so skipping the
    node wire silently exports gray).
  - Bake modifiers (none needed here beyond a final triangulate - geometry is
    built directly from primitives, not a Skin modifier) BEFORE the Armature
    modifier is added; applying a modifier that isn't first in the stack
    produces garbage geometry.
  - RIGID nearest-bone-segment vertex weighting (see _closest_point_on_segment
    below) instead of Blender's automatic heat-diffusion weights - on these
    low-poly procedural meshes heat diffusion warps limbs badly; rigid
    per-segment assignment is deterministic and correct for a blocky
    cartoon body that only bends at the shoulder/elbow/hip/knee.
  - reset_to_rest_pose() before the neutral preview renders (and before
    export) so leftover Walk-cycle keyframe rotations don't freeze the mesh
    into a warped mid-stride pose.
  - export_glb(..., export_animation_mode="ACTIONS").

Style target: same "chunky Nintendo-Mii-meets-claymation" cartoon look as
the original stick-figure character, but a full family built from ONE
parameterized builder function (build_character) called 4x with different
proportions/features - not four copy-pasted bodies of code.

The face/hair convention from build_character.py is reused exactly: the
skinned body mesh (torso/hips/arms/legs/hands/feet, one object with several
material slots) is weight-painted to the armature, while the head, hair, and
face details are separate small objects rigidly BONE-parented to the "Head"
bone (no weight painting needed there - matches the proven pattern and
sidesteps any risk of face geometry getting misweighted).

Base at z=0, facing +Y - identical convention to build_character.py, so the
client's atan2 facing math (CharacterModel.setFacing) needs no changes.

Run with: ../blender/venv/bin/python build_family.py
Outputs:
  - client/public/models/characters/{father,mother,son,daughter}.glb
  - assets/blender/family_previews/{name}_{front,angle,walk}.png (gitignored)
"""

import math
import os

import bpy
import bmesh
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS_OUT = os.path.abspath(os.path.join(HERE, "..", "..", "client", "public", "models", "characters"))
PREVIEW_DIR = os.path.join(HERE, "family_previews")
os.makedirs(MODELS_OUT, exist_ok=True)
os.makedirs(PREVIEW_DIR, exist_ok=True)

V = mathutils.Vector

# ---------------------------------------------------------------------------
# Parameters. One shared DEFAULTS dict (fractions of total character height,
# "frac" suffix) with small per-character overrides layered on top - this is
# what lets a single build_character() produce four distinct silhouettes.
# ---------------------------------------------------------------------------

DEFAULTS = dict(
    head_r_frac=0.168,
    shoulder_frac=0.62,
    hip_frac=0.47,
    knee_frac=0.24,
    shoulder_w_frac=0.170,
    hip_w_frac=0.120,
    elbow_x_mult=1.05,
    hand_x_mult=1.10,
    knee_x_mult=0.90,
    foot_x_mult=0.80,
    upperarm_len_frac=0.19,
    forearm_len_frac=0.17,
    torso_r_top_frac=0.155,
    torso_r_bot_frac=0.170,
    hip_r_frac=0.145,
    upperarm_r_frac=0.075,
    forearm_r_frac=0.062,
    hand_r_frac=0.060,
    thigh_r_frac=0.090,
    shin_r_frac=0.065,
    shoe_len_frac=0.150,
    shoe_h_frac=0.060,
    shoe_w_frac=0.095,
    belly=0.0,
    skirt_flare=0.0,
    skirt_len_frac=0.06,
    mustache=False,
    hair_style="side_part",
)

TEAM_NEUTRAL = (0.6, 0.6, 0.6, 1.0)  # 0x999999 - client tints this per-team at runtime

FATHER = dict(
    DEFAULTS,
    name="father",
    height=1.95,
    skin=(0.86, 0.63, 0.48, 1.0),
    hair_color=(0.22, 0.15, 0.10, 1.0),  # dark brown
    hair_style="side_part",
    mustache=True,
    belly=0.28,
    shoulder_w_frac=0.185,
    hip_w_frac=0.140,
    torso_r_bot_frac=0.185,
    pants_color=(0.16, 0.20, 0.30, 1.0),
    shoe_color=(0.08, 0.08, 0.09, 1.0),
)

MOTHER = dict(
    DEFAULTS,
    name="mother",
    height=1.80,
    skin=(0.90, 0.68, 0.53, 1.0),
    hair_color=(0.45, 0.20, 0.09, 1.0),  # auburn
    hair_style="bun",
    belly=0.0,
    shoulder_w_frac=0.145,
    hip_w_frac=0.130,
    torso_r_bot_frac=0.140,
    skirt_flare=0.28,
    skirt_len_frac=0.12,
    pants_color=(0.55, 0.12, 0.24, 1.0),
    shoe_color=(0.35, 0.16, 0.09, 1.0),
)

SON = dict(
    DEFAULTS,
    name="son",
    height=1.35,
    skin=(0.88, 0.65, 0.50, 1.0),
    hair_color=(0.80, 0.52, 0.24, 1.0),  # sandy
    hair_style="spiky",
    head_r_frac=0.185,
    shoulder_w_frac=0.140,
    hip_w_frac=0.105,
    torso_r_bot_frac=0.150,
    pants_color=(0.20, 0.45, 0.55, 1.0),
    shoe_color=(0.85, 0.24, 0.19, 1.0),
)

DAUGHTER = dict(
    DEFAULTS,
    name="daughter",
    height=1.28,
    skin=(0.90, 0.67, 0.52, 1.0),
    hair_color=(0.14, 0.10, 0.08, 1.0),  # dark
    hair_style="pigtails",
    head_r_frac=0.190,
    shoulder_w_frac=0.135,
    hip_w_frac=0.100,
    torso_r_bot_frac=0.145,
    pants_color=(0.85, 0.35, 0.55, 1.0),
    shoe_color=(0.93, 0.83, 0.20, 1.0),
)

FAMILY = [FATHER, MOTHER, SON, DAUGHTER]


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name, rgba):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = 0.75
    mat.diffuse_color = rgba
    return mat


# ---------------------------------------------------------------------------
# Low-level primitive helpers. Every helper applies the object's transform
# immediately (so world-space vertex coordinates are baked before the later
# bpy.ops.object.join calls) and assigns a material slot on the spot.
# ---------------------------------------------------------------------------

def _apply_transform(obj):
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)


def add_sphere(name, radius, loc, material, segments=10, rings=7):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=loc, segments=segments, ring_count=rings)
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(material)
    _apply_transform(obj)
    return obj


def add_capsule(name, a, b, ra, rb, material, segments=8):
    """A tapered cylinder (cone frustum) between points a and b, radius ra at
    a and rb at b, capped with spheres at both ends so the joints (shoulder/
    elbow/hip/knee) read as smooth ball joints rather than sharp seams."""
    a, b = V(a), V(b)
    direction = b - a
    length = direction.length
    mid = (a + b) / 2

    bpy.ops.mesh.primitive_cone_add(
        vertices=segments, radius1=ra, radius2=rb, depth=length, location=mid, end_fill_type="NGON"
    )
    body = bpy.context.active_object
    body.name = f"{name}_body"
    if length > 1e-6:
        quat = direction.to_track_quat("Z", "Y")
        body.rotation_euler = quat.to_euler()
    body.data.materials.append(material)
    _apply_transform(body)

    cap_a = add_sphere(f"{name}_capA", ra, a, material, segments=8, rings=5)
    cap_b = add_sphere(f"{name}_capB", rb, b, material, segments=8, rings=5)

    bpy.ops.object.select_all(action="DESELECT")
    for o in (body, cap_a, cap_b):
        o.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.join()
    body.name = name
    return body


def add_frustum(name, a, b, ra, rb, material, segments=10):
    """A plain tapered cylinder (no rounded sphere caps) between a and b -
    used for blocky shapes like the hip/skirt block where add_capsule's
    spherical end caps would bulge into an unwanted lumpy bead at the hem."""
    a, b = V(a), V(b)
    direction = b - a
    length = direction.length
    mid = (a + b) / 2
    bpy.ops.mesh.primitive_cone_add(
        vertices=segments, radius1=ra, radius2=rb, depth=length, location=mid, end_fill_type="NGON"
    )
    obj = bpy.context.active_object
    obj.name = name
    if length > 1e-6:
        quat = direction.to_track_quat("Z", "Y")
        obj.rotation_euler = quat.to_euler()
    obj.data.materials.append(material)
    _apply_transform(obj)
    return obj


def add_flattened_hemisphere(name, center, radius, material, keep_frac=0.62, squash=1.0, offset=(0.0, 0.0, 0.0)):
    """A hair-cap: a UV sphere with the lower verts trimmed off (bmesh delete
    below a z threshold), used as the base "hair helmet" shape for every
    hairstyle. keep_frac controls how much of the sphere (from the top) is
    kept - a bob keeps more, a short crop keeps less."""
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, location=center, segments=12, ring_count=8)
    obj = bpy.context.active_object
    obj.name = name

    bm = bmesh.new()
    bm.from_mesh(obj.data)
    threshold = radius * (1.0 - 2.0 * keep_frac)
    to_delete = [v for v in bm.verts if v.co.z < threshold]
    bmesh.ops.delete(bm, geom=to_delete, context="VERTS")
    bm.to_mesh(obj.data)
    bm.free()

    obj.scale = (1.02, 1.02, squash)
    obj.location = (center[0] + offset[0], center[1] + offset[1], center[2] + offset[2])
    obj.data.materials.append(material)
    _apply_transform(obj)
    return obj


def add_box(name, dims, loc, material, rot=(0.0, 0.0, 0.0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_euler = rot
    obj.scale = dims
    obj.data.materials.append(material)
    _apply_transform(obj)
    return obj


def add_cone(name, radius, depth, loc, material, rot=(0.0, 0.0, 0.0), segments=8):
    bpy.ops.mesh.primitive_cone_add(vertices=segments, radius1=radius, radius2=0.0, depth=depth, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_euler = rot
    obj.data.materials.append(material)
    _apply_transform(obj)
    return obj


def add_torus(name, loc, major_r, minor_r, material, rot=(0.0, 0.0, 0.0), scale=(1.0, 1.0, 1.0), major_seg=14, minor_seg=6):
    bpy.ops.mesh.primitive_torus_add(
        location=loc, major_radius=major_r, minor_radius=minor_r, major_segments=major_seg, minor_segments=minor_seg
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.rotation_euler = rot
    obj.scale = scale
    obj.data.materials.append(material)
    _apply_transform(obj)
    return obj


def join_all(name, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    objs[0].name = name
    return objs[0]


def tri_count(obj):
    return sum(max(0, len(p.vertices) - 2) for p in obj.data.polygons)


# ---------------------------------------------------------------------------
# Layout: turns a fraction-based params dict into absolute Blender-unit
# points/radii used by both the mesh builder and the armature builder (same
# numbers feed both, so weighting and visuals always agree).
# ---------------------------------------------------------------------------

def compute_layout(p):
    H = p["height"]
    L = {}
    L["H"] = H
    L["head_r"] = H * p["head_r_frac"]
    L["head_top"] = H
    L["head_center"] = V((0, 0, H - L["head_r"]))
    L["shoulder_z"] = H * p["shoulder_frac"]
    L["hip_z"] = H * p["hip_frac"]
    L["knee_z"] = H * p["knee_frac"]
    L["foot_z"] = 0.0

    sw = H * p["shoulder_w_frac"]
    hw = H * p["hip_w_frac"]
    L["shoulder_w"] = sw
    L["hip_w"] = hw
    L["elbow_x"] = sw * p["elbow_x_mult"]
    L["hand_x"] = sw * p["hand_x_mult"]
    L["knee_x"] = hw * p["knee_x_mult"]
    L["foot_x"] = hw * p["foot_x_mult"]

    L["elbow_z"] = L["shoulder_z"] - H * p["upperarm_len_frac"]
    L["hand_z"] = L["elbow_z"] - H * p["forearm_len_frac"]

    L["torso_r_top"] = H * p["torso_r_top_frac"]
    L["torso_r_bot"] = H * p["torso_r_bot_frac"] * (1.0 + 0.5 * p["belly"])
    L["hip_r"] = H * p["hip_r_frac"]
    L["upperarm_r"] = H * p["upperarm_r_frac"]
    L["forearm_r"] = H * p["forearm_r_frac"]
    L["hand_r"] = H * p["hand_r_frac"]
    L["thigh_r"] = H * p["thigh_r_frac"]
    L["shin_r"] = H * p["shin_r_frac"]
    L["shoe_len"] = H * p["shoe_len_frac"]
    L["shoe_h"] = H * p["shoe_h_frac"]
    L["shoe_w"] = H * p["shoe_w_frac"]

    hip_bone_len = H * 0.045
    L["hip_bone_bottom"] = L["hip_z"] - hip_bone_len

    # Named skeleton points (head, tail) - shared by build_armature() (as
    # edit-bone endpoints) and BONE_SEGMENTS (as rigid-weighting segments).
    bones = {}
    bones["Root"] = (V((0, 0, L["hip_bone_bottom"])), V((0, 0, L["hip_z"])))
    bones["Spine"] = (V((0, 0, L["hip_z"])), V((0, 0, L["shoulder_z"])))
    bones["Head"] = (V((0, 0, L["shoulder_z"])), V((0, 0, L["head_top"])))
    for side, sign in (("L", -1), ("R", 1)):
        shoulder_pt = V((sign * sw, 0, L["shoulder_z"]))
        elbow_pt = V((sign * L["elbow_x"], 0, L["elbow_z"]))
        hand_pt = V((sign * L["hand_x"], 0, L["hand_z"]))
        hip_pt = V((sign * hw, 0, L["hip_z"]))
        knee_pt = V((sign * L["knee_x"], 0, L["knee_z"]))
        foot_pt = V((sign * L["foot_x"], 0, L["foot_z"]))
        bones[f"UpperArm.{side}"] = (shoulder_pt, elbow_pt)
        bones[f"Forearm.{side}"] = (elbow_pt, hand_pt)
        bones[f"Thigh.{side}"] = (hip_pt, knee_pt)
        bones[f"Shin.{side}"] = (knee_pt, foot_pt)
    L["bones"] = bones
    return L


# ---------------------------------------------------------------------------
# Mesh building
# ---------------------------------------------------------------------------

def build_body_mesh(p, L, materials):
    parts = []
    skin = materials["Skin"]
    team = materials["Team"]
    pants = materials["Pants"]
    shoe = materials["Shoe"]

    # Torso (shirt) - tapered capsule from hip to shoulder, extra-wide at the
    # bottom for a belly on characters with belly > 0.
    parts.append(
        add_capsule(
            "Torso",
            (0, 0, L["hip_z"]),
            (0, 0, L["shoulder_z"]),
            L["torso_r_bot"],
            L["torso_r_top"],
            team,
        )
    )

    # Hips/pelvis block - a short waistband by default, or (via skirt_len_frac
    # + skirt_flare) a flared short skirt for mother. Its hem sits well above
    # the knee so the separate thigh/shin capsules below still read as
    # distinct legs during the walk cycle, even under a flared skirt.
    hem_z = L["hip_z"] - L["H"] * p["skirt_len_frac"]
    hip_bottom_r = L["hip_r"] * (1.0 + p["skirt_flare"])
    parts.append(
        add_frustum(
            "Hips",
            (0, 0, hem_z),
            (0, 0, L["hip_z"] + L["H"] * 0.02),
            hip_bottom_r,
            L["hip_r"],
            pants,
        )
    )

    for side, sign in (("L", -1), ("R", 1)):
        shoulder_pt = (sign * L["shoulder_w"], 0, L["shoulder_z"])
        elbow_pt = (sign * L["elbow_x"], 0, L["elbow_z"])
        hand_pt = (sign * L["hand_x"], 0, L["hand_z"])
        hip_pt = (sign * L["hip_w"], 0, L["hip_z"])
        knee_pt = (sign * L["knee_x"], 0, L["knee_z"])
        foot_pt = (sign * L["foot_x"], 0, L["foot_z"])

        parts.append(add_capsule(f"UpperArm.{side}", shoulder_pt, elbow_pt, L["upperarm_r"], L["upperarm_r"] * 0.9, team))
        parts.append(add_capsule(f"Forearm.{side}", elbow_pt, hand_pt, L["forearm_r"], L["forearm_r"] * 0.85, skin))
        parts.append(add_sphere(f"Hand.{side}", L["hand_r"], hand_pt, skin, segments=8, rings=6))

        parts.append(add_capsule(f"Thigh.{side}", hip_pt, knee_pt, L["thigh_r"], L["thigh_r"] * 0.85, pants))
        # The Shin capsule's bottom sphere cap is centered on its endpoint -
        # if that endpoint were the bone's actual foot_pt (z=0) the cap's
        # bottom half would poke below the ground plane. Raise the MESH
        # endpoint by the cap radius so the sphere sits flush with z=0; the
        # armature's Shin bone (used for weighting/animation) still ends
        # exactly at foot_pt.
        ankle_r = L["shin_r"] * 0.8
        ankle_mesh_pt = (foot_pt[0], foot_pt[1], foot_pt[2] + ankle_r)
        parts.append(add_capsule(f"Shin.{side}", knee_pt, ankle_mesh_pt, L["shin_r"], ankle_r, pants))

        shoe_center = (sign * L["foot_x"], L["shoe_len"] * 0.15, L["shoe_h"] * 0.5)
        parts.append(
            add_box(
                f"Shoe.{side}",
                (L["shoe_w"], L["shoe_len"], L["shoe_h"]),
                shoe_center,
                shoe,
            )
        )

    body = join_all("Body", parts)
    return body


BONE_NAMES = [
    "Root",
    "Spine",
    "Head",
    "UpperArm.L",
    "UpperArm.R",
    "Forearm.L",
    "Forearm.R",
    "Thigh.L",
    "Thigh.R",
    "Shin.L",
    "Shin.R",
]

BONE_PARENT = {
    "Spine": ("Root", True),
    "Head": ("Spine", True),
    "UpperArm.L": ("Spine", False),
    "UpperArm.R": ("Spine", False),
    "Forearm.L": ("UpperArm.L", True),
    "Forearm.R": ("UpperArm.R", True),
    "Thigh.L": ("Root", False),
    "Thigh.R": ("Root", False),
    "Shin.L": ("Thigh.L", True),
    "Shin.R": ("Thigh.R", True),
}


def build_armature(L):
    arm_data = bpy.data.armatures.new("FamilyArmature")
    arm_obj = bpy.data.objects.new("Armature", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj

    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones
    created = {}
    for name in BONE_NAMES:
        head, tail = L["bones"][name]
        b = eb.new(name)
        b.head = head
        b.tail = tail
        created[name] = b

    for name, (parent_name, connect) in BONE_PARENT.items():
        created[name].parent = created[parent_name]
        created[name].use_connect = connect

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def _closest_point_on_segment(p, a, b):
    ab = b - a
    len_sq = ab.length_squared
    if len_sq < 1e-9:
        return a
    t = max(0.0, min(1.0, (p - a).dot(ab) / len_sq))
    return a + ab * t


def bind_mesh_to_armature(mesh_obj, arm_obj, bone_segments):
    vgs = {name: mesh_obj.vertex_groups.new(name=name) for name in bone_segments}
    for v in mesh_obj.data.vertices:
        best_name, best_dist = None, None
        for name, (a, b) in bone_segments.items():
            d = (v.co - _closest_point_on_segment(v.co, a, b)).length
            if best_dist is None or d < best_dist:
                best_name, best_dist = name, d
        vgs[best_name].add([v.index], 1.0, "REPLACE")

    mesh_obj.parent = arm_obj
    mod = mesh_obj.modifiers.new("Armature", type="ARMATURE")
    mod.object = arm_obj


# ---------------------------------------------------------------------------
# Head, face, and hair - all rigidly BONE-parented to the "Head" bone (no
# weight painting, matching build_character.py's proven approach).
# ---------------------------------------------------------------------------

def bone_parent_to_head(arm_obj, parts):
    for part in parts:
        bpy.ops.object.select_all(action="DESELECT")
        part.select_set(True)
        arm_obj.select_set(True)
        bpy.context.view_layer.objects.active = arm_obj
        arm_obj.data.bones.active = arm_obj.data.bones["Head"]
        bpy.ops.object.parent_set(type="BONE", keep_transform=True)


def add_head_and_face(arm_obj, p, L, materials):
    skin = materials["Skin"]
    hair = materials["Hair"]
    eye_white = materials["EyeWhite"]
    pupil = materials["Pupil"]
    mouth_mat = materials["Mouth"]

    center = L["head_center"]
    r = L["head_r"]
    parts = []

    parts.append(add_sphere("Head", r, center, skin, segments=14, rings=10))

    front_y = r * 0.92
    eye_z = center.z + r * 0.12
    for side, x in (("L", -0.36 * r), ("R", 0.36 * r)):
        parts.append(add_sphere(f"EyeWhite.{side}", r * 0.22, (x, front_y, eye_z), eye_white, segments=8, rings=6))
        parts.append(
            add_sphere(f"Pupil.{side}", r * 0.11, (x, front_y * 1.05, eye_z), pupil, segments=6, rings=5)
        )

    # Eyebrows - sit just above the eyes, pushed out past the head sphere's
    # own surface (front_y is INSIDE the sphere - eyes/mouth read fine there
    # because their own radius pokes past the surface, but a thin flat box
    # centered at front_y ends up almost entirely embedded and reads as a
    # stray diagonal sliver instead of a brow). A slight asymmetric raise on
    # one side gives a bit of "funny/offbeat" personality.
    brow_y = r * 1.06
    brow_z = eye_z + r * 0.22
    for side, x, raise_amt in (("L", -0.36 * r, 0.0), ("R", 0.36 * r, r * 0.05)):
        parts.append(
            add_box(
                f"Brow.{side}",
                (r * 0.30, r * 0.10, r * 0.075),
                (x, brow_y, brow_z + raise_amt),
                hair,
                rot=(0, 0, math.radians(6 if side == "L" else -8)),
            )
        )

    mouth_z = center.z - r * 0.32
    parts.append(
        add_torus(
            "Mouth",
            (0, front_y, mouth_z),
            r * 0.30,
            r * 0.05,
            mouth_mat,
            rot=(math.radians(90), 0, 0),
            scale=(1.0, 0.5, 1.0),
        )
    )

    if p["mustache"]:
        # Darker than the hair itself (not just a same-tone bump) and a
        # handlebar shape (center bar + two downturned tip curls) so it
        # reads unambiguously as a mustache rather than a stray shadow.
        mustache_color = (
            hair.diffuse_color[0] * 0.5,
            hair.diffuse_color[1] * 0.5,
            hair.diffuse_color[2] * 0.5,
            1.0,
        )
        mustache_mat = make_material("Mustache", mustache_color)
        must_y = r * 1.16
        must_z = mouth_z + r * 0.24
        parts.append(add_box("Mustache", (r * 0.58, r * 0.22, r * 0.14), (0, must_y, must_z), mustache_mat))
        for side, sx in (("L", -1.0), ("R", 1.0)):
            tip_center = (sx * r * 0.32, must_y - r * 0.02, must_z - r * 0.10)
            parts.append(
                add_sphere(f"MustacheTip.{side}", r * 0.11, tip_center, mustache_mat, segments=8, rings=6)
            )

    # Hair - shared "hair cap" base (partial sphere) plus a per-style
    # decoration.
    style = p["hair_style"]
    if style == "side_part":
        parts.append(add_flattened_hemisphere("HairCap", center, r * 1.05, hair, keep_frac=0.55, squash=1.0))
    elif style == "bun":
        parts.append(add_flattened_hemisphere("HairCap", center, r * 1.04, hair, keep_frac=0.50, squash=0.95))
        bun_center = (0, -r * 0.55, center.z + r * 0.35)
        parts.append(add_sphere("Bun", r * 0.34, bun_center, hair, segments=10, rings=8))
    elif style == "spiky":
        parts.append(add_flattened_hemisphere("HairCap", center, r * 1.05, hair, keep_frac=0.42, squash=1.0))
        # Base of each spike sits on the crown (just above the cap's own
        # surface); the cone then sticks straight up/out from there so it
        # reads as a clear spike above the silhouette rather than a bump
        # buried in the cap.
        spike_positions = [
            (0.0, 0.0, 0.0),
            (0.55, -0.10, -18),
            (-0.55, -0.10, 18),
            (0.30, 0.50, -10),
            (-0.30, 0.50, 10),
        ]
        for sx, sy, tilt in spike_positions:
            base = center + V((sx * r * 0.55, sy * r * 0.55, r * 0.75))
            parts.append(
                add_cone(
                    "Spike",
                    r * 0.20,
                    r * 0.85,
                    base + V((0, 0, r * 0.35)),
                    hair,
                    rot=(math.radians(tilt), math.radians(tilt * 0.6), 0),
                    segments=6,
                )
            )
    elif style == "pigtails":
        parts.append(add_flattened_hemisphere("HairCap", center, r * 1.05, hair, keep_frac=0.58, squash=1.0))
        for side, x in (("L", -1.0), ("R", 1.0)):
            band_center = (x * r * 1.18, -r * 0.05, center.z - r * 0.05)
            parts.append(add_sphere(f"Pigtail.{side}", r * 0.38, band_center, hair, segments=9, rings=7))

    bone_parent_to_head(arm_obj, parts)


# ---------------------------------------------------------------------------
# Animation
# ---------------------------------------------------------------------------

def make_action(arm_obj, name, keyframes, bone_list):
    """keyframes: list of (frame, {bone_name: (rx, ry, rz)}) in radians. Every
    bone in bone_list is keyed at every frame (explicit rest value 0 where a
    given pose doesn't otherwise move it) so the resulting F-curves are clean
    and looping, with no stray un-keyed channels left at a prior action's
    last value."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    pose = arm_obj.pose

    action = bpy.data.actions.new(name)
    arm_obj.animation_data.action = action

    for b in bone_list:
        pose.bones[b].rotation_mode = "XYZ"

    for frame, pose_dict in keyframes:
        for bone_name in bone_list:
            rx, ry, rz = pose_dict.get(bone_name, (0.0, 0.0, 0.0))
            b = pose.bones[bone_name]
            b.rotation_euler = (rx, ry, rz)
            b.keyframe_insert(data_path="rotation_euler", frame=frame)

    bpy.ops.object.mode_set(mode="OBJECT")
    return action


def build_walk_action(arm_obj):
    SWING_LEG = math.radians(35)
    SWING_ARM = math.radians(40)
    KNEE_BEND = math.radians(48)
    ELBOW_BEND = math.radians(26)
    LEAN = math.radians(4)
    TWIST = math.radians(3)

    FRAMES = 24
    N_SAMPLES = 9  # one keyframe every 3 frames -> smooth curves at 24fps
    bone_list = [
        "Root",
        "Spine",
        "UpperArm.L",
        "UpperArm.R",
        "Forearm.L",
        "Forearm.R",
        "Thigh.L",
        "Thigh.R",
        "Shin.L",
        "Shin.R",
    ]

    keyframes = []
    for i in range(N_SAMPLES):
        t = i / (N_SAMPLES - 1)
        frame = t * FRAMES
        theta = 2 * math.pi * t

        # side sign: R=+1, L=-1 (Thigh.R forward at t=0)
        pose = {}
        for side, s in (("L", -1.0), ("R", 1.0)):
            thigh = s * SWING_LEG * math.cos(theta)
            shin = -KNEE_BEND * max(0.0, -s * math.sin(theta))
            arm = -s * SWING_ARM * math.cos(theta)  # contralateral to same-side thigh
            elbow = -ELBOW_BEND * (math.cos(theta) ** 2)
            pose[f"Thigh.{side}"] = (thigh, 0, 0)
            pose[f"Shin.{side}"] = (shin, 0, 0)
            pose[f"UpperArm.{side}"] = (arm, 0, 0)
            pose[f"Forearm.{side}"] = (elbow, 0, 0)

        # Torso bob (twice per stride) + slight forward lean + a small hip
        # twist for a fun, slightly chaotic cartoon waddle.
        bob = LEAN * 0.5 * (1 - math.cos(2 * theta))
        pose["Spine"] = (LEAN * 0.4 + bob * 0.3, 0, 0)
        pose["Root"] = (0, 0, TWIST * math.sin(theta))
        keyframes.append((frame, pose))

    return make_action(arm_obj, "Walk", keyframes, bone_list), FRAMES


def build_idle_action(arm_obj):
    BOB = math.radians(2.2)
    SWAY = math.radians(4.0)
    TILT = math.radians(3.0)
    FRAMES = 48
    bone_list = ["Root", "Spine", "Head", "UpperArm.L", "UpperArm.R"]

    keyframes = []
    for i, t in enumerate((0.0, 0.25, 0.5, 0.75, 1.0)):
        frame = t * FRAMES
        theta = 2 * math.pi * t
        pose = {
            "Root": (BOB * math.sin(theta), 0, 0),
            "Spine": (-BOB * 0.6 * math.sin(theta), 0, 0),
            "Head": (0, 0, TILT * math.sin(theta * 0.5)),
            "UpperArm.L": (0, 0, -SWAY * math.sin(theta)),
            "UpperArm.R": (0, 0, SWAY * math.sin(theta)),
        }
        keyframes.append((frame, pose))

    return make_action(arm_obj, "Idle", keyframes, bone_list), FRAMES


def reset_to_rest_pose(arm_obj):
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.pose.transforms_clear()
    bpy.ops.object.mode_set(mode="OBJECT")


# ---------------------------------------------------------------------------
# Preview rendering
# ---------------------------------------------------------------------------

def _add_camera(name, location, look_at):
    cam_data = bpy.data.cameras.new(name)
    cam_obj = bpy.data.objects.new(name, cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = location
    direction = mathutils.Vector(look_at) - mathutils.Vector(location)
    cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return cam_obj


def setup_lights_and_render_settings(L):
    key = bpy.data.lights.new("KeyLight", type="SUN")
    key.energy = 3.0
    key_obj = bpy.data.objects.new("KeyLight", key)
    key_obj.rotation_euler = (math.radians(55), 0, math.radians(35))
    bpy.context.collection.objects.link(key_obj)

    fill = bpy.data.lights.new("FillLight", type="SUN")
    fill.energy = 1.0
    fill_obj = bpy.data.objects.new("FillLight", fill)
    fill_obj.rotation_euler = (math.radians(60), 0, math.radians(-120))
    bpy.context.collection.objects.link(fill_obj)

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.render.resolution_x = 700
    scene.render.resolution_y = 900
    scene.render.image_settings.file_format = "PNG"

    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.09, 0.14, 1)
    scene.world = world

    mid_h = L["H"] * 0.55
    front_cam = _add_camera("FrontCam", (0, L["H"] * 1.9, mid_h), (0, 0, mid_h))
    angle_cam = _add_camera("AngleCam", (L["H"] * 1.0, L["H"] * 1.45, mid_h), (0, 0, mid_h))
    return front_cam, angle_cam


def render_view(cam_obj, filepath):
    scene = bpy.context.scene
    scene.camera = cam_obj
    scene.render.filepath = filepath
    bpy.ops.render.render(write_still=True)


def export_glb(filepath):
    bpy.ops.export_scene.gltf(
        filepath=filepath,
        export_format="GLB",
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_apply=False,
    )


# ---------------------------------------------------------------------------
# Top-level per-character builder (called once per family member)
# ---------------------------------------------------------------------------

def build_character(p):
    clear_scene()
    L = compute_layout(p)

    materials = {
        "Skin": make_material("Skin", p["skin"]),
        "Team": make_material("Team", TEAM_NEUTRAL),
        "Pants": make_material("Pants", p["pants_color"]),
        "Shoe": make_material("Shoe", p["shoe_color"]),
        "Hair": make_material("Hair", p["hair_color"]),
        "EyeWhite": make_material("EyeWhite", (0.95, 0.95, 0.93, 1.0)),
        "Pupil": make_material("Pupil", (0.03, 0.03, 0.04, 1.0)),
        "Mouth": make_material("Mouth", (0.35, 0.08, 0.10, 1.0)),
    }
    if materials["Team"].name != "Team":
        raise RuntimeError(f"Team material got renamed to {materials['Team'].name!r} - name collision")

    body = build_body_mesh(p, L, materials)
    triangles = tri_count(body)

    arm_obj = build_armature(L)
    bind_mesh_to_armature(body, arm_obj, L["bones"])
    add_head_and_face(arm_obj, p, L, materials)

    if not arm_obj.animation_data:
        arm_obj.animation_data_create()
    walk_action, walk_frames = build_walk_action(arm_obj)
    idle_action, idle_frames = build_idle_action(arm_obj)

    front_cam, angle_cam = setup_lights_and_render_settings(L)

    # Walk mid-stride preview: show the Walk action at a clear mid-swing
    # frame before clearing pose data.
    arm_obj.animation_data.action = walk_action
    bpy.context.scene.frame_set(int(walk_frames * 0.75))
    render_view(angle_cam, os.path.join(PREVIEW_DIR, f"{p['name']}_walk.png"))

    # Clear the action assignment BEFORE resetting pose, otherwise the next
    # depsgraph evaluation (triggered by rendering) re-applies the Walk
    # action's frame-18 pose over our manual transforms_clear() and the
    # "neutral" front/angle renders come out frozen mid-stride.
    arm_obj.animation_data.action = None
    reset_to_rest_pose(arm_obj)
    bpy.context.scene.frame_set(0)

    render_view(front_cam, os.path.join(PREVIEW_DIR, f"{p['name']}_front.png"))
    render_view(angle_cam, os.path.join(PREVIEW_DIR, f"{p['name']}_angle.png"))

    out_path = os.path.join(MODELS_OUT, f"{p['name']}.glb")
    export_glb(out_path)
    size_bytes = os.path.getsize(out_path)

    return {
        "name": p["name"],
        "height": L["H"],
        "triangles": triangles,
        "path": out_path,
        "size_bytes": size_bytes,
        "clips": [a.name for a in bpy.data.actions],
    }


def main():
    results = []
    for p in FAMILY:
        info = build_character(p)
        results.append(info)
        print(
            f"[{info['name']}] height={info['height']:.3f} tris={info['triangles']} "
            f"clips={info['clips']} size={info['size_bytes']} -> {info['path']}"
        )
    print("Done.")


if __name__ == "__main__":
    main()
