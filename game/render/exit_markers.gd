class_name ExitMarkers
extends Node3D
## Shows the ways into other levels (SimState.exits): a soft glowing ring on
## the ground and the place's name over it, once the party has explored there.
## Rebuilt only when the level's exits change.

const COLOR := Color(1.0, 0.85, 0.45)

var _drawn: Dictionary = {}


func render(state: SimState) -> void:
	var shown := {}
	for c: Vector3i in state.exits:
		if ExplorationRules.is_explored(state, c):
			shown[c] = state.exits[c].get("name", "")
	if shown == _drawn:
		return
	_drawn = shown
	for child in get_children():
		child.queue_free()
	for c: Vector3i in shown:
		add_child(_marker(c, shown[c]))


func _marker(c: Vector3i, title: String) -> Node3D:
	var root := Node3D.new()
	root.position = WorldSpace.cell_to_world(c)
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.emission_enabled = true
	material.emission = COLOR
	material.emission_energy_multiplier = 1.5
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	torus.material = material
	ring.mesh = torus
	ring.position.y = 0.05
	root.add_child(ring)
	var label := Label3D.new()
	label.text = title
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.pixel_size = 0.008
	label.outline_size = 8
	label.modulate = COLOR
	label.position.y = 2.2
	root.add_child(label)
	return root
