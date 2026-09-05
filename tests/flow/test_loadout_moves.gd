# #741: the pre-mission phase's live gear, and every way it moves. Four directions -- stash to unit,
# unit to stash, unit to unit, and the no-op back where it started -- are ONE function taking owners,
# with null meaning the stash at either end.
#
# The case that matters most is the stash's PROVENANCE. Before this, PreMissionScreen read
# `roster.stash` off whatever RosterCatalog.resolve() returned, which is Godot's resource CACHE --
# so the first item moved out would have depleted the authored Roster for the rest of the session.
# Nothing on disk was ever at risk (nothing saves a roster); the cached object was, and that is what
# test_the_phases_stash_is_a_copy asks about.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const SCRATCH := "user://__loadout_741.tres"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const ROW_WIDTH := 10
const ZONE_CELLS := 6

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController


func before_test() -> void:
	_main = (load("res://Scenes/Main.tscn") as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	mc = game.mission_controller
	sm = game.scenario_manager
	mc._close_mission_select()
	sm.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _roster_name() -> String:
	var names: Array[String] = RosterCatalog.saved_rosters()
	return "" if names.is_empty() else names[0]


func _author(roster: String, cap: int) -> String:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	sm.current_roster = roster
	sm.current_deployment_cap = cap
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT]
	mc.set_objectives(objectives)
	var scenario := sm.capture_scenario("loadout_741", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


func _enter_phase(cap := 2) -> bool:
	var roster := _roster_name()
	if roster == "":
		push_warning("no rosters are shipped, so the loadout cannot be exercised")
		return false
	mc.begin_mission(_author(roster, cap))
	await await_idle_frame()
	return mc.is_deploying()


func _a_unit() -> Unit:
	var units := mc.roster_units()
	return null if units.is_empty() else units[0]


func _sword() -> WeaponInstance:
	var weapon := WeaponInstance.new()
	weapon.display_name = "Test Sword"
	return weapon


func _held(unit: Unit) -> Array[String]:
	var names: Array[String] = []
	for item: Item in unit.inventory:
		if item != null:
			names.append(item.display_name)
	return names


# --- the four directions ---------------------------------------------------------------------

# One real sequence rather than four cases: stash -> unit -> another unit -> stash, asserting at every
# step that the source lost exactly what the destination gained. A move that COPIED instead of moving
# passes any single-ended assertion and fails here on the first hop.
func test_gear_makes_the_whole_round_trip_and_only_one_end_moves() -> void:
	if not await _enter_phase():
		return
	var units := mc.roster_units()
	if units.size() < 2:
		push_warning("the shipped roster has fewer than two members, so unit-to-unit cannot be walked")
		return
	var first: Unit = units[0]
	var second: Unit = units[1]
	var loadout := mc.loadout()

	var sword := _sword()
	loadout.stash.append(sword)
	var stash_before := loadout.stash.size()

	assert_str(loadout.move(sword, null, first)).override_failure_message(
		"stash -> unit was refused").is_empty()
	assert_int(loadout.stash.size()).override_failure_message(
		"the stash kept its copy -- a move that copies is two owners of one object").is_equal(stash_before - 1)
	assert_array(_held(first)).contains(["Test Sword"])

	assert_str(loadout.move(sword, first, second)).override_failure_message(
		"unit -> unit was refused").is_empty()
	assert_array(_held(first)).override_failure_message(
		"the giver kept it").not_contains(["Test Sword"])
	assert_array(_held(second)).contains(["Test Sword"])

	assert_str(loadout.move(sword, second, null)).override_failure_message(
		"unit -> stash was refused").is_empty()
	assert_array(_held(second)).not_contains(["Test Sword"])
	assert_int(loadout.stash.size()).override_failure_message(
		"the stash did not take it back").is_equal(stash_before)

	# ...and a drop back where it started is a no-op, not a refusal: the drag lands on its own row
	# constantly, and answering that with a red sentence would be noise.
	assert_str(loadout.move(sword, null, null)).is_empty()
	assert_int(loadout.stash.size()).is_equal(stash_before)


# Both refusals SPEAK, which is the whole reason Unit grew add_block_reason and remove_block_reason
# rather than this file re-asking is_installed_prosthetic and wording its own sentence.
func test_a_full_unit_and_a_fitted_limb_each_refuse_with_their_own_reason() -> void:
	if not await _enter_phase():
		return
	var unit := _a_unit()
	assert_object(unit).is_not_null()
	var loadout := mc.loadout()

	# Fill every slot, then offer a seventh.
	for i in range(Unit.MAX_INVENTORY_SIZE):
		if unit.inventory[i] == null:
			unit.inventory[i] = _sword()
	var spare := _sword()
	loadout.stash.append(spare)
	var refusal := loadout.move(spare, null, unit)
	assert_str(refusal).override_failure_message(
		"a seventh item was accepted into six slots").is_not_empty()
	assert_str(refusal).override_failure_message(
		"the refusal does not name who is full: %s" % refusal).contains(unit.get_unit_name())
	assert_bool(loadout.stash.has(spare)).override_failure_message(
		"a refused move still took the item out of the stash").is_true()

	# A fitted prosthetic lives IN the inventory and is not gear the player may trade away. Fitted
	# through the real door, so the case cannot pass against a hand-built fitting the game would
	# never produce.
	var arm := _prosthetic_arm()
	unit.inventory[0] = arm
	assert_bool(unit.unit_instance.install_prosthetic(UnitInstance.LimbSlot.ARM_L, arm)) 		.override_failure_message("fixture: the arm did not install").is_true()
	var limb_refusal := loadout.move(arm, unit, null)
	assert_str(limb_refusal).override_failure_message(
		"a fitted limb was traded away").is_not_empty()
	assert_bool(unit.inventory.has(arm)).override_failure_message(
		"the arm left the unit anyway").is_true()


func _prosthetic_arm() -> WeaponInstance:
	var template := WeaponData.new()
	template.display_name = "Test Arm"
	template.weapon_type = WeaponData.WeaponType.PROSTHETIC
	template.main_attack = WeaponAttackData.new()
	template.built_in_stat = 7
	return WeaponInstance.make(template)


# --- the stash's provenance -------------------------------------------------------------------

# THE CACHE, not the disk. Nothing ever saves a Roster, so the file was never at risk; what was at
# risk is the object RosterCatalog.resolve() hands back, which is Godot's resource cache and is the
# SAME object for every resolve in a session. Reading roster.stash directly -- which is what the
# screen did before this ticket -- meant the first move out of the stash depleted the authored roster
# for every mission after it, which is #731 ruling 3 broken by one drag.
func test_the_phases_stash_is_a_copy_and_the_cached_roster_never_moves() -> void:
	if not await _enter_phase():
		return
	var name := _roster_name()
	var authored: Roster = RosterCatalog.resolve(name)
	assert_object(authored).is_not_null()
	var authored_size := authored.stash.size()
	assert_int(authored_size).override_failure_message(
		"the shipped roster carries no stash, so this case cannot see the bug it exists for"
		).is_greater(0)

	var loadout := mc.loadout()
	assert_int(loadout.stash.size()).override_failure_message(
		"the phase did not take the roster's stash").is_equal(authored_size)
	assert_bool(loadout.stash[0] == authored.stash[0]).override_failure_message(
		"the phase holds the AUTHORED objects, so editing one edits the roster").is_false()

	var unit := _a_unit()
	assert_str(loadout.move(loadout.stash[0], null, unit)).is_empty()
	assert_int(loadout.stash.size()).is_equal(authored_size - 1)

	var still: Roster = RosterCatalog.resolve(name)
	assert_int(still.stash.size()).override_failure_message(
		"a move out of the phase's stash reached the cached authored roster").is_equal(authored_size)


# ...and the phase's gear dies with the phase, which is the other half of ruling 3: a second mission
# in the same session opens on the roster as authored, not on whatever the last one left behind.
func test_a_second_phase_opens_on_a_full_stash_again() -> void:
	if not await _enter_phase():
		return
	var full := mc.loadout().stash.size()
	assert_str(mc.loadout().move(mc.loadout().stash[0], null, _a_unit())).is_empty()
	assert_int(mc.loadout().stash.size()).is_equal(full - 1)

	mc.begin_mission(SCRATCH)
	await await_idle_frame()
	assert_int(mc.loadout().stash.size()).override_failure_message(
		"the next mission inherited the last one's depleted stash").is_equal(full)
