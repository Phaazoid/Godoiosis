extends Control
class_name UnitInfoPanelControl

# Controller for the click-to-inspect panel (UnitInfoPanel.tscn) — a docked, full-height
# left column as of #68 (replaces the old flip-top/bottom popup). Owns show/hide + which
# unit is open, sets the header (name/jobs), and fans set_unit/clear out to the child
# sections so their signal hookups tear down together.
#
# Opened by the Inspect key (#1105): Z over a unit opens it here, Z again swaps the body for the tile
# that unit stands on, and a third Z closes it (inspect_step). The Unit/Tile buttons beside the
# portrait do the same swap by mouse. A swap rather than a section underneath because the unit body
# already fills the dock (660 of 700px on every authored unit, measured). An EMPTY tile is not
# inspected here -- it grows the hover card instead -- so the dock only ever holds a unit.
#
# The tile body is re-read every frame it shows and rebuilt only when what it says changed, so a
# watch firing or a fire spreading cannot leave it stale. It sits in its own scroll area as a safety
# net (dev, 2026-09-23): an ordinary tile fits with room to spare, and only a stack of watches and
# zones on one cell ever shows a bar.

enum View { UNIT, TILE }

const SWITCH_LABELS: Dictionary[View, String] = {View.UNIT: "Unit", View.TILE: "Tile"}   # PLACEHOLDER

@onready var portrait_panel = $UnitInfoPanel/Margin/VBox/HeaderRow/PortraitPanel
@onready var name_label: Label = $UnitInfoPanel/Margin/VBox/HeaderRow/HeaderText/NameLabel
@onready var jobs_label: Label = $UnitInfoPanel/Margin/VBox/HeaderRow/HeaderText/JobsLabel
@onready var stats_section = $UnitInfoPanel/Margin/VBox/StatsSection
@onready var inventory_panel = $UnitInfoPanel/Margin/VBox/InventoryPanel
@onready var squad_panel = $UnitInfoPanel/Margin/VBox/SquadInfoPanel
@onready var states_bar = $UnitInfoPanel/Margin/VBox/UnitStatesBar

# The player changed what this unit carries or holds. Forwarded rather than handled here: the
# panel knows nothing about the queue, and the plan's numbers are the game's to re-resolve (#697).
signal loadout_changed
signal loadout_acted(unit: Unit, verb: String, index: int)   # #53: what the player DID, not that it is stale

var current_unit: Unit
var current_board: BoardContext   # kept so a live refresh can recompute terrain-dependent DEF

# A cell's TileReadout sections, injected by game (the board_source idiom) so this panel never
# learns what a game is. Unset = the tile body stays empty.
var tile_sections_source: Callable

# Hidden while a cinematic pass owns the frame (#722), and what the CONTENT rule last decided.
# `_content_shown` is exactly what `visible` meant before #722, which is why is_showing/
# is_showing_unit read it: a panel hidden for a cinematic has NOT let go of its unit, and
# HoverPresenter asks those two to decide where the hover card parks and whether it would be a
# second card for the same unit. Answering "no unit is open" there would move the card mid-pass.
var _hidden_for_playback := false
var _content_shown := false

var _view := View.UNIT
var _tile_sections: TileInfoSections
var _tile_scroll: ScrollContainer
var _spacer: Control
var _switch: HBoxContainer
var _switch_buttons: Dictionary[View, Button] = {}
var _unit_body: Array[Control] = []

func _ready() -> void:
	$UnitInfoPanel/Margin/VBox/HeaderRow/CloseButton.pressed.connect(clear)
	inventory_panel.loadout_changed.connect(_refresh_derived_rows)
	inventory_panel.loadout_changed.connect(loadout_changed.emit)
	inventory_panel.loadout_acted.connect(loadout_acted.emit)   # #53: forwarded on the line above's idiom
	var body: VBoxContainer = $UnitInfoPanel/Margin/VBox
	_unit_body.assign([stats_section, $UnitInfoPanel/Margin/VBox/HSep3, inventory_panel, squad_panel,
		states_bar])
	_spacer = $UnitInfoPanel/Margin/VBox/Spacer
	# The tile body takes the height the header leaves, and scrolls only past it. The Spacer stands
	# down in tile view, or the two expanding children would split that height between them.
	_tile_scroll = ScrollContainer.new()
	_tile_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tile_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tile_scroll.visible = false
	_tile_sections = TileInfoSections.new(section_box())
	_tile_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tile_scroll.add_child(_tile_sections)
	body.add_child(_tile_scroll)
	body.move_child(_tile_scroll, squad_panel.get_index() + 1)
	_build_switch()

