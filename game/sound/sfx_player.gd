class_name SfxPlayer
extends Node3D
## Plays sound cues (SoundBank) in the world: one-shots at a position with a
## little pitch and volume jitter, at most MAX_PER_CUE of a cue at once (four
## footsteps a tick don't pile up), optionally after a delay to land with the
## effect they belong to. Also keeps a looping fire crackle on the burning cell
## nearest the camera's focus while anything burns.

const MAX_PER_CUE := 3
const PITCH_JITTER := 0.08
## Distance (m) at which a sound is at full volume; the top-down camera sits
## 8-48 m away, so this keeps the view's sounds at a steady level.
const UNIT_SIZE := 24.0
const MAX_DISTANCE := 90.0
## Fire crackle: louder with more burning cells, up to this many.
const FIRE_FULL_AT := 12

var _playing := {}
var _fire: AudioStreamPlayer3D


func _ready() -> void:
	SoundBank.ensure_buses()


## Plays `cue` at `at` (world position), after `delay` seconds.
func play(cue: String, at: Vector3, delay: float = 0.0, volume_db: float = 0.0) -> void:
	if delay > 0.0:
		get_tree().create_timer(delay).timeout.connect(func() -> void: play(cue, at, 0.0, volume_db))
		return
	if _playing.get(cue, 0) >= MAX_PER_CUE:
		return
	var stream := SoundBank.stream(cue)
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.bus = "SFX"
	player.unit_size = UNIT_SIZE
	player.max_distance = MAX_DISTANCE
	player.volume_db = volume_db + randf_range(-1.5, 1.5)
	player.pitch_scale = 1.0 + randf_range(-PITCH_JITTER, PITCH_JITTER)
	player.position = at
	add_child(player)
	_playing[cue] = _playing.get(cue, 0) + 1
	player.finished.connect(func() -> void:
		_playing[cue] = maxi(_playing.get(cue, 1) - 1, 0)
		player.queue_free())
	player.play()


## Plays `cue` everywhere at once (interface sounds: loot, level up).
func play_ui(cue: String, volume_db: float = 0.0) -> void:
	var stream := SoundBank.stream(cue)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = volume_db
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()


## Moves the fire crackle to the burning cell nearest `focus` (or silences it).
func update_fire(grid: SimGrid, focus: Vector3) -> void:
	if grid.fire_cells.is_empty():
		if _fire != null:
			_fire.stop()
		return
	if _fire == null:
		var paths := SoundBank.paths_of("fire_loop")
		if paths.is_empty():
			return
		_fire = AudioStreamPlayer3D.new()
		_fire.stream = load(paths[0])
		_fire.bus = "SFX"
		_fire.unit_size = UNIT_SIZE * 0.6
		_fire.max_distance = MAX_DISTANCE
		add_child(_fire)
		_fire.finished.connect(func() -> void: _fire.play())  # loops whatever the file's import says
	var nearest := Vector3.INF
	for i: int in grid.fire_cells:
		var at := WorldSpace.cell_to_world(grid.coord(i))
		if at.distance_squared_to(focus) < nearest.distance_squared_to(focus):
			nearest = at
	_fire.position = nearest
	_fire.volume_db = linear_to_db(clampf(grid.fire_cells.size() / float(FIRE_FULL_AT), 0.25, 1.0))
	if not _fire.playing:
		_fire.play()
