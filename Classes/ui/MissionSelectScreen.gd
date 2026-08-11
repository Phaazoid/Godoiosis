extends ModalCard
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
# Signal-based rather than awaited (unlike MissionEndBanner): this screen outlives
# any single choice -- MissionController reopens it every time a mission ends.
#
# The ModalCard surface that is NOT a card: a full-screen takeover, so it is UNFRAMED (no panel or
# margin, the content column sits straight in the centre) and it does NOT claim ModalLock -- it is
# not a modal, and a Game left DISABLED behind it would never run the mission picked next
# (pinned by test_return_to_title_lands_on_the_menu_with_the_game_thawed).

signal mission_chosen(path: String)
signal sandbox_chosen
signal glossary_chosen
signal feedback_chosen
signal quit_chosen

const BUTTON_WIDTH := 360
const LIST_ROW_HEIGHT := 40

func _init() -> void:
	claims_modal_lock = false
	framed = false
	# OPAQUE, and that is LOAD-BEARING rather than styling: MissionController.abandon_mission
	# deliberately leaves the abandoned board standing and relies on this to hide it.
	backdrop_color = Color(0.06, 0.06, 0.09)
	card_z_index = UiLayers.MENU_SCREEN
	content_alignment = BoxContainer.ALIGNMENT_BEGIN
	content_separation = 10
	title_font_size = 36
	button_size = Vector2(BUTTON_WIDTH, 44)

# Takes the Game node rather than a parent, for the reason PauseMenu.show_menu does -- one
# construction convention across every ModalCard, even the one that does not lock.
static func open(game_node: Node, mission_paths: Array[String], other_paths: Array[String]) -> MissionSelectScreen:
	var screen := MissionSelectScreen.new()
	game_node.ui_layer.add_child(screen)
	screen._build(mission_paths, other_paths)
	return screen

# Branding sits between the backdrop and the content column -- which is exactly what the base's
# _build_branding step is for; adding it after _build_chrome would draw it over the menu.
func _build_branding() -> void:
	var logo := TextureRect.new()
	logo.texture = preload("res://Art/UI/Logo.png")
	logo.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	logo.position = Vector2(24, 24)
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never eat a click meant for a button
	add_child(logo)

func _build(mission_paths: Array[String], other_paths: Array[String]) -> void:
	var column := _build_chrome()
	_build_title(column, "SELECT MISSION")

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
			_add_board_button(list, path, Color(1, 1, 1))

	# Everything outside missions/ -- root playtest saves and fixtures/. Dimmer, and below the
	# missions, but selectable: during development these ARE the content.
	if not other_paths.is_empty():
		_add_section(list, "SCENARIOS & FIXTURES")
		for path in other_paths:
			_add_board_button(list, path, Color(0.72, 0.72, 0.78))

	column.add_child(HSeparator.new())

	# Dev scaffolding, deliberately last: TestBoard is no longer the boot path, but it is still
	# the fastest way onto a board with units on it.
	_add_button(column, "Sandbox (Test Board)", func(): sandbox_chosen.emit(), Color(0.72, 0.72, 0.78))

	column.add_child(HSeparator.new())

	# The reference page (#135): readable before ever starting a mission, so a stranger can meet
	# the vocabulary before the vocabulary meets them.
	_add_button(column, "Glossary", func(): glossary_chosen.emit())

	# Someone who bounces off this screen without ever starting a mission still has something to
	# tell us, and it is the one thing a mid-battle pause menu can never collect (#131).
	_add_button(column, "Send Feedback", func(): feedback_chosen.emit())
	_add_button(column, "Quit Game", func(): quit_chosen.emit(), Color(0.85, 0.6, 0.6))

func _add_section(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = Color(0.6, 0.6, 0.68)
	parent.add_child(label)

# Label = the path the dev typed when saving, minus the Scenarios/ root and the extension --
# so "missions/Camp" reads as "Camp" and "fixtures/SquadJoinLeave" keeps its folder.
func _add_board_button(parent: Container, path: String, tint: Color) -> void:
	var label := path.trim_prefix(ScenarioManager.SCENARIO_DIR).trim_suffix(".tres")
	var button := _add_button(parent, label.trim_prefix("missions/"),
		func(): mission_chosen.emit(path), tint)
	button.custom_minimum_size.y = LIST_ROW_HEIGHT   # list rows sit tighter than the action buttons
