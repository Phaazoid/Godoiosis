extends Node
class_name ActionMenuController

# Control-based replacement for the old PopupMenu (a subwindow). A CanvasLayer holding a
# PanelContainer of Buttons is immune to the embed/subwindow quirks that forced the manual
# _input() dismissal patch (CLAUDE.md "Sharp edges"): an outside click lands on a full-rect
# backdrop Control instead. Buttons consume their own clicks, so a click on the menu never
# reaches the backdrop.
#
# Behavior preserved from the PopupMenu version: picking an item emits `cancelled` (the old
# popup_hide -> clear_selection) and THEN `action_selected`, so the handlers with no state of
# their own (Inspect, Leave/Disband Squad, Execute Orders) still return to IDLE, and the
# targeting handlers (Move/Attack/Rescue/Group Move/Squad) re-set their state afterwards. This
# pins the clear-then-act order the old code left up to Godot's popup_hide/id_pressed ordering.

const MENU_MARGIN := 6   # px kept between the panel and the viewport edge

var local_unit: Unit

var _layer: CanvasLayer
var _backdrop: Control
var _panel: PanelContainer
var _button_box: VBoxContainer
var _wanted_pos: Vector2 = Vector2.ZERO

signal action_selected(action_id, local_unit)
signal cancelled(me)

func setup(unit: Unit) -> void:
	local_unit = unit

	_layer = CanvasLayer.new()
	_layer.layer = 10   # above the board + HUD so the modal backdrop actually covers them
	add_child(_layer)

	# Backdrop: fills the view, sits behind the panel, turns any click that misses the panel
	# into a cancel. Replaces the old _input() outside-click hack.
	_backdrop = Control.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.gui_input.connect(_on_backdrop_input)
	_layer.add_child(_backdrop)

	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_layer.add_child(_panel)

	_button_box = VBoxContainer.new()
	_panel.add_child(_button_box)

func populate(items: Array, action_data: Dictionary) -> void:
	for item in items:
		var button := Button.new()
		button.text = action_data[item].name
		button.focus_mode = Control.FOCUS_NONE
		if action_data[item].get("disabled", false):
			button.disabled = true
			button.tooltip_text = action_data[item].get("tooltip", "")
		else:
			button.pressed.connect(_on_button_pressed.bind(item))
		_button_box.add_child(button)

func setpos(pos: Vector2i) -> void:
	_wanted_pos = Vector2(pos)
	# Panel size isn't known until it lays out, so place it after this frame.
	_place_panel.call_deferred()

func _place_panel() -> void:
	if _panel == null:
		return
	var view_size := _panel.get_viewport_rect().size
	var panel_size := _panel.get_combined_minimum_size()
	var p := _wanted_pos
	# Clamp so the menu never opens off the edge of the view.
	p.x = clampf(p.x, MENU_MARGIN, maxf(MENU_MARGIN, view_size.x - panel_size.x - MENU_MARGIN))
	p.y = clampf(p.y, MENU_MARGIN, maxf(MENU_MARGIN, view_size.y - panel_size.y - MENU_MARGIN))
	_panel.position = p

func _on_button_pressed(action_id: int) -> void:
	# clear-then-act: cancelled (-> clear_selection) first, then run the action. See header.
	cancelled.emit(self)
	action_selected.emit(action_id, local_unit)
	cleanup()

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		cancelled.emit(self)
		cleanup()

func cleanup() -> void:
	queue_free()
