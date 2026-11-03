# THE SPLIT FORECAST IS STAMPED INSIDE THE PASS'S SEALS (#1529). SplitForecast.stamp replays the pass's
# blows over the bodies and ground it left, so a live read added to it is a pass reading live; it runs in
# SquadManager._resolve_actions, after the tiles are given back and before either seal closes, where such
# a read counts on Unit.seal_breaks / PlannedTiles.seal_breaks like one in the pass itself.
#
# The witness is the board the pass is handed: it notes, at every planned() the stamp asks of it, whether
# both seals are open. A shove on a member of a squad of two seeds a band, which is what sends the stamp
# to the board at all (SplitForecast._seed_bands).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager


# A board that remembers whether the seals were open each time it was asked for a planned view.
class _Witness extends BoardContext:
	var asked: Array[Dictionary] = []

	func planned(planned_tiles: PlannedTiles) -> BoardContext:
		asked.append({"bodies": Unit._sealed > 0, "tiles": PlannedTiles.is_sealed()})
		return super(planned_tiles)


func before_test() -> void:
	_sm = H.make_manager(self)


func test_the_stamp_reads_the_board_inside_both_seals() -> void:
	var shover := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.MHP: 60}, false)
	var shove := WeaponAttackData.new()
	shove.display_name = "Shove"
	shove.power = 1
	shove.knockback = 1
	P.point(shove, 1, 1)
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = shove
	assert_bool(shover.add_item(WeaponInstance.make(t))).override_failure_message("fixture: the weapon did not fit").is_true()
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 60}, false)
	var mate := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 1), {Stats.Stat.MHP: 60}, false)
	_sm.join_squad(mate, foe.squad)
	assert_bool(foe.squad.has_squadmates()).override_failure_message("fixture: the foe must have a squadmate").is_true()
	shover.squad._queue_action(H.stamped_attack(shover, foe))
	_sm.active_squad = shover.squad

	var grid: TileMapLayer = (_sm.board_source.call() as BoardContext).grid
	var witness := _Witness.new(grid, _sm._all_units(), _sm)
	var body_breaks := Unit.seal_breaks
	var tile_breaks := PlannedTiles.seal_breaks
	var plan := _sm.resolve_plan(shover.squad, witness)

	var shoved := plan.attacks.filter(func(a: AttackAction) -> bool:
		return a.target == foe and a.resolved_outcome() != null and a.resolved_outcome().knockback_applied)
	assert_int(shoved.size()).override_failure_message("fixture: the shove must land, or no band is seeded").is_equal(1)
	assert_array(witness.asked).override_failure_message("fixture: the stamp never asked the board for its ground") \
		.is_not_empty()
	for seen: Dictionary in witness.asked:
		assert_bool(seen.bodies).override_failure_message("the stamp read the board with the body seal closed").is_true()
		assert_bool(seen.tiles).override_failure_message("the stamp read the board with the tile seal closed").is_true()
	assert_int(Unit.seal_breaks).override_failure_message("the stamp read a live body").is_equal(body_breaks)
	assert_int(PlannedTiles.seal_breaks).override_failure_message("the stamp read a live tile").is_equal(tile_breaks)
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for ctr in plan.counters:
		ctr.volley = empty
