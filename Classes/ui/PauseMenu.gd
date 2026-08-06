extends Control
class_name PauseMenu

# The in-play pause card (#132): the only way a demo player can restart a botched mission or
# leave the game. MissionEndBanner's shape -- Control-based, awaited, one Choice out.

enum Choice { RESUME, RESTART, TITLE, REPORT, QUIT }

signal chosen(choice: Choice)

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
	# Freezes the game subtree and marks this as the open modal (#131). Two jobs, one call: it stops
	# the board moving behind the card, and it stops game._input opening a report card on top of
	# this one -- the Esc gate is relaxed while the board is locked, and MENU counts as locked.
	ModalLock.claim(self, game_node)

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # eat stray clicks meant for the board behind

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	vbox.add_child(title)

	var resume := Button.new()
	resume.text = "Resume"
	resume.custom_minimum_size = Vector2(220, 44)
	resume.pressed.connect(func(): chosen.emit(Choice.RESUME))
	vbox.add_child(resume)

	# Hidden on a board with nothing to reload (the Sandbox), mirroring MissionEndBanner's retry.
	if can_restart:
		var restart := Button.new()
		restart.text = "Restart Mission"
		restart.custom_minimum_size = Vector2(220, 44)
		restart.pressed.connect(func(): chosen.emit(Choice.RESTART))
		vbox.add_child(restart)

	# Always offered, unlike Restart: a Sandbox board has no file to reload but the way out of it
	# is the same. Before this the only route back to the title was finishing a mission.
	var title_row := Button.new()
	title_row.text = "Return to Title"
	title_row.custom_minimum_size = Vector2(220, 44)
	title_row.pressed.connect(func(): chosen.emit(Choice.TITLE))
	vbox.add_child(title_row)

	# The demo's report affordance (#131). F3 is correct for the developer and invisible to
	# a stranger, so it needs a row somebody can find without being told it exists.
	var report := Button.new()
	report.text = "Report a Bug / Feedback"
	report.custom_minimum_size = Vector2(220, 44)
	report.pressed.connect(func(): chosen.emit(Choice.REPORT))
	vbox.add_child(report)

	var quit := Button.new()
	quit.text = "Quit Game"
	quit.custom_minimum_size = Vector2(220, 44)
	quit.modulate = Color(0.85, 0.6, 0.6)
	quit.pressed.connect(func(): chosen.emit(Choice.QUIT))
	vbox.add_child(quit)
