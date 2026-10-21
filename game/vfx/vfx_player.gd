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
	EntityOps.Element.DEATH: {"color": Color(0.7, 0.45, 0.95), "burst": "arcane"},
}

signal shake_requested(strength: float)

## Thrown spells: colour, procedural impact preset, and pack effects for the
## cast flash, the projectile and the impact ("" = procedural only).
const ABILITY_PROJECTILES := {
	SimAbilities.Ability.FIREBOLT: {"color": Color(1.0, 0.45, 0.1), "fallback": "fire", "cast": "fire_cast", "projectile": "fire_projectile", "impact": ["fire_area"]},
	SimAbilities.Ability.FROST: {"color": Color(0.6, 0.9, 1.0), "fallback": "ice", "cast": "water_cast", "projectile": "water_projectile", "impact": ["ice_impact", "ice"]},
	SimAbilities.Ability.OIL_FLASK: {"color": Color(0.35, 0.22, 0.08), "fallback": "oil", "cast": "", "projectile": "", "impact": []},
	SimAbilities.Ability.KINDLE: {"color": Color(1.0, 0.6, 0.2), "fallback": "spark", "cast": "", "projectile": "", "impact": []},
	SimAbilities.Ability.DRAIN: {"color": Color(0.6, 0.3, 0.9), "fallback": "arcane", "cast": "", "projectile": "", "impact": []},
	SimAbilities.Ability.BLIGHT: {"color": Color(0.5, 0.75, 0.2), "fallback": "dust", "cast": "", "projectile": "", "impact": []},
	SimAbilities.Ability.DISTRACT: {"color": Color(0.75, 0.65, 1.0), "fallback": "arcane", "cast": "", "projectile": "", "impact": []},
	SimAbilities.Ability.LOADED_SHOT: {"color": Color(0.9, 0.8, 0.55), "fallback": "spark", "cast": "", "projectile": "", "impact": []},
	SimAbilities.Ability.PINNING_SHOT: {"color": Color(0.9, 0.8, 0.55), "fallback": "dust", "cast": "", "projectile": "", "impact": []},
	SimAbilities.Ability.COMBUST: {"color": Color(1.0, 0.4, 0.1), "fallback": "fire", "cast": "fire_cast", "projectile": "", "impact": []},
	SimAbilities.Ability.GLACIER: {"color": Color(0.6, 0.9, 1.0), "fallback": "ice", "cast": "water_cast", "projectile": "water_projectile", "impact": ["ice_impact"]},
	SimAbilities.Ability.WELLSPRING: {"color": Color(0.45, 0.85, 1.0), "fallback": "heal", "cast": "", "projectile": "", "impact": []},
	SimAbilities.Ability.SHROUD: {"color": Color(0.3, 0.15, 0.45), "fallback": "arcane", "cast": "", "projectile": "", "impact": []},
	SimAbilities.Ability.DREAD: {"color": Color(0.55, 0.3, 0.8), "fallback": "arcane", "cast": "", "projectile": "", "impact": []},
	SimAbilities.Ability.SMOKE_BOMB: {"color": Color(0.45, 0.45, 0.45), "fallback": "dust", "cast": "", "projectile": "", "impact": []},
}
## Colour of an arrow or stone from a bow or sling.
const SHOT_COLOR := Color(0.9, 0.8, 0.55)


## Whether this batch's cast was a bow shot (its projectile already flew).
var _last_cast_was_shot := false


