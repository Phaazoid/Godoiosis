# Regrouping (#1230): a loose enemy rejoins its old squad first, else the nearest with room, of its own
# archetype unless its profile joins any; loose units may form a squad together when both profiles
# allow it; and a stray with nobody to fight walks back towards the squad it would join. Every rule
# here is the dev's (2026-10-05, on #1230).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const ENEMY := Team.Faction.ENEMY
const PLAYER := Team.Faction.PLAYER


func before_test() -> void:
	AIProfiles.use_fixtures({"": AIProfile.new()})   # #1230: this suite owns its AI profile


func after_test() -> void:
	AIProfiles.clear_fixtures()


func _board(size := Rect2i(0, 0, 16, 4)) -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, size)
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i, stats := {}) -> Unit:
	var unit: Unit = BB.spawn(board, H.make_unit_data(stats, faction), cell)
	unit.equipped_weapon = H.make_weapon()
	return unit


func _ctx(board: Dictionary) -> BoardContext:
	return board.squad_manager.board_source.call()


func _sm(board: Dictionary) -> SquadManager:
	return board.squad_manager


func _regroup(board: Dictionary) -> int:
	return AIController.regroup(ENEMY, _sm(board), _ctx(board))


func _profile_off(knobs: Array) -> AIProfile:
	var profile := AIProfile.new()
	for knob: String in knobs:
		profile.set(knob, false)
	return profile


# Enough leadership for a squad of four (Squad.capacity_of), so a squad of two has room.
const ROOMY := {Stats.Stat.LDR: 6}


# L leads X and M; M is then ejected and stands at `stray_cell` remembering the squad it left.
func _old_squad_and_stray(board: Dictionary, stray_cell: Vector2i, archetype := AIArchetype.Type.FACTION_DEFAULT) -> Dictionary:
	var l := _spawn(board, ENEMY, Vector2i(0, 0), ROOMY)
	l.squad.archetype = archetype
	var x := _spawn(board, ENEMY, Vector2i(0, 1))
	var m := _spawn(board, ENEMY, stray_cell)
	_sm(board).join_squad(x, l.squad)
	_sm(board).join_squad(m, l.squad)
	_sm(board).eject(m, SquadManager.LeaveCause.FORCED)
	assert_object(m.left_squad).override_failure_message("fixture: eject did not remember the squad").is_same(l.squad)
	return {"l": l, "x": x, "m": m, "old": l.squad}


# A second squad of two whose leader stands one cell from the stray, nearer than its old leader.
func _nearer_squad(board: Dictionary, archetype := AIArchetype.Type.FACTION_DEFAULT) -> Squad:
	var l2 := _spawn(board, ENEMY, Vector2i(4, 0), ROOMY)
	l2.squad.archetype = archetype
	var y := _spawn(board, ENEMY, Vector2i(4, 1))
	_sm(board).join_squad(y, l2.squad)
	return l2.squad


# Fills `squad` to its capacity from the cells of column 1.
func _fill(board: Dictionary, squad: Squad) -> void:
	var y := 0
	while squad.get_members().size() < squad.max_size():
		_sm(board).join_squad(_spawn(board, ENEMY, Vector2i(1, y)), squad)
		y += 1
	assert_int(squad.get_members().size()).override_failure_message("fixture: the squad is not full") \
		.is_equal(squad.max_size())


# --- Which squad ----------------------------------------------------------------------------------

func test_a_stray_rejoins_its_old_squad_before_a_nearer_one() -> void:
	var board := _board()
	var s := _old_squad_and_stray(board, Vector2i(3, 0))
	var _other := _nearer_squad(board)
	_regroup(board)
	assert_object((s.m as Unit).squad).override_failure_message("the stray joined the nearer squad first") \
		.is_same(s.old)


func test_with_its_old_squad_full_a_stray_joins_the_nearest_with_room() -> void:
	var board := _board()
	var s := _old_squad_and_stray(board, Vector2i(3, 0))
	_fill(board, s.old)
	var other := _nearer_squad(board)
	_regroup(board)
	assert_object((s.m as Unit).squad).is_same(other)


func test_a_stray_does_not_join_a_squad_of_another_archetype() -> void:
	var board := _board()
	var s := _old_squad_and_stray(board, Vector2i(3, 0))
	_fill(board, s.old)
	var _other := _nearer_squad(board, AIArchetype.Type.HOLD)
	assert_int(_regroup(board)).is_equal(0)
	assert_int((s.m as Unit).squad.get_members().size()).is_equal(1)


func test_the_toggle_lets_a_stray_join_another_archetype() -> void:
	var flexible := AIProfile.new()
	flexible.joins_any_archetype = true
	AIProfiles.use_fixtures({"": flexible})
	var board := _board()
	var s := _old_squad_and_stray(board, Vector2i(3, 0))
	_fill(board, s.old)
	var other := _nearer_squad(board, AIArchetype.Type.HOLD)
	_regroup(board)
	assert_object((s.m as Unit).squad).is_same(other)


# squads_up stays on, so the pass still asks about this stray and only regroups refuses the old squad.
func test_a_unit_that_does_not_regroup_stays_alone() -> void:
	AIProfiles.use_fixtures({"": _profile_off(["regroups"])})
	var board := _board()
	var s := _old_squad_and_stray(board, Vector2i(3, 0))
	assert_int(_regroup(board)).is_equal(0)
	assert_object((s.m as Unit).squad).is_not_same(s.old)


# --- Forming a squad ----------------------------------------------------------------------------------

