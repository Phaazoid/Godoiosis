# The rescue HAUL (#116). A rescue puts a body somewhere it can STAND: from ordinary ground that is
# where it already lies and nothing moves, which is every rescue before this ticket. From deep water
# -- ground nothing may stand on, and the only such ground a unit can legally end up on -- the
# rescuer drags it out onto a cell beside them.
#
# The dev's ruling that made it part of the ticket (2026-08-26): "we need the rescue function to be
# what actually gets new lifecycle when rescuing from deep water, we need a valid tile next to the
# rescuer to bring the drowning unit onto." A unit revived standing in the lake is not a rescue.
#
# Three seams, and the cases below drive each at its own layer rather than through one end-to-end
# path: RulesService.rescue_landing is the RULE, SquadManager.resolve_plan PUBLISHES it so the board
# draws the body on the bank before Execute, and RescueAction._haul_out replays that published cell.
# The publication case is the one that matters most -- both ends can be correct while nothing joins
# them, which is #103's shape.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

# The authored deep-water tile: WATER kind, and no `walkable` flag, which is what "deep" means (#116).
const DEEP_WATER := Vector2i(5, 6)

var _sm: SquadManager
var _grid: TileMapLayer


func before_test() -> void:
	_sm = H.make_manager(self)
	_grid = _sm.get_node("../Grid") as TileMapLayer


func _board() -> BoardContext:
	return _sm.board_source.call()


func _flood(cells: Array) -> void:
	for cell: Vector2i in cells:
		_grid.set_cell(cell, 0, DEEP_WATER)


# A downed ally at `cell`. Exactly-lethal, so the rung is a clean down (the rescue-validation
# suite's arrangement). The fixture spawner writes movement.cell directly, so a body can sit on
# water here exactly as a drowning shove leaves one on the real board.
func _downed_ally(cell: Vector2i) -> Unit:
	var ally := H.spawn_solo(self, _sm, PLAYER, cell)
	ally.take_damage(ally.get_current_hp())
	assert_bool(ally.is_downed()) \
		.override_failure_message("fixture assumption broke: the ally did not go down").is_true()
	return ally


func _queue_rescue(rescuer: Unit, ally: Unit) -> RescueAction:
	var rescue := RescueAction.new()
	rescue.init(rescuer, ally)
	rescuer.squad._queue_action(rescue)
	return rescue


# --- The rule ---------------------------------------------------------------------------------

func test_a_body_on_dry_ground_is_left_exactly_where_it_lies() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := _downed_ally(Vector2i(1, 0))
	# Not "some cell near the rescuer" -- the body's OWN cell, which is what keeps every rescue
	# before #116 bit-for-bit unchanged instead of quietly relocating bodies on dry land.
	assert_bool(RulesService.rescue_landing(rescuer, ally, _board()) == Vector2i(1, 0)).is_true()


func test_a_body_in_deep_water_is_pulled_to_a_cell_beside_the_rescuer() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	_flood([Vector2i(1, 0)])
	var ally := _downed_ally(Vector2i(1, 0))
	var landing := RulesService.rescue_landing(rescuer, ally, _board())
	assert_bool(landing != GridUtils.NO_CELL) \
		.override_failure_message("there is dry ground all round the rescuer; something must qualify") \
		.is_true()
	assert_int(GridUtils.manhattan_distance(landing, rescuer.movement.cell)).is_equal(1)
	assert_bool(_board().is_walkable(landing)) \
		.override_failure_message("hauled onto ground the body still cannot stand on").is_true()


func test_a_body_nobody_can_pull_out_answers_NO_CELL() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	# Every cell the rescuer could drag it to is water too, so there is nowhere to put it.
	_flood([Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)])
	var ally := _downed_ally(Vector2i(1, 0))
	assert_bool(RulesService.rescue_landing(rescuer, ally, _board()) == GridUtils.NO_CELL).is_true()


