"""Builds outdoor/nature props for Phase 3 "Real Houses & World Believability"
as plain static (non-rigged) low-poly GLBs, one export per prop. Reuses the
make_material() pattern from build_cashbundle.py: Cycles/glTF reads the
Principled BSDF "Base Color" node input, NOT material.diffuse_color alone,
so both must be set or colors silently export gray.

Style: clean chunky low-poly, solid flat colors (no image textures). Foliage
greens are deliberately brighter/more saturated than the game's dark lawn
plane (client/src/constants.ts ground: 0x37452e) so props read as distinct
from the ground instead of blending into it.

Authored in METERS at real-world scale; the client scales every prop
uniformly by 45 (same factor as character.glb). Each prop's footprint is
centered on the origin in X/Y with its base sitting at z=0.

Outputs -> client/public/models/props/<name>.glb (width x depth x height, m):
  tree        ~1.8 canopy width x 3.2 tall (trunk ~0.35 wide)
  bush        0.9 x 0.9 x 0.7
  fence       2.0 x 0.1 x 1.0   (3-4 pickets + 2 rails)
  shed        1.6 x 1.2 x 1.9   (walls + pitched roof + door hint)
  fountain    1.4 x 1.4 x 1.0   (round basin + center spout)
  stone_path  2.0 x 0.9 x 0.02  (flat tile of 5-8 flat stones)

Previews -> assets/blender/prop_previews/nature_<name>.png

Run with: ./venv/bin/python build_nature.py
"""

import math
import os
import random

import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS_OUT = os.path.abspath(os.path.join(HERE, "..", "..", "client", "public", "models", "props"))
PREVIEW_DIR = os.path.join(HERE, "prop_previews")
os.makedirs(MODELS_OUT, exist_ok=True)
os.makedirs(PREVIEW_DIR, exist_ok=True)

# ---- shared color palette (foliage brighter than lawn 0x37452e) -----------
TRUNK_BROWN = (0.36, 0.235, 0.135, 1.0)
LEAF_GREEN = (0.32, 0.62, 0.22, 1.0)
LEAF_GREEN_2 = (0.40, 0.70, 0.26, 1.0)
BUSH_GREEN = (0.30, 0.58, 0.24, 1.0)
FENCE_WOOD = (0.60, 0.42, 0.24, 1.0)
SHED_WALL = (0.72, 0.58, 0.40, 1.0)
SHED_ROOF = (0.55, 0.20, 0.18, 1.0)
SHED_DOOR = (0.36, 0.235, 0.135, 1.0)
STONE_GRAY = (0.64, 0.62, 0.55, 1.0)
STONE_GRAY_2 = (0.34, 0.33, 0.30, 1.0)
BASIN_STONE = (0.62, 0.63, 0.62, 1.0)
WATER_BLUE = (0.20, 0.45, 0.62, 1.0)

_mat_cache = {}


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    _mat_cache.clear()


def make_material(name, rgba):
    if name in _mat_cache:
        return _mat_cache[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
        if "Roughness" in bsdf.inputs:
            bsdf.inputs["Roughness"].default_value = 0.85
    mat.diffuse_color = rgba
    _mat_cache[name] = mat
    return mat


def box(name, size, location, mat=None, rotation=None):
    """size = (w, d, h) full extents in meters. primitive_cube_add(size=1)
    creates a 1x1x1 cube (spanning -0.5..0.5 per axis), so scale must equal
    the desired full size directly - NOT size/2 - to hit the target extents."""
    bpy.ops.mesh.primitive_cube_add(size=1, location=location)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = (size[0], size[1], size[2])
    if rotation:
        obj.rotation_euler = rotation
    if mat:
        obj.data.materials.append(mat)
    return obj


def cylinder(name, radius, depth, location, mat=None, rotation=None, verts=12, radius2=None):
    if radius2 is not None:
        bpy.ops.mesh.primitive_cone_add(radius1=radius, radius2=radius2, depth=depth, location=location, vertices=verts)
    else:
        bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=location, vertices=verts)
    obj = bpy.context.active_object
    obj.name = name
    if rotation:
        obj.rotation_euler = rotation
    if mat:
        obj.data.materials.append(mat)
    return obj


def icosphere(name, radius, location, mat=None, subdiv=1, scale=None):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=radius, location=location, subdivisions=subdiv)
    obj = bpy.context.active_object
    obj.name = name
    if scale:
        obj.scale = scale
    if mat:
        obj.data.materials.append(mat)
    return obj


