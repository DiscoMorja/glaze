class_name VfxPlayer
extends Node3D
## Turns sim events into effects: projectiles for thrown spells, bursts for
## hits, fire, ice, steam and spills, floating numbers for damage and healing.
## Events after a projectile in the same batch wait for it to land, so the hit
## shows when the bolt arrives. Uses BinbunVFX pack effects (PackVfx) where
## they exist and the procedural VfxFactory ones otherwise.

const PROJECTILE_SECONDS := 0.35
## Per batch, so a spreading fire doesn't spawn hundreds of bursts at once.
const MAX_IGNITE_BURSTS := 12
const BIG_HIT := 5
## Damage number colour and hit burst per EntityOps.Element.
const ELEMENT_LOOK := {
	EntityOps.Element.PHYSICAL: {"color": Color(1.0, 1.0, 1.0), "burst": "blood"},
	EntityOps.Element.FIRE: {"color": Color(1.0, 0.55, 0.15), "burst": "fire"},
	EntityOps.Element.FROST: {"color": Color(0.5, 0.8, 1.0), "burst": "ice"},
}

signal shake_requested(strength: float)

## Thrown spells: colour, procedural impact preset, and pack effects for the
## cast flash, the projectile and the impact ("" = procedural only).
const ABILITY_PROJECTILES := {
	SimAbilities.Ability.FIREBOLT: {"color": Color(1.0, 0.45, 0.1), "fallback": "fire", "cast": "fire_cast", "projectile": "fire_projectile", "impact": ["fire_area"]},
	SimAbilities.Ability.FROST: {"color": Color(0.6, 0.9, 1.0), "fallback": "ice", "cast": "water_cast", "projectile": "water_projectile", "impact": ["ice_impact", "ice"]},
	SimAbilities.Ability.OIL_FLASK: {"color": Color(0.35, 0.22, 0.08), "fallback": "oil", "cast": "", "projectile": "", "impact": []},
}


func play(state: SimState, events: Array[SimEvent]) -> void:
	var delay := 0.0
	var ignites := 0
	for e in events:
		match e.type:
			SimEvent.Type.CAST:
				delay = _cast(state, e, delay)
			SimEvent.Type.DAMAGED:
				var text := "-%d" % e.amount
				var big := e.amount >= BIG_HIT
				var look: Dictionary = ELEMENT_LOOK.get(e.element, ELEMENT_LOOK[EntityOps.Element.PHYSICAL])
				_later(delay, func() -> void:
					var at := _body(e.cell)
					VfxFactory.burst(self, at, look.burst, 0.8)
					VfxFactory.burst(self, at, "spark", 0.6)
					VfxFactory.floating_text(self, at + Vector3(0, 0.6, 0), text, look.color, 96 if big else 72)
					if big:
						shake_requested.emit(0.25))
			SimEvent.Type.HEALED:
				var healed := "+%d" % e.amount
				_later(delay, func() -> void:
					VfxFactory.burst(self, _feet(e.cell), "heal")
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 0.6, 0), healed, Color(0.45, 1.0, 0.5)))
			SimEvent.Type.DIED:
				_later(delay, func() -> void:
					VfxFactory.burst(self, _body(e.cell), "dust", 1.4)
					shake_requested.emit(0.2))
			SimEvent.Type.IGNITED:
				ignites += 1
				if ignites <= MAX_IGNITE_BURSTS:
					_later(delay, func() -> void: VfxFactory.burst(self, _feet(e.cell), "fire", 0.7))
			SimEvent.Type.EXTINGUISHED:
				_later(delay, func() -> void: VfxFactory.burst(self, _feet(e.cell), "steam"))
			SimEvent.Type.FROZE:
				_later(delay, func() -> void: VfxFactory.burst(self, _feet(e.cell), "ice", 0.8))
			SimEvent.Type.MELTED:
				_later(delay, func() -> void: VfxFactory.burst(self, _feet(e.cell), "water", 0.6))
			SimEvent.Type.SPILLED:
				var preset := "oil" if e.amount == SimMaterials.Surface.OIL else "water"
				_later(delay, func() -> void: VfxFactory.burst(self, _feet(e.cell), preset, 1.6))
			SimEvent.Type.TELEPORTED:
				if e.cells.size() == 2:
					var from := e.cells[0]
					var to := e.cells[1]
					_later(delay, func() -> void:
						VfxFactory.burst(self, _body(from), "arcane")
						VfxFactory.burst(self, _body(to), "arcane"))
			SimEvent.Type.ATTACKED:
				_later(delay, func() -> void: VfxFactory.burst(self, _body(e.cell), "slash"))
			SimEvent.Type.COLLIDED:
				_later(delay, func() -> void:
					VfxFactory.burst(self, _body(e.cell), "dust")
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.0, 0), "Crash!", Color(1.0, 0.9, 0.6), 60)
					shake_requested.emit(0.2))
			SimEvent.Type.FELL:
				if e.amount > 1:
					_later(delay, func() -> void:
						VfxFactory.burst(self, _feet(e.cell), "dust", 1.3)
						shake_requested.emit(0.15))
			SimEvent.Type.SLIPPED:
				_later(delay, func() -> void:
					VfxFactory.burst(self, _feet(e.cell), "ice", 0.6)
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.0, 0), "Slipped!", Color(0.7, 0.92, 1.0), 60))
			SimEvent.Type.BURNING:
				_later(delay, func() -> void:
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.3, 0), "Burning", Color(1.0, 0.55, 0.15), 56))
			SimEvent.Type.SLOWED:
				_later(delay, func() -> void:
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.0, 0), "Slowed", Color(0.85, 0.7, 0.4), 56))
			SimEvent.Type.STOLEN:
				var stolen := "Stole %s" % e.text
				_later(delay, func() -> void:
					VfxFactory.burst(self, _body(e.cell), "coins")
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.0, 0), stolen, Color(1.0, 0.85, 0.3), 56))


