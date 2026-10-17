class_name SimCombat
extends RefCounted
## Combat state. Turns are side-based: the whole side acts in any order, then
## the other side does.

var active := false
var side: SimEntity.Faction = SimEntity.Faction.PLAYERS
var round_number := 0


func to_dict() -> Dictionary:
	return {"active": active, "side": side, "round_number": round_number}


func duplicate_combat() -> SimCombat:
	var copy := SimCombat.new()
	copy.active = active
	copy.side = side
	copy.round_number = round_number
	return copy
