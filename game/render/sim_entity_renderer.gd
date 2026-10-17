class_name SimEntityRenderer
extends Node3D
## Greybox views for entities: capsules for characters, cylinders for props,
## with a name/HP/AP label and an optional preview label.

const PLAYER_COLOR := Color(0.25, 0.6, 1.0)
const ENEMY_COLOR := Color(0.9, 0.25, 0.2)
const PROP_COLOR := Color(0.55, 0.38, 0.2)
const MOVE_SECONDS_PER_CELL := 0.08
const TARGETABLE_GLOW := Color(1.0, 0.8, 0.15)

var _views := {}  # entity id -> _View


func render(state: SimState, events: Array[SimEvent] = []) -> void:
	var paths := {}
	for e in events:
		if e.type == SimEvent.Type.MOVED or e.type == SimEvent.Type.SHOVED:
			paths[e.entity_id] = e.cells
	for e in state.entities:
		var view: _View = _views.get(e.id)
		if view == null:
			view = _View.new(e)
			add_child(view)
			_views[e.id] = view
			view.position = cell_position(e.cell)
		view.visible = e.is_alive()
		view.set_stats(e)
		view.move_to(cell_position(e.cell), paths.get(e.id, []))


func set_selected(id: int) -> void:
	for view_id: int in _views:
		_views[view_id].set_selected(view_id == id)


## Tints entities that the hovered or aimed action can target (id -> true).
func set_targetable(ids: Dictionary) -> void:
	for view_id: int in _views:
		_views[view_id].set_targetable(ids.has(view_id))


## Shows preview text above entities (id -> text); others are cleared.
func set_preview(texts: Dictionary) -> void:
	for view_id: int in _views:
		_views[view_id].set_preview(texts.get(view_id, ""))


static func cell_position(c: Vector3i) -> Vector3:
	return Vector3(c.x + 0.5, c.y, c.z + 0.5)


class _View:
	extends Node3D

	var _body: MeshInstance3D
	var _label: Label3D
	var _preview: Label3D
	var _material: StandardMaterial3D
	var _base_color: Color
	var _tween: Tween
	var _selected := false
	var _targetable := false

	func _init(e: SimEntity) -> void:
		_material = StandardMaterial3D.new()
		_body = MeshInstance3D.new()
		if e.takes_turns():
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.3
			capsule.height = 1.5
			_body.mesh = capsule
			_body.position.y = 0.75
			_base_color = PLAYER_COLOR if e.faction == SimEntity.Faction.PLAYERS else ENEMY_COLOR
		else:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.32
			cylinder.bottom_radius = 0.32
			cylinder.height = 0.9
			_body.mesh = cylinder
			_body.position.y = 0.45
			_base_color = PROP_COLOR
		_material.albedo_color = _base_color
		_body.material_override = _material
		add_child(_body)

		_label = _make_label(Color.WHITE, 1.9 if e.takes_turns() else 1.3)
		_preview = _make_label(Color(1.0, 0.85, 0.2), (1.9 if e.takes_turns() else 1.3) + 0.45)

	func _make_label(color: Color, height: float) -> Label3D:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.pixel_size = 0.009
		label.outline_size = 8
		label.modulate = color
		label.position.y = height
		add_child(label)
		return label

	func set_stats(e: SimEntity) -> void:
		if e.takes_turns():
			_label.text = "%s  %d/%d  AP %d" % [e.name, e.hp, e.max_hp, e.ap]
		else:
			_label.text = "%s  %d/%d" % [e.name, e.hp, e.max_hp]

	func set_selected(selected: bool) -> void:
		_selected = selected
		_update_look()

	func set_targetable(targetable: bool) -> void:
		_targetable = targetable
		_update_look()

	func _update_look() -> void:
		_material.albedo_color = _base_color.lightened(0.45) if _selected else _base_color
		_material.emission_enabled = _selected or _targetable
		_material.emission = TARGETABLE_GLOW if _targetable else _base_color * 0.4

	func set_preview(text: String) -> void:
		_preview.text = text

	func move_to(target: Vector3, path: Array) -> void:
		if position.is_equal_approx(target):
			return
		if _tween != null:
			_tween.kill()
		_tween = create_tween()
		for c: Vector3i in path:
			_tween.tween_property(self, "position", SimEntityRenderer.cell_position(c), MOVE_SECONDS_PER_CELL)
		_tween.tween_property(self, "position", target, MOVE_SECONDS_PER_CELL * 2.0)
