extends Control
class_name PreMissionBar

# The pre-mission phase's board-side affordance (#774). The screen (#740) swaps away so the player
# can look at the ground they are about to fight over, and before this there was nothing left on
# screen saying the phase was still running: #739 takes the queue dock and End Turn down for the
# phase, so the board came up with a lit deployment zone, no chrome, and two keys nobody had been
# told about. The dev found the way back missing by looking for it and not finding it.
#
# IT SITS IN END TURN'S SLOT, empty and still reserved during the phase -- MissionStatusPanel lifts
# itself BUTTON_CLEARANCE clear of the corner whether or not that button is visible, so this reflows
# nothing. The height is read OFF that clearance rather than measured again: the slot is one fact,
# and a second copy of it is how the panel and the corner drift apart.
#
# Root is full-rect with mouse_filter IGNORE, the MissionStatusPanel/EndTurnButton shape -- it sits
# in UILayer without eating clicks anywhere but its own two buttons. That is also what keeps the 3D
# view honest: battle3d picks cells from _unhandled_input, so a click one of these Buttons consumes
# never reaches its raycast. (The SCREEN cannot rely on that and joins game.menu_is_up() instead,
# because it has to stop picks that land nowhere near a control.)
#
# MissionController owns the lifecycle, in the same one place the screen's lives -- built at the
# phase's entry, freed by _close_deployment_menu, swapped with the screen by toggle_deployment_menu.
# The two are never up together, and inside the phase never both down.
#
# NEITHER BUTTON GREYS. Begin with nobody placed is refused with a VOICE (#739), and the screen's own
# Begin carries the same rule -- two surfaces, one refusal.
#
# No cinematic term, and that is a declaration rather than an omission: the director is unarmed until
# commit_deployment, so no playback pass can start while this is on screen.

const CORNER_MARGIN := MissionStatusPanel.CORNER_MARGIN
const SLOT_HEIGHT := MissionStatusPanel.BUTTON_CLEARANCE - MissionStatusPanel.CORNER_MARGIN
const BUTTON_SEPARATION := 6

var _controller: MissionController
var _loadout_button: Button
var _begin_button: Button


static func open(game_node: Node, controller: MissionController) -> PreMissionBar:
	var bar := PreMissionBar.new()
	bar._controller = controller
	game_node.ui_layer.add_child(bar)
	bar._build()
	return bar


func _build() -> void:
	z_index = UiLayers.MISSION_STATUS   # the same always-on corner-HUD tier as the panel above us
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", BUTTON_SEPARATION)
	add_child(row)

	_loadout_button = _button("Loadout",
		"Back to the roster, the stash and the contract (Tab).", _controller.toggle_deployment_menu)
	_loadout_button.add_theme_stylebox_override("normal", QueueStyle.row_box(false, false))
	_loadout_button.add_theme_stylebox_override("hover", QueueStyle.row_box(false, true))
	row.add_child(_loadout_button)

	_begin_button = _button("Begin Mission",
		"Start the battle with the force you have placed (Enter).", _controller.commit_deployment)
	_begin_button.add_theme_stylebox_override("normal", QueueStyle.execute_box())
	_begin_button.add_theme_stylebox_override("hover", QueueStyle.execute_hover_box())
	_begin_button.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.EXECUTE_TEXT))
	row.add_child(_begin_button)

	# From the row's own minimum size, after both buttons are in it -- the MissionStatusPanel idiom.
	row.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE,
		CORNER_MARGIN)


# FOCUS_NONE is load-bearing rather than tidiness: Tab is ALSO Godot's built-in ui_focus_next, so a
# focusable button in this row would collect a focus ring from the very key that swaps the screen
# back -- and then answer Space and Enter as well.
func _button(text: String, tip: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = UiText.wrap(tip)
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = SLOT_HEIGHT
	button.pressed.connect(action)
	return button


# The board preview and back (#731 ruling 6) -- the other half of the screen's own set_shown. No
# set_process_input twin: this has no _input of its own to silence.
func set_shown(shown: bool) -> void:
	visible = shown
