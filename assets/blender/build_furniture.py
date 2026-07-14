"""Builds indoor furniture/interior props for Phase 3 "Real Houses" as plain
static (non-rigged) low-poly GLBs, one export per prop. Reuses the
make_material() pattern from build_cashbundle.py: Cycles/glTF reads the
Principled BSDF "Base Color" node input, NOT material.diffuse_color alone,
so both must be set or colors silently export gray.

Style: clean chunky low-poly, solid flat colors (no image textures), boxes/
cylinders with light bevels where noted. Authored in METERS at real-world
scale; the client scales every prop uniformly by 45 (same factor as
character.glb). Each prop's footprint is centered on the origin in X/Y with
its base sitting at z=0.

Outputs -> client/public/models/props/<name>.glb (width x depth x height, m):
  bed          2.0 x 1.1 x 0.7   (mattress + headboard + pillow)
  nightstand   0.45 x 0.45 x 0.55
  dresser      1.5 x 0.5 x 0.9   (with drawer-front detailing)
  sofa         1.8 x 0.75 x 0.8
  tv           1.3 x 0.5 x 1.0   (low console + flat screen on top)
  coffee_table 0.9 x 0.55 x 0.4
  rug          2.4 x 1.8 x 0.02  (flat panel)
  crate        0.75 x 0.75 x 0.75
  shelf        1.8 x 0.5 x 1.8   (open shelving + a few box items)
  pipes        2.6 x 0.3 x 0.4   (wall-run of 2 horizontal pipes + joints)
  jail_bars    2.0 x 0.12 x 2.2  (vertical bars panel, 9 bars + rails)

Previews -> assets/blender/prop_previews/furniture_<name>.png

Run with: ./venv/bin/python build_furniture.py
"""

import math
import os

import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS_OUT = os.path.abspath(os.path.join(HERE, "..", "..", "client", "public", "models", "props"))
PREVIEW_DIR = os.path.join(HERE, "prop_previews")
os.makedirs(MODELS_OUT, exist_ok=True)
os.makedirs(PREVIEW_DIR, exist_ok=True)

# ---- shared color palette -------------------------------------------------
WOOD = (0.478, 0.322, 0.188, 1.0)  # ~0x7a5230
WOOD_DARK = (0.36, 0.235, 0.135, 1.0)
FABRIC_RED = (0.72, 0.22, 0.20, 1.0)
FABRIC_BLUE = (0.20, 0.35, 0.62, 1.0)
FABRIC_CREAM = (0.86, 0.79, 0.66, 1.0)
METAL_GRAY = (0.55, 0.56, 0.58, 1.0)
METAL_DARK = (0.28, 0.29, 0.30, 1.0)
SCREEN_BLACK = (0.03, 0.03, 0.04, 1.0)
RUG_MAROON = (0.55, 0.16, 0.18, 1.0)
CRATE_TAN = (0.62, 0.46, 0.28, 1.0)
WHITE = (0.92, 0.92, 0.9, 1.0)

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
            bsdf.inputs["Roughness"].default_value = 0.75
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


def cylinder(name, radius, depth, location, mat=None, rotation=None, verts=16):
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=depth, location=location, vertices=verts)
    obj = bpy.context.active_object
    obj.name = name
    if rotation:
        obj.rotation_euler = rotation
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
    # bake the size/location scale onto the mesh so the glTF export doesn't
    # rely on non-uniform object transforms surviving export_apply.
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    return result


# ---------------------------------------------------------------------------
# bed: 2.0 x 1.1 x 0.7 (with headboard)
def build_bed():
    wood = make_material("BedWood", WOOD)
    sheet = make_material("BedSheet", FABRIC_BLUE)
    pillow_mat = make_material("Pillow", WHITE)

    W, D, H = 2.0, 1.1, 0.7
    FRAME_H = 0.28
    MATTRESS_H = 0.20
    objs = []
    # base frame
    objs.append(box("Frame", (W, D, FRAME_H), (0, 0, FRAME_H / 2), wood))
    # mattress
    mat_z = FRAME_H + MATTRESS_H / 2
    objs.append(box("Mattress", (W * 0.97, D * 0.94, MATTRESS_H), (0, 0, mat_z), sheet))
    # headboard at -Y edge (back of bed), full height. Slightly wider than
    # the frame so its side faces don't sit exactly coplanar with the
    # frame's sides - coincident faces there caused a dark z-fighting seam.
    hb_h = H
    objs.append(box("Headboard", (W + 0.02, 0.08, hb_h), (0, -D / 2 + 0.04, hb_h / 2), wood))
    # pillow near headboard
    pillow_z = FRAME_H + MATTRESS_H + 0.06
    objs.append(box("Pillow", (0.55, 0.35, 0.12), (0, -D / 2 + 0.32, pillow_z), pillow_mat))
    return join_all(objs, "Bed")


