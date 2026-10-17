class_name HealthBar
extends Node3D
## A camera-facing health bar drawn with quads. Besides current HP it can show
## what an action would do: a bright segment for damage taken right away, a
## dimmer one for damage by the end of the turn, a green one for healing, and
## a flashing bar when the hit would be lethal.

const WIDTH := 1.0
const HEIGHT := 0.16
const BORDER := 0.03

const COLOR_BACK := Color(0.05, 0.05, 0.06, 0.85)
const COLOR_FILL := Color(0.85, 0.18, 0.15)
const COLOR_FILL_ALLY := Color(0.3, 0.8, 0.35)
const COLOR_LOSS_NOW := Color(1.0, 0.7, 0.15)
const COLOR_LOSS_LATER := Color(1.0, 0.85, 0.5, 0.6)
const COLOR_GAIN := Color(0.55, 1.0, 0.6, 0.8)

var _back: MeshInstance3D
var _fill: MeshInstance3D
var _loss_now: MeshInstance3D
var _loss_later: MeshInstance3D
var _gain: MeshInstance3D
var _lethal := false
var _flash := 0.0


func _init(ally: bool) -> void:
	_back = _quad(COLOR_BACK, 0)
	_back.scale = Vector3(WIDTH + BORDER * 2.0, 1.0 + BORDER * 2.0 / HEIGHT, 1.0)
	_fill = _quad(COLOR_FILL_ALLY if ally else COLOR_FILL, 1)
	_loss_later = _quad(COLOR_LOSS_LATER, 2)
	_loss_now = _quad(COLOR_LOSS_NOW, 3)
	_gain = _quad(COLOR_GAIN, 2)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		global_basis = camera.global_basis
	if _lethal:
		_flash += delta * 8.0
		var on := 0.55 + 0.45 * sin(_flash)
		(_loss_now.material_override as StandardMaterial3D).albedo_color.a = on


## hp: current. now_hp: right after the previewed action. later_hp: by the end
## of the turn. Pass now_hp = later_hp = hp when nothing is previewed.
func set_values(max_hp: int, hp: int, now_hp: int, later_hp: int) -> void:
	var top := float(maxi(max_hp, 1))
	var lowest := mini(hp, mini(now_hp, later_hp))
	_span(_fill, 0.0, lowest / top)
	_span(_loss_now, now_hp / top, hp / top)
	_span(_loss_later, later_hp / top, mini(now_hp, hp) / top)
	_span(_gain, hp / top, now_hp / top)
	_lethal = later_hp <= 0 and hp > 0
	if not _lethal:
		(_loss_now.material_override as StandardMaterial3D).albedo_color.a = 1.0


## Places a segment over the bar between two fractions (hidden when empty).
func _span(segment: MeshInstance3D, from: float, to: float) -> void:
	var a := clampf(from, 0.0, 1.0)
	var b := clampf(to, 0.0, 1.0)
	segment.visible = b > a + 0.001
	if segment.visible:
		segment.scale = Vector3((b - a) * WIDTH, 1.0, 1.0)
		segment.position = Vector3(-WIDTH / 2.0 + (a + b) / 2.0 * WIDTH, 0.0, 0.0)


func _quad(color: Color, priority: int) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.0, HEIGHT)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.render_priority = 10 + priority
	material.albedo_color = color
	var quad := MeshInstance3D.new()
	quad.mesh = mesh
	quad.material_override = material
	quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(quad)
	return quad
