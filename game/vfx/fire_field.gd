class_name FireField
extends Node3D
## Looping flames on every burning cell, kept in sync with the grid: the pack's
## fire effect when installed, procedural particles otherwise. Replaces the
## greybox fire boxes in scenes that use it.

const FADE_SECONDS := 0.8

var _flames := {}  # cell index -> Node3D (pack effect or GPUParticles3D)


func sync(grid: SimGrid) -> void:
	var burning := {}
	for i in grid.cell_count:
		if grid.fire[i] > 0:
			burning[i] = true
			if not _flames.has(i):
				var c := grid.coord(i)
				var at := Vector3(c.x + 0.5, c.y + 0.05, c.z + 0.5)
				var flame := PackVfx.start(self, "burning", at)
				if flame == null:
					flame = VfxFactory.emitter("fire", 1.0)
					add_child(flame)
					flame.global_position = at + Vector3(0, 0.1, 0)
				_flames[i] = flame
			if _flames[i] is GPUParticles3D:
				var heat := grid.fire[i] / float(SimMaterials.FIRE_MAX)
				(_flames[i] as GPUParticles3D).amount_ratio = clampf(0.35 + 0.65 * heat, 0.0, 1.0)
	for i: int in _flames.keys():
		if not burning.has(i):
			var flame: Node3D = _flames[i]
			_flames.erase(i)
			if flame is GPUParticles3D:
				(flame as GPUParticles3D).emitting = false
				get_tree().create_timer(FADE_SECONDS).timeout.connect(flame.queue_free)
			else:
				PackVfx.stop(flame)


func clear() -> void:
	for flame: Node in _flames.values():
		flame.queue_free()
	_flames.clear()
