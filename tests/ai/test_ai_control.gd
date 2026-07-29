# AIController toggles + the group-move zone clamp (#29). The toggle contract backs the
# Crisis auto-yes gate and the dev-console checkboxes: default OFF, per-faction, session-only.
# The clamp contract backs the Sentry leash: no squadmate may be assigned a cell outside
# `allowed_cells`, and a member parked on a dis-allowed cell must step back inside.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")
const F := preload("res://tests/support/job_fixtures.gd")

# Scout's ability_pool is forced to just WATERWALK for the duration of every test here (mirrors
# tests/rules/test_movement_cost.gd), so the #115 traversal case stays correct regardless of
# Scout's real authored kit. Harmless to the other tests — none of them assigns a job.
var _scout: JobData
var _scout_snap: Dictionary

func before_test() -> void:
	_scout = JobCatalog.get_job("scout")
	_scout_snap = F.snapshot(_scout)
	var ability := AbilityData.new()
	ability.id = Abilities.Id.WATERWALK
	_scout.ability_pool = [ability]

func after_test() -> void:
	F.restore(_scout, _scout_snap)


# --- AIController enable toggles ---

func test_factions_default_to_manual_control() -> void:
	var controller: AIController = auto_free(AIController.new())
	for faction in Team.all_factions():
		assert_bool(controller.is_ai_faction(faction)).is_false()


func test_toggle_is_per_faction() -> void:
	var controller: AIController = auto_free(AIController.new())
	controller.set_faction_ai_enabled(Team.Faction.ENEMY, true)

	assert_bool(controller.is_ai_faction(Team.Faction.ENEMY)).is_true()
	assert_bool(controller.is_ai_faction(Team.Faction.PLAYER)).is_false()

	controller.set_faction_ai_enabled(Team.Faction.ENEMY, false)
	assert_bool(controller.is_ai_faction(Team.Faction.ENEMY)).is_false()


func test_archetype_resolution_falls_back_to_default() -> void:
	# FACTION_DEFAULT is a sentinel, not an implementation -- it must resolve to a callable.
	assert_bool(AIArchetype.resolve(AIArchetype.Type.FACTION_DEFAULT).is_valid()).is_true()
	for archetype_value in AIArchetype.Type.values():
		assert_bool(AIArchetype.resolve(archetype_value).is_valid()).is_true()


# --- GroupMoveSolver.plan allowed_cells clamp ---

func _build_squad_board() -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, Rect2i(0, 0, 8, 3))

	var leader: Unit = BB.spawn(board, H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(0, 0))
	leader.equipped_weapon = H.make_weapon()
	var member: Unit = BB.spawn(board, H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(1, 0))
	member.equipped_weapon = H.make_weapon()
	board.squad_manager.join_squad(member, leader.squad)

	board["leader"] = leader
	board["member"] = member
	return board


func _context(board: Dictionary) -> BoardContext:
	var units: Array[Unit] = []
	for child in board.units_root.get_children():
		units.append(child as Unit)
	return BoardContext.new(board.grid, units, board.squad_manager)


func test_group_move_members_stay_inside_allowed() -> void:
	var board: Dictionary = _build_squad_board()
	var leader: Unit = board.leader

	# Unclamped, the member (displacement +3) would chase (4,0); the clamp excludes it.
	var allowed := {
		Vector2i(0, 0): true, Vector2i(1, 0): true, Vector2i(2, 0): true,
		Vector2i(3, 0): true, Vector2i(3, 1): true,
	}
	var moves: Array[MoveAction] = GroupMoveSolver.plan(leader.squad, Vector2i(3, 0), _context(board), allowed)

	assert_int(moves.size()).is_equal(2)   # leader + member both got destinations
	for move in moves:
		assert_bool(allowed.has(move.destination)).is_true()


func test_group_move_member_on_disallowed_cell_steps_inside() -> void:
	var board: Dictionary = _build_squad_board()
	var leader: Unit = board.leader
	var member: Unit = board.member

	# The member's own cell (1,0) is NOT allowed -> its stay-put candidate is dropped, so it
	# must be assigned a move into the allowed set rather than idling outside it.
	var allowed := { Vector2i(0, 0): true, Vector2i(2, 0): true, Vector2i(3, 0): true }
	var moves: Array[MoveAction] = GroupMoveSolver.plan(leader.squad, Vector2i(3, 0), _context(board), allowed)

	var member_moves: Array[MoveAction] = []
	for move in moves:
		if move.actor == member:
			member_moves.append(move)
	assert_int(member_moves.size()).is_equal(1)
	assert_bool(allowed.has(member_moves[0].destination)).is_true()
	assert_that(member_moves[0].destination).is_not_equal(Vector2i(1, 0))


