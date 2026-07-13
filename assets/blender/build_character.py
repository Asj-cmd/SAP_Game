"""Builds the Cash Grab player character in Blender (via the `bpy` pip module,
headless - no GUI/display needed) and exports it as a rigged, animated glTF.

Style target: a "defined"/cartoonish stick figure, not thin flat lines - an
oversized rounded head, chunky capsule-like torso/limbs (a stick-figure
skeleton inflated with Blender's Skin modifier), simple dot eyes + a smile,
and a 6-bone armature with baked Idle and Walk actions. Team color is NOT
baked in here - the exported material is neutral; the game applies team
color as a runtime material override (see client/src/three/CharacterModel.ts).

Note: the head is a separate sphere primitive, not part of the skin-inflated
body mesh. An earlier version tried a 7th "head" skin vertex directly off the
high-degree "chest" junction (4 edges meeting there) and the modifier produced
a barely-there bulge with a visible seam glitch at the neck - a dedicated
sphere sidesteps that entirely and gives full control over the head's size.

Run with: ./venv/bin/python build_character.py
Outputs:
  - client/public/models/character.glb  (the game asset)
  - assets/blender/character_preview_{front,angle}.png (rendered previews)
"""

import math
import os

import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS_OUT = os.path.abspath(os.path.join(HERE, "..", "..", "client", "public", "models"))
PREVIEW_PNG = os.path.join(HERE, "character_preview.png")
os.makedirs(MODELS_OUT, exist_ok=True)

# Blender units for this rig; the game scales the loaded model up to world units.
BODY_VERTS = {
    "hip": (0.0, 0.0, 1.00),
    "chest": (0.0, 0.0, 1.32),
    "hand_l": (-0.42, 0.06, 1.02),
    "hand_r": (0.42, 0.06, 1.02),
    "foot_l": (-0.13, 0.05, 0.00),
    "foot_r": (0.13, 0.05, 0.00),
}
BODY_RADII = {
    "hip": 0.20,
    "chest": 0.15,
    "hand_l": 0.075,
    "hand_r": 0.075,
    "foot_l": 0.09,
    "foot_r": 0.09,
}
HEAD_CENTER = (0.0, 0.0, 1.55)
HEAD_RADIUS = 0.30


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name, rgba):
    # Cycles renders (and glTF export reads baseColorFactor from) the
    # Principled BSDF node's Base Color, NOT material.diffuse_color directly -
    # that field only drives viewport solid shading, so without wiring the
    # node too, both the preview render AND the exported asset's actual color
    # would silently fall back to Blender's default gray.
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
    mat.diffuse_color = rgba
    return mat


def build_body_mesh():
    names = list(BODY_VERTS.keys())
    idx = {n: i for i, n in enumerate(names)}
    coords = [BODY_VERTS[n] for n in names]
    edges = [
        (idx["hip"], idx["chest"]),
        (idx["chest"], idx["hand_l"]),
        (idx["chest"], idx["hand_r"]),
        (idx["hip"], idx["foot_l"]),
        (idx["hip"], idx["foot_r"]),
    ]

    mesh = bpy.data.meshes.new("CharacterBody")
    mesh.from_pydata(coords, edges, [])
    mesh.update()

    obj = bpy.data.objects.new("Character", mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)

    skin_mod = obj.modifiers.new(name="Skin", type="SKIN")
    skin_layer = mesh.skin_vertices[0].data
    for n, i in idx.items():
        skin_layer[i].radius = (BODY_RADII[n], BODY_RADII[n])
    skin_layer[idx["hip"]].use_root = True

    # Bake skin + smoothing into real geometry now, while Skin/Subsurf are the
    # only modifiers - applying a modifier that isn't first in the stack (e.g.
    # after an Armature modifier is added later) produces garbage geometry, so
    # both bakes must happen before bind_mesh_to_armature() adds Armature.
    bpy.ops.object.modifier_apply(modifier=skin_mod.name)
    subsurf = obj.modifiers.new("Subsurf", type="SUBSURF")
    subsurf.levels = 2
    subsurf.render_levels = 2
    bpy.ops.object.modifier_apply(modifier=subsurf.name)

    body_mat = make_material("Body", (0.82, 0.82, 0.82, 1.0))
    obj.data.materials.append(body_mat)

    return obj


