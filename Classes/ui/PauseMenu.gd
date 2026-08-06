extends ModalCard
class_name PauseMenu

# The in-play pause card (#132): the only way a demo player can restart a botched mission or
# leave the game. Built on ModalCard, the base shared with every other full-screen surface.

enum Choice { RESUME, RESTART, TITLE, REPORT, QUIT }

signal chosen(choice: Choice)

func _init() -> void:
	title_font_size = 40
	button_size = Vector2(220, 44)

# Takes the Game node rather than a parent: ModalLock needs it (it is what gets frozen), and
# deriving the parent from it removes any chance of a modal being built outside ui_layer.
static func show_menu(game_node: Node, can_restart: bool) -> Choice:
	var menu := PauseMenu.new()
	game_node.ui_layer.add_child(menu)
	menu._build(can_restart, game_node)
	var choice: Choice = await menu.chosen
	menu.queue_free()
	return choice

func _build(can_restart: bool, game_node: Node) -> void:
	var content := _build_chrome(game_node)
	_build_title(content, "PAUSED")

	# The one card whose choices stack vertically: five rows read as a list, not a button bar.
	var row := _build_button_row(content, true, content_separation)

	_add_button(row, "Resume", func(): chosen.emit(Choice.RESUME))

	# Hidden on a board with nothing to reload (the Sandbox), mirroring MissionEndBanner's retry.
	if can_restart:
		_add_button(row, "Restart Mission", func(): chosen.emit(Choice.RESTART))

	# Always offered, unlike Restart: a Sandbox board has no file to reload but the way out of it
	# is the same. Before this the only route back to the title was finishing a mission.
	_add_button(row, "Return to Title", func(): chosen.emit(Choice.TITLE))

	# The demo's report affordance (#131). F3 is correct for the developer and invisible to
	# a stranger, so it needs a row somebody can find without being told it exists.
	_add_button(row, "Report a Bug / Feedback", func(): chosen.emit(Choice.REPORT))

	_add_button(row, "Quit Game", func(): chosen.emit(Choice.QUIT), Color(0.85, 0.6, 0.6))
