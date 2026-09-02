# Report-a-bug dump guard (#128, 2026-08-02). BugReporter.build_report_text is pure + static so
# the whole report can be pinned without a game scene -- the same capture/save split #87 made.
#
# #131 grew the signature by a Kind and a note; every case here passes BUG with no note, because
# what this file guards is the BODY of a report and neither of those changes it. The note, the
# kind heading and the menu-side "no board" branch are pinned in tests/ui/test_report_flow.gd,
# beside the wire that carries them.
#
# Every case here is falsified against a bug this feature actually shipped and had to have found
# by eye, or against a doctrine call that has an obvious-looking wrong "fix":
#   * the units loop silently stopped emitting rows (the section header printed, zero rows under
#     it) -- so a row COUNT is asserted, never just "the header is there";
#   * a solo squad has no squad_name, so the plan header rendered "Squad: " blank;
#   * attack rows print the RAW target_hp_after. The queue panel clamps a fatal value to 0/1 by
#     matching on lethality; copying that ladder here would duplicate a decision LethalityRules
#     owns. If someone "fixes" the raw number, the fatal-hit case below goes red.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)

# Everything under "## Units", up to the log section.
func _units_section(text: String) -> String:
	var halves := text.split("## Units")
	if halves.size() < 2:
		return ""
	return halves[1].split("## Engine log")[0]

func _row_count(section: String) -> int:
	var count := 0
	for line in section.split("\n"):
		if line.begins_with("- "):
			count += 1
	return count

# ---- the plan header ----

func test_a_solo_squad_is_named_for_its_leader() -> void:
	var board: Dictionary = BoardBuilder.build(self)
	auto_free(board.root)
	BoardBuilder.paint_rect(board.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(board, _data("Hero", PLAYER), Vector2i(0, 0))
	var manager: SquadManager = board.squad_manager

	var context := BoardContext.new(board.grid, [hero], manager)
	var plan: ResolvedPlan = manager.resolve_plan(hero.squad, context)
	var units: Array[Unit] = [hero]
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "",hero.squad, plan, units, "log")

	# A solo squad exists but was never named -- the fallback is what keeps this line meaningful.
	assert_str(text).contains("Squad: Hero's squad")

func test_a_named_squad_keeps_its_name() -> void:
	var board: Dictionary = BoardBuilder.build(self)
	auto_free(board.root)
	BoardBuilder.paint_rect(board.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(board, _data("Hero", PLAYER), Vector2i(0, 0))
	var mate: Unit = BoardBuilder.spawn(board, _data("Mate", PLAYER), Vector2i(0, 1))
	var manager: SquadManager = board.squad_manager
	manager.join_squad(mate, hero.squad)
	hero.squad.squad_name = "Vanguard"

	var context := BoardContext.new(board.grid, [hero, mate], manager)
	var plan: ResolvedPlan = manager.resolve_plan(hero.squad, context)
	var units: Array[Unit] = [hero, mate]
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "",hero.squad, plan, units, "log")

	assert_str(text).contains("Squad: Vanguard")
	assert_str(text).not_contains("Hero's squad")

func test_no_queued_orders_says_so() -> void:
	var no_units: Array[Unit] = []
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "",null, null, no_units, "log")

	assert_str(text).contains("(no squad has queued orders)")
	assert_str(text).contains("Game state: **IDLE**")

# ---- the units section ----

func test_every_unit_gets_a_row() -> void:
	var board: Dictionary = BoardBuilder.build(self)
	auto_free(board.root)
	BoardBuilder.paint_rect(board.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(board, _data("Hero", PLAYER), Vector2i(0, 0))
	var mate: Unit = BoardBuilder.spawn(board, _data("Mate", PLAYER), Vector2i(0, 1))
	var foe: Unit = BoardBuilder.spawn(board, _data("Foe", ENEMY), Vector2i(1, 0))

	var units: Array[Unit] = [hero, mate, foe]
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "",null, null, units, "log")
	var section := _units_section(text)

	# The COUNT is the point: the loop once computed its squad note and appended nothing, which
	# left a correct-looking header over an empty section.
	assert_int(_row_count(section)).is_equal(3)
	assert_str(section).contains("Hero")
	assert_str(section).contains("Mate")
	assert_str(section).contains("Foe")
	assert_str(section).contains("(ENEMY)")
	assert_str(section).contains("ACTIVE")

func test_the_row_counter_can_see_an_empty_section() -> void:
	# Falsifies the detector in test_every_unit_gets_a_row. The shipped bug printed a correct
	# header over zero rows -- the same shape an empty unit list makes. If _row_count could not
	# tell that from a populated section, that test would have stayed green straight through it.
	var no_units: Array[Unit] = []
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "",null, null, no_units, "log")

	assert_str(text).contains("## Units")
	assert_int(_row_count(_units_section(text))).is_equal(0)

