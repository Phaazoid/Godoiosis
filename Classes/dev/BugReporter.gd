extends Node
class_name BugReporter

# The report system (#128, made player-facing by #131): one keypress or one card writes the live
# board, the queued plan, the player's own note and the tail of the engine log to
# user://reports/<stamp>/, then ships it to the intake endpoint. Built in
# game._build_collaborators with a `game` back-ref (the DevController pattern).
#
# user:// and not res://: res:// is read-only once exported, so the whole feature was inert in a
# build. Reports also stay outside Scenarios/, so Mission Select and #9's folder scan never see one.
#
# It owns NO state and adds no new seam: the board is ScenarioManager.capture_scenario (#87), the
# plan is ActionQueueDisplayEntry.build_for (what the queue panel draws), and the transport is
# ReportUploader, which never looks inside a report. board.tres is authoritative; report.md is a
# read-only projection of it plus what a scenario doesn't carry.
#
# Kind is the ONLY fork between a bug and a feedback note -- same folder, same files, same transport,
# same code path. Only the prompt and the label differ. That is the whole of what #131 item 6 asks
# for: what has to be distinct is the QUESTION, not the plumbing, and two transports for one act
# would be a second seam for a fact one field already carries.

enum Kind { BUG, FEEDBACK }

const REPORT_DIR := "user://reports/"
const LOG_TAIL_LINES := 80

# Discord caps a message at 2000 characters, and the untruncated note is in report.md regardless.
const NOTE_IN_MESSAGE := 400

# What the stamped lines say when nothing answered them (#240, #328). Named so a test can assert
# the honest sentence rather than the absence of a section.
const NO_3D_VIEW := "flat 2D (no 3D host)"
const DEFAULT_LOOK := "(default)"
const NO_DEVTOOLS := "closed"

var game   # untyped back-ref: game.gd has no class_name

# What the 3D host is showing, PUSHED in by battle3d._ready (#240) rather than looked up: the game
# subtree keeps no upward path to the 3D scene, which is why the Look host and HoverPresenter's
# pointer source arrive the same way. Unset = a flat Main.tscn launch, which the report says.
var view_source: Callable

var _uploader: ReportUploader
var _card: ReportPanel

func _ready() -> void:
	# It drives the whole exchange from behind a modal, so it outlives the freeze the modal sets.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_uploader = ReportUploader.new()
	add_child(_uploader)

func upload_configured() -> bool:
	return _uploader != null and _uploader.is_configured()

# The ONE path from "the player wants to say something" to a filed report. All four entry points
# call this and nothing else, because the frame has to be grabbed BEFORE the card covers the
# screen -- four callers each having to remember that is how you get three that do and one that
# doesn't. state_name is passed for the same reason report() takes it: game.gd owns GameState.
func open_card(state_name: String, default_kind: Kind, frame: Image = null) -> void:
	if is_instance_valid(_card):
		return   # already collecting; a second Esc must not stack a second card

	# A caller that already had something on screen grabs its own frame earlier and passes it in
	# (the pause menu does). Everyone else is opening the card over a clean board.
	if frame == null:
		frame = await capture_frame()
	var units: Array[Unit] = game._all_units()
	_card = ReportPanel.open(game, default_kind, not units.is_empty(), upload_configured())

	var submitted: bool = await _card.finished
	if not submitted:
		_close_card()
		return

	var kind := _card.selected_kind()
	var note := _card.note_text()
	_card.show_sending()
	var result: Dictionary = await report(state_name, kind, note, frame)

	# The upload can outlive its card: returning to mission select frees the whole ui_layer.
	if not is_instance_valid(_card):
		_card = null
		return
	_card.show_outcome(result["dir"], result["sent"])
	await _card.dismissed
	_close_card()

func _close_card() -> void:
	if is_instance_valid(_card):
		_card.queue_free()
	_card = null

