# Report-a-bug dump guard (#128, 2026-08-02). BugReporter.build_report_text is static and needs no
# game scene, so the whole report can be pinned here -- the same capture/save split #87 made. It
# stopped being PURE at #1036: the path scrub reads the machine's own directories.
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
#   * attack rows print the RAW target_hp_after. The queue panel clamps a KILL's negative to 0;
#     copying that ladder here would duplicate a decision LethalityRules owns. If someone "fixes"
#     the raw number, the fatal-hit case below goes red. (Since #1002 a DOWN is no longer part of
#     that claim: the resolver threads the cling, so raw and clamped agree for one -- which is why
#     the case below aims at a kill and says so.)
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

func _data(unit_name: String, fac: Team.Faction,
		overrides: Dictionary[Stats.Stat, int] = {}) -> UnitData:
	var stats: Dictionary[Stats.Stat, int] = Stats.STAT_DEFAULTS.duplicate()
	stats.merge(overrides, true)
	return UnitFactory.create_unit_data(stats, unit_name, fac)

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
	# A KILL, not a down -- the hit has to clear OVERKILL_CEILING past the foe's remaining HP. Since
	# #1002 a DOWN threads the cling (1) rather than the raw subtraction, so a down is exactly the
	# rung this case cannot use: its raw and its clamp would be the same number and there would be
	# nothing left to distinguish. A kill still threads below zero, which is the whole claim here.
	var hero: Unit = BoardBuilder.spawn(board, _data("Hero", PLAYER, {Stats.Stat.STR: 30}), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(board, _data("Foe", ENEMY), Vector2i(1, 0))
	var manager: SquadManager = board.squad_manager

	foe.take_damage(foe.get_current_hp() - 1)   # 1 HP left: the next hit overshoots, hugely
	assert_int(foe.get_current_hp()).is_equal(1)

	var attack := AttackAction.declare(hero, hero.movement.cell, Vector2i(1, 0))
	assert_bool(manager.queue_action(hero.squad, attack)).is_true()

	var context := BoardContext.new(board.grid, [hero, foe], manager)
	var plan: ResolvedPlan = manager.resolve_plan(hero.squad, context)
	var resolved: ResolvedOutcome = plan.attacks[0].resolved

	# Guard the guard: the raw value must be STRICTLY negative, so it cannot coincide with what the
	# panel would clamp a kill to (0). At -1 or better this case is blind to the clamp it forbids.
	assert_int(resolved.lethality).override_failure_message(
			"the fixture hit no longer kills, so the raw number is the cling and this case "
			+ "is blind to the clamp it exists to forbid") \
			.is_equal(ResolvedOutcome.Lethality.KILLED)
	assert_int(resolved.target_hp_after).is_less(0)

	var units: Array[Unit] = [hero, foe]
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "",hero.squad, plan, units, "log")

	# The RAW number, and the lethality name that gives it meaning. The queue panel would show
	# this same hit clamped to 0 -- deliberately not copied here.
	assert_str(text).contains("%d raw" % resolved.target_hp_after)
	assert_str(text).contains(ResolvedOutcome.Lethality.keys()[resolved.lethality])

# ---- the build stamp (#134) ----

func test_the_report_and_the_summary_name_the_build() -> void:
	# Interpolated off Build.version(), never a pinned literal: this pins the WIRING to the one
	# version source, not the value, which is content and free to move.
	var no_units: Array[Unit] = []
	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "", null, null, no_units, "log")
	assert_str(text).contains("Build: **%s**" % Build.version())

	var summary := BugReporter.build_summary("stamp", "IDLE", BugReporter.Kind.BUG, "note", "", "")
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

	var summary := BugReporter.build_summary("stamp", "IDLE", BugReporter.Kind.BUG, "note", "", "")
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

# ---- nothing shipped names the machine it came from (#1036) ----
#
# Every case interpolates off OS.get_user_data_dir() or the environment, never a pinned literal --
# the convention the build and checkout cases above already use, and what makes these pass on the
# Linux runners as well as here. The leak they guard was real: BugReporter's own print globalized
# the report folder into godot.log, and the NEXT report shipped that tail to a public channel.

