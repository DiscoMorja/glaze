class_name SnareMarkers
extends Node3D
## Shows the hidden snares (SimState.snares) the party set: a small ring of
## stakes on the ground. Enemies' snares stay hidden. Rebuilt only when the
## set of snares changes.

const COLOR := Color(0.75, 0.62, 0.4)

var _drawn := {}


func render(state: SimState) -> void:
	var shown := {}
	for c: Vector3i in state.snares:
		var setter := state.get_entity(state.snares[c])
		if setter != null and setter.faction == SimEntity.Faction.PLAYERS:
			shown[c] = true
	if shown.keys() == _drawn.keys():
		return
	_drawn = shown
	for child in get_children():
		child.queue_free()
	for c: Vector3i in shown:
		add_child(_marker(c))


func _marker(c: Vector3i) -> Node3D:
	var root := Node3D.new()
	root.position = WorldSpace.cell_to_world(c)
	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR
	material.roughness = 0.9
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.22
	torus.outer_radius = 0.28
	torus.material = material
	ring.mesh = torus
	ring.position.y = 0.03
	root.add_child(ring)
	for k in 4:
		var stake := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.04, 0.16, 0.04)
		box.material = material
		stake.mesh = box
		var angle := k * TAU / 4.0 + PI / 4.0
		stake.position = Vector3(cos(angle) * 0.25, 0.08, sin(angle) * 0.25)
		root.add_child(stake)
	return root
