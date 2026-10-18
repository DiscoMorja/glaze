class_name PartyChains
extends RefCounted
## Which of this player's characters move together (chains, as in Divinity).
## Everyone starts in one chain; a walk order moves the selected character
## and the rest of its chain. Characters can be unchained (they then walk
## alone) and chained to anyone else, in any grouping. A control preference of
## this player, not a game rule: it lives here, not in the sim.

## Member id -> chain number.
var _chain := {}
## Member ids in party order (from the last sync).
var _order: Array[int] = []
var _next := 1


## Follows the party: newcomers join the first chain, the gone are dropped.
func sync(ids: Array[int]) -> void:
	_order = ids.duplicate()
	for id: int in _chain.keys():
		if not ids.has(id):
			_chain.erase(id)
	var first := -1
	for id in ids:
		if _chain.has(id):
			first = _chain[id]
			break
	if first == -1:
		first = _new_chain()
	for id in ids:
		if not _chain.has(id):
			_chain[id] = first


## The members chained with `id` (itself included), in party order.
func chain_of(id: int) -> Array[int]:
	var result: Array[int] = []
	if not _chain.has(id):
		result.append(id)
		return result
	for other in _order:
		if _chain.get(other) == _chain[id]:
			result.append(other)
	return result


func is_chained(id: int) -> bool:
	return chain_of(id).size() > 1


## Whether a and b move together.
func together(a: int, b: int) -> bool:
	return _chain.has(a) and _chain.get(a) == _chain.get(b)


## `id` walks alone from now on.
func unchain(id: int) -> void:
	if _chain.has(id) and is_chained(id):
		_chain[id] = _new_chain()


## `id` joins the chain of `to_id`.
func chain(id: int, to_id: int) -> void:
	if _chain.has(id) and _chain.has(to_id) and id != to_id:
		_chain[id] = _chain[to_id]


## Ctrl+G: a chained character is unchained; a lone one joins the biggest
## other chain (the first in party order on a tie). Returns whether it is
## chained now.
func toggle(id: int) -> bool:
	if not _chain.has(id):
		return false
	if is_chained(id):
		unchain(id)
		return false
	var best := -1
	var best_size := 0
	for other in _order:
		if other == id:
			continue
		var size := chain_of(other).size()
		if size > best_size:
			best = other
			best_size = size
	if best != -1:
		chain(id, best)
	return is_chained(id)


## Party order regrouped so each chain's members sit together, chains in the
## order of their first member: [ids, chain number per id].
func layout() -> Array:
	var ids: Array[int] = []
	var chains: Array[int] = []
	for id in _order:
		if ids.has(id):
			continue
		for member in chain_of(id):
			ids.append(member)
			chains.append(_chain.get(member, -1))
	return [ids, chains]


func _new_chain() -> int:
	_next += 1
	return _next
