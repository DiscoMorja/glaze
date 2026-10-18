extends SceneTree
## Writes tests/fixtures/snapshot_v<N>.bin: a snapshot of a busy little world
## (fire, oil, facts, a quest, a conversation, items, combat) at the current
## SimState.SNAPSHOT_VERSION. Run once per new version, never to overwrite an
## old one; tests/sim/test_save_format.gd checks every fixture still loads.
##
##   godot --headless --path . -s tools/make_snapshot_fixture.gd

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")


func _init() -> void:
	var path := "res://tests/fixtures/snapshot_v%d.bin" % SimState.SNAPSHOT_VERSION
	if FileAccess.file_exists(path):
		print("%s exists; fixtures are never overwritten." % path)
		quit(1)
		return
	var y := Fixtures.FLOOR_Y
	var state := Fixtures.duel_state()
	Fixtures.give_flasks(Fixtures.hero(state))
	state.apply_command(CastCommand.new(1, SimAbilities.Ability.OIL_FLASK, Vector3i(5, y, 5)))
	state.apply_command(IgniteCommand.new(Vector3i(5, y, 5)))
	state.step_ticks(3)
	var hero := Fixtures.hero(state)
	hero.inventory.assign(["Gold", "Silver ring"])
	hero.stolen.assign(["Village:Silver ring"])
	hero.owner = 1
	hero.dexterity = 3
	hero.thievery = 1
	hero.schools[StatRules.School.DEATH] = 1
	hero.combat_points = 1
	state.facts["bandits_known"] = 1
	state.quests["bandits"] = {"known": true, "outcome": ""}
	DirAccess.make_dir_recursive_absolute("res://tests/fixtures")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_buffer(state.to_snapshot())
	file.close()
	print("wrote %s: hero %s hp %d at %s, %d fire cells, tick %d, combat %s" % [
		path, hero.name, hero.hp, hero.cell, state.grid.fire_cells.size(), state.tick, state.combat.active])
	quit()
