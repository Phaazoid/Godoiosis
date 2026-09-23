extends Control
class_name UnitInfoPanelControl

# Controller for the click-to-inspect panel (UnitInfoPanel.tscn) — a docked, full-height
# left column as of #68 (replaces the old flip-top/bottom popup). Owns show/hide + which
# unit is open, sets the header (name/jobs), and fans set_unit/clear out to the child
# sections so their signal hookups tear down together.
#
# IT INSPECTS TILES TOO since #1105, and stays the ONE dock, so HoverPresenter's is_showing /
# panel_width checks need no second answer. Two ways in: show_tile (an empty tile was clicked; the
# header becomes the tile's) and the Unit/Tile switch beside a unit's portrait, which swaps the body
# for the tile that unit stands on. A switch rather than a section underneath because the unit body
# already fills the dock (660 of 700px on every authored unit, measured). Either way the tile body
# is re-read every frame it shows and rebuilt only when what it says changed, so a watch firing or
# a fire spreading cannot leave it stale.

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
var _tile_only := false                 # an empty tile is open rather than a unit
var _tile_cell := GridUtils.NO_CELL
var _drawn := ""                        # TileReadout.signature of what the tile body shows now
var _tile_sections: TileInfoSections
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
	_tile_sections = TileInfoSections.new(inventory_panel.get_theme_stylebox("panel"))
	_tile_sections.visible = false
	body.add_child(_tile_sections)
	body.move_child(_tile_sections, squad_panel.get_index() + 1)
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
	_tile_only = false
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
	_switch.visible = true
	_set_view(View.UNIT)   # Inspect means the unit; its tile is one press away

# An empty tile was clicked (#1105). The caller names and pictures it (TileReadout.title_of /
# icon_of), the same pair the hover card wears.
func show_tile(cell: Vector2i, title: String, icon: Texture2D) -> void:
	_release_current_unit()
	current_unit = null
	current_board = null
	_tear_down_unit_sections()
	_tile_only = true
	_tile_cell = cell
	_content_shown = true
	_apply_visibility()
	name_label.text = title
	jobs_label.text = ""
	portrait_panel.show_picture(icon)
	_switch.visible = false
	_set_view(View.TILE)

func _set_view(view: View) -> void:
	_view = view
	_switch_buttons[view].set_pressed_no_signal(true)
	for node in _unit_body:
		node.visible = view == View.UNIT
	_tile_sections.visible = view == View.TILE
	_drawn = ""
	_refresh_tile()

func _refresh_tile() -> void:
	if _view != View.TILE or not tile_sections_source.is_valid():
		return
	var cell := _inspected_cell()
	if cell == GridUtils.NO_CELL:
		return
	var sections: Array[TileReadout.Section] = tile_sections_source.call(cell)
	var said := TileReadout.signature(sections)
	if said == _drawn:
		return
	_drawn = said
	_tile_sections.show_sections(sections)

# The clicked tile, or the one the open unit stands on now.
func _inspected_cell() -> Vector2i:
	if _tile_only:
		return _tile_cell
	if current_unit != null and is_instance_valid(current_unit):
		return current_unit.movement.cell
	return GridUtils.NO_CELL

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
	_tile_only = false
	_tile_cell = GridUtils.NO_CELL
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
	return _content_shown and (current_unit != null or _tile_only)

func is_showing_unit(unit: Unit) -> bool:
	return _content_shown and current_unit == unit

func panel_width() -> float:
	return $UnitInfoPanel.size.x

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
