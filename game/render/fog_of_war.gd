class_name FogOfWar
extends Node
## Draws the sim's fog of war (ExplorationRules) and decides what of the world
## is shown: a screen pass darkens the view (black where unexplored, dimmed
## out of sight), characters out of the party's sight are hidden, and level
## visuals (structures, trees) in unexplored ground aren't drawn at all until
## the party gets there. Presentation only.

const SHADER := preload("res://game/render/fog_of_war.gdshader")
const MAX_SEERS := 8

var _quad: MeshInstance3D
var _material: ShaderMaterial
var _texture: ImageTexture
var _shown_explored := PackedByteArray()
var _tiles := Vector2i.ZERO
## Level visuals not drawn yet: [node, tile rect (Rect2i, inclusive)].
var _hidden: Array = []


## Puts the screen pass in front of `camera` and hides the level's visuals
## that stand on unexplored ground.
func setup(camera: Camera3D, level: Node, state: SimState) -> void:
	if _quad == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
		_material.render_priority = 100  # over everything else in the 3D view
		var mesh := QuadMesh.new()
		mesh.size = Vector2(2, 2)
		_quad = MeshInstance3D.new()
		_quad.mesh = mesh
		_quad.material_override = _material
		_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_quad.extra_cull_margin = 16384.0
		_quad.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	if _quad.get_parent() != camera:
		if _quad.get_parent() != null:
			_quad.get_parent().remove_child(_quad)
		camera.add_child(_quad)
	_quad.position = Vector3(0, 0, -1)
	_tiles = Vector2i(ExplorationRules.tiles_x(state.grid), ExplorationRules.tiles_z(state.grid))
	_material.set_shader_parameter("world_size", Vector2(_tiles * ExplorationRules.TILE))
	_material.set_shader_parameter("sight", float(ExplorationRules.SIGHT))
	_texture = null
	_shown_explored = PackedByteArray()
	_collect_hidden(level)
	update(state, [])


## Follows the sim's explored tiles and the party's (drawn) positions.
func update(state: SimState, seers: Array[Vector3]) -> void:
	if state == null or _material == null:
		return
	if state.explored != _shown_explored and state.explored.size() == _tiles.x * _tiles.y:
		_shown_explored = state.explored.duplicate()
		var image := Image.create_from_data(_tiles.x, _tiles.y, false, Image.FORMAT_L8, state.explored)
		if _texture == null:
			_texture = ImageTexture.create_from_image(image)
			_material.set_shader_parameter("explored", _texture)
		else:
			_texture.set_image(image)  # 20 KB; update() didn't take on L8
		_reveal(state)
	var points := PackedVector2Array()
	for p in seers:
		if points.size() < MAX_SEERS:
			points.append(Vector2(p.x, p.z))
	_material.set_shader_parameter("seer_count", points.size())
	points.resize(MAX_SEERS)
	_material.set_shader_parameter("seers", points)


## Whether the entity's model is shown: the party always; living characters
## while the party sees them (or fight in the current battle); props and the
## fallen once their ground is explored.
static func shows(state: SimState, e: SimEntity) -> bool:
	if ExplorationRules.is_seer(e) or e.faction == SimEntity.Faction.PLAYERS:
		return true
	if e.takes_turns() and e.is_alive():
		return ExplorationRules.in_sight(state, e.cell) or (state.combat.active and e.in_combat)
	return ExplorationRules.is_explored(state, e.cell)


func _collect_hidden(level: Node) -> void:
	_hidden.clear()
	if level == null:
		return
	for node in level.find_children("*", "CSGShape3D", true, false):
		var csg := node as CSGShape3D
		if csg.is_root_shape():
			_hide(csg, csg.global_transform * csg.get_aabb())
	var props: Array[Node] = level.find_children("*", "StaticBody3D", true, false)
	for node in level.get_tree().get_nodes_in_group("level_prop"):
		if node is Node3D and not node is StaticBody3D and level.is_ancestor_of(node):
			props.append(node)  # torches and other props without collision
	for node in props:
		var prop := node as Node3D
		var box := AABB(prop.global_position, Vector3.ZERO)
		for child in prop.find_children("*", "VisualInstance3D", true, false):
			if child is GeometryInstance3D:
				box = box.merge((child as VisualInstance3D).global_transform * (child as VisualInstance3D).get_aabb())
		_hide(prop, box)


func _hide(node: Node3D, box: AABB) -> void:
	var t := float(ExplorationRules.TILE)
	var rect := Rect2i(floori(box.position.x / t), floori(box.position.z / t), 0, 0)
	rect.end = Vector2i(floori(box.end.x / t), floori(box.end.z / t))
	node.visible = false
	_hidden.append([node, rect])


## Shows the hidden visuals that touch an explored tile.
func _reveal(state: SimState) -> void:
	var still: Array = []
	for entry: Array in _hidden:
		var node: Node3D = entry[0]
		if not is_instance_valid(node):
			continue
		if _touches_explored(state, entry[1]):
			node.visible = true
		else:
			still.append(entry)
	_hidden = still


func _touches_explored(state: SimState, rect: Rect2i) -> bool:
	for tz in range(maxi(rect.position.y, 0), mini(rect.end.y, _tiles.y - 1) + 1):
		var row := tz * _tiles.x
		for tx in range(maxi(rect.position.x, 0), mini(rect.end.x, _tiles.x - 1) + 1):
			if state.explored[row + tx] == ExplorationRules.EXPLORED:
				return true
	return false
