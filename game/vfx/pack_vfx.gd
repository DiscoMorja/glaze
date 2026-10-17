class_name PackVfx
extends RefCounted
## Effects from the BinbunVFX_Vol2 pack (assetlibs/, not in git). Every call
## returns false/null when the pack isn't installed, so callers fall back to
## the procedural VfxFactory effects.
##
## Entries can set "props": exported properties applied to the effect after
## it is created (e.g. light_energy).
##
## Kinds:
##   oneshot   - plays its "main" animation once, then frees itself
##   openclose - plays "open", holds, plays "close", then frees itself
##   particles - one-shot particle burst with no animation
##   emitter   - looping effect (projectiles, burning cells); caller stops it

const ROOT := "res://assetlibs/BinbunVFX_Vol2/"

const EFFECTS := {
	"fire_cast": {"path": "ElementalMagicFX/effects/cast/vfx_fire_cast_01.tscn", "kind": "oneshot", "scale": 0.5},
	"water_cast": {"path": "ElementalMagicFX/effects/cast/vfx_water_cast_01.tscn", "kind": "oneshot", "scale": 0.5},
	"nature_cast": {"path": "ElementalMagicFX/effects/cast/vfx_nature_cast_01.tscn", "kind": "oneshot", "scale": 0.5},
	"fire_projectile": {"path": "ElementalMagicFX/effects/projectile/vfx_fire_projectile_01.tscn", "kind": "emitter", "scale": 0.5},
	"water_projectile": {"path": "ElementalMagicFX/effects/projectile/vfx_water_projectile_01.tscn", "kind": "emitter", "scale": 0.5},
	"nature_projectile": {"path": "ElementalMagicFX/effects/projectile/vfx_nature_projectile_01.tscn", "kind": "emitter", "scale": 0.4},
	"fire_area": {"path": "ElementalMagicFX/effects/area/vfx_fire_area_01.tscn", "kind": "openclose", "scale": 0.5, "hold": 0.3},
	"water_area": {"path": "ElementalMagicFX/effects/area/vfx_water_area_01.tscn", "kind": "openclose", "scale": 0.7, "hold": 0.6},
	# Many cells burn at once, so each flame gets a much dimmer light.
	"burning": {"path": "FlameFX/effects/fire/vfx_basic_fire_01.tscn", "kind": "emitter", "scale": 0.7, "props": {"light_energy": 0.8}},
	"ice_impact": {"path": "StatusFX/effects/status/ice_impact.tscn", "kind": "particles", "scale": 0.6},
	"ice": {"path": "StatusFX/effects/status/vfx_status_ice.tscn", "kind": "openclose", "scale": 0.6, "hold": 0.4},
	"heal": {"path": "StatusFX/effects/status/vfx_status_heal.tscn", "kind": "openclose", "scale": 0.7, "hold": 0.6},
	"magic": {"path": "StatusFX/effects/status/vfx_status_magic.tscn", "kind": "openclose", "scale": 0.7, "hold": 0.2},
	"shatter": {"path": "StatusFX/effects/status/vfx_status_shatter.tscn", "kind": "openclose", "scale": 0.6, "hold": 0.2},
	"hit": {"path": "StylizedHitFX/effects/hit/vfx_hit_01.tscn", "kind": "oneshot", "scale": 0.5},
	"impact": {"path": "StylizedHitFX/effects/impact/vfx_impact_01.tscn", "kind": "oneshot", "scale": 0.5},
	"big_impact": {"path": "StylizedHitFX/effects/big_impact/vfx_big_impact_01.tscn", "kind": "oneshot", "scale": 0.5},
	"strike": {"path": "StylizedHitFX/effects/strike/vfx_strike_01.tscn", "kind": "oneshot", "scale": 0.6},
}

## Upper bound on how long a "particles" effect lives before it is freed.
const PARTICLE_SECONDS := 2.0

static var _scenes := {}  # key -> PackedScene, or null when missing


## Loads every pack effect up front (call during scene setup) so the first
## use of an effect doesn't hitch mid-combat.
static func preload_all() -> void:
	for key: String in EFFECTS:
		_scene(key)


static func has(key: String) -> bool:
	return _scene(key) != null


