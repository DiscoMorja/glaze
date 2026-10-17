class_name CameraRig
extends Node3D
## Top-down orbit camera. WASD pan, Q/E rotate, mouse wheel zoom.

const PITCH_DEGREES := 55.0
const PAN_SPEED := 20.0
const ROTATE_SPEED := 90.0

var camera: Camera3D
var yaw := 45.0
var zoom := 30.0
var _shake := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	add_child(camera)
	_update_camera()


func _process(delta: float) -> void:
	var pan := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): pan.z -= 1
	if Input.is_key_pressed(KEY_S): pan.z += 1
	if Input.is_key_pressed(KEY_A): pan.x -= 1
	if Input.is_key_pressed(KEY_D): pan.x += 1
	if Input.is_key_pressed(KEY_Q): yaw += ROTATE_SPEED * delta
	if Input.is_key_pressed(KEY_E): yaw -= ROTATE_SPEED * delta
	rotation_degrees.y = yaw
	position += basis * pan * PAN_SPEED * delta
	_update_camera()
	_shake = move_toward(_shake, 0.0, delta * 1.5)
	camera.h_offset = randf_range(-1.0, 1.0) * _shake
	camera.v_offset = randf_range(-1.0, 1.0) * _shake


## Glides the pivot to a world point (e.g. the selected character).
func focus(target: Vector3, seconds: float = 0.35) -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", Vector3(target.x, position.y, target.z), seconds).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


## Brief camera shake; strength is in metres and fades out.
func shake(strength: float) -> void:
	_shake = maxf(_shake, strength)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP: zoom = maxf(zoom - 2.0, 8.0)
			MOUSE_BUTTON_WHEEL_DOWN: zoom = minf(zoom + 2.0, 80.0)


func _update_camera() -> void:
	var pitch := deg_to_rad(PITCH_DEGREES)
	camera.position = Vector3(0, sin(pitch), cos(pitch)) * zoom
	if camera.is_inside_tree():
		camera.look_at(global_position)


## Ray-marches from the screen point and returns the cell under the cursor: a
## living entity's cell if the ray hits one, otherwise the open cell on top of
## the first solid cell. Returns null when nothing is hit.
func pick_cell(state: SimState, screen_pos: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var grid := state.grid
	var t := 0.0
	while t < 300.0:
		var p := origin + dir * t
		var c := Vector3i(floori(p.x), floori(p.y), floori(p.z))
		if grid.in_bounds(c):
			if state.entity_at(c) != null:
				return c
			if grid.is_solid(c):
				var above := c + Vector3i.UP
				return above if grid.in_bounds(above) and not grid.is_solid(above) else null
		t += 0.05
	return null
