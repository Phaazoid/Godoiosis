# A whole BOARD round-trips through capture_scenario/apply_scenario (#87) — the layer above
# test_battle_state_snapshot.gd, which pins one unit's entry in isolation.
#
# It needs the real game scene, because the two things tested here have no per-unit entry to live
# on: squad has_acted (a Squad field, saved on the leader's entry) and MissionController's progress
# latches (captured zones, `contested`). Both are only reachable through a real ScenarioManager
# with a real MissionController beside it — and load_scenario's ordering constraints (spawn ->
# apply_unit_state -> rebuild squads -> mark spent) only exist at this layer.
#
# No disk. capture_scenario/apply_scenario were split out of save_scenario/load_scenario precisely
# so this suite can round-trip in memory: writing a test .tres into res://Scenarios/ would be
# picked up by the Mission Select list and by test_scenario_load_integrity.gd's folder scan.
#
# Fixture is the #114 one — the instanced root MUST be named "Main" under /root, or game.gd's
# absolute /root/Main/DevOverlay lookup returns null and clear_board() dies on it.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

var _main: Node
var game: Node2D
var mc: MissionController
var sm: ScenarioManager


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	mc = game.mission_controller
	sm = game.scenario_manager
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()   # off-map or unwalkable cell — the test's own setup is wrong
	return unit


# Snapshot the live board and rebuild it from that snapshot. Everything a real Save + Load does
# except touching the filesystem.
func _round_trip() -> void:
	var snapshot: ScenarioData = sm.capture_scenario("__round_trip")
	sm.apply_scenario(snapshot)


func _units() -> Array:
	return game.units_root.get_children()


func _unit_at(cell: Vector2i) -> Unit:
	for unit: Unit in _units():
		if unit.movement.cell == cell:
			return unit
	return null


# ==============================================================================
#  The split itself
# ==============================================================================

func test_a_board_survives_a_round_trip_at_all() -> void:
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.ENEMY, Vector2i(4, 4))

	_round_trip()

	assert_int(_units().size()).is_equal(2)
	assert_object(_unit_at(Vector2i(1, 1))).is_not_null()
	assert_object(_unit_at(Vector2i(4, 4))).is_not_null()


# ==============================================================================
#  Squad has_acted
# ==============================================================================

func test_a_spent_squad_reloads_spent() -> void:
	# Without this, a mid-turn save hands every squad that already moved a second turn — the
	# lopsided-snapshot failure #87 exists to prevent, one layer up from weapon charge.
	var leader := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	game.squad_manager.set_has_acted(leader.squad, true)

	_round_trip()

	assert_bool(_unit_at(Vector2i(1, 1)).squad.has_acted).is_true()


func test_an_unspent_squad_reloads_unspent() -> void:
	var leader := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	assert_bool(leader.squad.has_acted).is_false()

	_round_trip()

	assert_bool(_unit_at(Vector2i(1, 1)).squad.has_acted).is_false()


func test_a_spent_squad_reloads_with_its_members_still_joined() -> void:
	# has_acted and squad MEMBERSHIP have to survive together. The loader joins through the
	# ungated join_squad, so marking a squad spent mid-assembly would not break it today — this is
	# a forward guard, deliberately stated: the player-facing formation path DOES refuse an acted
	# squad, so if the loader is ever routed through it, this is the case that catches it.
	var leader := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var member := _spawn(Team.Faction.PLAYER, Vector2i(2, 1))
	game.squad_manager.join_squad(member, leader.squad)
	leader.squad.squad_name = "Vanguard"
	game.squad_manager.set_has_acted(leader.squad, true)

	_round_trip()

	var loaded_leader := _unit_at(Vector2i(1, 1))
	var loaded_member := _unit_at(Vector2i(2, 1))
	assert_object(loaded_leader.squad).is_same(loaded_member.squad)
	assert_int(loaded_leader.squad.get_members().size()).is_equal(2)
	assert_str(loaded_leader.squad.squad_name).is_equal("Vanguard")
	assert_bool(loaded_leader.squad.has_acted).is_true()


# ==============================================================================
#  Mission progress — the board-wide latches
# ==============================================================================

func test_a_captured_zone_stays_captured() -> void:
	# clear_board() -> reset() wipes captured zones on every load; restore_progress is what puts a
	# snapshot's progress back over that blank slate. Without it, reloading mid-mission silently
	# un-takes every objective the player has already paid for.
	game.zone_manager.paint_cell("Point", ZoneManager.Kind.CAPTURE, Vector2i(2, 2))
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.CAPTURE]
	mc.set_objectives(objectives)
	mc.capture("Point")
	assert_bool(mc.is_zone_captured("Point")).is_true()

	_round_trip()

	assert_bool(mc.is_zone_captured("Point")).is_true()
	assert_array(mc.objectives).contains_exactly([MissionRules.Objective.CAPTURE])


