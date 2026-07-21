# BoardContext's census queries (present_factions/faction_has_active_units/has_active_units),
# extracted from game.gd + play_session.gd -- both drove the same turn-cycle auto-skip logic
# with a byte-identical, independently-maintained copy of these three functions before the
# extraction. Mirrors test_rules_service.gd's parity-guard framing.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

func _board() -> BoardContext:
	var units: Array[Unit] = []
	for squad in _sm.squads:
		for member in squad.get_members():
			if not units.has(member):
				units.append(member)
	return BoardContext.new(_sm.grid, units, _sm)

# ---- present_factions ----

func test_present_factions_includes_a_faction_whose_only_unit_is_downed() -> void:
	var unit := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	unit.lifecycle_state = Unit.LifecycleState.DOWNED

	assert_array(_board().present_factions()).contains([ENEMY])

func test_present_factions_excludes_a_faction_whose_only_unit_is_dead() -> void:
	var unit := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	unit.lifecycle_state = Unit.LifecycleState.DEAD

	assert_array(_board().present_factions()).not_contains([ENEMY])

func test_present_factions_includes_an_active_faction() -> void:
	H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))

	assert_array(_board().present_factions()).contains([PLAYER])

# ---- faction_has_active_units ----

func test_faction_has_active_units_false_when_all_its_units_are_downed() -> void:
	var unit := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	unit.lifecycle_state = Unit.LifecycleState.DOWNED

	assert_bool(_board().faction_has_active_units(ENEMY)).is_false()

func test_faction_has_active_units_true_with_one_active_unit() -> void:
	var downed := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	downed.lifecycle_state = Unit.LifecycleState.DOWNED
	H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))   # stays ACTIVE

	assert_bool(_board().faction_has_active_units(ENEMY)).is_true()

func test_faction_has_active_units_false_for_a_faction_with_no_units_at_all() -> void:
	H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))

	assert_bool(_board().faction_has_active_units(ENEMY)).is_false()

# ---- has_active_units ----

func test_has_active_units_false_on_an_all_downed_board() -> void:
	var a := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var b := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	a.lifecycle_state = Unit.LifecycleState.DOWNED
	b.lifecycle_state = Unit.LifecycleState.DOWNED

	assert_bool(_board().has_active_units()).is_false()

func test_has_active_units_true_when_one_unit_is_still_active() -> void:
	var downed := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	downed.lifecycle_state = Unit.LifecycleState.DOWNED
	H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))   # stays ACTIVE

	assert_bool(_board().has_active_units()).is_true()