func _user_data_dir() -> String:
	return OS.get_user_data_dir().trim_suffix("/")

# Forward slashes whatever the platform wrote: get_user_data_dir() uses them and USERPROFILE does
# not, so a case comparing the two has to normalise or it is asserting about a separator.
func _home_forward() -> String:
	var home := OS.get_environment("USERPROFILE")
	if home == "":
		home = OS.get_environment("HOME")
	return home.replace("\\", "/").trim_suffix("/")

func _report_with_tail(tail: String) -> String:
	var no_units: Array[Unit] = []
	return BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "", null, null,
		no_units, tail)

func test_the_log_tail_loses_the_user_data_directory() -> void:
	# The shipped leak's exact shape. Falsified by dropping the scrub call, and also by matching
	# the bare directory instead of the directory-plus-separator, which emits "user:///reports/".
	var dir := _user_data_dir()
	assert_str(dir).is_not_empty()

	var text := _report_with_tail("Report written to %s/reports/2026-01-01_00-00-00/" % dir)

	assert_str(text).contains("user://reports/2026-01-01_00-00-00/")
	assert_str(text).not_contains(dir)

func test_the_backslash_form_of_that_path_is_scrubbed_too() -> void:
	# Godot writes forward slashes and Windows writes backslashes, and the engine log carries
	# whatever the writer used. Falsified by dropping the second form from _replace_both_forms.
	var back := _user_data_dir().replace("/", "\\")

	var text := _report_with_tail("could not open %s\\reports\\x\\board.tres" % back)

	assert_str(text).contains("user://reports\\x\\board.tres")
	assert_str(text).not_contains(back)

func test_a_case_shifted_path_is_scrubbed() -> void:
	# replacen() is the case-insensitive replace; falsified by swapping it for replace().
	var dir := _user_data_dir()
	assert_str(dir.to_upper()).is_not_equal(dir)   # or the case says nothing about either one

	var text := _report_with_tail("opening %s/logs/godot.log" % dir.to_upper())

	assert_str(text).contains("user://logs/godot.log")
	assert_str(text).not_contains(dir.to_upper())

func test_a_home_path_outside_the_data_directory_becomes_a_tilde() -> void:
	# Pass 2 -- the net for a path the engine prints that is not under user:// at all, which is
	# every absolute path in a crash trace. Falsified by dropping the home half.
	var home := _home_forward()
	assert_str(home).is_not_empty()

	var text := _report_with_tail("loading %s/Desktop/iosis-demo/Iosis.exe" % home)

	assert_str(text).contains("%s/Desktop/iosis-demo/Iosis.exe" % BugReporter.HOME_TOKEN)
	assert_str(text).not_contains(home)

func test_a_bare_data_directory_still_loses_the_account_name() -> void:
	# THE CASCADE. Pass 1 needs a separator, so a bare mention of the directory falls through to
	# pass 2 and comes back under ~ -- no account name either way. Falsified by dropping pass 2.
	var dir := _user_data_dir()
	var home := _home_forward()
	assert_bool(dir.to_lower().begins_with(home.to_lower())).is_true()   # the cascade's premise

	var text := _report_with_tail("user data dir is %s" % dir)

	assert_str(text).contains(BugReporter.HOME_TOKEN)
	assert_str(text).not_contains(home)
	assert_str(text).not_contains(dir)

# ---- who sent it (#1049) ----

func test_the_summary_and_the_report_both_name_the_reporter() -> void:
	# The whole point of the ticket: a report that arrives from a stranger can be followed up on.
	# Falsified by dropping `who` from build_summary's format, or the From line from the report.
	var no_units: Array[Unit] = []
	var summary := BugReporter.build_summary("stamp", "IDLE", BugReporter.Kind.BUG, "note",
		"Jae", "abc123")
	assert_str(summary).contains("Jae")
	assert_str(summary).contains("abc123")

	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "",
		null, null, no_units, "log", "", "", "", "", "Jae", "abc123")
	assert_str(text).contains("From: **Jae**")
	assert_str(text).contains("Install: **abc123**")