func test_an_uncaptured_zone_stays_uncaptured() -> void:
	game.zone_manager.paint_cell("Point", ZoneManager.Kind.CAPTURE, Vector2i(2, 2))
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.CAPTURE]
	mc.set_objectives(objectives)

	_round_trip()

	assert_bool(mc.is_zone_captured("Point")).is_false()


func test_the_contested_latch_survives_so_a_won_mission_can_still_end() -> void:
	# The latch exists because the board FORGETS: present_factions drops a wiped side, so a live
	# read goes false at the exact moment a mission should end. Reload after the last enemy falls
	# with the latch reset and the mission becomes unwinnable — check() can never fire again.
	var player := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var enemy := _spawn(Team.Faction.ENEMY, Vector2i(4, 4))
	mc.check()                       # latches contested while both stand
	assert_bool(mc.is_contested()).is_true()
	enemy.die()
	await await_idle_frame()

	_round_trip()

	assert_bool(mc.is_contested()).is_true()
	assert_object(player).is_not_null()
	mc.check()
	assert_that(mc.outcome).is_equal(MissionRules.Outcome.VICTORY)


func test_a_fresh_board_is_not_contested() -> void:
	# The default direction: an authored mission records nothing here, so a load leaves reset()'s
	# blank slate alone. This is what keeps a dev sandbox board inert.
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))

	_round_trip()

	assert_bool(mc.is_contested()).is_false()


# ==============================================================================
#  Who the computer plays (#150)
# ==============================================================================

func test_ai_factions_survive_a_round_trip() -> void:
	# Before #150 the flags were session-only, so a board could not say who the computer played --
	# which is why an authored mission handed the player its own enemies.
	var controller: AIController = game.ai_controller
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.ENEMY, Vector2i(4, 4))
	controller.set_faction_ai_enabled(Team.Faction.ENEMY, true)

	_round_trip()

	assert_bool(controller.is_ai_faction(Team.Faction.ENEMY)).is_true()
	assert_bool(controller.is_ai_faction(Team.Faction.PLAYER)).is_false()


func test_loading_a_board_that_declares_no_ai_turns_a_live_faction_OFF() -> void:
	# The apply must REPLACE the set, not merge into it. Merged, a faction ticked on the previous
	# board stays AI-controlled on the next one -- and the flag decides three things beyond whose
	# turn it is (concede-vs-hand-back on an invalid plan, and the Crisis prompt), so the leak would
	# not read as "the AI moved", it would read as the player's own prompt silently not appearing.
	var controller: AIController = game.ai_controller
	_spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var snapshot: ScenarioData = sm.capture_scenario("__no_ai")   # captured while everything is manual
	assert_array(snapshot.ai_factions).is_empty()

	controller.set_faction_ai_enabled(Team.Faction.ENEMY, true)
	sm.apply_scenario(snapshot)

	assert_bool(controller.is_ai_faction(Team.Faction.ENEMY)).is_false()


func test_a_squads_archetype_survives_a_round_trip() -> void:
	# The other half of #150. It was already captured (on the leader's entry) and already applied,
	# but nothing in tests/ asserted it -- so the half that worked was as unpinned as the half
	# that didn't.
	var leader := _spawn(Team.Faction.ENEMY, Vector2i(4, 4))
	leader.squad.archetype = AIArchetype.Type.SENTRY

	_round_trip()

	assert_that(_unit_at(Vector2i(4, 4)).squad.archetype).is_equal(AIArchetype.Type.SENTRY)


# ==============================================================================
#  Unit battle state, through the REAL loader
# ==============================================================================

func test_a_downed_unit_reloads_downed_through_the_real_loader() -> void:
	# test_battle_state_snapshot.gd pins the entry; this pins the whole path, including that a
	# restore does not re-enter the went_downed -> OrderExecutor.on_unit_downed wire game.spawn_unit
	# connects. Re-firing it would queue an ejection for a unit that was never downed this session.
	var player := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	_spawn(Team.Faction.ENEMY, Vector2i(4, 4))
	player.take_damage(player.get_current_hp())   # exactly lethal = the DOWN rung; more would overkill
	assert_bool(player.is_downed()).is_true()
	await await_idle_frame()   # the went_downed wire ejects the unit from its squad at pass end

	_round_trip()

	var loaded := _unit_at(Vector2i(1, 1))
	assert_object(loaded).is_not_null()
	assert_bool(loaded.is_downed()).is_true()
	assert_int(loaded.downed_turns_remaining).is_equal(3)


func test_a_carried_weapons_battle_state_reloads_through_the_real_loader() -> void:
	var player := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.KINETIC_MACE
	template.main_attack = WeaponAttackData.new()
	var mace := WeaponInstance.make(template) as KineticMaceWeaponInstance
	player.add_item(mace)
	mace.charge = 2

	_round_trip()

	var loaded := _unit_at(Vector2i(1, 1))
	assert_int((loaded.inventory[0] as KineticMaceWeaponInstance).charge).is_equal(2)
