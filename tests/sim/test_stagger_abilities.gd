extends GutTest
## Shockwave (Vanguard: 2 stagger along a line) and Low Blow (Trickster: 3
## stagger on one adjacent character, 3-turn cooldown).

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")
const Y := Fixtures.FLOOR_Y
const A := SimAbilities.Ability
const PLAYERS := SimEntity.Faction.PLAYERS
const ENEMIES := SimEntity.Faction.ENEMIES


## In combat on a 12x5x12 field: the hero (id 1, all abilities) at (2,1,2),
## the bandit (id 2) moved to (5,1,2) in a line east of it.
func _line_up() -> SimState:
	var state := Fixtures.duel_state()
	EntityOps.place(state, Fixtures.bandit(state), Vector3i(5, Y, 2))
	Fixtures.bandit(state).stagger_max = 5  # don't knock down: count the stagger
	return state


func _thug(state: SimState, cell: Vector3i, faction: SimEntity.Faction = ENEMIES) -> SimEntity:
	var e := state.add_entity(SimEntity.character("Thug", faction, cell, 12, "Club", 3))
	e.stagger_max = 5
	return e


func test_the_line_runs_from_the_caster_toward_the_target() -> void:
	var state := _line_up()
	var line := SimAbilities.line_cells(state.grid, Vector3i(2, Y, 2), Vector3i(4, Y, 2))
	assert_eq(line, [Vector3i(3, Y, 2), Vector3i(4, Y, 2), Vector3i(5, Y, 2), Vector3i(6, Y, 2), Vector3i(7, Y, 2)] as Array[Vector3i],
			"always SHOCKWAVE_LENGTH long, past the target")
	var diagonal := SimAbilities.line_cells(state.grid, Vector3i(2, Y, 2), Vector3i(5, Y, 5))
	assert_eq(diagonal[2], Vector3i(5, Y, 5))


func test_shockwave_staggers_everyone_on_the_line_allies_too() -> void:
	var state := _line_up()
	var ally := _thug(state, Vector3i(4, Y, 2), PLAYERS)
	var off_line := _thug(state, Vector3i(4, Y, 4))
	assert_true(state.apply_command(CastCommand.new(1, A.SHOCKWAVE, Vector3i(5, Y, 2))))
	assert_eq(Fixtures.bandit(state).stagger, SimAbilities.SHOCKWAVE_STAGGER)
	assert_eq(ally.stagger, SimAbilities.SHOCKWAVE_STAGGER, "allies on the line too")
	assert_eq(off_line.stagger, 0)
	assert_eq(Fixtures.hero(state).stagger, 0, "not the caster")
	assert_eq(Fixtures.hero(state).cooldown(A.SHOCKWAVE), SimAbilities.COOLDOWN[A.SHOCKWAVE])


func test_walls_stop_the_shockwave() -> void:
	var state := _line_up()
	state.grid.fill_solid(Vector3i(4, Y, 0), Vector3i(4, Y + 2, 11))
	assert_eq(SimAbilities.line_cells(state.grid, Vector3i(2, Y, 2), Vector3i(5, Y, 2)), [Vector3i(3, Y, 2)] as Array[Vector3i])
	state.apply_command(CastCommand.new(1, A.SHOCKWAVE, Vector3i(5, Y, 2)))
	assert_eq(Fixtures.bandit(state).stagger, 0)


func test_shockwave_and_a_hit_knock_a_normal_character_down() -> void:
	var state := _line_up()
	var bandit := Fixtures.bandit(state)
	bandit.stagger_max = SimArchetypes.DEFAULT_STAGGER
	state.apply_command(CastCommand.new(1, A.SHOCKWAVE, bandit.cell))
	assert_false(bandit.knocked_down)
	EntityOps.add_stagger(state, bandit, 1, 1)
	assert_true(bandit.knocked_down)


func test_low_blow_knocks_a_normal_character_down_alone() -> void:
	var state := _line_up()
	var bandit := Fixtures.bandit(state)
	bandit.stagger_max = SimArchetypes.DEFAULT_STAGGER
	EntityOps.place(state, bandit, Vector3i(3, Y, 2))
	assert_true(state.apply_command(CastCommand.new(1, A.LOW_BLOW, bandit.cell)))
	assert_true(bandit.knocked_down)
	assert_eq(Fixtures.hero(state).cooldown(A.LOW_BLOW), 3)


func test_low_blow_needs_someone_adjacent() -> void:
	var state := _line_up()
	assert_false(CastCommand.new(1, A.LOW_BLOW, Fixtures.bandit(state).cell).validate(state), "too far")
	assert_false(CastCommand.new(1, A.LOW_BLOW, Vector3i(3, Y, 2)).validate(state), "nobody there")


func test_the_roles_have_them() -> void:
	assert_true(SimArchetypes.ROLES.vanguard.abilities.has(A.SHOCKWAVE))
	assert_true(SimArchetypes.ROLES.trickster.abilities.has(A.LOW_BLOW))


func test_saves_from_before_these_abilities_still_load() -> void:
	var state := _line_up()
	var data := Fixtures.hero(state).to_dict()
	data.cooldowns = PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])  # 13 abilities back then
	var old := SimEntity.from_dict(data)
	assert_eq(old.cooldowns.size(), SimAbilities.NAMES.size())
	assert_eq(old.cooldown(A.LOW_BLOW), 0)