## Plays a fire-and-forget effect at a world position. Returns false if the
## pack (or this effect) isn't available.
static func play(parent: Node, key: String, at: Vector3, scale_mul: float = 1.0) -> bool:
	var node := _instance(key, scale_mul)
	if node == null:
		return false
	var info: Dictionary = EFFECTS[key]
	parent.add_child(node)
	node.global_position = at
	match info.kind:
		"oneshot":
			var length := _play_animation(node, "main")
			_free_after(node, length + 0.2)
		"openclose":
			var open_length := _play_animation(node, "open")
			var hold: float = info.get("hold", 0.5)
			node.get_tree().create_timer(open_length + hold).timeout.connect(func() -> void:
				if is_instance_valid(node):
					_free_after(node, _play_animation(node, "close") + 0.2))
		"particles":
			for p in _all_particles(node):
				p.one_shot = true
				p.emitting = true
			_free_after(node, PARTICLE_SECONDS)
		_:
			_free_after(node, PARTICLE_SECONDS)
	return true


## A looping effect the caller positions and stops with stop().
static func start(parent: Node, key: String, at: Vector3, scale_mul: float = 1.0) -> Node3D:
	var node := _instance(key, scale_mul)
	if node == null:
		return null
	parent.add_child(node)
	node.global_position = at
	if "emitting" in node:
		node.set("emitting", true)
	else:
		_play_animation(node, "open")
	return node


## Fades a looping effect out and frees it.
static func stop(node: Node3D) -> void:
	if not is_instance_valid(node):
		return
	var length := 0.6
	if "emitting" in node:
		node.set("emitting", false)
	else:
		length = _play_animation(node, "close")
	for p in _all_particles(node):
		p.emitting = false
	_free_after(node, length + 0.6)


## Flies a looping projectile effect from `from` to `to`, then calls on_arrive.
static func projectile(parent: Node, key: String, from: Vector3, to: Vector3, duration: float, on_arrive: Callable, arc: float = 0.6) -> bool:
	var node := start(parent, key, from)
	if node == null:
		return false
	if not from.is_equal_approx(to):
		node.look_at_from_position(from, to)
	var tween := node.create_tween()
	tween.tween_method(func(t: float) -> void:
		var p := from.lerp(to, t) + Vector3(0, sin(t * PI) * arc, 0)
		var ahead := from.lerp(to, minf(t + 0.05, 1.0)) + Vector3(0, sin(minf(t + 0.05, 1.0) * PI) * arc, 0)
		node.global_position = p
		if not p.is_equal_approx(ahead):
			node.look_at(ahead), 0.0, 1.0, duration)
	tween.tween_callback(func() -> void:
		on_arrive.call()
		stop(node))
	return true


static func _scene(key: String) -> PackedScene:
	if not _scenes.has(key):
		var scene: PackedScene = null
		if EFFECTS.has(key):
			var path: String = ROOT + EFFECTS[key].path
			if ResourceLoader.exists(path):
				scene = load(path) as PackedScene
		_scenes[key] = scene
	return _scenes[key]


static func _instance(key: String, scale_mul: float) -> Node3D:
	var scene := _scene(key)
	if scene == null:
		return null
	var node := scene.instantiate() as Node3D
	if node == null:
		return null
	if "one_shot" in node:
		node.set("one_shot", true)
	var s: float = EFFECTS[key].get("scale", 1.0) * scale_mul
	node.scale = Vector3.ONE * s
	var props: Dictionary = EFFECTS[key].get("props", {})
	for property: String in props:
		if property in node:
			node.set(property, props[property])
	return node


## Plays an animation if the effect has it; returns its length (0 if none).
static func _play_animation(node: Node, anim_name: String) -> float:
	var anim := node.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim == null or not anim.has_animation(anim_name):
		return 0.0
	anim.play(anim_name)
	anim.seek(0.0, true)
	return anim.get_animation(anim_name).length


static func _all_particles(node: Node) -> Array[GPUParticles3D]:
	var result: Array[GPUParticles3D] = []
	for child in node.find_children("*", "GPUParticles3D", true, false):
		result.append(child as GPUParticles3D)
	return result


static func _free_after(node: Node, seconds: float) -> void:
	node.get_tree().create_timer(maxf(seconds, 0.1)).timeout.connect(func() -> void:
		if is_instance_valid(node):
			node.queue_free())
