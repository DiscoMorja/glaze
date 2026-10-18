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
## Every debuff gets a tag colour and looping effects on the character. Each
## effect is a BinbunVFX pack effect ("pack", skipped if the pack is missing)
## or a procedural VfxFactory emitter ("emitter"), at a height above the feet.
## Keep them outside the body (rings, above the head) so the capsule doesn't
## hide them.
## "turns": show the turns left after the label.
const STATUS_LOOKS := {
	"burning": {"label": "Burning", "color": "ff8a2a", "turns": true, "effects": [
		{"emitter": "burning_body", "scale": 1.0, "height": 0.75},
		{"pack": "burning", "scale": 0.8, "height": 1.6},
	]},
	"hot": {"label": "Hot", "color": "ffb070", "effects": [
		{"emitter": "heat", "scale": 1.0, "height": 0.75},
	]},
	"cold": {"label": "Cold", "color": "9fd4ff", "effects": [
		{"emitter": "frost", "scale": 1.0, "height": 0.8},
	]},
	"frozen": {"label": "Frozen", "color": "6fc3ff", "turns": true, "effects": [
		{"emitter": "frozen_shell", "scale": 1.0, "height": 0.75},
	]},
	"slowed": {"label": "Slowed", "color": "c9a061", "turns": true, "effects": [
		{"emitter": "oil_drip", "scale": 1.0, "height": 0.8},
	]},
	"knocked": {"label": "Knocked down", "color": "e0e0e0", "effects": [
		{"emitter": "dazed", "scale": 1.0, "height": 0.7},
	]},
}
## Frozen characters take on an icy tint.
const FROZEN_TINT := Color(0.7, 0.9, 1.0)

## When > 0 (real-time exploration), each move glides linearly over this many
## seconds, matching the sim tick, instead of playing a combat walk animation.
var walk_seconds := 0.0

var show_all_bars := false
## Lends pooled pack flames to burning characters (optional).
var fire_field: FireField

var _views := {}  # entity id -> _View
var _hovered_id := -1
var _preview := {}  # entity id -> [now_hp, later_hp]


