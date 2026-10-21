extends GutTest
## Random loot at bake: containers and spawns with a `loot` table get items
## rolled with the level's seed (LootTables).


func _bake(seed_value: int) -> SimState:
	var level := GameLevel.new()
	level.grid_size = Vector3i(12, 5, 12)
	add_child_autofree(level)
	var ground := CSGBox3D.new()
	ground.use_collision = true
	ground.size = Vector3(12, 1, 12)
	ground.position = Vector3(6, 0.5, 6)
	level.add_child(ground)
	var chest := LevelContainer.new()
	chest.items.assign(["Key"])
	chest.loot = "cache"
	chest.loot_rolls = 3
	chest.position = Vector3(4.5, 2, 4.5)
	level.add_child(chest)
	var bandit := LevelSpawn.new()
	bandit.role = "thug"
	bandit.loot = "tomes"
	bandit.position = Vector3(8.5, 2, 8.5)
	level.add_child(bandit)
	return await level.bake(seed_value)


func _items(state: SimState, model: String) -> Array[String]:
	for e in state.entities:
		if (model == "chest") == (e.model == "chest"):
			return e.inventory
	return []


func test_markers_roll_their_loot_tables_by_seed() -> void:
	var a := await _bake(5)
	var chest := _items(a, "chest")
	assert_eq(chest.size(), 4, "its own item and three rolls (a cache never rolls nothing)")
	assert_eq(chest[0], "Key")
	var carried := _items(a, "")
	assert_eq(carried.size(), 1)
	assert_true(SimItems.teaches(carried[0]) >= 0, "a tome in the bandit's pocket")
	var b := await _bake(5)
	assert_eq(_items(b, "chest"), chest, "same seed, same loot")
