extends GutTest
## Container and barrel models, and the loot placed in the vertical slice.


func test_every_look_has_a_model() -> void:
	for look: String in PropLooks.LOOKS:
		var node := PropLooks.create(look)
		assert_not_null(node, look)
		if node != null:
			assert_gt(node.find_children("*", "MeshInstance3D", true, false).size(), 0, look + " has a mesh")
			node.free()


func test_containers_and_barrels_pick_their_look() -> void:
	var chest := SimEntity.container("Basket", Vector3i(1, 1, 1), [] as Array[String])
	chest.model = "basket"
	assert_eq(PropLooks.look_of(chest), "basket")
	var oil := SimEntity.barrel("Oil barrel", Vector3i(1, 1, 1), SimMaterials.Surface.OIL, 40)
	assert_eq(PropLooks.look_of(oil), PropLooks.BARREL_LOOK)
	var hero := SimEntity.character("Hero", SimEntity.Faction.PLAYERS, Vector3i(1, 1, 1), 10)
	assert_eq(PropLooks.look_of(hero), "", "characters have their own models")


func test_the_slice_containers_hold_real_items() -> void:
	var level := (load("res://levels/vertical_slice/vertical_slice.tscn") as PackedScene).instantiate()
	var containers := level.find_children("*", "LevelContainer", true, false)
	assert_gt(containers.size(), 20, "the dressing pass placed loot")
	for node in containers:
		var box := node as LevelContainer
		assert_true(PropLooks.LOOKS.has(box.look), "%s look %s" % [box.name, box.look])
		for item: String in box.items:
			assert_true(SimItems.ITEMS.has(item), "%s holds unknown item %s" % [box.name, item])
	level.free()