# The higher leadership stands FIRST in board order, so the first stray the pass reaches is the one that
# must not join -- a rule that let either stray join the other would put it under the weaker leader.
func test_two_strays_form_a_squad_and_the_higher_leadership_leads() -> void:
	var board := _board()
	var leader := _spawn(board, ENEMY, Vector2i(0, 0), {Stats.Stat.LDR: 8})
	var follower := _spawn(board, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 5})
	assert_int(_regroup(board)).is_equal(1)
	assert_object(follower.squad).is_same(leader.squad)
	assert_bool(leader.is_leader()).override_failure_message("the lower leadership ended up leading").is_true()


func test_strays_do_not_form_a_squad_unless_both_profiles_allow_it() -> void:
	AIProfiles.use_fixtures({"": AIProfile.new(), "Loner": _profile_off(["squads_up"])})
	var board := _board()
	var loner := _spawn(board, ENEMY, Vector2i(0, 0), {Stats.Stat.LDR: 8})
	loner.ai_profile = "Loner"
	var other := _spawn(board, ENEMY, Vector2i(1, 0), {Stats.Stat.LDR: 5})
	assert_int(_regroup(board)).is_equal(0)
	assert_object(other.squad).is_not_same(loner.squad)


# destroy_empty_squad frees on the frame's end, so in the frame its last member leaves the squad is
# still a valid instance with nobody in it. The stray must never be put into it.
func test_a_stray_is_never_put_into_a_squad_that_is_being_freed() -> void:
	var board := _board()
	var l := _spawn(board, ENEMY, Vector2i(0, 0))
	var m := _spawn(board, ENEMY, Vector2i(1, 0))
	_sm(board).join_squad(m, l.squad)
	var old: Squad = l.squad
	_sm(board).eject(m, SquadManager.LeaveCause.FORCED)
	_sm(board).eject(l, SquadManager.LeaveCause.FORCED)
	assert_bool(old.is_queued_for_deletion()).override_failure_message(
			"fixture: the old squad should be freeing this frame").is_true()

	_regroup(board)

	assert_object(m.squad).override_failure_message("the stray was put into the squad being freed").is_not_same(old)
	assert_bool(is_instance_valid(m.squad) and not m.squad.is_queued_for_deletion()).is_true()


# --- The walk back --------------------------------------------------------------------------------

# The old squad at the west end, the stray in the middle, an enemy far off to the east and out of reach.
func _walk_board(archetype := AIArchetype.Type.FACTION_DEFAULT, foe_x := 23) -> Dictionary:
	var board := _board(Rect2i(0, 0, 24, 4))
	var s := _old_squad_and_stray(board, Vector2i(12, 1), archetype)
	var foe := _spawn(board, PLAYER, Vector2i(foe_x, 1), {Stats.Stat.MHP: 40})
	s["board"] = board
	s["foe"] = foe
	return s


func _plan(board: Dictionary, unit: Unit) -> void:
	AIController.plan_squad(unit.squad, _ctx(board), _sm(board))


func test_an_idle_stray_walks_back_towards_its_squad_instead_of_pursuing() -> void:
	var s := _walk_board()
	var m: Unit = s.m
	_plan(s.board, m)
	assert_int(m.get_projected_destination().x).override_failure_message(
			"the stray pursued the far enemy instead of walking back (%s)" % [m.get_projected_destination()]) \
		.is_less(12)


func test_a_stray_that_does_not_regroup_pursues_as_ever() -> void:
	AIProfiles.use_fixtures({"": _profile_off(["regroups", "squads_up"])})
	var s := _walk_board()
	var m: Unit = s.m
	_plan(s.board, m)
	assert_int(m.get_projected_destination().x).is_greater(12)


func test_a_stray_that_can_attack_still_attacks() -> void:
	var s := _walk_board(AIArchetype.Type.FACTION_DEFAULT, 14)
	var m: Unit = s.m
	_plan(s.board, m)
	var attacked := false
	for action in m.squad.action_queue:
		attacked = attacked or (action is AttackAction and action.actor == m)
	assert_bool(attacked).override_failure_message("a stray with someone in reach walked back instead").is_true()


func test_a_hold_stray_never_walks() -> void:
	var s := _walk_board(AIArchetype.Type.HOLD)
	var m: Unit = s.m
	_plan(s.board, m)
	assert_that(m.get_projected_destination()).is_equal(m.movement.cell)


func test_a_rushdown_stray_still_walks_at_a_defended_point() -> void:
	var s := _walk_board()
	var board: Dictionary = s.board
	(board.zone_manager as ZoneManager).paint_cell("Cargo", ZoneManager.Kind.DEFEND, Vector2i(20, 1))
	var m: Unit = s.m
	_plan(board, m)
	assert_int(m.get_projected_destination().x).override_failure_message(
			"the stray walked back to its squad instead of at the cargo").is_greater(12)


# --- Both walks regroup ---------------------------------------------------------------------------

func test_the_headless_play_api_regroups_before_its_squads_plan() -> void:
	var board := _board()
	var a := _spawn(board, ENEMY, Vector2i(0, 0), {Stats.Stat.LDR: 8})
	var b := _spawn(board, ENEMY, Vector2i(1, 0))
	var _far := _spawn(board, PLAYER, Vector2i(15, 3), {Stats.Stat.MHP: 40})
	var session = PlaySession.new(board)
	session._take_ai_turn(ENEMY)
	assert_object(b.squad).override_failure_message("the Play API's AI turn never regrouped").is_same(a.squad)