def add_head_and_face(arm_obj):
    body_mat = bpy.data.materials["Body"]
    eye_mat = make_material("Eyes", (0.02, 0.02, 0.02, 1.0))

    bpy.ops.mesh.primitive_uv_sphere_add(radius=HEAD_RADIUS, location=HEAD_CENTER)
    head = bpy.context.active_object
    head.name = "Head"
    head.data.materials.append(body_mat)

    front_y = HEAD_CENTER[1] + HEAD_RADIUS * 0.9
    eye_z = HEAD_CENTER[2] + HEAD_RADIUS * 0.15
    parts = [head]
    for side, x in (("L", -0.11), ("R", 0.11)):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.045, location=(x, front_y, eye_z))
        eye = bpy.context.active_object
        eye.name = f"Eye.{side}"
        eye.data.materials.append(eye_mat)
        parts.append(eye)

    bpy.ops.mesh.primitive_torus_add(
        location=(0, front_y, HEAD_CENTER[2] - HEAD_RADIUS * 0.25),
        major_radius=0.09,
        minor_radius=0.014,
        major_segments=16,
        minor_segments=6,
    )
    mouth = bpy.context.active_object
    mouth.name = "Mouth"
    mouth.rotation_euler = (math.radians(90), 0, 0)
    mouth.scale = (1.0, 0.5, 1.0)
    mouth.data.materials.append(eye_mat)
    parts.append(mouth)

    for part in parts:
        bpy.ops.object.select_all(action="DESELECT")
        part.select_set(True)
        arm_obj.select_set(True)
        bpy.context.view_layer.objects.active = arm_obj
        arm_obj.data.bones.active = arm_obj.data.bones["Head"]
        bpy.ops.object.parent_set(type="BONE", keep_transform=True)


