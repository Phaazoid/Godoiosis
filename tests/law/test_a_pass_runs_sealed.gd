# A live read inside a real pass is COUNTED (#1480 stage 4, #1498 stage 4). The four seal laws
# (tests/law/test_a_pass_reads_no_live_body.gd, ..._reads_no_live_tiles.gd and their write twins) refuse
# a rise in Unit.seal_breaks or PlannedTiles.seal_breaks, and those counters rise only while
# SquadManager._resolve_actions holds the seals open. A pass that ran unsealed would count nothing, and
# every one of those laws would pass it. So each case here puts a deliberate live read inside a real
# pass, through both doors that open one, and expects the seal to catch it.
#
# The reads sit in the attacker's weapon's base_damage, which the pass calls on the attacker's body
# (PlanResolver._source_base_damage). Each pass that catches one logs one push_error: that is the seal
# working, not a failure.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager
var _probe: _LiveReader


# A weapon whose damage read also reads a live body and a live tile store, past both seals, and keeps
# what each seal caught.
class _LiveReader extends ChainswordWeaponInstance:
	var store: TerrainStateManager
	var calls := 0
	var body_breaks := 0
	var tile_breaks := 0

	func base_damage(wielder: UnitState, attack: WeaponAttackData) -> int:
		calls += 1
		var body_before := Unit.seal_breaks
		var tile_before := PlannedTiles.seal_breaks
		var _held: EquippableData = wielder.unit.equipped_weapon   # Unit.state, past PlanResolver's doors
		var _lit := store.has_state(Vector2i.ZERO, Terrain.TileState.BURNING)   # past PlannedTiles
		body_breaks += Unit.seal_breaks - body_before
		tile_breaks += PlannedTiles.seal_breaks - tile_before
		return super(wielder, attack)


func before_test() -> void:
	_sm = H.make_manager(self)


func _board() -> BoardContext:
	return _sm.board_source.call()


# A hero swinging the probe at a foe beside it, the swing queued, and the two doors into a pass: the
# squad's plan, and the hover's preview of one aim (resolve_hypothetical, the AI scorer's door too).
func _passes() -> Dictionary:
	var hero := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 60}, false)
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 60})
	_probe = _LiveReader.new()
	_probe.template = H.make_weapon(3).template
	_probe.store = auto_free(TerrainStateManager.new())
	hero.equipped_weapon = _probe
	var aim := AttackAction.declare(hero, hero.movement.cell, foe.movement.cell)
	assert_bool(_sm.queue_action(hero.squad, aim)).override_failure_message(
			"fixture: the swing would not queue").is_true()
	return {
		"the planned pass": func() -> void: _sm.resolve_plan(hero.squad, _board()),
		"the previewed pass": func() -> void: _sm.preview_aim(hero.squad, aim, _board()),
	}


func test_a_live_body_read_inside_a_pass_is_counted() -> void:
	var passes := _passes()
	for door: String in passes:
		var calls := _probe.calls
		var caught := _probe.body_breaks
		(passes[door] as Callable).call()
		assert_int(_probe.calls - calls).override_failure_message(
				"fixture: %s never asked the weapon its damage, so nothing here proves anything" % door) \
			.is_greater(0)
		assert_int(_probe.body_breaks - caught).override_failure_message(
				"%s read a live body and Unit.seal_breaks never rose: the pass ran unsealed" % door) \
			.is_greater(0)


func test_a_live_tile_read_inside_a_pass_is_counted() -> void:
	var passes := _passes()
	for door: String in passes:
		var calls := _probe.calls
		var caught := _probe.tile_breaks
		(passes[door] as Callable).call()
		assert_int(_probe.calls - calls).override_failure_message(
				"fixture: %s never asked the weapon its damage, so nothing here proves anything" % door) \
			.is_greater(0)
		assert_int(_probe.tile_breaks - caught).override_failure_message(
				"%s read a live tile store and PlannedTiles.seal_breaks never rose: the pass ran unsealed" % door) \
			.is_greater(0)