func test_an_unnamed_reporter_is_stated_rather_than_left_blank() -> void:
	# "(nothing typed)"'s rule one field along: a line that sometimes carries a field and sometimes
	# does not reads as a bug in the reporter itself, and anonymous is a real answer. The install id
	# still rides, which is what lets two unnamed reports be told apart.
	var no_units: Array[Unit] = []
	var summary := BugReporter.build_summary("stamp", "IDLE", BugReporter.Kind.BUG, "note",
		"", "abc123")
	assert_str(summary).contains("anonymous")
	assert_str(summary).contains("abc123")

	var text := BugReporter.build_report_text("stamp", "IDLE", BugReporter.Kind.BUG, "",
		null, null, no_units, "log", "", "", "", "", "", "abc123")
	assert_str(text).contains("From: **anonymous**")

func test_a_name_carrying_a_path_is_scrubbed_out_of_the_summary() -> void:
	# THE TRAILING SCRUB IS NO LONGER UNOBSERVABLE. build_summary's own comment kept that call for
	# "a field added to this line later"; the reporter name IS that field -- player-typed, and
	# unlike the note it is scrubbed by nothing upstream. Falsified by deleting the trailing
	# scrub_paths, which survived every case in this file before #1049.
	var dir := _user_data_dir()

	var summary := BugReporter.build_summary("stamp", "IDLE", BugReporter.Kind.BUG, "note",
		"%s/reports" % dir, "abc123")

	assert_str(summary).contains(BugReporter.USER_TOKEN)
	assert_str(summary).not_contains(dir)

func test_the_discord_summary_scrubs_the_note_too() -> void:
	# The other thing that leaves the machine, and the one carrying the player's own words.
	# Falsified by dropping the scrub from build_summary.
	var dir := _user_data_dir()

	var summary := BugReporter.build_summary("stamp", "IDLE", BugReporter.Kind.BUG,
		"crashed while saving to %s/reports/x/" % dir, "", "")

	assert_str(summary).contains("user://reports/x/")
	assert_str(summary).not_contains(dir)

func test_a_path_straddling_the_summary_truncation_is_scrubbed_before_the_cut() -> void:
	# The reason build_summary scrubs its NOTE and not only its return: a path cut at
	# NOTE_IN_MESSAGE leaves a head no later pass can match, so the return scrub is structurally
	# unable to catch it. Falsified by moving the note's scrub after the truncation -- which the
	# case above CANNOT see, its note being far short of the cut.
	# WHERE THE CUT LANDS IS THE WHOLE CASE, and two earlier versions of it were vacuous. A cut
	# falling anywhere BELOW the home directory leaves a fragment that still begins with the home
	# directory, and pass 2 scrubs that on the way out however late it runs -- so the only thing
	# the note's own scrub buys is a cut landing INSIDE the home directory, which leaves a partial
	# account name that neither pass can match. That is what this aims at: keep two characters
	# fewer than the home path, derived at runtime so it lands the same way on the Linux runners.
	var dir := _user_data_dir()
	var keep := _home_forward().length() - 2
	assert_int(keep).is_greater_equal(8)                      # or the fragment says nothing
	assert_int(keep).is_less(BugReporter.NOTE_IN_MESSAGE)

	var lead := "x".repeat(BugReporter.NOTE_IN_MESSAGE - keep)
	var fragment := dir.substr(0, keep)

	var summary := BugReporter.build_summary("stamp", "IDLE", BugReporter.Kind.BUG,
		"%s%s/reports/x/%s" % [lead, dir, "y".repeat(100)], "", "")

	assert_str(summary).contains("full text in report.md")   # the cut really happened
	assert_str(summary).not_contains(fragment)
