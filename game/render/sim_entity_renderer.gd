class_name SimEntityRenderer
extends Node3D
## Views for entities: animated character models (CharacterModel, from the
## placeholder packs; capsules without them), boxes and cylinders for props,
## with status icons, a name label and a health bar. To keep the view readable
## the name shows only on the hovered or selected entity (or all, holding Alt),
## and statuses are icons with their turns left; hovering spells them out.
## The health bar The bar shows when the entity was just
## hurt or healed, when it is hovered, when a previewed action would change its
## HP (with the predicted loss marked), or while show_all_bars is on.

const PLAYER_COLOR := Color(0.25, 0.6, 1.0)
const ENEMY_COLOR := Color(0.9, 0.25, 0.2)
const NEUTRAL_COLOR := Color(0.85, 0.75, 0.45)
const OUTLINE_NEUTRAL := Color(1.0, 0.85, 0.3)
const PROP_COLOR := Color(0.55, 0.38, 0.2)
const CHEST_COLOR := Color(0.45, 0.28, 0.14)
const MOVE_SECONDS_PER_CELL := 0.1
const TARGETABLE_GLOW := Color(1.0, 0.8, 0.15)
## How long a bar stays up after the entity's HP changes.
const RECENT_SECONDS := 3.0
## Every debuff gets a tag colour and looping effects on the character. Each
## effect is a BinbunVFX pack effect ("pack", skipped if the pack is missing)
## or a procedural VfxFactory emitter ("emitter"), at a height above the feet.
## Keep them outside the body (rings, above the head) so the capsule doesn't
## hide them.
## "turns": show the turns left on the icon.
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
	"suspicious": {"label": "Suspicious!", "color": "ffa040", "effects": []},
	"sneaking": {"label": "Sneaking", "color": "a0a8c0", "effects": []},
	"knocked": {"label": "Knocked down", "color": "e0e0e0", "effects": [
		{"emitter": "dazed", "scale": 1.0, "height": 0.7},
	]},
}
const STAGGER_COLOR := "d8c8a0"
## Frozen characters take on an icy tint.
const FROZEN_TINT := Color(0.7, 0.9, 1.0)
## Characters are outlined by side. The stencil value they write also keeps
## ground markers (CellMarkers.CHARACTER_STENCIL) from drawing over them.
const OUTLINE_ALLY := Color(0.35, 1.0, 0.45)
const OUTLINE_ENEMY := Color(1.0, 0.25, 0.2)
const OUTLINE_THICKNESS := 0.035
## The fallen lie where they died, greyed out.
const CORPSE_TINT := Color(0.32, 0.32, 0.34)

## When > 0 (real-time exploration), each move glides linearly over this many
## seconds, matching the sim tick, instead of playing a combat walk animation.
var walk_seconds := 0.0

## Alt held: every bar and name shows.
var show_all_bars := false
## Side outlines (green allies, red enemies) are drawn only in combat.
var outlines := false:
	set(value):
		if value == outlines:
			return
		outlines = value
		for view: _View in _views.values():
			view.set_outlined(value)
var _selected_id := -1
## Lends pooled pack flames to burning characters (optional).
var fire_field: FireField

var _views := {}  # entity id -> _View
## Bodies this player has opened (no more glitter on them).
var _searched := {}
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


