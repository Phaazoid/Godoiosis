extends ModalCard
class_name PauseMenu

# The in-play pause card (#132): the only way a demo player can restart a botched mission or
# leave the game. Built on ModalCard, the base shared with every other full-screen surface.

enum Choice { RESUME, RESTART, TITLE, GLOSSARY, REPORT, QUIT, SAVE_GAME, LOAD_GAME, SETTINGS }

signal chosen(choice: Choice)

func _init() -> void:
	title_font_size = 40
	button_size = Vector2(220, 44)

# Takes the Game node rather than a parent: ModalLock needs it (it is what gets frozen), and
# deriving the parent from it removes any chance of a modal being built outside ui_layer.
static func show_menu(game_node: Node, can_restart: bool, can_load: bool) -> Choice:
	var menu := PauseMenu.new()
	game_node.ui_layer.add_child(menu)
	menu._build(can_restart, can_load, game_node)
	var choice: Choice = await menu.chosen
	menu.queue_free()
	return choice

func _build(can_restart: bool, can_load: bool, game_node: Node) -> void:
	var content := _build_chrome(game_node)
	_build_title(content, "PAUSED")

	# The one card whose choices stack vertically: the rows read as a list, not a button bar.
	var row := _build_button_row(content, true, content_separation)

	_add_button(row, "Resume", func(): chosen.emit(Choice.RESUME))

	# Hidden on a board with nothing to reload (the Sandbox), mirroring MissionEndBanner's retry.
	if can_restart:
		_add_button(row, "Restart Mission", func(): chosen.emit(Choice.RESTART))

	# Save rides Restart's gate (#144): missions only, for now -- a sandbox save would have no
	# origin mission for Restart to return to. Campaign-scope saving is its own future issue.
	#
	# ...and is greyed during the pre-mission phase (#739), with the reason, on the Load row's
	# rule that a menu can only grey what it can explain (#166). The real gate is
	# ScenarioManager.save_to_slot -- this row is only its surface -- and the reason is worth
	# spelling out because the damage is silent: a save mid-phase records the units already placed
	# and nothing else, so resuming it drops the rest of the roster with no way to finish choosing.
	if can_restart:
		var save_button := _add_button(row, "Save Game", func(): chosen.emit(Choice.SAVE_GAME))
		if game_node.mission_controller.is_deploying():
			save_button.disabled = true
			save_button.tooltip_text = UiText.wrap(
				"Not while you are deploying -- a save would keep only the units already placed. "
				+ "Begin the mission first.")

	# Greyed rather than hidden when there is nothing to load: the row teaches that saving exists,
	# and a menu can only grey what it can explain (#166).
	var load_button := _add_button(row, "Load Game", func(): chosen.emit(Choice.LOAD_GAME))
	if not can_load:
		load_button.disabled = true
		load_button.tooltip_text = UiText.wrap("No saved games yet")

	# Always offered, unlike Restart: a Sandbox board has no file to reload but the way out of it
	# is the same. Before this the only route back to the title was finishing a mission.
	_add_button(row, "Return to Title", func(): chosen.emit(Choice.TITLE))

	# The reference page (#135) — reachable mid-battle, because mid-battle is when a stranger
	# first meets a term they don't know.
	_add_button(row, "Glossary", func(): chosen.emit(Choice.GLOSSARY))

	# The options page (#350). Sits under the reference page for the same reason that one exists:
	# a setting a player cannot find is a setting they do not have.
	_add_button(row, "Settings", func(): chosen.emit(Choice.SETTINGS))

	# The demo's report affordance (#131). F3 is correct for the developer and invisible to
	# a stranger, so it needs a row somebody can find without being told it exists.
	_add_button(row, "Report a Bug / Feedback", func(): chosen.emit(Choice.REPORT))

	_add_button(row, "Quit Game", func(): chosen.emit(Choice.QUIT), Color(0.85, 0.6, 0.6))


# Esc RESUMES -- the key that opened the card closes it, which is the one binding a player tries
# without being told. It was dead here for the same reason it was dead on the settings page: this
# card never answered ui_cancel, and game._input stands down while any modal is up.
func _on_cancel() -> bool:
	chosen.emit(Choice.RESUME)
	return true