func test_group_move_unclamped_is_unchanged() -> void:
	var board: Dictionary = _build_squad_board()
	var leader: Unit = board.leader
	var member: Unit = board.member

	# Default (null) clamp: the member preserves its +1 offset behind the leader.
	var moves: Array[MoveAction] = GroupMoveSolver.plan(leader.squad, Vector2i(3, 0), _context(board))

	assert_int(moves.size()).is_equal(2)
	var member_destination := Vector2i(-1, -1)
	for move in moves:
		if move.actor == member:
			member_destination = move.destination
	assert_that(member_destination).is_equal(Vector2i(4, 0))


# --- GroupMoveSolver BFS bounds (perf fix 2026-07-26) ---
# The solver stopped walking the whole board for every member. Both stopping rules must only skip
# work whose answer was going to be discarded, so a bounded walk has to agree with a full one
# everywhere it reports at all. These pin that; if they drift, formations change silently.

func test_depth_bounded_field_agrees_with_the_full_walk() -> void:
	var board: Dictionary = _build_squad_board()
	var context := _context(board)
	var source := Vector2i(0, 0)

	var walker: Unit = board.leader
	var full: Dictionary = GroupMoveSolver._path_hops(source, context, walker)
	var bounded: Dictionary = GroupMoveSolver._path_hops(source, context, walker, 3)

	assert_int(bounded.size()).is_less(full.size())   # it really did stop early
	for cell in bounded:
		assert_int(bounded[cell]).is_equal(full[cell])
		assert_int(bounded[cell]).is_less_equal(3)
	# Nothing within the bound may be missing.
	for cell in full:
		if full[cell] <= 3:
			assert_bool(bounded.has(cell)).is_true()


func test_until_bounded_field_covers_every_requested_cell() -> void:
	var board: Dictionary = _build_squad_board()
	var context := _context(board)
	var source := Vector2i(0, 0)
	var walker: Unit = board.leader
	var full: Dictionary = GroupMoveSolver._path_hops(source, context, walker)

	var wanted := { Vector2i(2, 0): true, Vector2i(1, 1): true }
	var bounded: Dictionary = GroupMoveSolver._path_hops(source, context, walker, -1, wanted)

	for cell in wanted:
		assert_bool(bounded.has(cell)).is_true()
		assert_int(bounded[cell]).is_equal(full[cell])


func test_until_falls_back_to_the_full_walk_when_a_cell_is_unreachable() -> void:
	# An unreachable request can never satisfy the stop condition; the walk must terminate anyway
	# rather than spin, and still answer correctly for everything it did reach.
	var board: Dictionary = _build_squad_board()
	var context := _context(board)
	var source := Vector2i(0, 0)

	var walker: Unit = board.leader
	var wanted := { Vector2i(99, 99): true }
	var bounded: Dictionary = GroupMoveSolver._path_hops(source, context, walker, -1, wanted)

	assert_bool(bounded.has(Vector2i(99, 99))).is_false()
	assert_int(bounded.size()).is_equal(GroupMoveSolver._path_hops(source, context, walker).size())


# --- #115: the cohesion field is per-unit, not per-cell ---

func test_hop_field_crosses_water_only_for_a_waterwalker() -> void:
	# The leash field used to be built once from the bare cell predicate and shared by every
	# member, which silently un-did Waterwalk: a Scout's own `reach` correctly included near-shore
	# water, then the leash rejected exactly those cells as UNREACHABLE. So the ability worked when
	# the unit moved alone and stopped working the moment it moved with its squad.
	var board: Dictionary = _build_squad_board()
	for y in range(0, 3):
		BB.paint_cell(board.grid, Vector2i(4, y), BB.WATER_ATLAS)   # a full-height wall of water
	var context := _context(board)

	var plain: Unit = board.leader
	var walker: Unit = board.member
	walker.unit_instance.add_job("scout")

	var plain_field: Dictionary = GroupMoveSolver._path_hops(Vector2i(0, 0), context, plain)
	var walker_field: Dictionary = GroupMoveSolver._path_hops(Vector2i(0, 0), context, walker)

	assert_bool(plain_field.has(Vector2i(4, 0))).is_false()    # the water itself
	assert_bool(plain_field.has(Vector2i(6, 0))).is_false()    # and everything behind it
	assert_bool(walker_field.has(Vector2i(4, 0))).is_true()
	assert_bool(walker_field.has(Vector2i(6, 0))).is_true()


func test_an_enemy_body_does_not_sever_the_cohesion_field() -> void:
	# _path_hops asks can_traverse, NOT movement_cost — occupancy blocks a move but is not terrain,
	# and it moves every turn. Pinned because routing the field through movement_cost is the
	# obvious-looking simplification and it would quietly change formations near any enemy.
	var board: Dictionary = _build_squad_board()
	BB.spawn(board, H.make_unit_data({}, Team.Faction.PLAYER), Vector2i(4, 0))   # hostile to the ENEMY squad
	var context := _context(board)

	var field: Dictionary = GroupMoveSolver._path_hops(Vector2i(0, 0), context, board.leader)

	assert_bool(field.has(Vector2i(4, 0))).is_true()
	assert_bool(field.has(Vector2i(6, 0))).is_true()