func _process(delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for view_id: int in _views:
		var view: _View = _views[view_id]
		view.animate(delta)
		var predicted: Array = _preview.get(view_id, [])
		view.show_bar(show_all_bars or view_id == _hovered_id or not predicted.is_empty() or now < view.recent_until, predicted)
		var hovered := show_all_bars or view_id == _hovered_id
		view.show_detail(hovered or view_id == _selected_id, hovered)


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
			view.set_outlined(outlines)
			_views[e.id] = view
			view.position = cell_position(e.cell)
		# Characters stay as corpses (they can be revived), broken containers
		# while they still hold something; other props just vanish.
		view.visible = (e.is_alive() or e.takes_turns() or not e.inventory.is_empty()) and FogOfWar.shows(state, e)
		view.set_dead(not e.is_alive())
		view.set_side(e.faction)
		if view.set_stats(e):
			view.recent_until = now + RECENT_SECONDS
		# Fallen characters with something on them glitter until opened.
		view.set_glitter(not e.is_alive() and e.takes_turns() and LootCommand.is_container(e) 				and not e.inventory.is_empty() and not _searched.has(e.id))
		# Slowed characters take twice as long per cell.
		var pace := 2.0 if e.slowed > 0 else 1.0
		view.move_to(cell_position(e.cell), paths.get(e.id, []), walk_seconds * pace, pace)
	_animate_events(events)


## Attacks, spells, hits and potions play on the models (presentation only).
func _animate_events(events: Array[SimEvent]) -> void:
	for e in events:
		match e.type:
			SimEvent.Type.ATTACKED:
				var attacker: _View = _views.get(e.other_id)
				if attacker != null:
					attacker.act("attack", cell_position(e.cell))
			SimEvent.Type.CAST:
				var caster: _View = _views.get(e.entity_id)
				if caster != null:
					caster.act("cast", cell_position(e.cell))
			SimEvent.Type.DAMAGED:
				var victim: _View = _views.get(e.entity_id)
				if victim != null:
					victim.act("hit", Vector3.INF)
			SimEvent.Type.ITEM_USED:
				var user: _View = _views.get(e.other_id)
				if user != null:
					user.act("drink", Vector3.INF)


## Gold sparkles, a soft pulsing light and a ring on the ground: "something
## to loot here, click inside the ring" (the body may lie across cells).
static func make_glitter() -> Node3D:
	var glitter := Node3D.new()
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.38
	torus.outer_radius = 0.46
	torus.rings = 24
	torus.ring_segments = 6
	ring.mesh = torus
	ring.scale = Vector3(1, 0.08, 1)
	ring.position = Vector3(0, 0.04, 0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ring_material := StandardMaterial3D.new()
	ring_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_material.albedo_color = Color(1.0, 0.82, 0.3, 0.85)
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_material.no_depth_test = true
	ring_material.render_priority = 1
	ring.material_override = ring_material
	glitter.add_child(ring)
	var sparks := VfxFactory.emitter("glitter", 1.0)
	sparks.position = Vector3(0, 0.25, 0)
	glitter.add_child(sparks)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.4)
	light.light_energy = 0.6
	light.omni_range = 1.6
	light.position = Vector3(0, 0.5, 0)
	glitter.add_child(light)
	glitter.ready.connect(func() -> void:
		var breathe := ring.create_tween().set_loops()
		breathe.tween_property(ring_material, "albedo_color:a", 0.45, 0.7).set_trans(Tween.TRANS_SINE)
		breathe.tween_property(ring_material, "albedo_color:a", 0.9, 0.7).set_trans(Tween.TRANS_SINE)
		var pulse := light.create_tween().set_loops()
		pulse.tween_property(light, "light_energy", 1.1, 0.7).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(light, "light_energy", 0.4, 0.7).set_trans(Tween.TRANS_SINE))
	return glitter


## This player opened a body: its glitter goes.
func mark_searched(id: int) -> void:
	_searched[id] = true
	var view: _View = _views.get(id)
	if view != null:
		view.set_glitter(false)


## The view node for an entity (e.g. for the camera to follow), or null.
func view_of(id: int) -> Node3D:
	return _views.get(id)


func set_selected(id: int) -> void:
	_selected_id = id
	for view_id: int in _views:
		_views[view_id].set_selected(view_id == id)


func set_hovered(id: int) -> void:
	var view: Node3D = _views.get(id)
	_hovered_id = id if view != null and view.visible else -1  # nothing to hover in the fog


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
	## The animated model (characters, when the packs are there), else null.
	var _model: CharacterModel
	## What poses tip over: the model or the capsule.
	var _figure: Node3D
	## Every material to tint and outline, with its own base colour.
	var _materials: Array[BaseMaterial3D] = []
	var _material_bases: Array[Color] = []
	## Facing (SimPerception.FACINGS index) and a point to turn to after an
	## action (Vector3.INF = none).
	var _facing := 4
	var _look_at := Vector3.INF
	var _in_combat := false
	var _last_position := Vector3.ZERO
	## The name: a ScreenLabels label when the scene has one, else a Label3D.
	var _label: Node
	## Status icons (always), and their names spelled out above the name while
	## hovered (ScreenLabels only).
	var _icons: StatusIcons
	var _status: RichTextLabel
	var _name_shown := false
	var _words_shown := false
	var _words := ""
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
	var _dead := false
	var _outline := Color.TRANSPARENT
	var _outlined := false
	var _glitter: Node3D
	var _side := -1
	var _sneaking := false
	## The body's height when standing.
	var _rest_height := 0.0
	## Drawn with a textured model (a character or a prop look), so tints keep
	## the model's own colours.
	var _textured := false
	var _hp := -1
	var _max_hp := 1
	var _name := ""

	func _init(e: SimEntity) -> void:
		_material = StandardMaterial3D.new()
		_body = MeshInstance3D.new()
		var top: float
		if e.takes_turns():
			_model = CharacterModel.create(e.model if CharacterLooks.LOOKS.has(e.model) else CharacterLooks.default_for(e))
		if _model != null:
			add_child(_model)
			_figure = _model
			_base_color = Color.WHITE
			top = _model.height + 0.15
		elif e.takes_turns():
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.3
			capsule.height = 1.5
			_body.mesh = capsule
			_body.position.y = 0.75
			_base_color = PLAYER_COLOR if e.faction == SimEntity.Faction.PLAYERS else ENEMY_COLOR
			top = 1.75
		var prop: Node3D = PropLooks.create(PropLooks.look_of(e)) if _model == null else null
		if prop != null:
			add_child(prop)
			_figure = prop
			_base_color = Color.WHITE
			_textured = true
		elif e.model == "chest":
			var box := BoxMesh.new()
			box.size = Vector3(0.9, 0.6, 0.6)
			_body.mesh = box
			_body.position.y = 0.3
			_base_color = CHEST_COLOR
			top = 0.95
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
		if prop != null:
			_materials = PropLooks.materials(prop)
			top = maxf(PropLooks.height(prop) * PropLooks.LOOKS[PropLooks.look_of(e)][1], 0.6) + 0.25
		elif _model != null:
			_textured = true
			_materials = _model.materials()
		else:
			_materials = [_material]
			_body.material_override = _material
			_rest_height = _body.position.y
			_figure = _body
			add_child(_body)
		for material in _materials:
			_material_bases.append(material.albedo_color if _textured else _base_color)
		if e.takes_turns() and e.faction != SimEntity.Faction.NONE:
			_outline = OUTLINE_ALLY if e.faction == SimEntity.Faction.PLAYERS else OUTLINE_ENEMY
			for material in _materials:
				material.stencil_mode = BaseMaterial3D.STENCIL_MODE_OUTLINE
				material.stencil_color = Color.TRANSPARENT  # shown in combat (set_outlined)
				material.stencil_outline_thickness = OUTLINE_THICKNESS
				material.stencil_reference = CellMarkers.CHARACTER_STENCIL

		_bar = HealthBar.new(e.faction == SimEntity.Faction.PLAYERS)
		_bar.position.y = top
		_bar.visible = false
		add_child(_bar)

		if ScreenLabels.instance != null:
			var at := Vector3(0, top + 0.3, 0)
			_icons = ScreenLabels.instance.follow_control(StatusIcons.new(), self, at) as StatusIcons
			_label = ScreenLabels.instance.follow(self, at, 15)
			_status = ScreenLabels.instance.follow_rich(self, at, Vector2(0, -42))
		else:
			var label := Label3D.new()
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			label.no_depth_test = true
			label.pixel_size = 0.009
			label.outline_size = 8
			label.position.y = top + 0.34
			add_child(label)
			_label = label

	## Updates the labels, icons and bar. Returns true if HP changed since last time.
	func set_stats(e: SimEntity) -> bool:
		var text := e.name
		# Status -> turns left (0 = not active; 1 for ones without a count).
		var turns := {
			"burning": e.temp_turns if e.is_burning() else 0,
			"hot": 1 if e.temperature == 1 else 0,
			"cold": 1 if e.temperature == -1 else 0,
			"frozen": e.temp_turns if e.is_frozen() else 0,
			"slowed": e.slowed,
			"knocked": 1 if e.knocked_down else 0,
			"suspicious": 1 if e.suspicious else 0,
			"sneaking": 1 if e.sneaking else 0,
		}
		var tags: Array[String] = []
		var icons: Array[Dictionary] = []
		for status: String in STATUS_LOOKS:
			var look: Dictionary = STATUS_LOOKS[status]
			var active: bool = turns[status] > 0 and e.is_alive()
			if active:
				var counted: bool = look.get("turns", false)
				var label: String = "%s (%d)" % [look.label, turns[status]] if counted else look.label
				tags.append("[color=#%s]%s[/color]" % [look.color, label])
				icons.append({"id": status, "color": Color(look.color), "count": turns[status] if counted else 0})
			_set_loop(status, active)
		if e.stagger > 0 and e.is_alive():
			tags.append("[color=#%s]Stagger %d/%d[/color]" % [STAGGER_COLOR, e.stagger, StatRules.stagger_limit(e)])
			icons.append({"id": "stagger", "color": Color(STAGGER_COLOR), "count": e.stagger})
		if e.sneaking != _sneaking:
			_sneaking = e.sneaking
			_update_look()
		_set_pose(e.knocked_down and e.is_alive(), e.is_frozen() and e.is_alive())
		_facing = e.facing
		_in_combat = e.in_combat
		if _model != null:
			_model.hold(e.weapon, e.worn.get("off_hand", ""))
		if _icons != null:
			if icons != _icons.icons:
				_icons.icons = icons
			_words = "[center]%s[/center]" % "  ".join(tags) if not tags.is_empty() else ""
			_status.text = _words if _words_shown else ""
			_label.set("text", text if _name_shown else "")
		else:
			if not tags.is_empty():
				text += "  " + " ".join(tags)
			_label.set("text", text)
		_name = text
		var changed := _hp >= 0 and e.hp != _hp
		_hp = e.hp
		_max_hp = e.max_hp
		return changed

	## name: show the name (hovered, selected, Alt). words: also spell out the
	## statuses (hovered, Alt). The icons sit higher while the name shows.
	func show_detail(name_shown: bool, words: bool) -> void:
		if _icons == null or _dead or (name_shown == _name_shown and words == _words_shown):
			return
		_name_shown = name_shown
		_words_shown = words
		_label.set("text", _name if name_shown else "")
		_status.text = _words if words else ""
		ScreenLabels.instance.set_screen_offset(_icons, Vector2(0, -20) if name_shown else Vector2.ZERO)

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
		shown = shown and not _dead
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

	## Colour and outline by side; townsfolk can turn hostile.
	func set_side(faction: int) -> void:
		if faction == _side or _outline.a == 0.0 and faction == SimEntity.Faction.NONE:
			return
		_side = faction
		match faction:
			SimEntity.Faction.PLAYERS:
				_base_color = PLAYER_COLOR
				_outline = OUTLINE_ALLY
			SimEntity.Faction.ENEMIES:
				_base_color = ENEMY_COLOR
				_outline = OUTLINE_ENEMY
			SimEntity.Faction.NEUTRAL:
				_base_color = NEUTRAL_COLOR
				_outline = OUTLINE_NEUTRAL
		_apply_outline()
		if _model == null:
			_material_bases.assign([_base_color])
		_update_look()

	## Gold sparkles over a body worth looting.
	func set_glitter(on: bool) -> void:
		if on == (_glitter != null):
			return
		if on:
			_glitter = SimEntityRenderer.make_glitter()
			add_child(_glitter)
		else:
			_glitter.queue_free()
			_glitter = null

	## Shows or hides the side outline (it keeps writing the stencil, so
	## ground markers still don't draw over the character).
	func set_outlined(shown: bool) -> void:
		_outlined = shown
		_apply_outline()

	func _apply_outline() -> void:
		var color := _outline if _outlined and not _dead else Color.TRANSPARENT
		if _outline.a > 0.0:
			for material in _materials:
				material.stencil_color = color

	## Dead: lies down, greyed out, no outline, label or bar.
	func set_dead(dead: bool) -> void:
		if dead == _dead:
			return
		_dead = dead
		_label.set("visible", not dead)
		if _status != null:
			_status.visible = not dead
			_icons.visible = not dead
			if dead:
				_icons.icons = []
				_label.set("text", "")
				_status.text = ""
				_name_shown = false
				_words_shown = false
		_bar.visible = false
		_apply_outline()
		_update_look()
		if _model != null and not dead:
			_model.revive()
		_set_pose(false, false)

	## Knocked down (or dead): the body tips over. Frozen: an icy tint.
	func _set_pose(down: bool, frozen: bool) -> void:
		down = down or _dead
		if frozen != _frozen:
			_frozen = frozen
			_update_look()
		if down == _down:
			return
		_down = down
		# Models with a death animation fall with it; others tip over.
		if _model != null:
			if down and _model.die():
				return
			if not down:
				_model.revive()
		var pose := create_tween().set_parallel(true)
		pose.tween_property(_figure, "rotation_degrees:x", 90.0 if down else 0.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		pose.tween_property(_figure, "position:y", _rest_height * 0.4 if down else _rest_height, 0.25)

	func _update_look() -> void:
		for i in _materials.size():
			var own := _material_bases[i]
			var base := own.lerp(FROZEN_TINT, 0.65) if _frozen else own
			if _sneaking:
				base = base.darkened(0.45)
			if _dead:
				base = own * CORPSE_TINT if _textured else CORPSE_TINT
			var material := _materials[i]
			material.albedo_color = base.lightened(0.3 if _textured else 0.45) if _selected else base
			material.emission_enabled = _selected or _targetable
			material.emission = TARGETABLE_GLOW if _targetable else (Color(0.25, 0.25, 0.25) if _textured else _base_color * 0.4)
			if _textured and material.emission_enabled:
				material.emission_energy_multiplier = 0.35 if _targetable else 0.2

	## A one-shot on the model (attack, cast, hit, drink), turning toward
	## `toward` first (Vector3.INF: stay facing as it is). Without a model, or
	## an animation for it, a hit makes the body flinch.
	func act(state: String, toward: Vector3) -> void:
		if _dead:
			return
		if toward != Vector3.INF:
			_look_at = toward
		var played := _model != null and _model.play_once(state)
		if not played and state == "hit" and _figure != null:
			var flinch := create_tween()
			flinch.tween_property(_figure, "scale", Vector3(1.05, 0.92, 1.05), 0.06)
			flinch.tween_property(_figure, "scale", Vector3.ONE, 0.12)

	## Every frame: run while moving, idle (or ready for a fight) when not;
	## turn toward the way it walks, the target of its last action, or its
	## facing.
	func animate(delta: float) -> void:
		if _model == null:
			return
		var step := position - _last_position
		_last_position = position
		var moving := step.length() > 0.0005 and not _dead
		if not _down:
			_model.set_looping("run" if moving else ("combat_idle" if _in_combat else "idle"))
		var dir := Vector3.ZERO
		if moving and Vector2(step.x, step.z).length() > 0.0005:
			dir = Vector3(step.x, 0, step.z)
			_look_at = Vector3.INF
		elif _look_at != Vector3.INF:
			dir = Vector3(_look_at.x - position.x, 0, _look_at.z - position.z)
		else:
			var f: Vector3i = SimPerception.FACINGS[_facing]
			dir = Vector3(f.x, 0, f.z)
		if dir.length() < 0.01 or _down:
			return
		var yaw := atan2(dir.x, dir.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, yaw, minf(1.0, delta * 12.0))

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
