# Blender script: makes human_male_rigged.glb / human_female_rigged.glb from
# assetlibs/Characters/modular_rpg_characters/*.blend. In the pack only the
# default body parts are bound to the armature; the armour, heads and hair
# have vertex groups but no Armature modifier, so they don't animate. This
# binds every mesh and exports glTF with all actions. The .blend files are
# not saved.
#
# Run from Blender (Scripting tab, or the MCP addon), or:
#   blender --background --python tools/rig_modular_characters.py
import bpy
import os

DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "assetlibs", "Characters", "modular_rpg_characters")

for name in ["human_male", "human_female"]:
    bpy.ops.wm.open_mainfile(filepath=os.path.join(DIR, name + ".blend"))
    arm = bpy.data.objects[name]
    for o in bpy.data.objects:
        if o.type != 'MESH' or any(m.type == 'ARMATURE' for m in o.modifiers):
            continue
        world = o.matrix_world.copy()
        o.parent = arm
        o.parent_type = 'OBJECT'
        o.matrix_world = world
        o.modifiers.new("Armature", 'ARMATURE').object = arm
    override = {"active_object": arm, "view_layer": bpy.context.scene.view_layers[0]}
    if bpy.context.window_manager.windows:
        override["window"] = bpy.context.window_manager.windows[0]
    with bpy.context.temp_override(**override):
        bpy.ops.export_scene.gltf(filepath=os.path.join(DIR, name + "_rigged.glb"), export_format='GLB',
                                  export_animation_mode='ACTIONS', export_force_sampling=True, export_skins=True,
                                  use_visible=False, export_lights=False, export_cameras=False)
