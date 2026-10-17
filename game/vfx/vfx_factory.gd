class_name VfxFactory
extends RefCounted
## Procedural greybox effects (no assets): particle bursts, looping emitters,
## projectiles and floating text. Swap individual presets for authored effects
## later without touching the callers.

## Burst presets: color, amount, lifetime, speed range, spread (degrees),
## gravity (y), particle size, emission radius, additive blending.
const PRESETS := {
	"fire": {"color": Color(1.0, 0.42, 0.05), "amount": 24, "lifetime": 0.6, "speed": Vector2(1.5, 3.5), "spread": 60.0, "gravity": 2.0, "size": 0.55, "radius": 0.3, "additive": false},
	"spark": {"color": Color(1.0, 0.75, 0.3), "amount": 14, "lifetime": 0.35, "speed": Vector2(2.5, 5.0), "spread": 180.0, "gravity": -6.0, "size": 0.18, "radius": 0.1, "additive": true},
	"blood": {"color": Color(0.85, 0.1, 0.1), "amount": 10, "lifetime": 0.45, "speed": Vector2(1.5, 3.0), "spread": 120.0, "gravity": -9.0, "size": 0.2, "radius": 0.15, "additive": false},
	"steam": {"color": Color(0.95, 0.95, 1.0, 0.7), "amount": 18, "lifetime": 1.2, "speed": Vector2(0.6, 1.4), "spread": 40.0, "gravity": 0.8, "size": 0.8, "radius": 0.4, "additive": false},
	"ice": {"color": Color(0.55, 0.85, 1.0), "amount": 20, "lifetime": 0.6, "speed": Vector2(1.5, 3.5), "spread": 90.0, "gravity": -5.0, "size": 0.22, "radius": 0.5, "additive": false},
	"heal": {"color": Color(0.25, 0.95, 0.35), "amount": 22, "lifetime": 1.0, "speed": Vector2(0.5, 1.5), "spread": 25.0, "gravity": 1.0, "size": 0.25, "radius": 0.4, "additive": false},
	"dust": {"color": Color(0.7, 0.65, 0.55, 0.8), "amount": 16, "lifetime": 0.8, "speed": Vector2(0.8, 2.0), "spread": 80.0, "gravity": -1.0, "size": 0.6, "radius": 0.4, "additive": false},
	"arcane": {"color": Color(0.65, 0.3, 1.0), "amount": 30, "lifetime": 0.6, "speed": Vector2(1.0, 3.0), "spread": 180.0, "gravity": 0.0, "size": 0.3, "radius": 0.5, "additive": false},
	"water": {"color": Color(0.35, 0.6, 1.0), "amount": 18, "lifetime": 0.5, "speed": Vector2(1.5, 3.0), "spread": 70.0, "gravity": -9.0, "size": 0.22, "radius": 0.4, "additive": false},
	"oil": {"color": Color(0.15, 0.1, 0.05), "amount": 18, "lifetime": 0.5, "speed": Vector2(1.5, 3.0), "spread": 70.0, "gravity": -9.0, "size": 0.24, "radius": 0.4, "additive": false},
	"coins": {"color": Color(1.0, 0.85, 0.2), "amount": 12, "lifetime": 0.7, "speed": Vector2(2.0, 3.5), "spread": 35.0, "gravity": -8.0, "size": 0.18, "radius": 0.1, "additive": false},
	"slash": {"color": Color(1.0, 1.0, 1.0), "amount": 20, "lifetime": 0.25, "speed": Vector2(3.0, 5.0), "spread": 180.0, "gravity": 0.0, "size": 0.1, "radius": 0.2, "additive": true},
}

static var _soft_texture: Texture2D
static var _materials := {}


