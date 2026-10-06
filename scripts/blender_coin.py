"""Blender 脚本：渲染 8 帧绕竖轴旋转的 ¥ 金币（透明背景、正交相机）。

    blender -b -P scripts/blender_coin.py
    python scripts/pixelize_frames.py "output/blender/coin_*.png" assets/sprites/anim/coin.png --size 24 --colors 16

（开发时是通过 Blender MCP 在运行中的 Blender 里执行同样的代码。）
"""
import math
import os

import bmesh
import bpy

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "output", "blender")
os.makedirs(OUT, exist_ok=True)

scene = bpy.data.scenes.new("CoinScene")
if bpy.context.window_manager.windows:
    bpy.context.window_manager.windows[0].scene = scene
col = scene.collection


def link(obj):
    col.objects.link(obj)
    return obj


def metal(name, rgb, rough, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Metallic"].default_value = 1.0
    b.inputs["Roughness"].default_value = rough
    if emit > 0 and "Emission Strength" in b.inputs:
        b.inputs["Emission Color"].default_value = (*rgb, 1)
        b.inputs["Emission Strength"].default_value = emit
    return m


me = bpy.data.meshes.new("CoinMesh")
bm = bmesh.new()
bmesh.ops.create_cone(bm, cap_ends=True, segments=48, radius1=1.0, radius2=1.0, depth=0.18)
bm.to_mesh(me)
bm.free()
for p in me.polygons:
    p.use_smooth = True
coin = link(bpy.data.objects.new("Coin", me))
coin.rotation_euler = (math.radians(90), 0, 0)
bev = coin.modifiers.new("Bevel", "BEVEL")
bev.width = 0.05
bev.segments = 3


def make_text(name, y, rz):
    cu = bpy.data.curves.new(name, type="FONT")
    cu.body = "¥"
    cu.align_x = "CENTER"
    cu.align_y = "CENTER"
    cu.size = 1.15
    cu.extrude = 0.05
    ob = link(bpy.data.objects.new(name, cu))
    ob.location = (0, y, 0)
    ob.rotation_euler = (math.radians(90), 0, rz)
    return ob


t1 = make_text("Yen1", -0.12, 0)
t2 = make_text("Yen2", 0.12, math.radians(180))
coin.data.materials.append(metal("Gold", (1.0, 0.78, 0.12), 0.18, 0.35))
dark = metal("GoldDark", (0.95, 0.5, 0.02), 0.35)
t1.data.materials.append(dark)
t2.data.materials.append(dark)

pivot = link(bpy.data.objects.new("Pivot", None))
for o in (coin, t1, t2):
    o.parent = pivot

camd = bpy.data.cameras.new("Cam")
camd.type = "ORTHO"
camd.ortho_scale = 2.5
cam = link(bpy.data.objects.new("Cam", camd))
cam.location = (0, -6, 0)
cam.rotation_euler = (math.radians(90), 0, 0)
scene.camera = cam
sund = bpy.data.lights.new("Sun", "SUN")
sund.energy = 7.0
sun = link(bpy.data.objects.new("Sun", sund))
sun.rotation_euler = (math.radians(50), math.radians(20), math.radians(30))
filld = bpy.data.lights.new("Fill", "AREA")
filld.energy = 600
filld.size = 3
fill = link(bpy.data.objects.new("Fill", filld))
fill.location = (-3, -3, -1)
fill.rotation_euler = (math.radians(110), 0, math.radians(-45))
world = bpy.data.worlds.new("W")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes.get("Background")
bg.inputs["Color"].default_value = (1.0, 0.95, 0.85, 1)
bg.inputs["Strength"].default_value = 1.0

engines = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
scene.render.resolution_x = 128
scene.render.resolution_y = 128
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
for i in range(8):
    pivot.rotation_euler = (math.radians(12), 0, math.radians(360.0 * i / 8))
    scene.render.filepath = os.path.join(OUT, f"coin_{i:02d}.png")
    bpy.ops.render.render(write_still=True, scene=scene.name)
print("done")
