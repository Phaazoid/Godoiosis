# The board lint (#390) — "is this board actually playable?", asked of a LIVE board.
#
# Two kinds of case.
#
# The TEETH cases build each fault the way an author reaches it and assert the lint names it. Every
# one of them has a non-vacuous twin (fix the fault, the finding goes) because a lint that reports
# unconditionally passes exactly the same assertions as a lint that reports correctly. The
# placement case is the one worth reading twice: it PAINTS OVER a unit that was legally placed,
# because that is the only route into the state — spawn_unit refuses both halves at placement time.
#
# The LAW cases run the same lint over every shipped mission, and they are what replaces
# test_every_mission_with_enemies_declares_them_ai_controlled in tests/flow/test_scenario_load_integrity.gd.
# One of them is not a lint case at all: `no shipped mission loses a unit on load` asks the FILE-shaped
# half of the placement question, which the lint structurally cannot answer. apply_scenario drops a
# unit whose cell spawn refuses and only push_warnings about it, so by the time a lint sees a
# reloaded board the evidence is gone — the only thing left to compare is how many units came back.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const ROCK_ATLAS := Vector2i(18, 10)   # "rock": declares no `walkable` custom data, so it reads false
const ROW_WIDTH := 12                  # wider than COH (4), so the cohesion case has somewhere to stand

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	# clear_board leaves the TILEMAP alone, so Main.tscn's own terrain is still under us; this row
	# is the known-walkable strip every case below places on.
	for x in range(ROW_WIDTH):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# --- helpers -------------------------------------------------------------------------------------

func _spawn(faction: Team.Faction, x: int) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), Vector2i(x, 0))
	assert_object(unit).override_failure_message(
		"precondition: could not spawn at x=%d, so nothing below proves anything" % x).is_not_null()
	return unit


func _texts_at(severity: BoardLint.Severity) -> Array[String]:
	var result: Array[String] = []
	for finding: Dictionary in BoardLint.check(game):
		if finding["severity"] == severity:
			result.append(String(finding["text"]))
	return result


func _mentions(severity: BoardLint.Severity, fragment: String) -> bool:
	for text in _texts_at(severity):
		if text.contains(fragment):
			return true
	return false


func _assert_reports(severity: BoardLint.Severity, fragment: String) -> void:
	assert_bool(_mentions(severity, fragment)).override_failure_message(
		"expected a finding mentioning '%s'; got %s" % [fragment, str(_texts_at(severity))]).is_true()


func _assert_silent(severity: BoardLint.Severity, fragment: String) -> void:
	assert_bool(_mentions(severity, fragment)).override_failure_message(
		"the fix did not clear the finding: %s" % str(_texts_at(severity))).is_false()


# --- teeth ---------------------------------------------------------------------------------------

func test_a_clean_board_reports_nothing() -> void:
	# The baseline every case below is measured against. If this ever reds, the fault cases are
	# passing on someone else's finding.
	_spawn(Team.Faction.PLAYER, 0)
	assert_array(BoardLint.check(game)).override_failure_message(
		"a clean board reported %s" % str(BoardLint.check(game))).is_empty()


func test_an_objective_with_no_zone_painted_blocks_play() -> void:
	_spawn(Team.Faction.PLAYER, 0)
	# Written the way the Properties checkbox writes it (append, not set_objectives) — that path
	# deliberately bypasses the load-time shout, and it is the path an author actually takes.
	game.mission_controller.objectives.append(MissionRules.Objective.CAPTURE)
	_assert_reports(BoardLint.Severity.BLOCKS, "CAPTURE")

	# Non-vacuous: paint the zone the objective needs and the finding goes.
	game.zone_manager.paint_cell("Landing", ZoneManager.Kind.CAPTURE, Vector2i(1, 0))
	_assert_silent(BoardLint.Severity.BLOCKS, "CAPTURE")