def join_all(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    result = bpy.context.active_object
    result.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return result


# ---------------------------------------------------------------------------
# tree: 3.2 tall, trunk ~0.35 wide, blobby low-poly canopy ~1.8 wide
def build_tree():
    trunk_mat = make_material("Trunk", TRUNK_BROWN)
    leaf_mat = make_material("Leaf", LEAF_GREEN)
    leaf_mat2 = make_material("Leaf2", LEAF_GREEN_2)

    TRUNK_H = 1.93
    TRUNK_R = 0.175
    objs = []
    objs.append(
        cylinder("Trunk", TRUNK_R, TRUNK_H, (0, 0, TRUNK_H / 2), trunk_mat, radius2=TRUNK_R * 0.72, verts=8)
    )

    # blobby canopy: cluster of overlapping icospheres for a low-poly "puffy"
    # look instead of one perfect sphere
    canopy_base_z = TRUNK_H - 0.15
    rng = random.Random(7)
    blob_defs = [
        (0.0, 0.0, 0.55, 0.95),
        (0.35, 0.1, 0.35, 0.62),
        (-0.32, -0.08, 0.4, 0.60),
        (0.05, 0.35, 0.42, 0.58),
        (-0.1, -0.32, 0.38, 0.55),
        (0.0, 0.0, 0.95, 0.55),
    ]
    for i, (dx, dy, dz, r) in enumerate(blob_defs):
        mat = leaf_mat if i % 2 == 0 else leaf_mat2
        jitter = rng.uniform(0.95, 1.08)
        objs.append(
            icosphere(
                f"Canopy.{i}",
                r * jitter,
                (dx, dy, canopy_base_z + dz),
                mat,
                subdiv=1,
                scale=(1.0, 1.0, 0.85),
            )
        )
    return join_all(objs, "Tree")


# bush: 0.9 x 0.9 x 0.7
def build_bush():
    leaf_mat = make_material("BushLeaf", BUSH_GREEN)
    leaf_mat2 = make_material("BushLeaf2", LEAF_GREEN_2)
    objs = []
    blob_defs = [
        (0.0, 0.0, 0.32, 0.34, leaf_mat),
        (0.22, 0.1, 0.24, 0.24, leaf_mat2),
        (-0.2, -0.12, 0.22, 0.24, leaf_mat2),
        (0.05, -0.2, 0.26, 0.22, leaf_mat),
        (-0.05, 0.22, 0.24, 0.22, leaf_mat),
    ]
    for i, (dx, dy, dz, r, mat) in enumerate(blob_defs):
        objs.append(icosphere(f"Blob.{i}", r, (dx, dy, dz), mat, subdiv=1, scale=(1.0, 1.0, 0.9)))
    return join_all(objs, "Bush")


# fence: 2.0 x 0.1 x 1.0 (3-4 pickets + 2 rails)
def build_fence():
    wood = make_material("FenceWood", FENCE_WOOD)
    W, D, H = 2.0, 0.1, 1.0
    N_PICKETS = 4
    PICKET_W = 0.14
    PICKET_H = H
    objs = []
    xs = [-W / 2 + PICKET_W / 2 + i * (W - PICKET_W) / (N_PICKETS - 1) for i in range(N_PICKETS)]
    for i, x in enumerate(xs):
        objs.append(box(f"Picket.{i}", (PICKET_W, D * 0.6, PICKET_H), (x, 0, PICKET_H / 2), wood))
    # 2 horizontal rails
    for frac in (0.3, 0.8):
        objs.append(box(f"Rail.{frac}", (W, D, 0.07), (0, 0, H * frac), wood))
    return join_all(objs, "Fence")


# shed: 1.6 x 1.2 x 1.9 (walls + pitched roof + door hint)
def build_shed():
    wall_mat = make_material("ShedWall", SHED_WALL)
    roof_mat = make_material("ShedRoof", SHED_ROOF)
    door_mat = make_material("ShedDoor", SHED_DOOR)
    W, D, H = 1.6, 1.2, 1.9
    WALL_H = 1.25
    objs = []
    objs.append(box("Walls", (W, D, WALL_H), (0, 0, WALL_H / 2), wall_mat))
    # door hint: recessed-looking panel on the +Y face
    door_w, door_h = 0.5, 1.05
    objs.append(box("Door", (door_w, 0.03, door_h), (0, D / 2 + 0.005, door_h / 2), door_mat))
    # pitched roof: two angled slabs meeting at a ridge above the center,
    # each sloping down to an eave at the wall top. Panel is authored as a
    # flat box along local Y then rotated about X; rotating by -side*angle
    # (NOT side*(pi/2-angle), which pointed the eave end up instead of down)
    # is what correctly sends the +Y-side panel's outer edge down to
    # (y=+D/2, z=WALL_H) and its inner edge up to the ridge (y=0, z=H).
    roof_h = H - WALL_H
    overhang = 0.05
    half_span = D / 2 + overhang
    slope_len = math.hypot(half_span, roof_h)
    angle = math.atan2(roof_h, half_span)
    for side in (-1, 1):
        panel = box(
            f"Roof.{side}",
            (W + 0.02, slope_len, 0.05),
            (0, side * (D / 4), WALL_H + roof_h / 2),
            roof_mat,
        )
        panel.rotation_euler = (-side * angle, 0, 0)
        objs.append(panel)
    return join_all(objs, "Shed")


# fountain: 1.4 x 1.4 x 1.0 (round basin + center spout)
def build_fountain():
    stone_mat = make_material("FountainStone", BASIN_STONE)
    water_mat = make_material("FountainWater", WATER_BLUE)
    BASIN_R = 0.7
    BASIN_H = 0.35
    objs = []
    objs.append(cylinder("BasinOuter", BASIN_R, BASIN_H, (0, 0, BASIN_H / 2), stone_mat, verts=20))
    # water surface flush with the basin rim (the basin cylinder above is a
    # SOLID block, not a hollow bowl - placing the water disc below its top
    # face would bury it inside the stone and make it invisible, so it sits
    # right at/just above the rim instead, like a brimming pool).
    water_z = BASIN_H + 0.006
    objs.append(cylinder("Water", BASIN_R * 0.88, 0.012, (0, 0, water_z), water_mat, verts=20))
    # center pedestal + spout
    ped_r = 0.14
    ped_h = 0.55
    objs.append(cylinder("Pedestal", ped_r, ped_h, (0, 0, BASIN_H + ped_h / 2), stone_mat, verts=10))
    # top basin cap on spout
    cap_r = 0.22
    cap_h = 0.08
    objs.append(cylinder("SpoutCap", cap_r, cap_h, (0, 0, BASIN_H + ped_h + cap_h / 2), stone_mat, verts=14))
    return join_all(objs, "Fountain")


# stone_path: 2.0 x 0.9 x 0.02 (flat tile of 5-8 flat stones)
def build_stone_path():
    stone_mat = make_material("Stone", STONE_GRAY)
    stone_mat2 = make_material("Stone2", STONE_GRAY_2)
    rng = random.Random(3)
    # Sized/spaced so neighboring stones overlap a little (like real
    # flagstones), instead of small isolated chips floating with big gaps.
    stone_defs = [
        (-0.82, 0.08, 0.46, 0.36, stone_mat),
        (-0.42, -0.14, 0.44, 0.4, stone_mat2),
        (0.0, 0.12, 0.42, 0.38, stone_mat),
        (0.4, -0.12, 0.44, 0.38, stone_mat2),
        (0.8, 0.1, 0.44, 0.36, stone_mat),
        (0.02, -0.26, 0.34, 0.3, stone_mat2),
        (-0.6, 0.24, 0.34, 0.3, stone_mat),
    ]
    objs = []
    for i, (x, y, w, d, mat) in enumerate(stone_defs):
        rot_z = rng.uniform(-0.35, 0.35)
        h = 0.02
        # Tiny per-stone z jitter avoids two overlapping stones sharing the
        # exact same plane, which otherwise causes dark z-fighting seams at
        # the overlap edges in both the preview render and in-engine.
        z = h / 2 + i * 0.0015
        obj = box(f"Stone.{i}", (w, d, h), (x, y, z), mat, rotation=(0, 0, rot_z))
        objs.append(obj)
    return join_all(objs, "StonePath")


PROPS = {
    "tree": build_tree,
    "bush": build_bush,
    "fence": build_fence,
    "shed": build_shed,
    "fountain": build_fountain,
    "stone_path": build_stone_path,
}


def _add_camera(name, location, look_at):
    cam_data = bpy.data.cameras.new(name)
    cam_obj = bpy.data.objects.new(name, cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = location
    direction = mathutils.Vector(look_at) - mathutils.Vector(location)
    cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return cam_obj


def render_preview(name, obj):
    dims = obj.dimensions
    radius = max(dims.x, dims.y, dims.z, 0.3) * 1.6
    cam = _add_camera("Cam", (radius, -radius, radius * 0.75), (0, 0, dims.z * 0.4))
    bpy.context.scene.camera = cam

    key = bpy.data.lights.new("Key", type="SUN")
    key.energy = 3.0
    key_obj = bpy.data.objects.new("Key", key)
    key_obj.rotation_euler = (math.radians(55), 0, math.radians(35))
    bpy.context.collection.objects.link(key_obj)

    fill = bpy.data.lights.new("Fill", type="SUN")
    fill.energy = 1.2
    fill_obj = bpy.data.objects.new("Fill", fill)
    fill_obj.rotation_euler = (math.radians(60), 0, math.radians(-120))
    bpy.context.collection.objects.link(fill_obj)

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.render.resolution_x = 640
    scene.render.resolution_y = 640
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.09, 0.14, 1)
    scene.world = world
    scene.render.filepath = os.path.join(PREVIEW_DIR, f"nature_{name}.png")
    bpy.ops.render.render(write_still=True)


def export_glb(name):
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(MODELS_OUT, f"{name}.glb"),
        export_format="GLB",
        export_animations=False,
        export_apply=True,
    )


def main():
    for name, build_fn in PROPS.items():
        clear_scene()
        obj = build_fn()
        print(f"{name}: dims={tuple(round(v, 3) for v in obj.dimensions)}")
        render_preview(name, obj)
        export_glb(name)
        print(f"Wrote {os.path.join(MODELS_OUT, name + '.glb')}")


if __name__ == "__main__":
    main()