# Two toggles in one group, in the header's free space beside the portrait, so it costs no height.
func _build_switch() -> void:
	_switch = HBoxContainer.new()
	var group := ButtonGroup.new()
	for view: View in [View.UNIT, View.TILE]:
		var button := Button.new()
		button.text = SWITCH_LABELS[view]
		button.toggle_mode = true
		button.button_group = group
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(_set_view.bind(view))
		_switch.add_child(button)
		_switch_buttons[view] = button
	$UnitInfoPanel/Margin/VBox/HeaderRow/HeaderText.add_child(_switch)

func _process(_delta: float) -> void:
	if visible:
		_refresh_tile()

func set_unit(unit: Unit, can_act := false, board: BoardContext = null):
	if current_unit == unit:
		return
	if unit == null:
		clear()
		return
	_release_current_unit()
	current_unit = unit
	current_board = board
	_content_shown = true
	_apply_visibility()
	name_label.text = unit.get_unit_name()
	jobs_label.text = _jobs_text(unit)
	portrait_panel.set_unit(unit)
	stats_section.set_unit(unit, board)
	inventory_panel.set_unit(unit, can_act)
	squad_panel.set_unit(unit)
	states_bar.set_unit(unit)
	unit.movement.movement_finished.connect(_refresh_derived_rows)
	_set_view(View.UNIT)   # Inspect means the unit; its tile is one press away

# The Inspect key's cycle over one unit (#1105, dev: "Z on a unit could inspect the unit, tapping Z
# again to swap to the tile the unit is on"): opens it on Unit, then its tile, then closes.
func inspect_step(unit: Unit, can_act := false, board: BoardContext = null) -> void:
	if not is_showing_unit(unit):
		set_unit(unit, can_act, board)
	elif _view == View.UNIT:
		_set_view(View.TILE)
	else:
		clear()

func _set_view(view: View) -> void:
	_view = view
	_switch_buttons[view].set_pressed_no_signal(true)
	for node in _unit_body:
		node.visible = view == View.UNIT
	_spacer.visible = view == View.UNIT
	_tile_scroll.visible = view == View.TILE
	_tile_sections.forget()
	_refresh_tile()

func _refresh_tile() -> void:
	if _view != View.TILE or not tile_sections_source.is_valid():
		return
	if current_unit == null or not is_instance_valid(current_unit):
		return
	var sections: Array[TileReadout.Section] = tile_sections_source.call(current_unit.movement.cell)
	_tile_sections.show_if_changed(sections)

# Re-read only the derived numbers. set_unit early-returns on the same unit (it's called on every
# inspect), so a change made while the panel is OPEN would otherwise leave DEF and MOV showing
# their values from inspect time -- and re-inspecting cannot clear it. Two triggers, because two
# things move these numbers: a loadout edit, and ARRIVAL -- DEF's cover term is read at the unit's
# current cell, so walking on or off Cover changes it.
func _refresh_derived_rows():
	if current_unit == null:
		return
	stats_section.set_unit(current_unit, current_board)

# The panel outlives the units it shows. Guarded the way info_panel.set_unit guards its own
# teardown: a freed ref compares == null as TRUE (#149), so this skips instead of faulting.
func _release_current_unit() -> void:
	if current_unit != null and is_instance_valid(current_unit):
		current_unit.movement.movement_finished.disconnect(_refresh_derived_rows)

func clear():
	_release_current_unit()
	current_unit = null
	_content_shown = false
	_apply_visibility()
	_tear_down_unit_sections()

func _tear_down_unit_sections() -> void:
	portrait_panel.set_unit(null)
	stats_section.set_unit(null)
	inventory_panel.set_unit(null)
	squad_panel.set_unit(null)
	states_bar.set_unit(null)

# #722's one input.
func set_hidden_for_playback(hidden: bool) -> void:
	_hidden_for_playback = hidden
	_apply_visibility()

func _apply_visibility() -> void:
	visible = _content_shown and not _hidden_for_playback

func is_showing() -> bool:
	return _content_shown and current_unit != null

func is_showing_unit(unit: Unit) -> bool:
	return _content_shown and current_unit == unit

func panel_width() -> float:
	return $UnitInfoPanel.size.x

# The box a tile section is drawn in -- the inventory's own, so the grown hover card matches the dock.
func section_box() -> StyleBox:
	return inventory_panel.get_theme_stylebox("panel")

# What the tile body says, headings included -- empty unless it is up.
func tile_texts() -> Array[String]:
	var none: Array[String] = []
	if not (_content_shown and _view == View.TILE):
		return none
	return _tile_sections.drawn_texts()

func switch_button(view: View) -> Button:
	return _switch_buttons[view]

func _jobs_text(unit: Unit) -> String:
	# Always-reveal placeholder (#69: the real PER-gated enemy-job reveal needs a
	# "who's inspecting" concept that doesn't exist yet).
	var names: Array[String] = []
	for job_id in unit.unit_instance.jobs:
		var job := JobCatalog.get_job(job_id)
		if job != null:
			names.append(job.display_name)
	return ", ".join(names) if not names.is_empty() else "Jobless"