func test_enemies_the_computer_is_not_playing_warn_without_blocking() -> void:
	# #150's rule, which moved here from the load-integrity suite. The consequence is not a stall
	# on the enemy turn — you play both sides, which is a board the dev deliberately authors
	# (2026-08-26: "controlling both sides is important to testing"). So the finding is a WARNING.
	_spawn(Team.Faction.PLAYER, 0)
	_spawn(Team.Faction.ENEMY, 1)
	var none: Array[Team.Faction] = []   # typed, not a bare [] — `game` is untyped, so a literal is not coerced
	game.ai_controller.set_ai_factions(none)
	_assert_reports(BoardLint.Severity.DEGRADES, "ENEMY")
	# The half that is actually load-bearing, and the reason this case is worth its runtime: BLOCKS
	# is the tier test_every_shipped_mission_is_playable reds the build on, so promoting this rule
	# back into it would refuse to ship an AI-less board. Pinning the FORK, not one side of it —
	# asserting only the DEGRADES line above would keep passing if the finding were filed at BOTH.
	_assert_silent(BoardLint.Severity.BLOCKS, "ENEMY")

	var declared: Array[Team.Faction] = [Team.Faction.ENEMY]
	game.ai_controller.set_ai_factions(declared)
	_assert_silent(BoardLint.Severity.DEGRADES, "ENEMY")


func test_a_unit_painted_over_stands_where_spawn_would_refuse_it() -> void:
	var unit := _spawn(Team.Faction.PLAYER, 2)
	_assert_silent(BoardLint.Severity.BLOCKS, "DROPPED")   # legal when placed — that is the whole point
	# The only route into the state: paint terrain UNDER a unit that is already standing there.
	game.grid.set_cell(Vector2i(2, 0), GRASS_SOURCE, ROCK_ATLAS)
	_assert_reports(BoardLint.Severity.BLOCKS, "DROPPED")
	_assert_reports(BoardLint.Severity.BLOCKS, unit.get_unit_name())


func test_a_unit_on_an_erased_cell_reads_as_off_the_map() -> void:
	# The other half of spawn_unit's answer, and a different sentence: no tile at all, rather than a
	# tile nothing may stand on.
	_spawn(Team.Faction.PLAYER, 3)
	game.grid.erase_cell(Vector2i(3, 0))
	_assert_reports(BoardLint.Severity.BLOCKS, "off the map")


func test_a_dropped_leader_names_the_squad_it_takes_with_it() -> void:
	# The leaderless-squad consequence (#390 fork): apply_scenario's "saved without a leader ->
	# leave them as solos" branch is reachable ONLY through a dropped leader, so it is this finding
	# wearing its full cost rather than a check of its own that could never fire on a live board.
	var leader := _spawn(Team.Faction.PLAYER, 2)
	var member := _spawn(Team.Faction.PLAYER, 3)
	game.squad_manager.join_squad(member, leader.squad)
	leader.squad.squad_name = "Blue Squad"

	game.grid.set_cell(Vector2i(2, 0), GRASS_SOURCE, ROCK_ATLAS)
	_assert_reports(BoardLint.Severity.BLOCKS, "Blue Squad")
	_assert_reports(BoardLint.Severity.BLOCKS, "1 member")


func test_a_squadmate_out_of_cohesion_range_degrades_the_board() -> void:
	# Joined while adjacent, then displaced — the authoring order, and the one join_squad allows
	# ungated. The sweep will eject this member the first time the squad acts; the lint says so first.
	var leader := _spawn(Team.Faction.PLAYER, 0)
	var member := _spawn(Team.Faction.PLAYER, 1)
	game.squad_manager.join_squad(member, leader.squad)
	_assert_silent(BoardLint.Severity.DEGRADES, member.get_unit_name())

	member.movement.set_cell(Vector2i(ROW_WIDTH - 1, 0))   # far beyond COH
	_assert_reports(BoardLint.Severity.DEGRADES, member.get_unit_name())
	_assert_reports(BoardLint.Severity.DEGRADES, leader.get_unit_name())


