class_name RetroLook
extends CanvasLayer
## Switchable retro presentation styles, to compare against the plain look
## (P cycles them in game). Presentation only: the level scenes and their
## materials on disk stay untouched, and turning a style off restores them.
##
## EARLY_2000S: soft, slightly low internal resolution (smooth upscale),
##   blurrier textures (mipmap bias), per-vertex (Gouraud) lighting, distance
##   fog and a little extra saturation.
## PSX: chunky nearest-upscaled pixels, 15-bit colour with ordered dithering,
##   nearest texture filtering and vertices snapped to the pixel grid.
##
## Tune a style in STYLES.

enum Style { OFF, EARLY_2000S, PSX }

const SCREEN_SHADER := preload("res://game/render/retro/psx_screen.gdshader")
const OBJECT_SHADER := preload("res://game/render/retro/retro_object.gdshader")

const STYLES := {
	Style.EARLY_2000S: {
		"name": "early 2000s",
		"render_scale": 0.6,  # internal 3D resolution, smoothly upscaled
		"pixel_size": 0,  # 0 = no screen pass
		"color_levels": 0,
		"nearest": false,
		"snap_pixels": 0.0,  # 0 = no vertex snapping
		"mipmap_bias": 1.0,  # > 0 = blurrier, lower-detail textures
		"fog": true,
		"saturation": 1.2,
		"contrast": 1.05,
	},
	Style.PSX: {
		"name": "PSX",
		"render_scale": 1.0 / 3.0,
		"pixel_size": 3,
		"color_levels": 32,
		"nearest": true,
		"snap_pixels": 1.0,
		"mipmap_bias": 0.0,
		"fog": false,
		"saturation": 1.0,
		"contrast": 1.0,
	},
}
## Distance fog (EARLY_2000S): starts this far past what the camera looks at
## and is solid this much further, so zooming out doesn't fog the action.
const FOG_START_PAST_FOCUS := 25.0
const FOG_LENGTH := 70.0
const FOG_COLOR := Color(0.66, 0.7, 0.72)

var style := Style.OFF

var _rect: ColorRect
var _screen_material: ShaderMaterial
## StandardMaterial3D -> its retro ShaderMaterial (shared by everything using it).
var _converted := {}
## Undo list: [object, property or surface index, original value].
var _changes: Array = []
var _environment: Environment


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


func style_name() -> String:
	return STYLES[style].name if STYLES.has(style) else "off"


## Off -> early 2000s -> PSX -> off.
func cycle(world: Node) -> void:
	set_style((style + 1) % Style.size(), world)


func set_style(p_style: Style, world: Node) -> void:
	style = p_style
	apply(world)


## Applies the current style to a (newly loaded) world.
func apply(world: Node) -> void:
	_restore()
	_environment = null
	_rect.visible = false
	if not STYLES.has(style) or world == null:
		return
	var settings: Dictionary = STYLES[style]
	var viewport := get_viewport()
	_change(viewport, "scaling_3d_mode", Viewport.SCALING_3D_MODE_BILINEAR)
	_change(viewport, "scaling_3d_scale", settings.render_scale)
	_change(viewport, "msaa_3d", Viewport.MSAA_DISABLED)
	_change(viewport, "screen_space_aa", Viewport.SCREEN_SPACE_AA_DISABLED)
	_change(viewport, "texture_mipmap_bias", settings.mipmap_bias)
	if settings.pixel_size > 0:
		_rect.visible = true
		_screen_material.set_shader_parameter("pixel_size", float(settings.pixel_size))
		_screen_material.set_shader_parameter("color_levels", float(settings.color_levels))

	for node in world.find_children("*", "", true, false):
		if node is CSGPrimitive3D:
			_swap_property(node, "material", settings)
		if node is GeometryInstance3D:
			_swap_property(node, "material_override", settings)
		if node is MeshInstance3D:
			_swap_surfaces(node as MeshInstance3D, settings)
		if node.get_class() == "Terrain3D" and settings.nearest:
			_terrain_nearest(node)
		if node is WorldEnvironment and (node as WorldEnvironment).environment != null:
			_tune_environment((node as WorldEnvironment).environment, settings)


