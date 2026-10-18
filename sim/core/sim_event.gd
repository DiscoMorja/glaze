class_name SimEvent
extends RefCounted
## Something notable that happened in the sim. Presentation (VFX, audio,
## narration) consumes these; the sim never knows about presentation.

enum Type {
	# Materials
	IGNITED, EXTINGUISHED, BURNED_OUT, FROZE, MELTED,
	# Entities
	MOVED, SLIPPED, DAMAGED, DIED, SPILLED, FELL, ATTACKED, CAST, TELEPORTED, SHOVED, COLLIDED, STOLEN, HEALED, SLOWED, BURNING,
	# Crowd control
	STAGGERED, KNOCKED_DOWN, STOOD_UP, TURN_SKIPPED, TEMPERATURE, FROZEN, THAWED,
	REVIVED,
	# Crime
	SUSPICIOUS, TURNED_HOSTILE, RECOGNIZED, PICKPOCKETED, GIVEN,
	# Talk and quests
	TALK_STARTED, TALK_PAGE, TALK_ENDED, QUEST_STARTED, QUEST_ENDED,
	# Combat flow
	COMBAT_STARTED, TURN_STARTED, COMBAT_ENDED, SPOTTED,
	# Loot
	LOOTED, UNLOCKED,
	# Items, trade, progression
	SHOCKWAVE,
	ITEM_USED, RESTED, TRADE_OFFERED, TRADED, EQUIPPED, XP_GAINED, LEVELED_UP,
	# Phase B skills and materials
	EXPLODED, PINNED, DISTRACTED, LEARNED, GREW, BLIGHTED,
}

var type: Type
var cell: Vector3i
## Entity the event is about (-1 if none).
var entity_id: int
## Other entity involved, e.g. the attacker or caster (-1 if none).
var other_id: int
## Type-specific number: damage, levels fallen, ability id, faction...
var amount: int
## Type-specific cells, e.g. the path walked.
var cells: Array[Vector3i] = []
## Type-specific text, e.g. the item stolen.
var text: String = ""
## DAMAGED: what dealt it (EntityOps.Element).
var element: int = 0


func _init(p_type: Type, p_cell: Vector3i = Vector3i.ZERO, p_entity_id: int = -1, p_other_id: int = -1, p_amount: int = 0) -> void:
	type = p_type
	cell = p_cell
	entity_id = p_entity_id
	other_id = p_other_id
	amount = p_amount