func test_a_look_preset_that_no_longer_exists_degrades_the_board() -> void:
	_spawn(Team.Faction.PLAYER, 0)
	game.scenario_manager.current_look_preset = "NoSuchPresetEverExisted"
	_assert_reports(BoardLint.Severity.DEGRADES, "NoSuchPresetEverExisted")

	# Non-vacuous against a preset that DOES resolve — otherwise this case passes on any non-empty name.
	var real: Array[String] = LookKnobs.saved_presets()
	if real.is_empty():   # content-absent: warn, never fail (tests/README.md rule 9)
		push_warning("no look presets are shipped, so the resolving twin cannot be shown")
		return
	game.scenario_manager.current_look_preset = real[0]
	_assert_silent(BoardLint.Severity.DEGRADES, "no longer exists")


func test_a_roster_that_does_not_exist_blocks_the_board() -> void:
	# BLOCKS where the look preset one case up is DEGRADES, and the tier is the finding: a board
	# with no look wears the default and plays exactly as authored, while a board whose pool cannot
	# be found has no pool to offer. Only BLOCKS reds CI, so filing this at the wrong tier would
	# leave every shipped roster-naming mission unswept.
	_spawn(Team.Faction.PLAYER, 0)
	game.scenario_manager.current_roster = "NoSuchRosterEverExisted"
	_assert_reports(BoardLint.Severity.BLOCKS, "NoSuchRosterEverExisted")

	# Non-vacuous against a roster that DOES resolve -- otherwise this passes on any non-empty name.
	var real: Array[String] = RosterCatalog.saved_rosters()
	if real.is_empty():   # content-absent: warn, never fail (tests/README.md rule 9)
		push_warning("no rosters are shipped, so the resolving twin cannot be shown")
		return
	game.scenario_manager.current_roster = real[0]
	_assert_silent(BoardLint.Severity.BLOCKS, "does not exist")


func test_a_board_naming_no_roster_says_nothing_about_rosters() -> void:
	# The ordinary board, and the case that would catch a rule that forgot its empty-name guard --
	# every scenario shipped before #735 names no roster, so a missing early-return would BLOCK
	# every one of them at once.
	_spawn(Team.Faction.PLAYER, 0)
	game.scenario_manager.current_roster = ""
	_assert_silent(BoardLint.Severity.BLOCKS, "roster")


func test_findings_that_block_play_are_listed_first() -> void:
	# The order IS part of what the report says, so it belongs to the rule and not to the panel.
	# Built degrades-first so a lint that merely preserved call order would fail this.
	_spawn(Team.Faction.PLAYER, 0)
	game.scenario_manager.current_look_preset = "NoSuchPresetEverExisted"
	game.mission_controller.objectives.append(MissionRules.Objective.CAPTURE)

	var findings := BoardLint.check(game)
	assert_int(findings.size()).is_greater_equal(2)
	assert_int(findings[0]["severity"]).override_failure_message(
		"the first finding was not a blocking one: %s" % str(findings)).is_equal(BoardLint.Severity.BLOCKS)


# --- the wire ------------------------------------------------------------------------------------

func test_the_check_button_fills_the_report_panel() -> void:
	# A lint with no reader is #103 again: both ends correct, nothing connecting them. Drives the
	# real button off the real page rather than calling check() twice.
	var tool: ScenarioTool = game.dev_overlay.scenario_tool
	var button := _check_button(tool)
	assert_object(button).override_failure_message(
		"no 'Check board' button on the Properties page").is_not_null()

	_spawn(Team.Faction.PLAYER, 0)
	game.mission_controller.objectives.append(MissionRules.Objective.CAPTURE)
	button.emit_signal("pressed")
	await await_idle_frame()

	assert_bool(_report_says(tool, "CAPTURE")).override_failure_message(
		"the report panel does not mention the fault: %s" % str(_report_lines(tool))).is_true()


func test_the_report_says_so_when_it_finds_nothing() -> void:
	# "Nothing found" is a RESULT, not an empty panel — an empty panel reads as "the button is broken".
	var tool: ScenarioTool = game.dev_overlay.scenario_tool
	_spawn(Team.Faction.PLAYER, 0)
	_check_button(tool).emit_signal("pressed")
	await await_idle_frame()
	assert_bool(_report_says(tool, "No problems found")).override_failure_message(
		"a clean board left the report saying: %s" % str(_report_lines(tool))).is_true()


