"""Builds the cash bundle prop: a small stack of bills with a paper band and a
couple of coins on top - plain and static (no rig/animation, unlike the
character).
Run with: ./venv/bin/python build_cashbundle.py
"""

import math
import os

import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS_OUT = os.path.abspath(os.path.join(HERE, "..", "..", "client", "public", "models"))
PREVIEW_PNG = os.path.join(HERE, "cashbundle_preview.png")
os.makedirs(MODELS_OUT, exist_ok=True)


def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def make_material(name, rgba):
    # Cycles renders the Principled BSDF node's Base Color, NOT
    # material.diffuse_color directly - that field only drives viewport solid
    # shading, so it has to be set on the node too or Cycles ignores it.
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = rgba
    mat.diffuse_color = rgba
    return mat


def build_bundle():
    bill_mat = make_material("Bill", (0.16, 0.55, 0.28, 1.0))
    band_mat = make_material("Band", (0.6, 0.1, 0.1, 1.0))
    coin_mat = make_material("Coin", (0.85, 0.68, 0.13, 1.0))

    objs = []

    # stack of bills: a few slightly-offset flattened boxes
    BILL_W, BILL_D, BILL_T = 0.28, 0.16, 0.012
    STACK_N = 5
    for i in range(STACK_N):
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, BILL_T / 2 + i * BILL_T * 1.4))
        bill = bpy.context.active_object
        bill.name = f"Bill.{i}"
        bill.scale = (BILL_W, BILL_D, BILL_T)
        bill.data.materials.append(bill_mat)
        objs.append(bill)
    stack_h = STACK_N * BILL_T * 1.4

    # paper band: a thin flat box wrapped across the middle (simpler and more
    # reliable than a torus loop for a small rectangular stack)
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, stack_h / 2))
    band = bpy.context.active_object
    band.name = "Band"
    band.scale = (BILL_W * 1.03, BILL_D * 0.32, stack_h * 1.05)
    band.data.materials.append(band_mat)
    objs.append(band)

    # two coins lying flat on top, slightly offset and tilted
    for i, (x, y, tilt) in enumerate([(-0.05, 0.02, 8), (0.05, -0.03, -6)]):
        bpy.ops.mesh.primitive_cylinder_add(radius=0.08, depth=0.018, location=(x, y, stack_h + 0.01 + i * 0.012))
        coin = bpy.context.active_object
        coin.name = f"Coin.{i}"
        coin.rotation_euler = (math.radians(tilt), math.radians(tilt * 0.6), math.radians(20 * i))
        coin.data.materials.append(coin_mat)
        objs.append(coin)

    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    bundle = bpy.context.active_object
    bundle.name = "CashBundle"
    return bundle


def _add_camera(name, location, look_at):
    cam_data = bpy.data.cameras.new(name)
    cam_obj = bpy.data.objects.new(name, cam_data)
    bpy.context.collection.objects.link(cam_obj)
    cam_obj.location = location
    direction = mathutils.Vector(look_at) - mathutils.Vector(location)
    cam_obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    return cam_obj


def render_preview():
    cam = _add_camera("Cam", (0.5, -0.55, 0.35), (0, 0, 0.06))
    bpy.context.scene.camera = cam

    key = bpy.data.lights.new("Key", type="SUN")
    key.energy = 3.0
    key_obj = bpy.data.objects.new("Key", key)
    key_obj.rotation_euler = (math.radians(55), 0, math.radians(35))
    bpy.context.collection.objects.link(key_obj)

    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.render.resolution_x = 600
    scene.render.resolution_y = 500
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.09, 0.14, 1)
    scene.world = world
    scene.render.filepath = PREVIEW_PNG
    bpy.ops.render.render(write_still=True)


def export_glb():
    bpy.ops.export_scene.gltf(
        filepath=os.path.join(MODELS_OUT, "cashbundle.glb"),
        export_format="GLB",
        export_animations=False,
    )


def main():
    clear_scene()
    build_bundle()
    render_preview()
    export_glb()
    print(f"Wrote {os.path.join(MODELS_OUT, 'cashbundle.glb')}")
    print(f"Wrote {PREVIEW_PNG}")


if __name__ == "__main__":
    main()
