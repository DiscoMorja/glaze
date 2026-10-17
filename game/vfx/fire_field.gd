class_name FireField
extends Node3D
## Looping flames on every burning cell, kept in sync with the grid: the pack's
## fire effect when installed, procedural particles otherwise. Replaces the
## greybox fire boxes in scenes that use it.
##
## Pack flames are expensive to create (~25 ms each), so they are pooled:
## prewarm() builds a stock up front and put-out flames are parked for reuse.

const FADE_SECONDS := 0.8
const PREWARM := 24

var _flames := {}  # cell index -> Node3D (pack effect or GPUParticles3D)
var _pool: Array[Node3D] = []


## Builds pooled pack flames a few per frame so startup doesn't hitch.
func prewarm(count: int = PREWARM) -> void:
	if not PackVfx.has("burning"):
		return
	for i in count:
		var flame := PackVfx.start(self, "burning", Vector3(0, -50, 0))
		if flame == null:
			return
		_park(flame)
		if i % 4 == 3:
			await get_tree().process_frame


func sync(grid: SimGrid) -> void:
	var burning := {}
	var fire := grid.fire
	for i in grid.cell_count:
		if fire[i] == 0:
			continue
		burning[i] = true
		if not _flames.has(i):
			var c := grid.coord(i)
			_flames[i] = _light(Vector3(c.x + 0.5, c.y + 0.05, c.z + 0.5))
		var flame: Node3D = _flames[i]
		if flame is GPUParticles3D:
			var heat := fire[i] / float(SimMaterials.FIRE_MAX)
			(flame as GPUParticles3D).amount_ratio = clampf(0.35 + 0.65 * heat, 0.0, 1.0)
	for i: int in _flames.keys():
		if not burning.has(i):
			_put_out(_flames[i])
			_flames.erase(i)


func clear() -> void:
	for flame: Node3D in _flames.values():
		_put_out(flame)
	_flames.clear()


func _light(at: Vector3) -> Node3D:
	if not _pool.is_empty():
		var reused: Node3D = _pool.pop_back()
		reused.global_position = at
		reused.visible = true
		reused.set("emitting", true)
		return reused
	var flame := PackVfx.start(self, "burning", at)
	if flame != null:
		return flame
	var particles := VfxFactory.emitter("fire", 1.0)
	add_child(particles)
	particles.global_position = at + Vector3(0, 0.1, 0)
	return particles


func _put_out(flame: Node3D) -> void:
	if flame is GPUParticles3D:
		(flame as GPUParticles3D).emitting = false
		get_tree().create_timer(FADE_SECONDS).timeout.connect(flame.queue_free)
		return
	flame.set("emitting", false)
	get_tree().create_timer(FADE_SECONDS).timeout.connect(func() -> void:
		if is_instance_valid(flame):
			_park(flame))


## Hides a pack flame and keeps it for reuse.
func _park(flame: Node3D) -> void:
	flame.set("emitting", false)
	flame.visible = false
	flame.global_position = Vector3(0, -50, 0)
	_pool.append(flame)
