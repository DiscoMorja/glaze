class_name SimEntityRenderer
extends Node3D
## Greybox views for entities: capsules for characters, cylinders for props,
## with a name label and a health bar. The bar shows when the entity was just
## hurt or healed, when it is hovered, when a previewed action would change its
## HP (with the predicted loss marked), or while show_all_bars is on.

const PLAYER_COLOR := Color(0.25, 0.6, 1.0)
const ENEMY_COLOR := Color(0.9, 0.25, 0.2)
const PROP_COLOR := Color(0.55, 0.38, 0.2)
const MOVE_SECONDS_PER_CELL := 0.1
const TARGETABLE_GLOW := Color(1.0, 0.8, 0.15)
## How long a bar stays up after the entity's HP changes.
const RECENT_SECONDS := 3.0

## When > 0 (real-time exploration), each move glides linearly over this many
## seconds, matching the sim tick, instead of playing a combat walk animation.
var walk_seconds := 0.0

var show_all_bars := false

var _views := {}  # entity id -> _View
var _hovered_id := -1
var _preview := {}  # entity id -> [now_hp, later_hp]


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for view_id: int in _views:
		var view: _View = _views[view_id]
		var predicted: Array = _preview.get(view_id, [])
		view.show_bar(show_all_bars or view_id == _hovered_id or not predicted.is_empty() or now < view.recent_until, predicted)


func render(state: SimState, events: Array[SimEvent] = []) -> void:
	var paths := {}
	for e in events:
		if e.type == SimEvent.Type.MOVED or e.type == SimEvent.Type.SHOVED:
			paths[e.entity_id] = e.cells
	var now := Time.get_ticks_msec() / 1000.0
	for e in state.entities:
		var view: _View = _views.get(e.id)
		if view == null:
			view = _View.new(e)
			add_child(view)
			_views[e.id] = view
			view.position = cell_position(e.cell)
		view.visible = e.is_alive()
		if view.set_stats(e):
			view.recent_until = now + RECENT_SECONDS
		view.move_to(cell_position(e.cell), paths.get(e.id, []), walk_seconds)


## The view node for an entity (e.g. for the camera to follow), or null.
func view_of(id: int) -> Node3D:
	return _views.get(id)


func set_selected(id: int) -> void:
	for view_id: int in _views:
		_views[view_id].set_selected(view_id == id)


func set_hovered(id: int) -> void:
	_hovered_id = id


## Tints entities that the hovered or aimed action can target (id -> true).
func set_targetable(ids: Dictionary) -> void:
	for view_id: int in _views:
		_views[view_id].set_targetable(ids.has(view_id))


## Predicted HP from a previewed action: id -> [hp right after, hp by turn end].
func set_preview(predicted: Dictionary) -> void:
	_preview = predicted


static func cell_position(c: Vector3i) -> Vector3:
	return WorldSpace.cell_to_world(c)


class _View:
	extends Node3D

	## Time (seconds) until which the bar stays up after an HP change.
	var recent_until := 0.0

	var _body: MeshInstance3D
	var _label: Label3D
	var _bar: HealthBar
	var _material: StandardMaterial3D
	var _base_color: Color
	var _tween: Tween
	var _selected := false
	var _targetable := false
	var _hp := -1
	var _max_hp := 1

	func _init(e: SimEntity) -> void:
		_material = StandardMaterial3D.new()
		_body = MeshInstance3D.new()
		var top: float
		if e.takes_turns():
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.3
			capsule.height = 1.5
			_body.mesh = capsule
			_body.position.y = 0.75
			_base_color = PLAYER_COLOR if e.faction == SimEntity.Faction.PLAYERS else ENEMY_COLOR
			top = 1.75
		else:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = 0.32
			cylinder.bottom_radius = 0.32
			cylinder.height = 0.9
			_body.mesh = cylinder
			_body.position.y = 0.45
			_base_color = PROP_COLOR
			top = 1.15
		_material.albedo_color = _base_color
		_body.material_override = _material
		add_child(_body)

		_bar = HealthBar.new(e.faction == SimEntity.Faction.PLAYERS)
		_bar.position.y = top
		_bar.visible = false
		add_child(_bar)

		_label = Label3D.new()
		_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_label.no_depth_test = true
		_label.pixel_size = 0.009
		_label.outline_size = 8
		_label.position.y = top + 0.34
		add_child(_label)

	## Updates the label and bar. Returns true if HP changed since last time.
	func set_stats(e: SimEntity) -> bool:
		_label.text = "%s  AP %d" % [e.name, e.ap] if e.takes_turns() else e.name
		var changed := _hp >= 0 and e.hp != _hp
		_hp = e.hp
		_max_hp = e.max_hp
		return changed

	func show_bar(shown: bool, predicted: Array) -> void:
		_bar.visible = shown
		if not shown:
			return
		var now_hp := _hp
		var later_hp := _hp
		if predicted.size() == 2:
			now_hp = predicted[0]
			later_hp = predicted[1]
		_bar.set_values(_max_hp, _hp, now_hp, later_hp)

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

	func move_to(target: Vector3, path: Array, glide_seconds: float = 0.0) -> void:
		if position.is_equal_approx(target):
			return
		if _tween != null:
			_tween.kill()
		_tween = create_tween()
		if glide_seconds > 0.0:
			_tween.tween_property(self, "position", target, glide_seconds)
			return
		for c: Vector3i in path:
			_tween.tween_property(self, "position", SimEntityRenderer.cell_position(c), MOVE_SECONDS_PER_CELL)
		_tween.tween_property(self, "position", target, MOVE_SECONDS_PER_CELL * 2.0)
