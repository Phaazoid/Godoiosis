extends Control
class_name CrisisPrompt

# Code-built modal for the Crisis Mode offer (#33, will-and-death.md). One-off awaited dialog;
# Control-based so it lives inside the game viewport and dodges the embedded-Window quirks.
# Usage:  var accept: bool = await CrisisPrompt.show_prompt(ui_layer, unit_name)

signal chosen(accept: bool)

static func show_prompt(parent: Node, unit_name: String) -> bool:
	var prompt := CrisisPrompt.new()
	parent.add_child(prompt)
	prompt._build(unit_name)
	var accept: bool = await prompt.chosen
	prompt.queue_free()
	return accept

func _build(unit_name: String) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # eat stray clicks meant for the board behind

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var panel := PanelContainer.new()
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "ENTER CRISIS MODE?"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.modulate = Color(1, 0.3, 0.3)
	vbox.add_child(title)

	var body := Label.new()
	body.text = "%s is going down.\nRise at 5 HP with a surge — but Will locks at 0,\nand the next fall is DEATH." % unit_name
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(body)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	vbox.add_child(buttons)

	var yes := Button.new()
	yes.text = "YES — Crisis"
	yes.custom_minimum_size = Vector2(150, 48)
	yes.pressed.connect(func(): chosen.emit(true))
	buttons.add_child(yes)

	var no := Button.new()
	no.text = "NO — Stay Down"
	no.custom_minimum_size = Vector2(150, 48)
	no.pressed.connect(func(): chosen.emit(false))
	buttons.add_child(no)

	# A pulse so it reads as a big moment. Bound to this node, so it stops when we free.
	var tween := create_tween().set_loops()
	tween.tween_property(title, "modulate", Color(1, 0.75, 0.2), 0.4)
	tween.tween_property(title, "modulate", Color(1, 0.3, 0.3), 0.4)