func test_loading_a_board_clears_a_report_about_the_old_one() -> void:
	# A report that outlives its board is worse than no report. Update and Save As deliberately do
	# NOT clear it, which is why this rides board_loaded rather than the header's file_changed.
	var tool: ScenarioTool = game.dev_overlay.scenario_tool
	_spawn(Team.Faction.PLAYER, 0)
	game.mission_controller.objectives.append(MissionRules.Objective.CAPTURE)
	_check_button(tool).emit_signal("pressed")
	await await_idle_frame()
	assert_bool(_report_says(tool, "CAPTURE")).override_failure_message(
		"precondition: nothing was reported, so the clear below proves nothing").is_true()

	var missions: Array[String] = game.scenario_manager.get_missions()
	assert_array(missions).is_not_empty()
	game.scenario_manager.load_scenario(missions[0])
	await await_idle_frame()
	assert_array(_report_lines(tool)).override_failure_message(
		"the report survived a board load").is_empty()


func _check_button(tool: ScenarioTool) -> Button:
	for child in tool.scroll_vbox.get_children():
		var button := child as Button
		if button != null and button.text == "Check board":
			return button
	return null


func _report_lines(tool: ScenarioTool) -> Array[String]:
	var lines: Array[String] = []
	for child in tool._report_box.get_children():
		var label := child as Label
		if label != null:
			lines.append(label.text)
	return lines


func _report_says(tool: ScenarioTool, fragment: String) -> bool:
	for line in _report_lines(tool):
		if line.contains(fragment):
			return true
	return false


# --- laws over the shipped missions ---------------------------------------------------------------

func test_scan_finds_shipped_missions() -> void:
	# Guards both laws below against passing vacuously because the mission scan broke — the same
	# shape test_scenario_load_integrity opens with, and for the same reason.
	assert_array(game.scenario_manager.get_missions()).is_not_empty()


func test_every_shipped_mission_is_playable() -> void:
	# What replaces the ai_factions case that left the load-integrity suite, and four checks wider.
	#
	# BLOCKS only, and that tier choice is the whole gate: a look preset falling back is a real
	# finding but not a reason to red the build, and neither is a board that hands the dev both
	# sides — he authors those on purpose (2026-08-26, after this case red-ed main on a fresh
	# Level_2). So this asks "is any shipped board BROKEN", never "is any shipped board unusual".
	# Anything that reds here must be a thing no mission may ever be, because the only way to
	# clear it is to edit CONTENT.
	var problems: Array[String] = []
	for path: String in game.scenario_manager.get_missions():
		game.scenario_manager.load_scenario(path)
		await await_idle_frame()
		for text: String in _texts_at(BoardLint.Severity.BLOCKS):
			problems.append("%s: %s" % [path.get_file(), text])
	assert_array(problems).is_empty()


func test_no_shipped_mission_loses_a_unit_on_load() -> void:
	# The file-shaped half of the placement question, and the one thing the live lint cannot see:
	# a unit whose cell spawn refuses is already gone by the time anything looks at the board, and
	# apply_scenario only push_warnings on its way past. Count the survivors instead.
	var problems: Array[String] = []
	for path: String in game.scenario_manager.get_missions():
		var scenario := load(path) as ScenarioData
		assert_object(scenario).override_failure_message("%s did not load" % path).is_not_null()
		var expected: int = ScenarioManager.valid_entries(scenario).size()
		game.scenario_manager.load_scenario(path)
		await await_idle_frame()
		var actual: int = game.units_root.get_child_count()
		if actual != expected:
			problems.append("%s: %d of %d entries reached the board — the rest were dropped as blocked or off-map"
				% [path.get_file(), actual, expected])
	assert_array(problems).is_empty()


# --- the dialog checks (#397, deferred from #390) --------------------------------------------------