## Effects for the cast itself. Returns the delay for the events that follow.
func _cast(state: SimState, e: SimEvent, delay: float) -> float:
	var caster := state.get_entity(e.entity_id)
	var ability := e.amount
	var target := e.cell
	if ABILITY_PROJECTILES.has(ability) and caster != null:
		var look: Dictionary = ABILITY_PROJECTILES[ability]
		var from := _body(caster.cell) + Vector3(0, 0.5, 0)
		var to := _body(target)
		var caster_feet := _feet(caster.cell)
		_later(delay, func() -> void:
			if look.cast != "":
				PackVfx.play(self, look.cast, caster_feet)
			var arrive := func() -> void:
				var pack_hit := false
				for key: String in look.impact:
					pack_hit = PackVfx.play(self, key, _feet(target)) or pack_hit
				if not pack_hit:
					VfxFactory.burst(self, to, look.fallback, 1.5)
				VfxFactory.flash(self, to, look.color, 4.0, 0.3)
				shake_requested.emit(0.12)
			if look.projectile == "" or not PackVfx.projectile(self, look.projectile, from, to, PROJECTILE_SECONDS, arrive):
				VfxFactory.projectile(self, from, to, look.color, PROJECTILE_SECONDS, arrive))
		return delay + PROJECTILE_SECONDS
	match ability:
		SimAbilities.Ability.RAIN:
			var caster_at := _feet(caster.cell) if caster != null else _feet(target)
			_later(delay, func() -> void:
				PackVfx.play(self, "water_cast", caster_at)
				if not PackVfx.play(self, "water_area", _feet(target)):
					VfxFactory.burst(self, _feet(target) + Vector3(0, 3.0, 0), "water", 2.2)
				VfxFactory.burst(self, _feet(target), "steam", 1.2))
		SimAbilities.Ability.MEND:
			if caster != null:
				var caster_at := _feet(caster.cell)
				_later(delay, func() -> void: PackVfx.play(self, "nature_cast", caster_at))
		SimAbilities.Ability.CLEAVE, SimAbilities.Ability.SHOVE:
			if caster != null:
				var at := _body(caster.cell)
				_later(delay, func() -> void: _fx("strike", at, "slash", 1.5))
	return delay


## A pack effect, or the procedural preset when the pack doesn't have it.
func _fx(pack_key: String, at: Vector3, fallback_preset: String, fallback_scale: float = 1.0) -> void:
	if not PackVfx.play(self, pack_key, at):
		VfxFactory.burst(self, at, fallback_preset, fallback_scale)


func _later(delay: float, effect: Callable) -> void:
	if delay <= 0.0:
		effect.call()
	else:
		get_tree().create_timer(delay).timeout.connect(effect)


static func _feet(c: Vector3i) -> Vector3:
	return WorldSpace.cell_to_world(c) + Vector3(0, 0.1, 0)


static func _body(c: Vector3i) -> Vector3:
	return WorldSpace.cell_to_world(c) + Vector3(0, 0.8, 0)
