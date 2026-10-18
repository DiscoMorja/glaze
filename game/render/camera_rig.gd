class_name CameraRig
extends Node3D
## Top-down orbit camera. WASD pan, Q/E rotate, mouse wheel zoom. Gameplay can
## glide it to a point, frame two points (and later restore the previous view),
## or follow a moving node for a while. Gameplay never rotates it.

const PITCH_DEGREES := 55.0
const PAN_SPEED := 20.0
const ROTATE_SPEED := 90.0
## How quickly the pivot catches up with a followed node (per second).
const FOLLOW_RATE := 6.4
## Share of the screen (from centre to edge) framed points may use.
const FIT_MARGIN := 0.7
## Extra room around framed points, in metres.
const FIT_PADDING := 1.5
const MAX_FIT_ZOOM := 40.0

var camera: Camera3D
var yaw := 45.0
var zoom := 30.0
var _shake := 0.0
var _move_tween: Tween
## View saved by frame_pair() so restore() can return to it.
var _framed := false
var _saved_yaw := 0.0
var _saved_zoom := 0.0
var _follow: Node3D
var _follow_until := 0.0


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
	if _follow != null and is_instance_valid(_follow) and Time.get_ticks_msec() / 1000.0 < _follow_until:
		var target := _follow.global_position
		position = position.lerp(Vector3(target.x, position.y, target.z), minf(1.0, delta * FOLLOW_RATE))
	else:
		_follow = null
	rotation_degrees.y = yaw
	position += basis * pan * PAN_SPEED * delta
	_update_camera()
	_shake = move_toward(_shake, 0.0, delta * 1.5)
	camera.h_offset = randf_range(-1.0, 1.0) * _shake
	camera.v_offset = randf_range(-1.0, 1.0) * _shake


## Glides the pivot to a world point (e.g. the selected character).
func focus(target: Vector3, seconds: float = 0.42) -> void:
	_glide(target, yaw, zoom, seconds)


## Glides the pivot to the midpoint of a and b without turning. Zooms out only
## as far as needed to keep both on screen (never in); the previous zoom is
## kept for restore().
func frame_pair(a: Vector3, b: Vector3, seconds: float = 0.42) -> void:
	if not _framed:
		_framed = true
		_saved_yaw = yaw
		_saved_zoom = zoom
	_glide((a + b) / 2.0, yaw, maxf(zoom, _zoom_to_fit(a, b)), seconds)


## Smallest zoom that keeps a and b inside FIT_MARGIN of the screen, seen from
## the current angle with the pivot halfway between them.
func _zoom_to_fit(a: Vector3, b: Vector3) -> float:
	var d := b - a
	d.y = 0.0
	var right := basis.x
	var forward := Vector3(basis.z.x, 0.0, basis.z.z).normalized()
	var half_across := absf(d.dot(right)) / 2.0 + FIT_PADDING
	# Depth on the ground is foreshortened by the camera pitch.
	var half_depth := absf(d.dot(forward)) * sin(deg_to_rad(PITCH_DEGREES)) / 2.0 + FIT_PADDING
	var tan_v := tan(deg_to_rad(camera.fov) / 2.0)
	var viewport_size := get_viewport().get_visible_rect().size
	var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
	var needed := maxf(half_across / (tan_v * aspect * FIT_MARGIN), half_depth / (tan_v * FIT_MARGIN))
	return minf(needed, MAX_FIT_ZOOM)


## Glides back to the angle and zoom from before frame_pair(), centred on `at`.
func restore(at: Vector3, seconds: float = 0.54) -> void:
	if not _framed:
		focus(at, seconds)
		return
	_framed = false
	_glide(at, _saved_yaw, _saved_zoom, seconds)


## Keeps the pivot on a moving node for `seconds`.
func follow(node: Node3D, seconds: float) -> void:
	if _move_tween != null:
		_move_tween.kill()
	_follow = node
	_follow_until = Time.get_ticks_msec() / 1000.0 + seconds