def build_armature():
    arm_data = bpy.data.armatures.new("CharacterArmature")
    arm_obj = bpy.data.objects.new("Armature", arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active = arm_obj

    bpy.ops.object.mode_set(mode="EDIT")
    eb = arm_data.edit_bones

    root = eb.new("Root")
    root.head = BODY_VERTS["hip"]
    root.tail = BODY_VERTS["chest"]

    head_bone = eb.new("Head")
    head_bone.head = BODY_VERTS["chest"]
    head_bone.tail = HEAD_CENTER
    head_bone.parent = root
    head_bone.use_connect = True

    for side in ("L", "R"):
        arm_bone = eb.new(f"Arm.{side}")
        arm_bone.head = BODY_VERTS["chest"]
        arm_bone.tail = BODY_VERTS[f"hand_{side.lower()}"]
        arm_bone.parent = root
        arm_bone.use_connect = False

        leg_bone = eb.new(f"Leg.{side}")
        leg_bone.head = BODY_VERTS["hip"]
        leg_bone.tail = BODY_VERTS[f"foot_{side.lower()}"]
        leg_bone.parent = root
        leg_bone.use_connect = False

    bpy.ops.object.mode_set(mode="OBJECT")
    return arm_obj


def _closest_point_on_segment(p, a, b):
    ab = b - a
    len_sq = ab.length_squared
    if len_sq < 1e-9:
        return a
    t = max(0.0, min(1.0, (p - a).dot(ab) / len_sq))
    return a + ab * t


# One bone per body-mesh vertex, chosen by literal nearest-bone-segment distance
# (rigid assignment, no smooth blending). Deliberately NOT using Blender's
# automatic heat-diffusion weights here: on this procedural low-poly mesh they
# produced badly warped results (limbs collapsing together) - heat diffusion
# expects mesh topology/density cues that a hand-built skin-modifier mesh
# doesn't provide. Rigid per-segment assignment is fully deterministic and
# visually correct for a blocky stick-figure body that only rotates at the
# shoulder/hip (no mid-limb bending needed).
BONE_SEGMENTS = {
    "Root": (mathutils.Vector(BODY_VERTS["hip"]), mathutils.Vector(BODY_VERTS["chest"])),
    "Arm.L": (mathutils.Vector(BODY_VERTS["chest"]), mathutils.Vector(BODY_VERTS["hand_l"])),
    "Arm.R": (mathutils.Vector(BODY_VERTS["chest"]), mathutils.Vector(BODY_VERTS["hand_r"])),
    "Leg.L": (mathutils.Vector(BODY_VERTS["hip"]), mathutils.Vector(BODY_VERTS["foot_l"])),
    "Leg.R": (mathutils.Vector(BODY_VERTS["hip"]), mathutils.Vector(BODY_VERTS["foot_r"])),
}


def bind_mesh_to_armature(mesh_obj, arm_obj):
    vgs = {name: mesh_obj.vertex_groups.new(name=name) for name in BONE_SEGMENTS}
    for v in mesh_obj.data.vertices:
        best_name, best_dist = None, None
        for name, (a, b) in BONE_SEGMENTS.items():
            d = (v.co - _closest_point_on_segment(v.co, a, b)).length
            if best_dist is None or d < best_dist:
                best_name, best_dist = name, d
        vgs[best_name].add([v.index], 1.0, "REPLACE")

    mesh_obj.parent = arm_obj
    mod = mesh_obj.modifiers.new("Armature", type="ARMATURE")
    mod.object = arm_obj


def make_action(arm_obj, name, keyframes):
    """keyframes: list of (frame, {bone_name: (rx, ry, rz)}) in radians."""
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    pose = arm_obj.pose

    action = bpy.data.actions.new(name)
    if not arm_obj.animation_data:
        arm_obj.animation_data_create()
    arm_obj.animation_data.action = action

    bone_names = {b for _, pose_dict in keyframes for b in pose_dict}
    for b in bone_names:
        pose.bones[b].rotation_mode = "XYZ"

    for frame, pose_dict in keyframes:
        for bone_name, (rx, ry, rz) in pose_dict.items():
            b = pose.bones[bone_name]
            b.rotation_euler = (rx, ry, rz)
            b.keyframe_insert(data_path="rotation_euler", frame=frame)

    bpy.ops.object.mode_set(mode="OBJECT")
    return action


def build_animations(arm_obj):
    SWING = math.radians(35)
    WALK_FRAMES = 24
    make_action(
        arm_obj,
        "Walk",
        [
            (0, {"Leg.L": (SWING, 0, 0), "Leg.R": (-SWING, 0, 0), "Arm.L": (-SWING, 0, 0), "Arm.R": (SWING, 0, 0)}),
            (
                WALK_FRAMES / 2,
                {"Leg.L": (-SWING, 0, 0), "Leg.R": (SWING, 0, 0), "Arm.L": (SWING, 0, 0), "Arm.R": (-SWING, 0, 0)},
            ),
            (WALK_FRAMES, {"Leg.L": (SWING, 0, 0), "Leg.R": (-SWING, 0, 0), "Arm.L": (-SWING, 0, 0), "Arm.R": (SWING, 0, 0)}),
        ],
    )
    BOB = math.radians(2)
    IDLE_FRAMES = 48
    make_action(
        arm_obj,
        "Idle",
        [
            (0, {"Root": (0, 0, 0), "Head": (0, 0, 0)}),
            (IDLE_FRAMES / 2, {"Root": (BOB, 0, 0), "Head": (-BOB, 0, 0)}),
            (IDLE_FRAMES, {"Root": (0, 0, 0), "Head": (0, 0, 0)}),
        ],
    )


def reset_to_rest_pose(arm_obj):
    # make_action() leaves every keyed bone sitting at whatever rotation its
    # LAST keyframe call assigned (e.g. Walk's final frame leaves Arm/Leg
    # bones at +/-35 degrees) - since Idle's keyframes never touch those same
    # bones, that leftover rotation has no F-curve to reset it and would
    # otherwise render as a frozen, warped mid-stride pose instead of rest.
    bpy.context.view_layer.objects.active = arm_obj
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.pose.transforms_clear()
    bpy.ops.object.mode_set(mode="OBJECT")


def _add_camera(name, location, look_at):
    cam_data = bpy.data.cameras.new(name)
    cam_obj = bpy.data.objects.new(name, cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = location
    direction = mathutils.Vector(look_at) - mathutils.Vector(location)
    cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return cam_obj


def setup_preview_render():
    # The face (eyes/mouth) is built at +Y, i.e. the character faces +Y.
    front_cam = _add_camera("FrontCam", (0, 3.4, 1.1), (0, 0, 1.05))
    angle_cam = _add_camera("AngleCam", (1.8, 2.6, 1.3), (0, 0, 1.05))

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

    for cam_obj, suffix in ((front_cam, "front"), (angle_cam, "angle")):
        scene.camera = cam_obj
        scene.render.filepath = PREVIEW_PNG.replace(".png", f"_{suffix}.png")
        bpy.ops.render.render(write_still=True)


def export_glb():
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(MODELS_OUT, "character.glb"),
        export_format="GLB",
        export_animations=True,
        export_animation_mode="ACTIONS",
        export_apply=False,
    )


def main():
    clear_scene()
    mesh_obj = build_body_mesh()
    arm_obj = build_armature()
    bind_mesh_to_armature(mesh_obj, arm_obj)
    add_head_and_face(arm_obj)
    build_animations(arm_obj)
    reset_to_rest_pose(arm_obj)
    setup_preview_render()
    export_glb()
    print(f"Wrote {os.path.join(MODELS_OUT, 'character.glb')}")
    print(f"Wrote {PREVIEW_PNG}")


if __name__ == "__main__":
    main()