# nightstand: 0.45 x 0.45 x 0.55
def build_nightstand():
    wood = make_material("Wood", WOOD)
    handle = make_material("Handle", METAL_DARK)
    W, D, H = 0.45, 0.45, 0.55
    objs = []
    objs.append(box("Body", (W, D, H), (0, 0, H / 2), wood))
    # two drawer front lines (simple raised boxes). Front faces -Y to match
    # the preview camera (which views the scene from -Y) as well as the
    # tv/shelf "front" convention used elsewhere in this file.
    for i, frac in enumerate((0.32, 0.68)):
        z = H * frac
        objs.append(box(f"DrawerFront.{i}", (W * 0.9, 0.02, H * 0.28), (0, -D / 2, z), wood))
        objs.append(cylinder(f"Handle.{i}", 0.012, 0.05, (0, -D / 2 - 0.012, z), handle, rotation=(math.radians(90), 0, 0)))
    return join_all(objs, "Nightstand")


# dresser: 1.5 x 0.5 x 0.9
def build_dresser():
    wood = make_material("Wood", WOOD)
    wood_dark = make_material("WoodDark", WOOD_DARK)
    handle = make_material("Handle", METAL_DARK)
    W, D, H = 1.5, 0.5, 0.9
    objs = []
    objs.append(box("Body", (W, D, H), (0, 0, H / 2), wood))
    n_drawers = 3
    drawer_h = H / n_drawers
    # Front faces -Y to match the preview camera and the tv/shelf convention.
    for i in range(n_drawers):
        z = drawer_h * (i + 0.5)
        objs.append(box(f"DrawerFront.{i}", (W * 0.92, 0.02, drawer_h * 0.82), (0, -D / 2, z), wood_dark))
        for side in (-1, 1):
            x = side * W * 0.28
            objs.append(cylinder(f"Handle.{i}.{side}", 0.014, 0.05, (x, -D / 2 - 0.015, z), handle, rotation=(math.radians(90), 0, 0)))
    return join_all(objs, "Dresser")


# sofa: 1.8 x 0.75 x 0.8
def build_sofa():
    fabric = make_material("SofaFabric", FABRIC_RED)
    W, D, H = 1.8, 0.75, 0.8
    SEAT_H = 0.38
    ARM_W = 0.16
    objs = []
    # base/seat cushion
    objs.append(box("Seat", (W, D, SEAT_H), (0, 0, SEAT_H / 2), fabric))
    # backrest - sized to sit between the armrests rather than sharing their
    # exact outer-edge X position, which caused a dark z-fighting seam where
    # the backrest's side faces were exactly coplanar with the armrests'.
    back_h = H - SEAT_H
    objs.append(box("Back", (W - ARM_W * 2, D * 0.28, back_h), (0, -D / 2 + D * 0.14, SEAT_H + back_h / 2), fabric))
    # armrests
    for side in (-1, 1):
        x = side * (W / 2 - ARM_W / 2)
        objs.append(box(f"Arm.{side}", (ARM_W, D, H * 0.85), (x, 0, H * 0.85 / 2), fabric))
    # legs
    leg_mat = make_material("SofaLeg", WOOD_DARK)
    for sx in (-1, 1):
        for sy in (-1, 1):
            x = sx * (W / 2 - ARM_W - 0.05)
            y = sy * (D / 2 - 0.05)
            objs.append(cylinder(f"Leg.{sx}.{sy}", 0.03, 0.12, (x, y, 0.06), leg_mat))
    return join_all(objs, "Sofa")