# state_name is PASSED, not looked up -- game.gd owns the GameState enum. `frame` is passed for the
# same reason plus a sharper one: with four entry points the screenshot has to be grabbed BEFORE
# whatever card is about to cover the screen, so the MOMENT belongs to the caller. Pass null only
# from a path with nothing on top of the board (F3), and this grabs one itself.
#
# Returns {"dir": String, "sent": bool}. An empty dir means the write itself failed; `sent` false
# with a real dir means it is safely on disk and the player should be pointed at it.
func report(state_name: String, kind: Kind, note: String, frame: Image) -> Dictionary:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var dir := REPORT_DIR + stamp + "/"
	DirAccess.make_dir_recursive_absolute(dir)

	var units: Array[Unit] = game._all_units()

	# No units means no board worth snapshotting -- feedback sent from the mission select screen.
	if not units.is_empty():
		var scenario: ScenarioData = game.scenario_manager.capture_scenario("report-" + stamp)
		var board_path := dir + "board.tres"
		scenario.take_over_path(board_path)   # whoever writes a path claims it
		var save_err := ResourceSaver.save(scenario, board_path)
		if save_err != OK:
			push_error("Report: could not write board.tres (error %s)" % save_err)

	var squad := _plan_squad()
	var plan: ResolvedPlan = null
	if squad != null:
		# Resolve only, never validate: a dump READS state, it must not rewrite is_valid flags.
		plan = game.squad_manager.resolve_plan(squad, game._board())

	var md := FileAccess.open(dir + "report.md", FileAccess.WRITE)
	if md == null:
		push_error("Report: could not write report.md")
		return {"dir": "", "sent": false}
	var look: String = game.scenario_manager.current_look_preset
	md.store_string(build_report_text(stamp, state_name, kind, note, squad, plan, units, _log_tail(),
		_view_note(), look, _devtools_note()))
	md.close()

	if frame == null:
		frame = await capture_frame()
	# A report without its screenshot is still worth having, and ReportUploader already skips a
	# file that isn't there -- so an unsized viewport degrades the report instead of killing it.
	if frame != null and not frame.is_empty():
		frame.save_png(dir + "board.png")

	# The dev-tools window is a SECOND file, never a fork of the first (#328): it is a real OS
	# window with its own viewport, so it is not in the composited frame above by construction.
	# Nothing to grab when it is closed, which the report.md line above has already said.
	var dev_frame := await capture_devtools_frame()
	if dev_frame != null and not dev_frame.is_empty():
		dev_frame.save_png(dir + "devtools.png")

	print("Report written to %s" % ProjectSettings.globalize_path(dir))
	var sent: bool = await _uploader.submit(dir, build_summary(stamp, state_name, kind, note))
	return {"dir": dir, "sent": sent}

# The viewport texture is only valid after a draw, so this always costs a frame. Callers grab it
# BEFORE opening a card -- a screenshot taken with the report panel already up is a picture of the
# report panel, which is precisely the thing nobody is complaining about.
func capture_frame() -> Image:
	# A headless run never draws, so awaiting frame_post_draw there waits FOREVER -- not a slow
	# report, a hung one, and the caller is mid-await with a card on screen. A report with no
	# screenshot is already a supported outcome, so say so immediately instead.
	if DisplayServer.get_name() == "headless":
		return null
	await RenderingServer.frame_post_draw
	var texture: ViewportTexture = capture_viewport().get_texture()
	if texture == null:
		return null
	return texture.get_image()

# WHERE the picture comes from, and it is always the window's own viewport (#240).
#
# game.get_viewport() is the SubViewport the 2D game lives in, and since #222 that viewport is
# transparent with the board visuals hidden -- the 2D game is the UI layer drawn OVER the 3D
# world -- so a frame grabbed there is UI on nothing, with the diorama and every visual bug in
# it missing. The root is the COMPOSITED frame in every hosting mode by construction: HD_2D
# draws that UI over the diorama, FLAT_2D covers the window opaquely, CORNER adds the PiP,
# demo_mode hides the container, and a bare Main.tscn launch fills the window with the 2D game.
# So this is one answer rather than a fork on Battle3D's view, and the reporter never has to
# learn whether it is being hosted.
#
# Explicitly typed: `game` has no class_name, so everything reached through it is Variant and
# := cannot infer (CLAUDE.md, the untyped back-ref rule).
func capture_viewport() -> Viewport:
	var tree: SceneTree = game.get_tree()
	return tree.root