func play(state: SimState, events: Array[SimEvent]) -> void:
	var delay := 0.0
	_last_cast_was_shot = false
	var ignites := 0
	for e in events:
		match e.type:
			SimEvent.Type.CAST:
				delay = _cast(state, e, delay)
			SimEvent.Type.SHOCKWAVE:
				# Dust rolls out along the line, cell by cell.
				for i in e.cells.size():
					var at := _feet(e.cells[i])
					_later(delay + i * 0.06, func() -> void: VfxFactory.burst(self, at, "dust", 1.1))
				shake_requested.emit(0.18)
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
				var shooter := state.get_entity(e.other_id)
				var ranged := shooter != null and not SimAbilities.is_adjacent(shooter.cell, e.cell) and SimItems.has_property(shooter.weapon, "ranged")
				if ranged and not _last_cast_was_shot:
					# A bow or sling attack: the arrow flies first (shots fly as their cast).
					var from := _body(shooter.cell) + Vector3(0, 0.5, 0)
					var to := _body(e.cell)
					_later(delay, func() -> void: VfxFactory.projectile(self, from, to, SHOT_COLOR, PROJECTILE_SECONDS, func() -> void: VfxFactory.burst(self, to, "spark")))
					delay += PROJECTILE_SECONDS
				else:
					_later(delay, func() -> void: VfxFactory.burst(self, _body(e.cell), "slash"))
			SimEvent.Type.EXPLODED:
				var blast := e.cells.duplicate()
				_later(delay, func() -> void:
					for c: Vector3i in blast:
						VfxFactory.burst(self, _body(c), "fire", 1.8)
					VfxFactory.flash(self, _body(e.cell), Color(1.0, 0.6, 0.2), 10.0, 0.4)
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.2, 0), "Boom!", Color(1.0, 0.7, 0.3), 80)
					shake_requested.emit(0.45))
			SimEvent.Type.GREW:
				var grown := e.cells.duplicate()
				_later(delay, func() -> void:
					for c: Vector3i in grown:
						VfxFactory.burst(self, _feet(c), "heal", 0.6))
			SimEvent.Type.BLIGHTED:
				var rotted := e.cells.duplicate()
				_later(delay, func() -> void:
					for c: Vector3i in rotted:
						VfxFactory.burst(self, _feet(c), "arcane", 0.6))
			SimEvent.Type.PINNED:
				_later(delay, func() -> void:
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.0, 0), "Pinned!", Color(0.9, 0.8, 0.55), 60))
			SimEvent.Type.DISTRACTED:
				_later(delay, func() -> void:
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.0, 0), "Huh?", Color(0.75, 0.65, 1.0), 60))
			SimEvent.Type.COMBUSTED:
				var burst := e.cells.duplicate()
				_later(delay, func() -> void:
					for c: Vector3i in burst:
						VfxFactory.burst(self, _body(c), "fire", 1.6)
					if not burst.is_empty():
						shake_requested.emit(0.25))
			SimEvent.Type.WELLSPRING:
				var healed := e.cells.duplicate()
				_later(delay, func() -> void:
					for c: Vector3i in healed:
						VfxFactory.burst(self, _feet(c), "heal", 1.0))
			SimEvent.Type.CLOUDED:
				var cloud := e.cells.duplicate()
				var look := "arcane" if e.amount == SimMaterials.Gas.DARKNESS else "dust"
				_later(delay, func() -> void:
					for c: Vector3i in cloud:
						VfxFactory.burst(self, _body(c), look, 0.9))
			SimEvent.Type.DREADED:
				_later(delay, func() -> void:
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.0, 0), "Aaah!", Color(0.7, 0.45, 0.95), 60))
			SimEvent.Type.BRACED:
				var held := e.other_id >= 0  # a shove that didn't move it
				_later(delay, func() -> void:
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.0, 0), "Holds!" if held else "Braced", Color(0.85, 0.85, 0.75), 60))
			SimEvent.Type.SNARED:
				_later(delay, func() -> void:
					VfxFactory.burst(self, _feet(e.cell), "dust", 1.0)
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.0, 0), "Snared!", Color(0.9, 0.8, 0.55), 60))
			SimEvent.Type.LEARNED:
				var skill := e.text
				_later(delay, func() -> void:
					VfxFactory.burst(self, _feet(e.cell), "glitter", 1.0)
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.0, 0), "Learned %s" % skill, Color(1.0, 0.88, 0.4), 60))
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
			SimEvent.Type.SUSPICIOUS:
				_later(delay, func() -> void:
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.4, 0), "!", Color(1.0, 0.65, 0.2), 110))
			SimEvent.Type.TURNED_HOSTILE:
				_later(delay, func() -> void:
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.4, 0), "Hostile!", Color(1.0, 0.3, 0.25), 64))
			SimEvent.Type.RECOGNIZED:
				_later(delay, func() -> void:
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.8, 0), "That's mine!", Color(1.0, 0.5, 0.3), 56))
			SimEvent.Type.PICKPOCKETED:
				var took := "Took %s" % e.text
				_later(delay, func() -> void:
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.0, 0), took, Color(1.0, 0.85, 0.3), 52))
			SimEvent.Type.REVIVED:
				_later(delay, func() -> void:
					VfxFactory.burst(self, _body(e.cell), "heal", 1.4)
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.3, 0), "Revived", Color(0.5, 1.0, 0.6), 60))
			SimEvent.Type.KNOCKED_DOWN:
				_later(delay, func() -> void:
					VfxFactory.burst(self, _feet(e.cell), "dust", 1.3)
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.3, 0), "Knocked down!", Color(1.0, 0.95, 0.75), 60)
					shake_requested.emit(0.2))
			SimEvent.Type.STOOD_UP:
				_later(delay, func() -> void:
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.3, 0), "Back up", Color(0.8, 1.0, 0.8), 52))
			SimEvent.Type.TURN_SKIPPED:
				_later(delay, func() -> void:
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.3, 0), "Skips turn", Color(0.85, 0.85, 0.85), 52))
			SimEvent.Type.FROZEN:
				_later(delay, func() -> void:
					VfxFactory.burst(self, _body(e.cell), "ice", 1.2)
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.3, 0), "Frozen!", Color(0.6, 0.85, 1.0), 60))
			SimEvent.Type.THAWED:
				_later(delay, func() -> void:
					VfxFactory.burst(self, _body(e.cell), "steam", 0.8)
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0, 1.3, 0), "Thawed", Color(0.75, 0.9, 1.0), 52))
			SimEvent.Type.STAGGERED:
				var amount := "+%d stagger" % e.amount
				_later(delay, func() -> void:
					VfxFactory.floating_text(self, _body(e.cell) + Vector3(0.4, 0.9, 0), amount, Color(0.85, 0.78, 0.6), 44))
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
	_last_cast_was_shot = SimAbilities.SHOTS.has(ability)
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
		SimAbilities.Ability.CLEAVE, SimAbilities.Ability.SHOVE, SimAbilities.Ability.LOW_BLOW:
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
