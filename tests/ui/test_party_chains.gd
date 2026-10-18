extends GutTest
## Chaining and unchaining party members (who follows a walk order).

var _chains: PartyChains


func before_each() -> void:
	_chains = PartyChains.new()
	_chains.sync([1, 2, 3, 4] as Array[int])


func test_everyone_starts_chained() -> void:
	assert_eq(_chains.chain_of(2), [1, 2, 3, 4] as Array[int])


func test_an_unchained_member_walks_alone() -> void:
	_chains.unchain(3)
	assert_eq(_chains.chain_of(3), [3] as Array[int])
	assert_eq(_chains.chain_of(1), [1, 2, 4] as Array[int])
	assert_false(_chains.is_chained(3))


func test_any_grouping() -> void:
	_chains.unchain(3)
	_chains.unchain(4)
	_chains.chain(4, 3)
	assert_eq(_chains.chain_of(1), [1, 2] as Array[int])
	assert_eq(_chains.chain_of(4), [3, 4] as Array[int])
	var layout := _chains.layout()
	assert_eq(layout[0], [1, 2, 3, 4] as Array[int])
	var c: Array[int] = layout[1]
	assert_true(c[0] == c[1] and c[2] == c[3] and c[1] != c[2], "two chains of two")


func test_toggle_unchains_then_rejoins_the_biggest_chain() -> void:
	assert_false(_chains.toggle(2), "unchained")
	_chains.unchain(4)
	_chains.chain(4, 2)  # chains: [1, 3] and [2, 4]...
	_chains.unchain(1)  # now [3], [2, 4], [1]
	assert_true(_chains.toggle(1), "joins the biggest chain")
	assert_eq(_chains.chain_of(1), [1, 2, 4] as Array[int])


func test_layout_keeps_chains_together() -> void:
	_chains.unchain(2)
	_chains.chain(4, 2)
	assert_eq(_chains.layout()[0], [1, 3, 2, 4] as Array[int])


func test_sync_adds_newcomers_to_the_first_chain_and_drops_the_gone() -> void:
	_chains.unchain(1)
	_chains.sync([1, 2, 3, 5] as Array[int])
	assert_eq(_chains.chain_of(5), [1, 5] as Array[int], "joins the first member's chain")
	assert_eq(_chains.chain_of(2), [2, 3] as Array[int])
	assert_false(_chains._chain.has(4))


func _party() -> Array[SimEntity]:
	var party: Array[SimEntity] = []
	for i in 4:
		var e := SimEntity.character("Hero %d" % (i + 1), SimEntity.Faction.PLAYERS, Vector3i(i, 1, 1), 10)
		e.id = i + 1
		party.append(e)
	return party


func test_party_frames_sit_by_chain_with_links() -> void:
	var bar := PartyBar.new()
	add_child_autofree(bar)
	_chains.unchain(2)
	_chains.chain(4, 2)
	bar.update_party(_party(), 1, {}, 0, {}, _chains)
	var order: Array[int] = []
	var spacers := 0
	for child in bar.get_children():
		if child is PartyBar._Card:
			order.append(child._id)
		else:
			spacers += 1
	assert_eq(order, [1, 3, 2, 4] as Array[int])
	assert_eq(spacers, 1, "one gap between the two chains")
	assert_false(bar._cards[1]._linked)
	assert_true(bar._cards[3]._linked, "chained to the frame above")
	assert_false(bar._cards[2]._linked, "starts a new chain")
	assert_true(bar._cards[4]._linked)


func test_dragging_a_frame_onto_another_chains_them() -> void:
	var bar := PartyBar.new()
	add_child_autofree(bar)
	var dropped: Array = []
	bar.chain_dropped.connect(func(id: int, onto: int) -> void: dropped.append([id, onto]))
	bar.update_party(_party(), 1, {}, 0, {}, _chains)
	var data: Variant = bar._cards[3]._get_drag_data(Vector2.ZERO)
	assert_true(bar._cards[1]._can_drop_data(Vector2.ZERO, data))
	bar._cards[1]._drop_data(Vector2.ZERO, data)
	bar._cards[3]._drop_data(Vector2.ZERO, data)  # back on itself: nothing
	assert_eq(dropped, [[3, 1]])


func test_partner_frames_dont_drag_or_take_chains() -> void:
	var bar := PartyBar.new()
	add_child_autofree(bar)
	bar.update_party(_party(), 1, {}, 0, {4: true}, _chains)
	assert_null(bar._cards[4]._get_drag_data(Vector2.ZERO))
	assert_false(bar._cards[4]._can_drop_data(Vector2.ZERO, {"kind": PartyBar.DRAG_KIND, "id": 1}))