func test_a_body_nobody_can_pull_out_is_not_offered_as_a_target() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	_flood([Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)])
	var ally := _downed_ally(Vector2i(1, 0))
	# The menu may not offer a rescue execution could not finish: a preview that promises a pickup
	# and then fizzles is exactly what the BREAK repeal (#155) calls a bug.
	assert_bool(RulesService.adjacent_downed_allies(rescuer, _board()).has(ally)).is_false()


func test_a_body_in_reachable_water_IS_still_offered() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	_flood([Vector2i(1, 0)])
	var ally := _downed_ally(Vector2i(1, 0))
	# The twin of the case above, so "not offered" is a rule about the BANK and not about water.
	assert_bool(RulesService.adjacent_downed_allies(rescuer, _board()).has(ally)).is_true()


# --- The wire: the resolve publishes it, so the board draws it ---------------------------------

func test_a_queued_rescue_draws_the_body_on_the_bank_before_execute() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	_flood([Vector2i(1, 0)])
	var ally := _downed_ally(Vector2i(1, 0))
	_queue_rescue(rescuer, ally)
	_sm.resolve_plan(rescuer.squad, _board())

	var bank := ally.get_projected_destination()
	assert_bool(bank != Vector2i(1, 0)) \
		.override_failure_message("the resolve published nothing -- the board would jump the body "
			+ "onto the bank on Execute, which is the divergence Law #2 forbids").is_true()
	# The whole point of publishing: the cell reads OCCUPIED, so nothing else can be ordered onto it.
	assert_object(_board().projected_unit_at_cell(bank)).is_same(ally)


func test_a_dry_land_rescue_publishes_nothing() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := _downed_ally(Vector2i(1, 0))
	_queue_rescue(rescuer, ally)
	_sm.resolve_plan(rescuer.squad, _board())
	assert_bool(ally.get_projected_destination() == Vector2i(1, 0)) \
		.override_failure_message("an ordinary rescue must move nobody").is_true()


func test_the_publication_is_cleared_and_recomputed_each_resolve() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	_flood([Vector2i(1, 0)])
	var ally := _downed_ally(Vector2i(1, 0))
	_queue_rescue(rescuer, ally)
	_sm.resolve_plan(rescuer.squad, _board())
	var first := ally.get_projected_destination()
	# Resolving again must reach the SAME answer. It only can if the clear ran: rescue_landing reads
	# the body's PROJECTED cell, so a haul left standing would be read back as where the body already
	# is and freeze the answer, which is a stale bank the moment the rescuer re-plans.
	_sm.resolve_plan(rescuer.squad, _board())
	assert_bool(ally.get_projected_destination() == first).is_true()
	assert_bool(ally.movement.cell == Vector2i(1, 0)) \
		.override_failure_message("publishing must not MOVE the body -- only execution does").is_true()


# --- Execution replays the published cell ------------------------------------------------------

func test_executing_the_rescue_drags_the_body_onto_the_bank_and_revives_it() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	_flood([Vector2i(1, 0)])
	var ally := _downed_ally(Vector2i(1, 0))
	var rescue := _queue_rescue(rescuer, ally)
	_sm.resolve_plan(rescuer.squad, _board())
	var bank := ally.get_projected_destination()

	rescue.execute()

	# This one is SELF-REFERENTIAL and cannot carry the case alone -- both sides read the published
	# cell, so with nothing published they agree on the water and it passes (measured, against the
	# no-publication mutant). It is here for what it says about DIVERGENCE; the walkability assertion
	# below is the one with teeth, and it is what actually reddened.
	assert_bool(ally.movement.cell == bank) \
		.override_failure_message("execution landed the body somewhere the preview never drew") \
		.is_true()
	assert_bool(ally.is_active()).is_true()
	assert_bool(_board().is_walkable(ally.movement.cell)) \
		.override_failure_message("revived still standing in the lake").is_true()


func test_executing_a_dry_land_rescue_moves_nobody() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := _downed_ally(Vector2i(1, 0))
	var rescue := _queue_rescue(rescuer, ally)
	_sm.resolve_plan(rescuer.squad, _board())

	rescue.execute()

	assert_bool(ally.movement.cell == Vector2i(1, 0)).is_true()
	assert_bool(ally.is_active()).is_true()
