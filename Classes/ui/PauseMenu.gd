extends Control
class_name PauseMenu

# The in-play pause card (#132): the only way a demo player can restart a botched mission or
# leave the game. MissionEndBanner's shape -- Control-based, awaited, one Choice out.

enum Choice { RESUME, RESTART, QUIT }

signal chosen(choice: Choice)

static func show_menu(parent: Node, can_restart: bool) -> Choice:
	var menu := PauseMenu.new()
	parent.add_child(menu)
	menu._build(can_restart)
	var choice: Choice = await menu.chosen
	menu.queue_free()
	return choice

func _build(can_restart: bool) -> void:
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

	var quit := Button.new()
	quit.text = "Quit Game"
	quit.custom_minimum_size = Vector2(220, 44)
	quit.modulate = Color(0.85, 0.6, 0.6)
	quit.pressed.connect(func(): chosen.emit(Choice.QUIT))
	vbox.add_child(quit)
