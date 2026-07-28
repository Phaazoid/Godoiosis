extends Control
class_name MissionEndBanner

# The end-of-mission card (#96 slice 1) -- the moment the game finally has an ENDING to show.
# Code-built modal in CrisisPrompt's shape: Control-based so it lives inside the game viewport
# and dodges the embedded-Window quirks (CLAUDE.md "Sharp edges").
#
# Usage:  var choice: Choice = await MissionEndBanner.show_banner(ui_layer, victory, can_retry)
#
# Slice 2 replaces "Dismiss" with a return to mission select. The button is a stub; the awaited
# bool contract is not.

# STAY leaves the finished board standing so it can be inspected with the dev tools; the mission
# is still over either way (MissionController's latch never unwinds).
enum Choice { RETRY, MISSION_SELECT, STAY }

signal chosen(choice: Choice)

static func show_banner(parent: Node, victory: bool, can_retry: bool) -> Choice:
	var banner := MissionEndBanner.new()
	parent.add_child(banner)
	banner._build(victory, can_retry)
	var choice: Choice = await banner.chosen
	banner.queue_free()
	return choice

func _build(victory: bool, can_retry: bool) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP   # eat stray clicks meant for the board behind

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
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
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 32)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "VICTORY" if victory else "DEFEAT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.modulate = Color(1, 0.85, 0.3) if victory else Color(0.85, 0.2, 0.2)
	vbox.add_child(title)

	var body := Label.new()
	body.text = "The field is yours." if victory else "Your squad has fallen."
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(body)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	vbox.add_child(buttons)

	# Hidden on a board that wasn't loaded from disk (the Sandbox board): there is nothing to
	# reload, and a dead button is worse than no button.
	if can_retry:
		var retry_button := Button.new()
		retry_button.text = "Retry Mission"
		retry_button.custom_minimum_size = Vector2(160, 48)
		retry_button.pressed.connect(func(): chosen.emit(Choice.RETRY))
		buttons.add_child(retry_button)

	var select := Button.new()
	select.text = "Mission Select"
	select.custom_minimum_size = Vector2(160, 48)
	select.pressed.connect(func(): chosen.emit(Choice.MISSION_SELECT))
	buttons.add_child(select)

	var stay := Button.new()
	stay.text = "Stay (inspect)"
	stay.custom_minimum_size = Vector2(160, 48)
	stay.modulate = Color(0.75, 0.75, 0.8)
	stay.pressed.connect(func(): chosen.emit(Choice.STAY))
	buttons.add_child(stay)
