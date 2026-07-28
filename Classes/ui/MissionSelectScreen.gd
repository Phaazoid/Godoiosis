extends Control
class_name MissionSelectScreen

# The game's front door (#96 slice 2) -- the first thing that appears, replacing the hardcoded
# TestBoard game._ready used to spawn. NOT a main menu yet: no title art, no options, no save
# slots. It answers one question -- which board are we playing? -- and is the thing a real main
# menu grows out of.
#
# There is ONE board resource, ScenarioData. A "mission" is a scenario saved under
# Scenarios/missions/; a fixture is one saved under Scenarios/fixtures/. The folder is the only
# difference, and objectives (slices 3-4) land on ScenarioData directly rather than in a wrapper
# resource -- a mission and its board are 1:1, so a wrapper would be an extra hop, not a split.
#
# Signal-based rather than awaited (unlike CrisisPrompt/MissionEndBanner): this screen outlives
# any single choice -- MissionController reopens it every time a mission ends.
#
# SIZING: uses set_anchors_and_offsets_preset, not set_anchors_preset. This screen is built
# during game._ready(), before the SubViewport container has computed a size, so anchors alone
# leave it 0x0 -- the background covers nothing and CenterContainer centres on the origin.
# Z_INDEX: HoverInfoPanelControl.tscn sets z_index = 2, which beats sibling order, so a
# full-screen takeover has to out-rank it explicitly.

signal mission_chosen(path: String)
signal sandbox_chosen

const MENU_Z := 100
const BUTTON_WIDTH := 360

static func open(parent: Node, mission_paths: Array[String], other_paths: Array[String]) -> MissionSelectScreen:
	var screen := MissionSelectScreen.new()
	parent.add_child(screen)
	screen._build(mission_paths, other_paths)
	return screen

func _build(mission_paths: Array[String], other_paths: Array[String]) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = MENU_Z

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.09)   # opaque: at boot there is no board behind this yet
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	# Branding
	var logo := TextureRect.new()
	logo.texture = preload("res://Art/UI/Logo.png")
	logo.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	logo.position = Vector2(24, 24)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never eat a click meant for a button
	add_child(logo)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)

	var title := Label.new()
	title.text = "SELECT MISSION"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	column.add_child(title)

	# The list scrolls: scenarios + fixtures accumulate, and an unbounded column would run off
	# the viewport with no way to reach the bottom entries.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(BUTTON_WIDTH + 16, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	if mission_paths.is_empty():
		var hint := Label.new()
		hint.text = "No missions yet — save a scenario named  missions/<name>"
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.modulate = Color(0.7, 0.7, 0.75)
		list.add_child(hint)
	else:
		_add_section(list, "MISSIONS")
		for path in mission_paths:
			list.add_child(_board_button(path, Color(1, 1, 1)))

	# Everything outside missions/ -- root playtest saves and fixtures/. Dimmer, and below the
	# missions, but selectable: during development these ARE the content.
	if not other_paths.is_empty():
		_add_section(list, "SCENARIOS & FIXTURES")
		for path in other_paths:
			list.add_child(_board_button(path, Color(0.72, 0.72, 0.78)))

	column.add_child(HSeparator.new())

	# Dev scaffolding, deliberately last: TestBoard is no longer the boot path, but it is still
	# the fastest way onto a board with units on it.
	var sandbox := Button.new()
	sandbox.text = "Sandbox (Test Board)"
	sandbox.custom_minimum_size = Vector2(BUTTON_WIDTH, 44)
	sandbox.modulate = Color(0.72, 0.72, 0.78)
	sandbox.pressed.connect(func(): sandbox_chosen.emit())
	column.add_child(sandbox)

func _add_section(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = Color(0.6, 0.6, 0.68)
	parent.add_child(label)

# Label = the path the dev typed when saving, minus the Scenarios/ root and the extension --
# so "missions/Camp" reads as "Camp" and "fixtures/SquadJoinLeave" keeps its folder.
func _board_button(path: String, tint: Color) -> Button:
	var button := Button.new()
	var label := path.trim_prefix(ScenarioManager.SCENARIO_DIR).trim_suffix(".tres")
	button.text = label.trim_prefix("missions/")
	button.custom_minimum_size = Vector2(BUTTON_WIDTH, 40)
	button.modulate = tint
	button.pressed.connect(func(): mission_chosen.emit(path))
	return button
