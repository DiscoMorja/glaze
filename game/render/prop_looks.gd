class_name PropLooks
extends RefCounted
## Models for containers and barrels (SimEntity.model, set from
## LevelContainer.look): Kenney CC0 models kept in the repo. An unknown look
## falls back to the renderer's plain box or cylinder. Presentation only.

const SURVIVAL := "res://levels/shared/props/kenney_survival/"
const NATURE := "res://levels/shared/props/kenney_nature/"

## look -> [model, scale]
const LOOKS := {
	"chest": [SURVIVAL + "chest.glb", 3.0],
	"barrel": [SURVIVAL + "barrel.glb", 3.0],
	"crate": [SURVIVAL + "box.glb", 3.2],
	"crate_large": [SURVIVAL + "box-large.glb", 3.2],
	"basket": [SURVIVAL + "bucket.glb", 3.4],
	"pot": [NATURE + "pot_small.glb", 2.6],
}
## Barrels of oil or water (no look of their own) use this one.
const BARREL_LOOK := "barrel"

static var _scenes := {}


## The look for an entity that isn't a character, or "" for none.
static func look_of(e: SimEntity) -> String:
	if LOOKS.has(e.model):
		return e.model
	if e.model == "" and e.contents_amount > 0:
		return BARREL_LOOK
	return ""


## A new model node for `look`, or null when it isn't available.
static func create(look: String) -> Node3D:
	if not LOOKS.has(look):
		return null
	var entry: Array = LOOKS[look]
	if not _scenes.has(look):
		_scenes[look] = load(entry[0]) if ResourceLoader.exists(entry[0]) else null
	var scene: PackedScene = _scenes[look]
	if scene == null:
		return null
	var holder := Node3D.new()
	var model := scene.instantiate() as Node3D
	model.scale = Vector3.ONE * float(entry[1])
	holder.add_child(model)
	return holder


## Own copies of every material on the model (so it can be tinted alone).
static func materials(node: Node3D) -> Array[BaseMaterial3D]:
	var result: Array[BaseMaterial3D] = []
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		if mesh.mesh == null:
			continue
		for i in mesh.mesh.get_surface_count():
			var source := mesh.get_active_material(i) as BaseMaterial3D
			if source == null:
				continue
			var own := source.duplicate() as BaseMaterial3D
			mesh.set_surface_override_material(i, own)
			result.append(own)
	return result


## Height of the model's top in its own units (multiply by the look's scale).
static func height(node: Node3D) -> float:
	var top := 0.0
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := child as MeshInstance3D
		top = maxf(top, mesh.position.y + mesh.get_aabb().end.y)
	return top