func _glide(target: Vector3, to_yaw: float, to_zoom: float, seconds: float) -> void:
	_follow = null
	if _move_tween != null:
		_move_tween.kill()
	_move_tween = create_tween().set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_move_tween.tween_property(self, "position", Vector3(target.x, position.y, target.z), seconds)
	_move_tween.tween_property(self, "yaw", to_yaw, seconds)
	_move_tween.tween_property(self, "zoom", to_zoom, seconds)


## Entry and exit distances of a ray through the box from the origin to `size`
## (x > y means it misses). Slab method.
static func _ray_box(origin: Vector3, dir: Vector3, size: Vector3) -> Vector2:
	var t_min := 0.0
	var t_max := 1e9
	for axis in 3:
		if absf(dir[axis]) < 1e-6:
			if origin[axis] < 0.0 or origin[axis] > size[axis]:
				return Vector2(1, 0)
			continue
		var a := (0.0 - origin[axis]) / dir[axis]
		var b := (size[axis] - origin[axis]) / dir[axis]
		t_min = maxf(t_min, minf(a, b))
		t_max = minf(t_max, maxf(a, b))
	return Vector2(t_min, t_max)


## Brief camera shake; strength is in metres and fades out.
func shake(strength: float) -> void:
	_shake = maxf(_shake, strength)


## Middle-mouse drag rotates: degrees per pixel dragged sideways.
const DRAG_ROTATE_DEG_PER_PX := 0.35


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP: zoom = maxf(zoom - 2.0, 8.0)
			MOUSE_BUTTON_WHEEL_DOWN: zoom = minf(zoom + 2.0, 80.0)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0:
		if _move_tween != null and _move_tween.is_running():
			_move_tween.kill()  # the player takes over from a camera glide
		yaw -= event.relative.x * DRAG_ROTATE_DEG_PER_PX


func _update_camera() -> void:
	var pitch := deg_to_rad(PITCH_DEGREES)
	camera.position = Vector3(0, sin(pitch), cos(pitch)) * zoom
	if camera.is_inside_tree():
		camera.look_at(global_position)


## Ray-marches from the screen point and returns the cell under the cursor: a
## living entity's cell if the ray hits one, otherwise the open cell on top of
## the first solid cell (or, in levels with terrain, the walk cell of the
## terrain the ray reaches). Returns null when nothing is hit.
func pick_cell(state: SimState, screen_pos: Vector2, cutaway: BuildingCutaway = null) -> Variant:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var grid := state.grid
	var span := _ray_box(origin, dir, Vector3(grid.size))
	if span.x > span.y:
		return null
	var t := span.x
	var grazed := {}  # wall columns under a removed roof the ray slid past
	while t <= span.y:
		var p := origin + dir * t
		var c := Vector3i(floori(p.x), floori(p.y), floori(p.z))
		if grid.in_bounds(c):
			if state.entity_at(c) != null:
				return c
			var ground := WorldSpace.terrain_height(c.x, c.z)
			if p.y <= ground:
				var walk := Vector3i(c.x, WorldSpace.terrain_floor(c.x, c.z), c.z)
				while grid.in_bounds(walk) and grid.is_solid(walk):
					walk += Vector3i.UP
				return walk if grid.in_bounds(walk) else null
			if grid.is_solid(c) and not (cutaway != null and cutaway.see_through(c)):
				var above := c + Vector3i.UP
				var column := Vector2i(c.x, c.z)
				if grazed.has(column) or (cutaway != null and grid.in_bounds(above) and cutaway.see_through(above)):
					# A wall top under a removed roof (walls fill whole cells, wider
					# than they look): look on into the room.
					grazed[column] = true
					t += 0.05
					continue
				return above if grid.in_bounds(above) and not grid.is_solid(above) else null
		t += 0.05
	return null
