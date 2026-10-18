class_name CharacterModel
extends Node3D
## An animated character model for a look (CharacterLooks): the rig's model
## with only the look's meshes shown, scaled to HEIGHT, facing -Z (the
## sim's north), with weapon models in its hands. Plays looping states
## (idle, run, combat idle) and one-shots (attack, cast, hit, drink, death);
## a one-shot returns to the looping state when done, except death.
##
## Every surface material is a private copy (materials()), so the entity
## view can tint, highlight and outline it like the capsule.

## A bit larger than life so they read at the game's camera distance, and
## a little broader than the slim packs.
const HEIGHT := 2.1
const BROADEN := 1.12
## Seconds to blend between animations.
const BLEND := 0.15

var rig: Dictionary
## Tuning (the look viewer's X key): overrides the rig's weapon axis when set.
static var weapon_axis_override := Vector3.ZERO
static var shield_axis_override := Vector3.ZERO
static var weapon_roll_tune := 0.0
static var weapon_tilt_tune := 0.0
var height := HEIGHT
var _model: Node3D
var _player: AnimationPlayer
var _skeleton: Skeleton3D
var _materials: Array[BaseMaterial3D] = []
var _hands := {}  # "r"/"l" -> BoneAttachment3D
var _held := ["", ""]
var _looping := "idle"
var _style := "unarmed"
var _one_shot := ""
var _dead := false


## Builds the model for `look`; null if the look or its files are missing.
static func create(look: String) -> CharacterModel:
	var rig_data := CharacterLooks.rig_of(look)
	if rig_data.is_empty():
		return null
	var packed := CharacterLooks.scene(rig_data.scene)
	if packed == null:
		return null
	var model := CharacterModel.new()
	model.rig = rig_data
	model._build(packed.instantiate() as Node3D, CharacterLooks.LOOKS[look].meshes)
	return model


func _build(root: Node3D, shown: Array) -> void:
	_model = root
	add_child(root)
	var meshes: Array[MeshInstance3D] = []
	for node in root.find_children("*", "", true, false):
		if node is Light3D or node is Camera3D:
			node.queue_free()
		elif node is MeshInstance3D:
			var mesh := node as MeshInstance3D
			mesh.visible = shown.has(String(mesh.name))
			if mesh.visible:
				meshes.append(mesh)
		elif node is AnimationPlayer and _player == null:
			_player = node
		elif node is Skeleton3D and _skeleton == null:
			_skeleton = node
	# The modular packs keep many meshes outside the skeleton node, bound to
	# nothing: move them under it so the animation deforms them.
	if _skeleton != null:
		for mesh in meshes:
			if mesh.get_parent() != _skeleton and mesh.skin != null:
				mesh.get_parent().remove_child(mesh)
				_skeleton.add_child(mesh)
				mesh.transform = Transform3D.IDENTITY
				mesh.skeleton = NodePath("..")
	for mesh in meshes:
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		for i in mesh.get_surface_override_material_count():
			var source := mesh.get_active_material(i)
			var copy: BaseMaterial3D = source.duplicate() if source is BaseMaterial3D else StandardMaterial3D.new()
			if copy.albedo_texture == null:
				copy.albedo_texture = CharacterLooks.texture_for(String(mesh.name), source.resource_name if source != null else "")
				if copy.albedo_texture != null:
					copy.albedo_color = Color.WHITE
			mesh.set_surface_override_material(i, copy)
			_materials.append(copy)
	_fit(meshes)
	if _skeleton != null:
		for side: String in ["r", "l"]:
			var bone: String = rig.get("hand_" + side, "")
			if bone != "" and _skeleton.find_bone(bone) >= 0:
				var hand := BoneAttachment3D.new()
				hand.bone_name = bone
				_skeleton.add_child(hand)
				_hands[side] = hand
	if _player != null:
		_player.animation_finished.connect(_on_finished)
		for state: String in ["idle", "run", "walk", "talk"]:
			_set_loop(_anim(state))
		for style: String in ["unarmed", "main_hand_melee", "two_handed_melee", "two_handed_staff", "dual_wield_melee"]:
			_set_loop(_anim("combat_idle", style))


## Animations only run once the player is in the tree.
func _ready() -> void:
	if not _dead:
		_play(_loop_anim())


