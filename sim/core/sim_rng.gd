class_name SimRng
extends RefCounted
## Deterministic, serializable xorshift32 RNG owned by the sim state.
## Never use global randf()/randi() inside the sim (CLAUDE.md rule 5).

var state: int


func _init(seed_value: int = 1) -> void:
	state = seed_value & 0xFFFFFFFF
	if state == 0:
		state = 0x9E3779B9


func next_u32() -> int:
	var x := state
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	state = x & 0xFFFFFFFF
	return state


## Returns an int in [0, max_exclusive).
func range_int(max_exclusive: int) -> int:
	assert(max_exclusive > 0)
	return next_u32() % max_exclusive
