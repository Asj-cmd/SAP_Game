"""Shared rig for every Cash Grab art script.

ONE UNIT IS ONE CENTIMETRE, because that is what the simulation uses
(WORLD_AUTHORING 8: actor radius 20, body 180 tall, room 1000 square). Blender's
own unit is nominally a metre, and the retired Three.js scripts in
assets/blender/ built at metre scale - a model authored there imports into Godot
a hundred times too small, which is the single most likely way this pipeline
goes wrong.

So everything here is authored in SIMULATION UNITS directly and the export
writes them unchanged. A 50-unit cash bundle is modelled as 50, not 0.5. The one
place that needs care is Blender's own primitives, which default to metre-ish
sizes; every call below passes an explicit size.
"""

import os

import bpy

HERE = os.path.dirname(os.path.abspath(__file__))
MODELS = os.path.abspath(os.path.join(HERE, "..", "models"))
os.makedirs(MODELS, exist_ok=True)


def clear():
    """Empty scene. read_factory_settings leaves the default cube otherwise."""
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, rgb, rough=0.6, metal=0.0):
    """A flat Principled material.

    Cycles and EEVEE read the Principled BSDF node, NOT material.diffuse_color -
    that field only drives viewport solid shading. Setting both keeps the
    viewport and the render agreeing.
    """
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
        bsdf.inputs["Roughness"].default_value = rough
        bsdf.inputs["Metallic"].default_value = metal
    mat.diffuse_color = (*rgb, 1.0)
    return mat


def box(name, size, at, mat, rot=None):
    """An axis-aligned box of `size` centred on `at`, in simulation units."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=at)
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (size[0], size[1], size[2])
    if rot is not None:
        ob.rotation_euler = rot
    ob.data.materials.append(mat)
    return ob


def cylinder(name, radius, depth, at, mat, rot=None, verts=16):
    bpy.ops.mesh.primitive_cylinder_add(
        radius=radius, depth=depth, location=at, vertices=verts
    )
    ob = bpy.context.active_object
    ob.name = name
    if rot is not None:
        ob.rotation_euler = rot
    ob.data.materials.append(mat)
    return ob


def sphere(name, radius, at, mat, segments=16, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(
        radius=radius, location=at, segments=segments, ring_count=rings
    )
    ob = bpy.context.active_object
    ob.name = name
    ob.data.materials.append(mat)
    bpy.ops.object.shade_smooth()
    return ob


def export(filename):
    """Writes every mesh in the scene to godot/art/models/<filename>.

    Y-up, because glTF is Y-up and Godot is Y-up; Blender is Z-up, and the
    exporter converts. Scale is left at 1 so simulation units survive the trip.
    """
    for ob in bpy.data.objects:
        ob.select_set(True)
    path = os.path.join(MODELS, filename)
    bpy.ops.export_scene.gltf(
        filepath=path,
        export_format="GLB",
        export_yup=True,
        export_apply=True,
        use_selection=False,
    )
    print("WROTE %s" % path)
    return path
