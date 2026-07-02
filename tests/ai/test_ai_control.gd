# AIController toggles + the group-move zone clamp (#29). The toggle contract backs the
# Crisis auto-yes gate and the dev-console checkboxes: default OFF, per-faction, session-only.
# The clamp contract backs the Sentry leash: no squadmate may be assigned a cell outside
# `allowed_cells`, and a member parked on a dis-allowed cell must step back inside.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")


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


# --- plan_group_move allowed_cells clamp ---

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
	var moves: Array[MoveAction] = board.squad_manager.plan_group_move(leader.squad, Vector2i(3, 0), _context(board), allowed)

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
	var moves: Array[MoveAction] = board.squad_manager.plan_group_move(leader.squad, Vector2i(3, 0), _context(board), allowed)

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
	var moves: Array[MoveAction] = board.squad_manager.plan_group_move(leader.squad, Vector2i(3, 0), _context(board))

	assert_int(moves.size()).is_equal(2)
	var member_destination := Vector2i(-1, -1)
	for move in moves:
		if move.actor == member:
			member_destination = move.destination
	assert_that(member_destination).is_equal(Vector2i(4, 0))
