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
#
# IT OVERRIDES THE FRAME STEP so the column FILLS the height instead of shrink-wrapping (#723).
# The base's unframed path returns a bare CenterContainer, which centres its child at the child's
# MINIMUM size -- so a column taller than the viewport overflows BOTH edges with no scrollbar, and
# the rows added last are the ones that fall off. Measured at 778px against a 720px design space
# with no save on disk, 832 with one: "Send Feedback" and "Quit Game" were below the bottom edge,
# which is why the title screen read as having no feedback door at all. #418's bug, one screen over.
#
# This is NOT window-size dependent, and that is why it needed fixing rather than shrugging at:
# GameSurface lays the UI out in a fixed DESIGN space (#659) that is exactly 1280x720 for ANY 16:9
# window, so a maximised 1440p monitor has the same 720px to spend as the dev's editor does.

signal mission_chosen(path: String)
signal load_game_chosen
signal sandbox_chosen
signal glossary_chosen
signal settings_chosen
signal credits_chosen
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
# `dev_tools` gates only what the SCREEN can gate: the Sandbox row, which is a hardcoded row with
# no list behind it, and the empty-state wording. It deliberately does NOT filter `other_paths` --
# WHICH boards belong in each list is MissionController's one answer (#860), and re-asking it here
# would be a second place to change when that rule moves. This screen renders what it is handed.
static func open(game_node: Node, mission_paths: Array[String], other_paths: Array[String],
		dev_tools := true) -> MissionSelectScreen:
	var screen := MissionSelectScreen.new()
	game_node.ui_layer.add_child(screen)
	screen._build(mission_paths, other_paths, dev_tools)
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
	# The build stamp (#134) -- the title screen names the build, same one-source read as the HUD.
	var version := Label.new()
	version.text = "v" + Build.version()
	version.add_theme_font_size_override("font_size", 12)
	version.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	version.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(version)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 12)

# Full-rect instead of the base's CenterContainer, so the column has the whole viewport to lay out
# in and the list below can absorb whatever the fixed rows leave. See the header for what the
# shrink-wrapped version did. Horizontal centring moves to the column itself, in _build.
func _build_frame() -> Container:
	var frame := MarginContainer.new()
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.add_theme_constant_override("margin_top", margin_v)
	frame.add_theme_constant_override("margin_bottom", margin_v)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE   # never eat a click meant for a button
	add_child(frame)
	return frame

func _build(mission_paths: Array[String], other_paths: Array[String], dev_tools := true) -> void:
	var column := _build_chrome()
	# The centring the CenterContainer used to do, on the axis that still wants it. Vertically the
	# column now FILLS, which is the whole point of the frame override.
	column.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_build_title(column, "SELECT MISSION")

	# The list scrolls: scenarios + fixtures accumulate, and an unbounded column would run off
	# the viewport with no way to reach the bottom entries.
	#
	# ITS HEIGHT IS WHAT THE FIXED ROWS LEAVE, never a number of its own (#723). A fixed 420 here
	# is what pushed the column past the bottom edge, and any row added below -- #724's reorder,
	# a new page -- would have pushed it further with nothing to notice. Expanding instead means
	# the list is the part that gives, which is right: it is the only region that can scroll.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(BUTTON_WIDTH + 16, 0)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	if mission_paths.is_empty():
		var hint := Label.new()
		# TWO empty states since #860, and the old text lies in the new one: a shipped build with
		# nothing ticked has missions on disk, so telling the reader to go save one is wrong.
		if dev_tools:
			hint.text = "No missions yet — save a scenario named  missions/<name>"
		else:
			hint.text = "No missions available in this build."
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

	# The way back into a saved battle (#144). Only offered when a slot is actually filled --
	# unlike the pause menu's greyed row, a stranger on the title screen with no saves has
	# nothing this row could teach.
	if ScenarioManager.any_save_exists():
		_add_button(column, "Load Game", func(): load_game_chosen.emit())

	# Dev scaffolding, deliberately last: TestBoard is no longer the boot path, but it is still
	# the fastest way onto a board with units on it. GATED since #860 -- it had shipped to every
	# exported build, one row under the fixtures its own comment calls development content.
	if dev_tools:
		_add_button(column, "Sandbox (Test Board)", func(): sandbox_chosen.emit(), Color(0.72, 0.72, 0.78))

	column.add_child(HSeparator.new())

	# The reference page (#135): readable before ever starting a mission, so a stranger can meet
	# the vocabulary before the vocabulary meets them.
	_add_button(column, "Glossary", func(): glossary_chosen.emit())

	# The options page (#350), beside the reference page and for the same reason -- a preference
	# set before the first mission is one the player never has to pause to find.
	_add_button(column, "Settings", func(): settings_chosen.emit())

	# Who made what in this build (#139). Two of its rows are licence CONDITIONS rather than
	# courtesies, so this row is what keeps the build inside the terms it was granted under.
	_add_button(column, "Credits", func(): credits_chosen.emit())

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