## Runs each status emitter once out of sight, so its particle shaders are
## compiled before the first character catches fire (no hitch then).
func _ready() -> void:
	for status: String in STATUS_LOOKS:
		for effect: Dictionary in STATUS_LOOKS[status].effects:
			if effect.has("emitter"):
				var warm := VfxFactory.emitter(effect.emitter, effect.scale)
				add_child(warm)
				warm.position = Vector3(0, -50, 0)
				get_tree().create_timer(1.0).timeout.connect(warm.queue_free)


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
			view.fire_field = fire_field
			add_child(view)
			_views[e.id] = view
			view.position = cell_position(e.cell)
		view.visible = e.is_alive()
		if view.set_stats(e):
			view.recent_until = now + RECENT_SECONDS
		# Slowed characters take twice as long per cell.
		var pace := 2.0 if e.slowed > 0 else 1.0
		view.move_to(cell_position(e.cell), paths.get(e.id, []), walk_seconds * pace, pace)


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
	## Name and AP: a ScreenLabels label when the scene has one, else a Label3D.
	var _label: Node
	## Debuff tags, coloured, above the name (ScreenLabels only).
	var _status: RichTextLabel
	## Status name -> its looping effect nodes.
	var _loops := {}
	var fire_field: FireField
	var _bar: HealthBar
	var _material: StandardMaterial3D
	var _base_color: Color
	var _tween: Tween
	var _selected := false
	var _targetable := false
	var _down := false
	var _frozen := false
	## The body's height when standing.
	var _rest_height := 0.0
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
		_rest_height = _body.position.y
		add_child(_body)

		_bar = HealthBar.new(e.faction == SimEntity.Faction.PLAYERS)
		_bar.position.y = top
		_bar.visible = false
		add_child(_bar)

		if ScreenLabels.instance != null:
			_label = ScreenLabels.instance.follow(self, Vector3(0, top + 0.34, 0))
			_status = ScreenLabels.instance.follow_rich(self, Vector3(0, top + 0.34, 0), Vector2(0, -20))
		else:
			var label := Label3D.new()
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.pixel_size = 0.009
			label.outline_size = 8
			label.position.y = top + 0.34
			add_child(label)
			_label = label

	## Updates the label and bar. Returns true if HP changed since last time.
	func set_stats(e: SimEntity) -> bool:
		var text := "%s  AP %d" % [e.name, e.ap] if e.takes_turns() else e.name
		# Status -> turns left (0 = not active; 1 for ones without a count).
		var turns := {
			"burning": e.temp_turns if e.is_burning() else 0,
			"hot": 1 if e.temperature == 1 else 0,
			"cold": 1 if e.temperature == -1 else 0,
			"frozen": e.temp_turns if e.is_frozen() else 0,
			"slowed": e.slowed,
			"knocked": 1 if e.knocked_down else 0,
		}
		var tags: Array[String] = []
		for status: String in STATUS_LOOKS:
			var look: Dictionary = STATUS_LOOKS[status]
			var active: bool = turns[status] > 0 and e.is_alive()
			if active:
				var label: String = look.label if not look.get("turns", false) else "%s %d" % [look.label, turns[status]]
				tags.append("[color=#%s]%s[/color]" % [look.color, label])
			_set_loop(status, active)
		if e.stagger > 0 and e.is_alive():
			tags.append("[color=#d8c8a0]Stagger %d/%d[/color]" % [e.stagger, e.stagger_max])
		_set_pose(e.knocked_down and e.is_alive(), e.is_frozen() and e.is_alive())
		if _status != null:
			_status.text = "[center]%s[/center]" % "  ".join(tags) if not tags.is_empty() else ""
		elif not tags.is_empty():
			text += "  " + " ".join(tags)
		_label.set("text", text)
		var changed := _hp >= 0 and e.hp != _hp
		_hp = e.hp
		_max_hp = e.max_hp
		return changed

	## Starts or stops a debuff's looping effect.
	func _set_loop(status: String, active: bool) -> void:
		if active == _loops.has(status):
			return
		if not active:
			for node: Node3D in _loops[status]:
				if node.has_meta("borrowed"):
					fire_field.give_back(node)
				else:
					PackVfx.stop(node)
			_loops.erase(status)
			return
		var nodes: Array[Node3D] = []
		for effect: Dictionary in STATUS_LOOKS[status].effects:
			var at := Vector3(0, effect.height, 0)
			var node: Node3D = null
			if effect.has("pack") and effect.pack == "burning" and fire_field != null and is_inside_tree():
				# Pooled flame: building a pack flame on the spot hitches.
				node = fire_field.borrow(global_position + at)
				node.reparent(self)
				node.position = at
				node.scale = Vector3.ONE * effect.scale
				node.set_meta("borrowed", true)
			elif effect.has("pack"):
				if is_inside_tree():
					node = PackVfx.start(self, effect.pack, global_position + at, effect.scale)
			else:
				node = VfxFactory.emitter(effect.emitter, effect.scale)
				add_child(node)
				node.position = at
			if node != null:
				nodes.append(node)
		_loops[status] = nodes

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

	## Knocked down: the body tips over. Frozen: an icy tint.
	func _set_pose(down: bool, frozen: bool) -> void:
		if frozen != _frozen:
			_frozen = frozen
			_update_look()
		if down == _down:
			return
		_down = down
		var pose := create_tween().set_parallel(true)
		pose.tween_property(_body, "rotation_degrees:x", 90.0 if down else 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pose.tween_property(_body, "position:y", _rest_height * 0.4 if down else _rest_height, 0.25)

	func _update_look() -> void:
		var base := _base_color.lerp(FROZEN_TINT, 0.65) if _frozen else _base_color
		_material.albedo_color = base.lightened(0.45) if _selected else base
		_material.emission_enabled = _selected or _targetable
		_material.emission = TARGETABLE_GLOW if _targetable else _base_color * 0.4

	func move_to(target: Vector3, path: Array, glide_seconds: float = 0.0, pace: float = 1.0) -> void:
		if position.is_equal_approx(target):
			return
		if _tween != null:
			_tween.kill()
		_tween = create_tween()
		if glide_seconds > 0.0:
			_tween.tween_property(self, "position", target, glide_seconds)
			return
		for c: Vector3i in path:
			_tween.tween_property(self, "position", SimEntityRenderer.cell_position(c), MOVE_SECONDS_PER_CELL * pace)
		_tween.tween_property(self, "position", target, MOVE_SECONDS_PER_CELL * 2.0 * pace)