func _process(_delta: float) -> void:
	if _environment == null:
		return
	# Keep the fog beyond what the camera looks at, whatever the zoom.
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var down := maxf(-(-camera.global_basis.z).y, 0.1)
	var focus := camera.global_position.y / down
	_environment.fog_depth_begin = focus + FOG_START_PAST_FOCUS
	_environment.fog_depth_end = focus + FOG_START_PAST_FOCUS + FOG_LENGTH


func _tune_environment(environment: Environment, settings: Dictionary) -> void:
	if settings.fog:
		_change(environment, "fog_enabled", true)
		_change(environment, "fog_mode", Environment.FOG_MODE_DEPTH)
		_change(environment, "fog_light_color", FOG_COLOR)
		_change(environment, "fog_density", 1.0)
		_change(environment, "fog_sky_affect", 0.0)
		_change(environment, "fog_depth_begin", environment.fog_depth_begin)
		_change(environment, "fog_depth_end", environment.fog_depth_end)
		_environment = environment
	if settings.saturation != 1.0 or settings.contrast != 1.0:
		_change(environment, "adjustment_enabled", true)
		_change(environment, "adjustment_saturation", settings.saturation)
		_change(environment, "adjustment_contrast", settings.contrast)


## Sets a property, remembering the old value for _restore().
func _change(target: Object, property: String, value: Variant) -> void:
	_changes.append([target, property, target.get(property)])
	target.set(property, value)


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


func _swap_property(target: Object, property: String, settings: Dictionary) -> void:
	var replacement := _replacement(target.get(property), settings)
	if replacement != null:
		_change(target, property, replacement)


func _swap_surfaces(mesh_instance: MeshInstance3D, settings: Dictionary) -> void:
	if mesh_instance.mesh == null or mesh_instance.material_override != null:
		return
	for i in mesh_instance.mesh.get_surface_count():
		var override := mesh_instance.get_surface_override_material(i)
		var material := override if override != null else mesh_instance.mesh.surface_get_material(i)
		var replacement := _replacement(material, settings)
		if replacement != null:
			_changes.append([mesh_instance, i, override])
			mesh_instance.set_surface_override_material(i, replacement)


## The retro material for a StandardMaterial3D, or null to leave it alone.
## Transparent and unshaded materials (markers, glass, effects) at most get
## nearest filtering.
func _replacement(material: Variant, settings: Dictionary) -> Material:
	if not material is StandardMaterial3D:
		return null
	var standard := material as StandardMaterial3D
	if standard.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED \
			or standard.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL \
			or standard.no_depth_test or standard.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
		if settings.nearest:
			_change(standard, "texture_filter", BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
		return null
	if not _converted.has(standard):
		var retro := ShaderMaterial.new()
		retro.shader = OBJECT_SHADER
		retro.set_shader_parameter("albedo", standard.albedo_color)
		retro.set_shader_parameter("has_texture", standard.albedo_texture != null)
		if standard.albedo_texture != null:
			retro.set_shader_parameter("albedo_texture", standard.albedo_texture)
			retro.set_shader_parameter("albedo_texture_nearest", standard.albedo_texture)
		retro.set_shader_parameter("use_vertex_color", standard.vertex_color_use_as_albedo)
		retro.set_shader_parameter("uv1_scale", standard.uv1_scale)
		retro.set_shader_parameter("uv1_offset", standard.uv1_offset)
		_converted[standard] = retro
	var result: ShaderMaterial = _converted[standard]
	result.set_shader_parameter("nearest", settings.nearest)
	result.set_shader_parameter("snap_pixels", settings.snap_pixels)
	return result


## Terrain3D: nearest texture filtering on the ground and on grass cards.
func _terrain_nearest(terrain: Node) -> void:
	var material: Object = terrain.get("material")
	if material != null:
		_change(material, "texture_filtering", 1)  # Terrain3DMaterial.NEAREST
	var assets: Object = terrain.get("assets")
	if assets == null:
		return
	for i in assets.call("get_mesh_count"):
		var mesh_asset: Object = assets.call("get_mesh_asset", i)
		var override: Variant = mesh_asset.get("material_override") if mesh_asset != null else null
		if override is BaseMaterial3D:
			_change(override, "texture_filter", BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS)