func test_a_beat_with_no_timeline_degrades() -> void:
	var beat := DialogBeat.new()   # timeline left null
	game.scenario_manager.current_dialog_beats.append(beat)
	assert_bool(_mentions(BoardLint.Severity.DEGRADES, "no timeline")).is_true()
	# Non-vacuous twin: give it a timeline and the finding goes.
	beat.timeline = DialogicTimeline.new()
	assert_bool(_mentions(BoardLint.Severity.DEGRADES, "no timeline")).is_false()


func test_a_step_naming_an_absent_unit_blocks() -> void:
	var step := TutorialStep.new()
	step.unit_name = "Torv"
	step.text = "Select Torv."
	game.scenario_manager.current_tutorial_steps.append(step)
	assert_bool(_mentions(BoardLint.Severity.BLOCKS, "Torv")).is_true()
	# Non-vacuous twin: put a Torv on the board and the finding goes.
	var torv_data := H.make_unit_data({}, Team.Faction.PLAYER)
	torv_data.display_name = "Torv"
	assert_object(game.spawn_unit(torv_data, Vector2i(0, 0))).is_not_null()
	assert_bool(_mentions(BoardLint.Severity.BLOCKS, "Torv")).is_false()


func test_an_empty_unit_name_is_never_a_finding() -> void:
	var step := TutorialStep.new()
	step.unit_name = ""   # "any unit" is always satisfiable
	game.scenario_manager.current_tutorial_steps.append(step)
	assert_bool(_texts_at(BoardLint.Severity.BLOCKS).is_empty()).is_true()


func test_the_name_check_stays_quiet_past_the_opening_turn() -> void:
	# Dev call (#397): mid-battle, a named unit may legitimately be gone (dead, extracted), so an
	# ARMED battle past turn 1 stops asking. The un-armed authoring board above always asks.
	var step := TutorialStep.new()
	step.unit_name = "Torv"
	game.scenario_manager.current_tutorial_steps.append(step)
	game.scenario_director.mission_started()   # arms
	game.turn_manager.turn_started.emit(Team.Faction.PLAYER)   # turn 1: still authored-time
	assert_bool(_mentions(BoardLint.Severity.BLOCKS, "Torv")).is_true()
	game.turn_manager.turn_started.emit(Team.Faction.PLAYER)   # turn 2: battle underway
	assert_bool(_mentions(BoardLint.Severity.BLOCKS, "Torv")).is_false()


# ==============================================================================
#  Content that only loaded because a reference was taken out of it (#608)
# ==============================================================================

# The one finding here that is not about the board's own authoring: it says the board is a DEGRADED
# copy of what was authored, which nothing else on screen would tell you. Driven through the real
# ContentRepair door rather than by poking its record, because the wire is what this pins -- the
# repair and the report were both correct in isolation while nothing connected them.
func test_a_board_holding_repaired_content_says_so() -> void:
	_spawn(Team.Faction.PLAYER, 0)
	var path := "user://__test_lint_degraded.tres"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string('[gd_resource type="Resource" script_class="WeaponModData" format=3]\n\n'
		+ '[ext_resource type="Script" path="res://Classes/weapons/WeaponModData.gd" id="1_m"]\n'
		+ '[ext_resource type="Script" path="res://Classes/weapons/WeaponAttackData.gd" id="2_w"]\n'
		+ '[ext_resource type="Resource" path="res://Resources/WeaponAttacks/__test_gone.tres" id="3_g"]\n\n'
		+ '[resource]\nscript = ExtResource("1_m")\ndisplay_name = "Degraded"\n'
		+ 'granted_attacks = Array[ExtResource("2_w")]([ExtResource("3_g")])\n')
	f.close()
	assert_object(ContentRepair.load_tolerant(path)).override_failure_message(
		"precondition: the fixture did not load degraded, so the finding below proves nothing"
	).is_not_null()

	_assert_reports(BoardLint.Severity.DEGRADES, "__test_lint_degraded")

	# Non-vacuous twin: with nothing degraded the finding goes, so it is not simply always on.
	ContentRepair.forget(path)
	_assert_silent(BoardLint.Severity.DEGRADES, "__test_lint_degraded")
	DirAccess.remove_absolute(path)