func test_a_unit_row_carries_its_live_hp() -> void:
	var board: Dictionary = BoardBuilder.build(self)
	auto_free(board.root)
	BoardBuilder.paint_rect(board.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(board, _data("Hero", PLAYER), Vector2i(0, 0))
	hero.take_damage(3)

	var units: Array[Unit] = [hero]
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "",null, null, units, "log")

	assert_str(text).contains("HP %d/%d" % [hero.get_current_hp(), hero.get_max_hp()])

# ---- attack rows ----

func test_an_attack_row_carries_its_resolved_numbers() -> void:
	var board: Dictionary = BoardBuilder.build(self)
	auto_free(board.root)
	BoardBuilder.paint_rect(board.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(board, _data("Hero", PLAYER), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(board, _data("Foe", ENEMY), Vector2i(1, 0))
	var manager: SquadManager = board.squad_manager

	var attack := AttackAction.declare(hero, hero.movement.cell, Vector2i(1, 0))
	assert_bool(manager.queue_action(hero.squad, attack)).is_true()

	var context := BoardContext.new(board.grid, [hero, foe], manager)
	var plan: ResolvedPlan = manager.resolve_plan(hero.squad, context)
	assert_int(plan.attacks.size()).is_equal(1)

	var units: Array[Unit] = [hero, foe]
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "",hero.squad, plan, units, "log")

	# Read the numbers back off the plan rather than hardcoding them: this pins the WIRING to
	# action.resolved, not the balance values, which are content and free to move.
	var resolved: ResolvedOutcome = plan.attacks[0].resolved
	assert_str(text).contains("%d dmg" % resolved.damage)
	assert_str(text).contains("HP %d -> %d raw" % [resolved.hp_before, resolved.target_hp_after])

func test_a_fatal_hit_reports_raw_hp_not_the_panels_clamp() -> void:
	var board: Dictionary = BoardBuilder.build(self)
	auto_free(board.root)
	BoardBuilder.paint_rect(board.grid, Rect2i(-2, -2, 8, 8))
	var hero: Unit = BoardBuilder.spawn(board, _data("Hero", PLAYER), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(board, _data("Foe", ENEMY), Vector2i(1, 0))
	var manager: SquadManager = board.squad_manager

	foe.take_damage(foe.get_current_hp() - 1)   # 1 HP left: the next hit overshoots
	assert_int(foe.get_current_hp()).is_equal(1)

	var attack := AttackAction.declare(hero, hero.movement.cell, Vector2i(1, 0))
	assert_bool(manager.queue_action(hero.squad, attack)).is_true()

	var context := BoardContext.new(board.grid, [hero, foe], manager)
	var plan: ResolvedPlan = manager.resolve_plan(hero.squad, context)
	var resolved: ResolvedOutcome = plan.attacks[0].resolved

	# Guard the guard: the raw value must be STRICTLY negative, so it cannot coincide with either
	# number the panel would clamp to (1 for a down/maim, 0 for a kill). At -1 or better this case
	# is blind to the clamp it exists to forbid.
	assert_int(resolved.target_hp_after).is_less(0)
	assert_int(resolved.lethality).is_not_equal(ResolvedOutcome.Lethality.NONE)

	var units: Array[Unit] = [hero, foe]
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "",hero.squad, plan, units, "log")

	# The RAW number, and the lethality name that gives it meaning. The queue panel would show
	# this same hit clamped to 0 or 1 -- deliberately not copied here.
	assert_str(text).contains("%d raw" % resolved.target_hp_after)
	assert_str(text).contains(ResolvedOutcome.Lethality.keys()[resolved.lethality])

# ---- the build stamp (#134) ----

func test_the_report_and_the_summary_name_the_build() -> void:
	# Interpolated off Build.version(), never a pinned literal: this pins the WIRING to the one
	# version source, not the value, which is content and free to move.
	var no_units: Array[Unit] = []
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "", null, null, no_units, "log")
	assert_str(text).contains("Build: **%s**" % Build.version())

	var summary := BugReporter.build_summary("stamp", "IDLE", BugReporter.Kind.BUG, "note")
	assert_str(summary).contains("v%s" % Build.version())

# ---- which checkout produced it (#295) ----