# tv: 1.3 x 0.5 x 1.0 (low console + flat screen on top)
def build_tv():
    console_mat = make_material("Console", WOOD_DARK)
    screen_mat = make_material("Screen", SCREEN_BLACK)
    frame_mat = make_material("TVFrame", METAL_DARK)
    W, D, H = 1.3, 0.5, 1.0
    CONSOLE_H = 0.45
    objs = []
    objs.append(box("Console", (W, D, CONSOLE_H), (0, 0, CONSOLE_H / 2), console_mat))
    screen_h = H - CONSOLE_H
    screen_w = W * 0.85
    screen_thick = 0.05
    screen_z = CONSOLE_H + screen_h / 2
    objs.append(box("Frame", (screen_w, screen_thick, screen_h), (0, 0, screen_z), frame_mat))
    objs.append(
        box(
            "Screen",
            (screen_w * 0.92, screen_thick * 0.4, screen_h * 0.88),
            (0, -screen_thick / 2 - 0.005, screen_z),
            screen_mat,
        )
    )
    return join_all(objs, "TV")


# coffee_table: 0.9 x 0.55 x 0.4
def build_coffee_table():
    wood = make_material("Wood", WOOD)
    W, D, H = 0.9, 0.55, 0.4
    TOP_H = 0.05
    LEG_R = 0.03
    objs = []
    objs.append(box("Top", (W, D, TOP_H), (0, 0, H - TOP_H / 2), wood))
    for sx in (-1, 1):
        for sy in (-1, 1):
            x = sx * (W / 2 - 0.06)
            y = sy * (D / 2 - 0.06)
            objs.append(cylinder(f"Leg.{sx}.{sy}", LEG_R, H - TOP_H, (x, y, (H - TOP_H) / 2), wood))
    return join_all(objs, "CoffeeTable")


# rug: 2.4 x 1.8 x 0.02 (flat)
def build_rug():
    rug_mat = make_material("Rug", RUG_MAROON)
    border_mat = make_material("RugBorder", FABRIC_CREAM)
    W, D, H = 2.4, 1.8, 0.02
    objs = []
    objs.append(box("Border", (W, D, H), (0, 0, H / 2), border_mat))
    objs.append(box("Field", (W * 0.86, D * 0.82, H), (0, 0, H / 2 + 0.001), rug_mat))
    return join_all(objs, "Rug")


# crate: 0.75 x 0.75 x 0.75
def build_crate():
    wood = make_material("CrateWood", CRATE_TAN)
    trim = make_material("CrateTrim", WOOD_DARK)
    S = 0.75
    objs = []
    objs.append(box("Body", (S, S, S), (0, 0, S / 2), wood))
    # corner trim strips (4 vertical edges) for a "crate" look
    trim_w = 0.05
    for sx in (-1, 1):
        for sy in (-1, 1):
            x = sx * (S / 2 - trim_w / 2)
            y = sy * (S / 2 - trim_w / 2)
            objs.append(box(f"Trim.{sx}.{sy}", (trim_w, trim_w, S * 1.01), (x, y, S / 2), trim))
    # horizontal trim bands
    for frac in (0.15, 0.85):
        objs.append(box(f"Band.{frac}", (S * 1.01, S * 1.01, trim_w), (0, 0, S * frac), trim))
    return join_all(objs, "Crate")