## A soft round sprite generated once and shared by every particle.
static func soft_texture() -> Texture2D:
	if _soft_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		var texture := GradientTexture2D.new()
		texture.gradient = gradient
		texture.fill = GradientTexture2D.FILL_RADIAL
		texture.fill_from = Vector2(0.5, 0.5)
		texture.fill_to = Vector2(1.0, 0.5)
		texture.width = 64
		texture.height = 64
		_soft_texture = texture
	return _soft_texture


static func particle_material(additive: bool) -> StandardMaterial3D:
	if not _materials.has(additive):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = soft_texture()
		_materials[additive] = m
	return _materials[additive]


static func _process_material(preset: Dictionary, scale: float) -> ParticleProcessMaterial:
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = preset.spread
	pm.initial_velocity_min = preset.speed.x * scale
	pm.initial_velocity_max = preset.speed.y * scale
	pm.gravity = Vector3(0, preset.gravity, 0)
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = preset.radius * scale
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	pm.color = preset.color
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	pm.color_ramp = ramp
	return pm


static func _particles(preset: Dictionary, scale: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = maxi(1, int(preset.amount * scale))
	p.lifetime = preset.lifetime
	p.process_material = _process_material(preset, scale)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * preset.size * scale
	quad.material = particle_material(preset.additive)
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-4, -4, -4), Vector3(8, 8, 8))
	return p


## One-shot burst that frees itself.
static func burst(parent: Node, at: Vector3, preset_name: String, scale: float = 1.0) -> void:
	var p := _particles(PRESETS[preset_name], scale)
	p.one_shot = true
	p.explosiveness = 0.9
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


## Looping emitter (e.g. a burning cell). Caller owns it.
static func emitter(preset_name: String, scale: float = 1.0) -> GPUParticles3D:
	var p := _particles(PRESETS[preset_name], scale)
	p.explosiveness = 0.0
	p.randomness = 0.5
	p.emitting = true
	return p


## A short light flash, e.g. on an impact.
static func flash(parent: Node, at: Vector3, color: Color, energy: float = 3.0, seconds: float = 0.25) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.omni_range = 4.0
	parent.add_child(light)
	light.global_position = at
	var tween := light.create_tween()
	tween.tween_property(light, "light_energy", 0.0, seconds)
	tween.tween_callback(light.queue_free)


## Text that rises and fades, e.g. damage numbers.
static func floating_text(parent: Node, at: Vector3, text: String, color: Color, size: int = 72) -> void:
	var label := Label3D.new()
	label.text = text
	label.modulate = color
	label.font_size = size
	label.outline_size = 14
	label.pixel_size = 0.008
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	parent.add_child(label)
	label.global_position = at
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position", at + Vector3(0, 1.0, 0), 1.0).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 1.0).set_delay(0.4)
	tween.chain().tween_callback(label.queue_free)


## A glowing ball flying from `from` to `to` along an arc, trailing particles.
## Calls on_arrive when it lands.
static func projectile(parent: Node, from: Vector3, to: Vector3, color: Color, duration: float, on_arrive: Callable, arc: float = 0.6) -> void:
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color.lightened(0.4)
	sphere.material = material
	ball.mesh = sphere
	parent.add_child(ball)
	ball.global_position = from

	var trail_preset: Dictionary = PRESETS.fire.duplicate()
	trail_preset.color = color
	trail_preset.speed = Vector2(0.1, 0.4)
	trail_preset.gravity = 0.0
	trail_preset.size = 0.25
	trail_preset.amount = 30
	trail_preset.lifetime = 0.35
	var trail := _particles(trail_preset, 1.0)
	trail.local_coords = false
	trail.emitting = true
	ball.add_child(trail)

	var tween := ball.create_tween()
	tween.tween_method(func(t: float) -> void:
		ball.global_position = from.lerp(to, t) + Vector3(0, sin(t * PI) * arc, 0), 0.0, 1.0, duration)
	tween.tween_callback(func() -> void:
		on_arrive.call()
		trail.emitting = false
		ball.mesh = null
		ball.get_tree().create_timer(trail.lifetime).timeout.connect(ball.queue_free))