# Is there a dev-tools window to report on? (#328) ONE gate, read by both the report.md line and the
# screenshot, so the two can never disagree about whether it was up. Null in a demo build (game.gd's
# _find_dev_overlay returns null without DevTools.enabled()) and null while it is closed.
#
# Deliberately NOT a branch inside capture_viewport(): that answers where the COMPOSITED frame comes
# from, and #240 forbids forking it. This is a different question with a different answer.
func devtools_panel() -> DevOverlay:
	var overlay: DevOverlay = game.dev_overlay
	if overlay == null or not overlay.visible:
		return null
	return overlay

# The second picture. Same headless escape as capture_frame() and for the same reason -- awaiting
# frame_post_draw there never resumes and takes the calling coroutine with it.
func capture_devtools_frame() -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	var panel := devtools_panel()
	if panel == null:
		return null
	await RenderingServer.frame_post_draw
	var texture: ViewportTexture = panel.get_texture()   # a Window IS a Viewport
	if texture == null:
		return null
	return texture.get_image()

# Which tab was up -- free, and the half that survives Discord's CDN expiry when the picture does not.
func _devtools_note() -> String:
	var panel := devtools_panel()
	if panel == null:
		return ""
	return panel.current_tab_title()

func _view_note() -> String:
	if not view_source.is_valid():
		return ""
	var note: String = view_source.call()
	return note

# The Discord message body, derived from the same four facts report() writes into report.md so the
# channel and the attachment can never disagree. The note is truncated HERE only -- the full text
# is always in report.md, which is attached to the same message.
static func build_summary(stamp: String, state_name: String, kind: Kind, note: String) -> String:
	var trimmed := note.strip_edges()
	if trimmed == "":
		trimmed = "(nothing typed)"
	elif trimmed.length() > NOTE_IN_MESSAGE:
		trimmed = trimmed.substr(0, NOTE_IN_MESSAGE) + " ... (full text in report.md)"
	# The version appears in the channel line too -- a second RENDER of Build.version()'s one fact
	# (declared, Law #4), so reports can be matched to builds without opening the attachment. The
	# checkout rides along for the same reason and is the sharper of the two in triage: every
	# branch off a base shares its version, so only "branch @ sha" says which code ran (#295).
	var build := "v%s" % Build.version()
	var checkout := Checkout.describe()
	if checkout != "":
		build += " -- %s" % checkout
	return "**%s** - state `%s` - %s - %s\n>>> %s" % [Kind.keys()[kind], state_name, stamp, build, trimmed]

# Pure + static so it is testable without a game scene, the capture/save split again.
static func build_report_text(stamp: String, state_name: String, kind: Kind, note: String,
		squad: Squad, plan: ResolvedPlan, units: Array[Unit], log_tail: String,
		view_note := "", look_note := "", devtools_note := "") -> String:
	var out := "# %s report %s\n\n" % [Kind.keys()[kind].to_lower().capitalize(), stamp]

	out += "## What they wrote\n\n"
	out += "%s\n\n" % ("(nothing typed)" if note.strip_edges() == "" else note.strip_edges())

	out += "Game state: **%s**\n\n" % state_name
	out += "Build: **%s**\n\n" % Build.version()
	# WHICH CHECKOUT produced it (#295), beside the version rather than instead of it: they answer
	# different questions and a report outlives the session that could have answered either by
	# hand. Omitted entirely outside a dev build, where the question has no answer.
	var checkout := Checkout.describe()
	if checkout != "":
		out += "Checkout: **%s**\n\n" % checkout
	# WHERE it was seen from (#240). A 3D report whose angle nobody knows is a much weaker
	# report, and the two facts have two homes on purpose: the view is the 3D host's, pushed
	# in, while the look is the BOARD's own (ScenarioData.look_preset, #253 part 2).
	out += "View: **%s**\n\n" % (NO_3D_VIEW if view_note == "" else view_note)
	out += "Look: **%s**\n\n" % (DEFAULT_LOOK if look_note == "" else look_note)
	# WHICH DEV TAB was up (#328). Names the tab only, never devtools.png: a picture of a second OS
	# window can fail where this line cannot, and a report naming a file it does not carry is the
	# small lie that wastes a triage session.
	out += "Dev tools: **%s**\n\n" % (NO_DEVTOOLS if devtools_note == "" else devtools_note)
	if units.is_empty():
		out += "No units on the board -- sent from a menu, so there is no `board.tres` beside this.\n\n"
	else:
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
