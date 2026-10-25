# The END OF TURN forecast never writes the body it reads (R2). The health bars ask
# TurnBoundary.tile_hits every frame, of the LIVE units, so a row that wrote its body would change a
# unit just by being looked at. TileHitAction.end_of_turn copies the body only when a row will write
# it (a scald, #1480); every case here asserts the live body is exactly as it was.
#
# The gas and the weather are found from their rules, never named, so retuning them reds nothing.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const CELL := Vector2i(1, 1)

var _sm: SquadManager
var _states: TerrainStateManager
var _gas: GasField


func before_test() -> void:
	_sm = H.make_manager(self)
	_states = auto_free(TerrainStateManager.new())
	_gas = GasField.new()


func _unit() -> Unit:
	return H.spawn_solo(self, _sm, PLAYER, CELL, {Stats.Stat.MHP: 40})


func _burn_under() -> void:
	var ignite := ResolvedCellEffect.new()
	ignite.cell = CELL
	ignite.states_added.assign([Terrain.TileState.BURNING])
	_states.apply(ignite)


# The first gas whose rules scald at THICK.
func _steam_under() -> void:
	for kind: Gas.Kind in Gas.Kind.values():
		var rules := GasRules.for_kind(kind)
		if rules != null and int(rules.damage.get(Gas.Level.THICK, 0)) > 0:
			_gas.set_level(CELL, kind, Gas.Level.THICK)
			return
	fail("fixture: no gas scalds at THICK, so nothing here writes")


# The first weather that gives a state: a soak with no HP row.
func _soaking_weather() -> Weather.Kind:
	for kind: Weather.Kind in Weather.Kind.values():
		var rules := WeatherRules.for_kind(kind)
		if rules != null and rules.state != Elemental.State.NONE:
			return kind
	fail("fixture: no weather gives a state")
	return Weather.Kind.CLEAR


func _snapshot(unit: Unit) -> Dictionary:
	var body := unit.state
	var limbs := {}
	for slot in body.instance.limbs:
		limbs[slot] = body.instance.limbs[slot].state
	return {
		"hp": body.get_current_hp(),
		"lifecycle": body.lifecycle_state,
		"wounded": body.wounded,
		"in_crisis": body.in_crisis,
		"surge": body.crisis_surge_pending,
		"downed_turns": body.downed_turns_remaining,
		"states": body.element_states.duplicate(),
		"limbs": limbs,
	}


# Forecasts `unit`'s end of turn the way the bars do, and asserts its body came through untouched.
func _forecast_leaves_it_alone(unit: Unit, weather := Weather.Kind.CLEAR) -> Array[TileHitAction]:
	var before := _snapshot(unit)
	var units: Array[Unit] = [unit]
	var rows := TurnBoundary.tile_hits(units, _states, _gas, weather, PLAYER)
	assert_dict(_snapshot(unit)).override_failure_message(
			"forecasting the end of turn wrote the live body").is_equal(before)
	return rows


func _damage_rows(rows: Array[TileHitAction]) -> int:
	var count := 0
	for row in rows:
		if row.resolved.reads_hp and row.resolved.damage > 0:
			count += 1
	return count


func test_a_burn_writes_nothing() -> void:
	var unit := _unit()
	_burn_under()
	var rows := _forecast_leaves_it_alone(unit)
	assert_int(_damage_rows(rows)).override_failure_message("fixture: the fire burns nobody").is_equal(1)


func test_a_scald_writes_nothing() -> void:
	var unit := _unit()
	_steam_under()
	var rows := _forecast_leaves_it_alone(unit)
	assert_int(_damage_rows(rows)).override_failure_message("fixture: the steam scalds nobody").is_equal(1)


func test_a_scald_then_a_burn_writes_nothing() -> void:
	var unit := _unit()
	_steam_under()
	_burn_under()
	var rows := _forecast_leaves_it_alone(unit)
	assert_int(_damage_rows(rows)).override_failure_message(
			"fixture: want a scald and a burn, the two rows the copy threads").is_equal(2)


func test_a_scald_that_kills_writes_nothing() -> void:
	var unit := _unit()
	unit.force_down()
	_steam_under()
	var rows := _forecast_leaves_it_alone(unit)
	var kills := rows.filter(func(row: TileHitAction) -> bool:
		return row.resolved.lethality == ResolvedOutcome.Lethality.KILLED)
	assert_int(kills.size()).override_failure_message("fixture: the scald kills nobody").is_equal(1)


func test_a_soak_from_the_sky_writes_nothing() -> void:
	var unit := _unit()
	var rows := _forecast_leaves_it_alone(unit, _soaking_weather())
	assert_int(rows.size()).override_failure_message("fixture: the weather soaks nobody").is_equal(1)
