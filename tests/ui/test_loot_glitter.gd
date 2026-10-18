extends GutTest
## Fallen characters with something on them glitter until this player opens
## them (or they are emptied); the living, the party and empty bodies don't.

const Fixtures := preload("res://tests/helpers/sim_fixtures.gd")

var _renderer: SimEntityRenderer
var _state: SimState


func before_each() -> void:
	_state = Fixtures.duel_state()  # hero (1) and a bandit (2) carrying Gold
	_state.combat.active = false
	_renderer = SimEntityRenderer.new()
	add_child_autofree(_renderer)


func _glittering(id: int) -> bool:
	return _renderer.view_of(id)._glitter != null


func test_a_fallen_bandit_glitters_until_opened() -> void:
	_renderer.render(_state)
	assert_false(_glittering(2), "alive")
	EntityOps.damage(_state, Fixtures.bandit(_state), 100, 1)
	_renderer.render(_state)
	assert_true(_glittering(2))
	_renderer.mark_searched(2)
	_renderer.render(_state)
	assert_false(_glittering(2), "opened: no more glitter, even with things left")


func test_emptied_bodies_and_fallen_party_members_dont_glitter() -> void:
	var bandit := Fixtures.bandit(_state)
	EntityOps.damage(_state, bandit, 100, 1)
	bandit.inventory.clear()
	EntityOps.damage(_state, Fixtures.hero(_state), 100, -1)
	_renderer.render(_state)
	assert_false(_glittering(2), "nothing left on it")
	assert_false(_glittering(1), "the party isn't loot")
