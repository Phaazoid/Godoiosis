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


# `landing` is the STAMP the order carries (#116) -- what the player picked, or the body's own cell
# on dry ground. Required rather than defaulted here for the reason it is required in production:
# a helper that chose one would hide exactly the fact these cases are about.
func _queue_rescue(rescuer: Unit, ally: Unit, landing: Vector2i) -> RescueAction:
	var rescue := RescueAction.new()
	rescue.init(rescuer, ally, landing)
	rescuer.squad._queue_action(rescue)
	return rescue


# --- The rule ---------------------------------------------------------------------------------

func test_a_body_on_dry_ground_is_left_exactly_where_it_lies() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := _downed_ally(Vector2i(1, 0))
	# ONE landing, and it is the body's OWN cell -- which is what keeps every rescue before #116
	# bit-for-bit unchanged instead of quietly relocating bodies on dry land, and what makes
	# rescue_needs_a_pick false so the menu never opens a second step for them.
	var expected: Array[Vector2i] = [Vector2i(1, 0)]
	assert_that(RulesService.rescue_landings(rescuer, ally, _board())).is_equal(expected)
	assert_bool(RulesService.rescue_needs_a_pick(ally, _board())).is_false()


func test_a_body_in_deep_water_is_pulled_to_a_cell_beside_the_rescuer() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	_flood([Vector2i(1, 0)])
	var ally := _downed_ally(Vector2i(1, 0))
	var landings := RulesService.rescue_landings(rescuer, ally, _board())
	# EVERY dry neighbour of the rescuer, not one. The player is choosing now (#116), so a rule that
	# still answered with a single pick would leave most of the flash unreachable — and the count is
	# derived from the geometry this case paints, not pinned as a magic number.
	assert_int(landings.size()) \
		.override_failure_message("the rescuer has dry ground on three sides and the body on the fourth") \
		.is_equal(3)
	for cell: Vector2i in landings:
		assert_int(GridUtils.manhattan_distance(cell, rescuer.movement.cell)).is_equal(1)
		assert_bool(_board().is_walkable(cell)) \
			.override_failure_message("offered ground the body still cannot stand on").is_true()
	assert_bool(RulesService.rescue_needs_a_pick(ally, _board())) \
		.override_failure_message("a haul must ASK, even when the answer looks obvious").is_true()


func test_a_body_nobody_can_pull_out_offers_NOTHING() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	# Every cell the rescuer could drag it to is water too, so there is nowhere to put it.
	_flood([Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)])
	var ally := _downed_ally(Vector2i(1, 0))
	assert_bool(RulesService.rescue_landings(rescuer, ally, _board()).is_empty()).is_true()


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



# --- The wire: the STAMP is published, so the board draws what the PLAYER chose -----------------

# Deliberately NOT first in NEIGHBOURS declaration order — (0,-1) is — so a publication that
# re-derived instead of reading the order's own stamp would land elsewhere and every case below
# would notice. That is the whole difference between "the rule picks" and "the player picks" (#116).
const CHOSEN_BANK := Vector2i(-1, 0)


func test_a_queued_rescue_draws_the_body_on_the_CHOSEN_bank_before_execute() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	_flood([Vector2i(1, 0)])
	var ally := _downed_ally(Vector2i(1, 0))
	_queue_rescue(rescuer, ally, CHOSEN_BANK)
	_sm.resolve_plan(rescuer.squad, _board())

	assert_bool(ally.get_projected_destination() == CHOSEN_BANK) \
		.override_failure_message("the board is not drawing the cell the player picked — either "
			+ "nothing was published (the body jumps on Execute, the divergence Law #2 forbids) or "
			+ "the resolve re-derived a bank of its own").is_true()
	# The point of publishing at all: the cell reads OCCUPIED, so nothing else is ordered onto it.
	assert_object(_board().projected_unit_at_cell(CHOSEN_BANK)).is_same(ally)


func test_a_dry_land_rescue_publishes_nothing() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := _downed_ally(Vector2i(1, 0))
	_queue_rescue(rescuer, ally, ally.get_projected_destination())
	_sm.resolve_plan(rescuer.squad, _board())
	assert_bool(ally.get_projected_destination() == Vector2i(1, 0)) \
		.override_failure_message("an ordinary rescue must move nobody").is_true()


func test_the_publication_is_cleared_and_recomputed_each_resolve() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	_flood([Vector2i(1, 0)])
	var ally := _downed_ally(Vector2i(1, 0))
	_queue_rescue(rescuer, ally, CHOSEN_BANK)
	_sm.resolve_plan(rescuer.squad, _board())
	# Resolving again must reach the SAME answer. It only can if the clear ran: rescue_landings reads
	# the body's PROJECTED cell, so a haul left standing is read back as where the body already is —
	# which would freeze the legality check at last pass's bank the moment the rescuer re-plans.
	_sm.resolve_plan(rescuer.squad, _board())
	assert_bool(ally.get_projected_destination() == CHOSEN_BANK).is_true()
	assert_bool(ally.movement.cell == Vector2i(1, 0)) \
		.override_failure_message("publishing must not MOVE the body — only execution does").is_true()


# --- A stamp the plan can no longer honour goes RED ---------------------------------------------

func test_a_stamp_that_is_no_longer_a_legal_bank_reds_the_row() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	_flood([Vector2i(1, 0)])
	var ally := _downed_ally(Vector2i(1, 0))
	# A cell nowhere near the rescuer — what a re-planned move leaves behind. NOT relocated silently:
	# the player chose this bank deliberately, so CaptureAction's frozen-stamp ruling applies and the
	# order reds while staying queued (one-way validity).
	var rescue := _queue_rescue(rescuer, ally, Vector2i(5, 5))
	var plan := _sm.resolve_plan(rescuer.squad, _board())
	_sm.validate_squad_plan(rescuer.squad, plan)

	assert_bool(rescue.is_valid) \
		.override_failure_message("a stranded stamp must red the row, not be quietly moved").is_false()
	assert_bool(ally.get_projected_destination() == Vector2i(1, 0)) \
		.override_failure_message("an illegal stamp must not be DRAWN either — the board would be "
			+ "promising a bank the plan cannot reach").is_true()


# --- Execution replays the stamp ----------------------------------------------------------------

func test_executing_the_rescue_drags_the_body_onto_the_CHOSEN_bank_and_revives_it() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	_flood([Vector2i(1, 0)])
	var ally := _downed_ally(Vector2i(1, 0))
	var rescue := _queue_rescue(rescuer, ally, CHOSEN_BANK)
	_sm.resolve_plan(rescuer.squad, _board())

	rescue.execute()

	# Against the LITERAL the player picked, never against the published cell. The previous form of
	# this assertion read the same store execution replays, so it agreed with itself whenever nothing
	# was published (measured, against the no-publication mutant) — a consistency check wearing a
	# correctness check's name.
	assert_bool(ally.movement.cell == CHOSEN_BANK) \
		.override_failure_message("execution landed the body somewhere the player never picked") \
		.is_true()
	assert_bool(ally.is_active()).is_true()
	assert_bool(_board().is_walkable(ally.movement.cell)) \
		.override_failure_message("revived still standing in the lake").is_true()


func test_executing_a_dry_land_rescue_moves_nobody() -> void:
	var rescuer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := _downed_ally(Vector2i(1, 0))
	var rescue := _queue_rescue(rescuer, ally, ally.get_projected_destination())
	_sm.resolve_plan(rescuer.squad, _board())

	rescue.execute()

	assert_bool(ally.movement.cell == Vector2i(1, 0)).is_true()
	assert_bool(ally.is_active()).is_true()