# shelf: 1.8 x 0.5 x 1.8 (open shelving with a few box items)
def build_shelf():
    wood = make_material("ShelfWood", WOOD)
    item_a = make_material("ItemA", FABRIC_RED)
    item_b = make_material("ItemB", FABRIC_BLUE)
    item_c = make_material("ItemC", FABRIC_CREAM)
    W, D, H = 1.8, 0.5, 1.8
    PANEL_T = 0.04
    N_SHELVES = 4  # bottom + 3 dividers -> 3 open compartments
    objs = []
    # sides
    for side in (-1, 1):
        x = side * (W / 2 - PANEL_T / 2)
        objs.append(box(f"Side.{side}", (PANEL_T, D, H), (x, 0, H / 2), wood))
    # back panel (thin)
    objs.append(box("Back", (W, PANEL_T, H), (0, D / 2 - PANEL_T / 2, H / 2), wood))
    # horizontal shelves
    shelf_zs = [H * i / (N_SHELVES - 1) for i in range(N_SHELVES)]
    for i, z in enumerate(shelf_zs):
        zc = max(PANEL_T / 2, min(H - PANEL_T / 2, z))
        objs.append(box(f"Shelf.{i}", (W - PANEL_T * 0.1, D, PANEL_T), (0, 0, zc), wood))
    # a few box "items" sitting in the compartments
    item_defs = [
        (0, 1, item_a, (0.32, 0.28, 0.3)),
        (0, 2, item_b, (0.22, 0.22, 0.22)),
        (1, 1, item_c, (0.3, 0.25, 0.35)),
    ]
    compartment_h = shelf_zs[1] - shelf_zs[0] if N_SHELVES > 1 else H
    for slot_x, slot_shelf, mat, (iw, idd, ih) in item_defs:
        x = slot_x * (W / 2 - 0.35)
        base_z = shelf_zs[slot_shelf - 1] if slot_shelf > 0 else 0
        ih = min(ih, compartment_h - 0.05)
        z = base_z + PANEL_T / 2 + ih / 2
        objs.append(box(f"Item.{slot_x}.{slot_shelf}", (iw, min(idd, D - 0.05), ih), (x, 0, z), mat))
    return join_all(objs, "Shelf")


# pipes: 2.6 x 0.3 x 0.4 (horizontal wall-run of 2 pipes + joints)
def build_pipes():
    pipe_mat = make_material("PipeMetal", METAL_GRAY)
    joint_mat = make_material("PipeJoint", METAL_DARK)
    W, D, H = 2.6, 0.3, 0.4
    PIPE_R = 0.06
    objs = []
    for i, z in enumerate((H * 0.25, H * 0.8)):
        y = 0 if i == 0 else D * 0.47
        objs.append(
            cylinder(
                f"Pipe.{i}",
                PIPE_R,
                W - 0.1,
                (0, y, z),
                pipe_mat,
                rotation=(0, math.radians(90), 0),
            )
        )
        # joint collars near each end
        for ex in (-(W - 0.1) / 2, (W - 0.1) / 2):
            objs.append(
                cylinder(
                    f"Joint.{i}.{ex}",
                    PIPE_R * 1.35,
                    0.08,
                    (ex, y, z),
                    joint_mat,
                    rotation=(0, math.radians(90), 0),
                )
            )
    # wall brackets connecting the two pipes vertically
    for bx in (-W * 0.32, 0, W * 0.32):
        objs.append(box(f"Bracket.{bx}", (0.05, 0.05, H * 0.6), (bx, D * 0.15, H * 0.5), joint_mat))
    return join_all(objs, "Pipes")


# jail_bars: 2.0 x 0.12 x 2.2 (vertical bars panel, ~9 bars + top/bottom rails)
def build_jail_bars():
    metal = make_material("JailMetal", METAL_DARK)
    W, D, H = 2.0, 0.12, 2.2
    RAIL_H = 0.12
    N_BARS = 9
    BAR_R = 0.025
    objs = []
    objs.append(box("RailBottom", (W, D, RAIL_H), (0, 0, RAIL_H / 2), metal))
    objs.append(box("RailTop", (W, D, RAIL_H), (0, 0, H - RAIL_H / 2), metal))
    bar_h = H - 2 * RAIL_H
    span = W - 0.12
    for i in range(N_BARS):
        x = -span / 2 + span * i / (N_BARS - 1)
        objs.append(cylinder(f"Bar.{i}", BAR_R, bar_h, (x, 0, RAIL_H + bar_h / 2), metal))
    return join_all(objs, "JailBars")


PROPS = {
    "bed": build_bed,
    "nightstand": build_nightstand,
    "dresser": build_dresser,
    "sofa": build_sofa,
    "tv": build_tv,
    "coffee_table": build_coffee_table,
    "rug": build_rug,
    "crate": build_crate,
    "shelf": build_shelf,
    "pipes": build_pipes,
    "jail_bars": build_jail_bars,
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
    scene.render.resolution_y = 560
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.09, 0.14, 1)
    scene.world = world
    scene.render.filepath = os.path.join(PREVIEW_DIR, f"furniture_{name}.png")
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