## Scales the shown meshes' rest-pose bounds to HEIGHT, feet on y = 0.
func _fit(meshes: Array[MeshInstance3D]) -> void:
	var bounds := AABB()
	var first := true
	for mesh in meshes:
		var box := mesh.get_aabb()
		var to_root := _model.global_transform.affine_inverse() * mesh.global_transform if mesh.is_inside_tree() else _relative(mesh)
		box = to_root * box
		bounds = box if first else bounds.merge(box)
		first = false
	if first or bounds.size.y <= 0.01:
		return
	var scale_factor := HEIGHT / bounds.size.y
	_model.scale = Vector3(scale_factor * BROADEN, scale_factor, scale_factor * BROADEN)
	_model.position.y = -bounds.position.y * scale_factor
	height = HEIGHT


## A node's transform relative to the model root, before entering the tree.
func _relative(node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node = node
	while n != null and n != _model:
		if n is Node3D:
			t = (n as Node3D).transform * t
		n = n.get_parent()
	return t


func materials() -> Array[BaseMaterial3D]:
	return _materials


## The weapon models in each hand (item names, "" = empty hand).
func hold(main: String, off: String) -> void:
	if [main, off] == _held:
		return
	_held = [main, off]
	_style = CharacterLooks.style_of(main, off)
	var left := off
	if CharacterLooks.PAIRED.has(main) and off == "":
		left = main
	for side: String in ["r", "l"]:
		var hand: BoneAttachment3D = _hands.get(side)
		if hand == null:
			continue
		for child in hand.get_children():
			child.queue_free()
		var item := main if side == "r" else left
		var packed := CharacterLooks.weapon_scene(item)
		if packed != null:
			var weapon := packed.instantiate() as Node3D
			# The holder follows the hand without its scale (the model is
			# scaled, a bit wider than tall): see _process().
			var holder := Node3D.new()
			holder.top_level = true
			hand.add_child(holder)
			var fit := Node3D.new()
			holder.add_child(fit)
			fit.add_child(weapon)
			_fit_weapon(weapon, item)
	if not _dead and _one_shot == "":
		_play(_loop_anim())


## Weapon models come in their own units and orientation: scale the
## longest side to the item's length and turn it along the hand bone's +Y
## (bones point along +Y), the far end (blade, head) away from the grip at
## the model's origin. Shields face out from the arm instead.
func _fit_weapon(weapon: Node3D, item: String) -> void:
	var box := AABB()
	var first := true
	for node in weapon.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var t := Transform3D.IDENTITY
		var n: Node = mesh
		while n != null and n != weapon:
			if n is Node3D:
				t = (n as Node3D).transform * t
			n = n.get_parent()
		var b := t * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	if first:
		return
	var size := box.size
	var axis := 0 if size.x >= size.y and size.x >= size.z else (1 if size.y >= size.z else 2)
	var long := size[axis]
	if long <= 0.0001:
		return
	# Which way along the axis the far end lies: the side further from the origin.
	var far_sign := 1.0 if box.end[axis] >= -box.position[axis] else -1.0
	var from := Vector3.ZERO
	from[axis] = far_sign
	var to: Vector3 = rig.get("weapon_axis", Vector3.UP)
	if CharacterLooks.STAFF_LIKE.has(item):
		to = rig.get("staff_axis", to)
	if weapon_axis_override != Vector3.ZERO:
		to = weapon_axis_override
	if CharacterLooks.is_shield(item):
		# A shield's face (its thinnest side) turns out from the forearm.
		axis = 0 if size.x <= size.y and size.x <= size.z else (1 if size.y <= size.z else 2)
		from = Vector3.ZERO
		from[axis] = 1.0 if box.end[axis] >= -box.position[axis] else -1.0
		to = shield_axis_override if shield_axis_override != Vector3.ZERO else rig.get("shield_axis", Vector3.RIGHT)
	var turn := Basis(Quaternion(from, to)) if not from.is_equal_approx(-to) else Basis(Vector3.RIGHT, PI)
	# Spin the weapon about its own length (edge forward) and tilt it a
	# little forward of the forearm, per rig (tuning: the look viewer).
	var roll: float = deg_to_rad(rig.get("weapon_roll", 0.0) + weapon_roll_tune)
	var tilt: float = deg_to_rad(rig.get("weapon_tilt", 0.0) + weapon_tilt_tune)
	# Lengths are for a 1.75 m person; ours are drawn larger.
	var s := CharacterLooks.weapon_length(item) * (HEIGHT / 1.75) / long
	var fit := weapon.get_parent() as Node3D
	var side := Vector3.RIGHT if not to.abs().is_equal_approx(Vector3.RIGHT) else Vector3.UP
	fit.basis = Basis(side, tilt) * Basis(to, roll) * turn * Basis.from_scale(Vector3.ONE * s)
	fit.position = to * 0.07 if CharacterLooks.is_shield(item) else Vector3.ZERO  # strapped on, not inside the arm
	# Put the grip in the hand: its centreline through the bone, at `grip`
	# of the length from the butt.
	var grip := box.get_center()
	if not CharacterLooks.is_shield(item):
		var butt := box.position[axis] if far_sign > 0.0 else box.end[axis]
		grip[axis] = butt + far_sign * long * CharacterLooks.weapon_grip(item)
	weapon.position = -grip


## Held weapons follow their hand's position and turn, never its scale.
func _process(_delta: float) -> void:
	for hand: BoneAttachment3D in _hands.values():
		for holder in hand.get_children():
			if holder is Node3D:
				var t := hand.global_transform
				(holder as Node3D).global_transform = Transform3D(t.basis.orthonormalized(), t.origin)


## Builds the weapons again (after tuning how they are held).
func rehold() -> void:
	var held: Array = _held.duplicate()
	_held = ["", ""]
	hold(held[0], held[1])


## The looping state: "idle", "run", "combat_idle" or "talk".
func set_looping(state: String) -> void:
	if state == _looping:
		return
	_looping = state
	if not _dead and _one_shot == "":
		_play(_loop_anim())


## A one-shot ("attack", "cast", "hit", "drink"). Returns false if the rig
## has no such animation (the caller can fall back to a procedural move).
func play_once(state: String) -> bool:
	if _dead or _player == null:
		return false
	var anim := _anim(state)
	if state == "cast" and _style == "two_handed_staff" and _anim("cast_staff") != "":
		anim = _anim("cast_staff")
	if anim == "":
		return false
	_one_shot = anim
	if is_inside_tree():
		_player.play(anim, BLEND)
	return true


## Plays the death animation and stays down. False if the rig has none.
func die() -> bool:
	_dead = true
	var anim := _anim("death")
	if anim == "" or _player == null:
		return false
	_one_shot = anim
	_player.play(anim, BLEND)
	return true


func revive() -> void:
	_dead = false
	_one_shot = ""
	_play(_loop_anim())


func _on_finished(anim: StringName) -> void:
	if String(anim) != _one_shot:
		return
	if _dead:
		return  # stays on the last frame of the death animation
	_one_shot = ""
	_play(_loop_anim())


func _loop_anim() -> String:
	var anim := _anim(_looping)
	if _looping == "combat_idle" and anim == "":
		anim = _anim("idle")
	if _looping == "run" and anim == "":
		anim = _anim("walk")
	return anim if anim != "" else _anim("idle")


## The rig's animation for a state ("" if it has none). Attacks pick one of
## the numbered variants for the weapon style.
func _anim(state: String, style: String = "") -> String:
	if _player == null:
		return ""
	var anims: Dictionary = rig.get("anims", {})
	if not anims.has(state):
		return ""
	var anim: String = anims[state]
	if anim.contains("%s"):
		var with_style := style if style != "" else _style
		if state == "attack":
			with_style = with_style + "_melee" if not with_style.ends_with("_melee") else with_style
			if with_style == "unarmed_melee" or with_style == "two_handed_staff_melee":
				with_style = "main_hand_melee"
		anim = anim % with_style
		if state == "attack":
			var variants: Array[String] = []
			for name in _player.get_animation_list():
				if name == anim or name.begins_with(anim + "_"):
					variants.append(name)
			return variants.pick_random() if not variants.is_empty() else ""
	return anim if _player.has_animation(anim) else ""


func _set_loop(anim: String) -> void:
	if anim != "":
		_player.get_animation(anim).loop_mode = Animation.LOOP_LINEAR


func _play(anim: String) -> void:
	if _player != null and anim != "" and is_inside_tree() and (_player.current_animation != anim or not _player.is_playing()):
		_player.play(anim, BLEND)
