extends Node
class_name BugReporter

# Dev-only report-a-bug dump (#128): one keypress writes the live board, the queued plan and the
# tail of the engine log to res://bug-reports/<stamp>/, turning a playtest bug into a reproducible
# artifact. Built in game._build_collaborators with a `game` back-ref (the DevController pattern).
#
# It owns NO state and adds no new seam: the board is ScenarioManager.capture_scenario (#87), the
# plan is ActionQueueDisplayEntry.build_for (what the queue panel draws). board.tres is
# authoritative; report.md is a read-only projection of it plus what a scenario doesn't carry.

const REPORT_DIR := "res://bug-reports/"
const LOG_TAIL_LINES := 80

var game   # untyped back-ref: game.gd has no class_name

# state_name is PASSED, not looked up -- game.gd owns the GameState enum.
func report(state_name: String) -> void:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var dir := REPORT_DIR + stamp + "/"
	DirAccess.make_dir_recursive_absolute(dir)

	var scenario: ScenarioData = game.scenario_manager.capture_scenario("bug-report-" + stamp)
	var board_path := dir + "board.tres"
	scenario.take_over_path(board_path)   # whoever writes a path claims it
	var err := ResourceSaver.save(scenario, board_path)
	if err != OK:
		push_error("Bug report: could not write board.tres (error %s)" % err)

	var squad := _plan_squad()
	var plan: ResolvedPlan = null
	if squad != null:
		# Resolve only, never validate: a dump READS state, it must not rewrite is_valid flags.
		plan = game.squad_manager.resolve_plan(squad, game._board())
	var units: Array[Unit] = game._all_units()

	var md := FileAccess.open(dir + "report.md", FileAccess.WRITE)
	if md == null:
		push_error("Bug report: could not write report.md")
		return
	md.store_string(build_report_text(stamp, state_name, squad, plan, units, _log_tail()))
	md.close()

	await RenderingServer.frame_post_draw   # the viewport texture is only valid after a draw
	var image = game.get_viewport().get_texture().get_image()
	image.save_png(dir + "board.png")

	print("Bug report written to %s" % dir)

# Pure + static so it is testable without a game scene, the capture/save split again.
static func build_report_text(stamp: String, state_name: String, squad: Squad,
		plan: ResolvedPlan, units: Array[Unit], log_tail: String) -> String:
	var out := "# Bug report %s\n\n" % stamp
	out += "Game state: **%s**\n\n" % state_name
	out += "`board.tres` is the authoritative snapshot. Everything below is a read-only "
	out += "projection of it, plus what a scenario deliberately does not carry.\n\n"

	out += "## Queued plan\n"
	if squad == null or plan == null:
		out += "\n(no squad has queued orders)\n"
	else:
		out += "\nSquad: %s\n" % _squad_label(squad)
		for entry in ActionQueueDisplayEntry.build_for(squad, plan):
			match entry.entry_type:
				ActionQueueDisplayEntry.EntryType.HEADER:
					out += "\n**%s**\n" % entry.label
				ActionQueueDisplayEntry.EntryType.ACTION:
					var flag: String = "" if entry.action.is_valid else "   **[INVALID]**"
					out += "- %s%s%s\n" % [entry.action.get_description(),
						_outcome_note(entry.action), flag]
				ActionQueueDisplayEntry.EntryType.DIVIDER:
					pass

	out += "\n## Units\n\n"
	for unit in units:
		# Solo units have a squad object but no name -- print membership only when it means something.
		var squad_note: String = ""
		if unit.has_squad():
			squad_note = ", %s" % _squad_label(unit.squad)
		out += "- %s (%s) @ %s -- HP %d/%d, Will %d, %s%s\n" % [
			unit.get_unit_name(),
			Team.Faction.keys()[unit.get_faction()],
			unit.movement.cell,
			unit.unit_instance.current_hp,
			unit.get_max_hp(),
			unit.unit_instance.current_will,
			Unit.LifecycleState.keys()[unit.lifecycle_state],
			squad_note,
		]
			
	out += "\n## Engine log (last %d lines)\n\n```\n%s\n```\n" % [LOG_TAIL_LINES, log_tail]
	return out

# The active squad is whose plan the panel is showing; fall back to whoever is selected.
func _plan_squad() -> Squad:
	var active: Squad = game.squad_manager.active_squad
	if active != null:
		return active
	var selected: Unit = game.selected_unit
	if selected != null:
		return selected.squad
	return null

# One answer to "what do I call this squad": a solo squad is never named, so fall back to its leader.
static func _squad_label(squad: Squad) -> String:
	if squad.squad_name != "":
		return squad.squad_name
	return "%s's squad" % squad.get_leader().get_unit_name()

# Numbers come straight off action.resolved -- the same ResolvedOutcome the queue panel reads, so
# there is no second source, only a second FORMAT. Deliberately RAW: the panel clamps a fatal
# hp_after to 0/1 for display, and re-deriving that ladder here would duplicate a decision
# LethalityRules owns. An overkill of -7 is exactly what a bug report wants to show.
static func _outcome_note(action: BaseAction) -> String:
	var atk := action as AttackAction
	if atk == null or atk.resolved == null:
		return ""
	return "  (%d dmg, HP %d -> %d raw, %s)" % [
		atk.resolved.damage,
		atk.resolved.hp_before,
		atk.resolved.target_hp_after,
		ResolvedOutcome.Lethality.keys()[atk.resolved.lethality],
	]

func _log_tail() -> String:
	var file := FileAccess.open("user://logs/godot.log", FileAccess.READ)
	if file == null:
		return "(no godot.log -- file logging is off)"
	var lines := file.get_as_text().split("\n")
	return "\n".join(lines.slice(maxi(0, lines.size() - LOG_TAIL_LINES)))