func test_the_report_and_the_summary_name_the_checkout() -> void:
	# Same convention as the version case above and for the same reason: interpolated off
	# Checkout.describe(), never a pinned branch or SHA. What is pinned is that the report reads
	# THE one git reader -- a second reader is the Law #4 failure this is guarding, not the value.
	assert_bool(DevTools.enabled()).is_true()   # the gate; without it both asserts pass on ""
	var expected := Checkout.describe()
	assert_str(expected).is_not_equal("")

	var no_units: Array[Unit] = []
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "", null, null, no_units, "log")
	assert_str(text).contains("Checkout: **%s**" % expected)

	var summary := BugReporter.build_summary("stamp", "IDLE", BugReporter.Kind.BUG, "note")
	assert_str(summary).contains(expected)

func test_the_checkout_does_not_displace_the_version() -> void:
	# Two facts, two lines. The version answers "which release", the checkout "which code" -- a
	# report that traded one for the other would lose the half every existing triage habit reads.
	var no_units: Array[Unit] = []
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "", null, null, no_units, "log")

	assert_str(text).contains("Build: **%s**" % Build.version())
	assert_str(text).contains("Checkout: **%s**" % Checkout.describe())
	assert_int(text.find("Build:")).is_less(text.find("Checkout:"))

# ---- where it was seen from (#240) ----

func test_the_report_names_the_view_and_the_look_it_was_seen_under() -> void:
	# Both are PASSED, not looked up: the view comes off the 3D host (which the reporter cannot
	# reach) and the look off the loaded board. This case pins that they land in the body at all.
	var no_units: Array[Unit] = []
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "", null, null,
		no_units, "log", "HD_2D -- yaw 90 deg, zoom 11.5, centred on (12, 8)", "Dusk")

	assert_str(text).contains("View: **HD_2D -- yaw 90 deg, zoom 11.5, centred on (12, 8)**")
	assert_str(text).contains("Look: **Dusk**")

func test_a_flat_launch_says_so_rather_than_stamping_a_blank() -> void:
	# The twin of "sent from a menu": a report claiming a View and then showing nothing is the
	# kind of small lie that wastes a triage session. An empty look_preset is a real state too --
	# every board that never named one falls back to DefaultLook.tres.
	var no_units: Array[Unit] = []
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "", null, null,
		no_units, "log")

	assert_str(text).contains("View: **%s**" % BugReporter.NO_3D_VIEW)
	assert_str(text).contains("Look: **%s**" % BugReporter.DEFAULT_LOOK)

# ---- what the dev tools were showing (#328) ----

func test_the_report_names_the_dev_tab_that_was_open() -> void:
	# Passed like the view and the look, and for the same reason: the window is outside the game
	# subtree. Free next to the screenshot, and it outlives Discord's CDN expiry as the picture does not.
	var no_units: Array[Unit] = []
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "", null, null,
		no_units, "log", "", "", "Tile Brush")

	assert_str(text).contains("Dev tools: **Tile Brush**")

func test_a_closed_dev_tools_window_is_stated_rather_than_left_blank() -> void:
	# A report with no devtools.png beside it must say WHY, or the missing file reads as a broken
	# reporter -- the "sent from a menu" rule again.
	var no_units: Array[Unit] = []
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "", null, null,
		no_units, "log")

	assert_str(text).contains("Dev tools: **%s**" % BugReporter.NO_DEVTOOLS)

# ---- what the camera just did (#669) ----

func test_the_report_carries_the_camera_trace_it_was_handed() -> void:
	# Passed like the view and the look, and for the same reason: the trace lives on the 3D rig,
	# which the reporter cannot reach. This pins that it lands in the body at all.
	var no_units: Array[Unit] = []
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "", null, null,
		no_units, "log", "", "", "", "2 moments over 3.0 s\nplayback lock ACQUIRED")

	assert_str(text).contains("## Camera trace")
	assert_str(text).contains("playback lock ACQUIRED")

func test_a_flat_launch_says_the_camera_trace_has_no_host() -> void:
	# The NO_3D_VIEW idiom again: an empty section reads as a broken dump, and "there was no 3D
	# host" is a real fact about the run rather than an absence.
	var no_units: Array[Unit] = []
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "", null, null,
		no_units, "log")

	assert_str(text).contains("## Camera trace")
	assert_str(text).contains(BugReporter.NO_CAMERA_TRACE)

func test_the_trace_sits_below_the_board_and_above_the_log() -> void:
	# Placement is a claim about what KIND of evidence it is: a sequence, read the way the log
	# tail is read, rather than more of the state the report is about.
	var no_units: Array[Unit] = []
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "", null, null,
		no_units, "log", "", "", "", "trace body")

	assert_int(text.find("## Units")).is_less(text.find("## Camera trace"))
	assert_int(text.find("## Camera trace")).is_less(text.find("## Engine log"))
