class_name PsxLook
extends CanvasLayer
## Toggleable PSX-style presentation, for comparing against the plain look:
##   - low internal 3D resolution, shown as chunky nearest-upscaled pixels
##   - reduced colour depth with ordered dithering (screen pass)
##   - nearest texture filtering (level materials, terrain, grass)
##   - vertices snapped to the pixel grid, with per-vertex lighting
##     (opaque level materials are swapped for psx_object.gdshader)
## Presentation only; the level scenes and their materials stay untouched on disk.

const SCREEN_SHADER := preload("res://game/render/psx/psx_screen.gdshader")
const OBJECT_SHADER := preload("res://game/render/psx/psx_object.gdshader")

## Screen pixels per PSX pixel (3 at 1152x648 gives 384x216).
@export var pixel_size := 3
## Levels per colour channel.
@export var color_levels := 32
## Internal pixels per vertex-snap step.
@export var snap_pixels := 1.0

var enabled := false

var _rect: ColorRect
var _screen_material: ShaderMaterial
## StandardMaterial3D -> its PSX ShaderMaterial (shared by everything using it).
var _converted := {}
## Undo list: [object, property or surface index, original value].
var _changes: Array = []
var _saved_viewport := {}


func _ready() -> void:
	layer = -1  # under the HUD, over the 3D view
	_screen_material = ShaderMaterial.new()
	_screen_material.shader = SCREEN_SHADER
	_rect = ColorRect.new()
	_rect.material = _screen_material
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.visible = false
	add_child(_rect)


func toggle(world: Node) -> void:
	set_enabled(not enabled, world)


func set_enabled(on: bool, world: Node) -> void:
	if on == enabled:
		return
	enabled = on
	_rect.visible = on
	var viewport := get_viewport()
	if on:
		_saved_viewport = {
			"mode": viewport.scaling_3d_mode, "scale": viewport.scaling_3d_scale,
			"msaa": viewport.msaa_3d, "aa": viewport.screen_space_aa,
		}
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = 1.0 / pixel_size
		viewport.msaa_3d = Viewport.MSAA_DISABLED
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		_screen_material.set_shader_parameter("pixel_size", float(pixel_size))
		_screen_material.set_shader_parameter("color_levels", float(color_levels))
		apply(world)
	else:
		viewport.scaling_3d_mode = _saved_viewport.mode
		viewport.scaling_3d_scale = _saved_viewport.scale
		viewport.msaa_3d = _saved_viewport.msaa
		viewport.screen_space_aa = _saved_viewport.aa
		_restore()


## Applies the look to a (newly loaded) world while enabled.
func apply(world: Node) -> void:
	if not enabled or world == null:
		return
	_restore()
	for node in world.find_children("*", "", true, false):
		if node is CSGPrimitive3D:
			_swap_property(node, "material")
		if node is GeometryInstance3D:
			_swap_property(node, "material_override")
		if node is MeshInstance3D:
			_swap_surfaces(node as MeshInstance3D)
		if node.get_class() == "Terrain3D":
			_terrain(node)


func _restore() -> void:
	for i in range(_changes.size() - 1, -1, -1):
		var change: Array = _changes[i]
		var target: Object = change[0]
		if not is_instance_valid(target):
			continue
		if change[1] is int:
			(target as MeshInstance3D).set_surface_override_material(change[1], change[2])
		else:
			target.set(change[1], change[2])
	_changes.clear()


func _swap_property(target: Object, property: String) -> void:
	var material: Variant = target.get(property)
	var replacement := _replacement(material)
	if replacement != null:
		_changes.append([target, property, material])
		target.set(property, replacement)


func _swap_surfaces(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.mesh == null or mesh_instance.material_override != null:
		return
	for i in mesh_instance.mesh.get_surface_count():
		var override := mesh_instance.get_surface_override_material(i)
		var material := override if override != null else mesh_instance.mesh.surface_get_material(i)
		var replacement := _replacement(material)
		if replacement != null:
			_changes.append([mesh_instance, i, override])
			mesh_instance.set_surface_override_material(i, replacement)


## The PSX material for a StandardMaterial3D, or null to leave it alone.
## Transparent and unshaded materials (markers, glass, effects) only get
## nearest filtering.
func _replacement(material: Variant) -> Material:
	if not material is StandardMaterial3D:
		return null
	var standard := material as StandardMaterial3D
	if standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
			or standard.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL \
			or standard.no_depth_test or standard.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		_nearest(standard)
		return null
	if not _converted.has(standard):
		var psx := ShaderMaterial.new()
		psx.shader = OBJECT_SHADER
		psx.set_shader_parameter("albedo", standard.albedo_color)
		psx.set_shader_parameter("has_texture", standard.albedo_texture != null)
		if standard.albedo_texture != null:
			psx.set_shader_parameter("albedo_texture", standard.albedo_texture)
		psx.set_shader_parameter("use_vertex_color", standard.vertex_color_use_as_albedo)
		psx.set_shader_parameter("uv1_scale", standard.uv1_scale)
		psx.set_shader_parameter("uv1_offset", standard.uv1_offset)
		psx.set_shader_parameter("snap_pixels", snap_pixels)
		_converted[standard] = psx
	return _converted[standard]


func _nearest(material: BaseMaterial3D) -> void:
	if material.texture_filter == BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS:
		return
	_changes.append([material, "texture_filter", material.texture_filter])
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS


## Terrain3D: nearest texture filtering on the ground and on grass cards.
func _terrain(terrain: Node) -> void:
	var material: Object = terrain.get("material")
	if material != null:
		_changes.append([material, "texture_filtering", material.get("texture_filtering")])
		material.set("texture_filtering", 1)  # nearest
	var assets: Object = terrain.get("assets")
	if assets == null:
		return
	for i in assets.call("get_mesh_count"):
		var mesh_asset: Object = assets.call("get_mesh_asset", i)
		var override: Variant = mesh_asset.get("material_override") if mesh_asset != null else null
		if override is BaseMaterial3D:
			_nearest(override)
