extends ModalCard
class_name PreMissionScreen

# The pre-mission screen (#740 + #743) -- the menu the player stands in while the phase #739 opened
# is running. Four regions, from his sketch: the roster's cards top-left, the stash down the whole
# right side, and along the bottom the force they have placed with the mission's contract cut into
# it.
#
# A ModalCard that is NOT a card, the way MissionSelectScreen is not: unframed, opaque, and it does
# NOT claim ModalLock -- the board underneath has to keep running, because Tab swaps to it.
#
# IT LOCKS THE BOARD BY JOINING game.menu_is_up(), NOT BY EATING CLICKS. A full-rect Control that
# swallows input is transparent to the 3D view, which picks cells with its own raycast and calls
# game._on_left_click directly; that door and _unhandled_input both gate on _board_locked_for_player,
# so one predicate covers them plus the camera rig. See game.menu_is_up.
#
# THE BACKDROP IS OPAQUE AND THAT IS LOAD-BEARING: nothing is frozen behind it, so CameraController's
# WASD poll and HoverPresenter._process are still running. Translucent, the player would watch the
# board pan under their menu. MissionSelectScreen carries the same rule for a different reason.
#
# HIDDEN, NEVER FREED, for the board preview -- the scroll position and anything open survive the
# look. MissionController owns the lifecycle and closes it at every exit: commit, reset (F2, a board
# swap, Load Game) and abandon, which needs its own because it never reaches clear_board.
#
# EVERY REGION THAT CAN GROW BOUNDS ITS OWN BODY (#418's law): the card grid, the stash, the contract
# list and the deployed force each scroll inside a fixed region rather than pushing the layout. The
# contract's is the one he asked for by name -- a board may author any number of conditions.

const BAND_HEIGHT := 210
const STASH_WIDTH := 260
const CONTRACT_WIDTH := 296
const GRID_COLUMNS := 3
const REGION_GAP := 12

# The deployed-force ring hugs the CHARACTER, not its canvas. Measured over all seven shipped map
# sprites: the ink runs x 8..23, y 13..31 of a 32x32 sheet, so the top half is empty on every one of
# them and a ring sized to the canvas frames padding. These centre that ink box in a 24px window.
const RING := 28
const RING_WINDOW := 24
const INK_OFFSET := Vector2(-4, -11)

var _controller: MissionController
var _cards: Array[PreMissionCard] = []
var _grid: GridContainer
var _stash_box: VBoxContainer
var _squads_row: HFlowContainer
var _objectives_box: VBoxContainer
var _begin_button: Button
var _force_count: Label
var _force_strip_count: Label


func _init() -> void:
	claims_modal_lock = false
	framed = false
	backdrop_color = Color(0.06, 0.06, 0.09)   # opaque -- see the header
	card_z_index = UiLayers.MENU_SCREEN


static func open(game_node: Node, controller: MissionController) -> PreMissionScreen:
	var screen := PreMissionScreen.new()
	screen._controller = controller
	game_node.ui_layer.add_child(screen)
	screen._build(game_node)
	return screen


# The base's unframed path centres its content, which shrink-wraps -- right for a column of buttons,
# wrong for four regions that fill the viewport. This is what the chrome being overridable STEPS is
# for.
func _build_frame() -> Container:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, REGION_GAP)
	add_child(margin)
	return margin


func _build_content_box(host: Container) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.add_child(box)
	return box


func _build(game_node: Node) -> void:
	var content := _build_chrome(game_node)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", REGION_GAP)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(columns)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", REGION_GAP)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	left.add_child(_build_roster())
	left.add_child(_build_band())

	columns.add_child(_build_stash())
	refresh()


# --- regions -------------------------------------------------------------------------------------

# A region is a panel with a header strip and a body. One builder, so the four cannot drift.
func _region(title: String, width: int = 0) -> Array:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", QueueStyle.panel_box())
	if width > 0:
		panel.custom_minimum_size.x = width
		panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	else:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 8)
	panel.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	pad.add_child(column)

	var header := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = title
	name_label.add_theme_font_size_override("font_size", 11)
	name_label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_label)
	var count := Label.new()
	count.add_theme_font_size_override("font_size", 11)
	count.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.TITLE_TEXT))
	header.add_child(count)
	column.add_child(header)
	column.add_child(HSeparator.new())
	return [panel, column, count]


# A scroll box that fills whatever room its region has left. THE growth law in one place: a list
# that can grow scrolls rather than pushing the layout out of the viewport (#418).
func _scroller(parent: Container) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	return scroll


func _build_roster() -> Control:
	var parts := _region("ROSTER")
	var panel: PanelContainer = parts[0]
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_force_count = parts[2]

	_grid = GridContainer.new()
	_grid.columns = GRID_COLUMNS
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroller(parts[1]).add_child(_grid)
	return panel


func _build_stash() -> Control:
	var parts := _region("STASH", STASH_WIDTH)
	var panel: PanelContainer = parts[0]
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_stash_box = VBoxContainer.new()
	_stash_box.add_theme_constant_override("separation", 4)
	_stash_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroller(parts[1]).add_child(_stash_box)

	# #741 owns every way gear MOVES; this ticket shows what is there. Said out loud rather than
	# left looking broken.
	var note := Label.new()
	note.text = "Moving gear comes with the loadout pass."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 10)
	note.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
	parts[1].add_child(note)
	return panel


func _build_band() -> Control:
	var band := HBoxContainer.new()
	band.add_theme_constant_override("separation", REGION_GAP)
	band.custom_minimum_size.y = BAND_HEIGHT

	var force := _region("DEPLOYED FORCE")
	_squads_row = HFlowContainer.new()
	_squads_row.add_theme_constant_override("h_separation", 14)
	_squads_row.add_theme_constant_override("v_separation", 10)
	_squads_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroller(force[1]).add_child(_squads_row)
	_force_strip_count = force[2]
	band.add_child(force[0])

	band.add_child(_build_contract())
	return band



func _build_contract() -> Control:
	var parts := _region("CONTRACT", CONTRACT_WIDTH)

	_objectives_box = VBoxContainer.new()
	_objectives_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroller(parts[1]).add_child(_objectives_box)

	var exits := VBoxContainer.new()
	exits.add_theme_constant_override("separation", 5)
	parts[1].add_child(exits)

	_begin_button = Button.new()
	_begin_button.text = "Begin Mission"
	_begin_button.add_theme_stylebox_override("normal", QueueStyle.execute_box())
	_begin_button.add_theme_stylebox_override("hover", QueueStyle.execute_hover_box())
	_begin_button.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.EXECUTE_TEXT))
	_begin_button.pressed.connect(_on_begin)
	exits.add_child(_begin_button)

	var pair := HBoxContainer.new()
	pair.add_theme_constant_override("separation", 5)
	exits.add_child(pair)
	pair.add_child(_exit_button("Board", "Look at the board you are about to fight over (Tab).",
		_controller.toggle_deployment_menu))
	pair.add_child(_exit_button("Leave", "Abandon this mission and go back to Mission Select.",
		_controller.abandon_mission))
	return parts[0]


func _exit_button(text: String, tip: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = UiText.wrap(tip)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 11)
	button.pressed.connect(action)
	return button


# --- state ---------------------------------------------------------------------------------------

# The board preview (#731 ruling 6). set_process_input goes with the visibility, because ModalCard's
# _input has no visibility guard of its own -- a hidden card still receives ui_cancel, which is
# harmless only while this screen declines to take it, and would silently break the moment it did.
func set_shown(shown: bool) -> void:
	visible = shown
	set_process_input(shown)
	if shown:
		refresh()


# Everything the screen draws, re-read. Called on show rather than wired to signals: the menu and the
# board are never on screen together, so there is no window in which a stale card is visible.
func refresh() -> void:
	_refresh_cards()
	_refresh_stash()
	_refresh_squads()
	_refresh_contract()
	_refresh_counts()


func _refresh_cards() -> void:
	var roster: Array[Unit] = _controller.roster_units()
	# Rebuilt only when the ROSTER changes, which is once per mission -- otherwise refreshed in
	# place, so a card's scroll position and hover survive a deploy.
	if _cards.size() != roster.size():
		for card in _cards:
			card.queue_free()
		_cards.clear()
		for child in _grid.get_children():
			_grid.remove_child(child)
		for unit: Unit in roster:
			if not is_instance_valid(unit):
				continue
			var card := PreMissionCard.build(unit, _controller)
			card.deploy_toggled.connect(_on_deploy_toggled)
			_cards.append(card)
			_grid.add_child(card)
		return
	for card in _cards:
		card.refresh()


func _refresh_stash() -> void:
	for child in _stash_box.get_children():
		_stash_box.remove_child(child)
		child.free()
	var roster: Roster = RosterCatalog.resolve(_controller.game.scenario_manager.current_roster)
	var stash: Array[EquippableData] = []
	if roster != null:
		stash = roster.stash
	for item: EquippableData in stash:
		if item == null:
			continue
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", QueueStyle.row_box(false, false))
		row.custom_minimum_size.y = 22
		# NO BLOCK REASON HERE, and that is the design: can_equip takes a wielder and the stash has
		# nobody to validate against, so the marking lives on the unit card (dev, 2026-09-05).
		row.tooltip_text = UiText.wrap(item.description if item.description != "" else item.display_name)
		var label := Label.new()
		label.text = item.display_name
		label.clip_text = true
		label.add_theme_font_size_override("font_size", 11)
		row.add_child(label)
		_stash_box.add_child(row)


func _refresh_squads() -> void:
	for child in _squads_row.get_children():
		_squads_row.remove_child(child)
		child.free()
	var seen: Array[Squad] = []
	for unit: Unit in _controller.game.units_root.get_children():
		if unit.get_faction() != Team.Faction.PLAYER or unit.squad == null:
			continue
		if seen.has(unit.squad):
			continue
		seen.append(unit.squad)
		_squads_row.add_child(_squad_block(unit.squad))


func _squad_block(squad: Squad) -> Control:
	var block := PanelContainer.new()
	block.add_theme_stylebox_override("panel", QueueStyle.section_box())
	block.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var pad := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		pad.add_theme_constant_override("margin_" + side, 6)
	block.add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	pad.add_child(column)

	var members: Array[Unit] = squad.get_members()
	var title := Label.new()
	title.text = ("%s leads" % squad.leader.get_unit_name()) if members.size() > 1 else "unsquadded"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
	title.clip_text = true
	column.add_child(title)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	column.add_child(row)
	for member: Unit in members:
		row.add_child(_ring(member, squad))
	return block


# A member, in its squad's own colour -- the same hue the map draws its ring in, so the strip and the
# board name the same squad the same way.
func _ring(member: Unit, squad: Squad) -> Control:
	var slot := VBoxContainer.new()
	slot.add_theme_constant_override("separation", 2)
	slot.custom_minimum_size.x = 46

	var hue: Color = squad.ring_hue if squad.ring_hue != Color.WHITE else Color(0.35, 0.38, 0.41)
	var ring := PanelContainer.new()
	ring.custom_minimum_size = Vector2(RING, RING)
	ring.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var box := QueueStyle.tint_box(hue)
	box.corner_radius_top_left = RING
	box.corner_radius_top_right = RING
	box.corner_radius_bottom_left = RING
	box.corner_radius_bottom_right = RING
	ring.add_theme_stylebox_override("panel", box)
	slot.add_child(ring)

	var window := Control.new()
	window.custom_minimum_size = Vector2(RING_WINDOW, RING_WINDOW)
	window.clip_contents = true
	ring.add_child(window)

	var sprite := TextureRect.new()
	sprite.texture = member.unit_data.map_sprite
	sprite.position = INK_OFFSET
	sprite.size = Vector2(32, 32)
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	window.add_child(sprite)

	var name_label := Label.new()
	name_label.text = member.get_unit_name()
	name_label.clip_text = true
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 9)
	name_label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
	slot.add_child(name_label)
	return slot


# The SAME briefing the corner HUD draws during the battle -- MissionStatusPanel.briefing_rows is the
# one builder, so the contract and the status readout cannot word a condition differently (Law #4).
func _refresh_contract() -> void:
	for child in _objectives_box.get_children():
		_objectives_box.remove_child(child)
		child.free()
	for row: Label in MissionStatusPanel.briefing_rows(_controller, _controller.game._board()):
		_objectives_box.add_child(row)


func _refresh_counts() -> void:
	var placed := _controller.deployed_roster_count()
	var cap: int = _controller.game.scenario_manager.current_deployment_cap
	var of_cap := "%d / %d" % [placed, cap] if cap != PreMission.NO_CAP else str(placed)
	_force_count.text = "%s deployed" % of_cap
	# The count belongs beside the FORCE, not beside the contract, and it says what it counts (dev,
	# 2026-09-05): a bare "3 / 4" names nothing.
	_force_strip_count.text = "%s members" % of_cap

	# Begin carries its own refusal. commit_deployment's banner is a TurnBanner, which is a plain
	# child of Game while this screen sits on a CanvasLayer -- so under the menu that banner cannot
	# be seen at all, and a silent dead button is exactly what #739 refused to ship on the board.
	_begin_button.disabled = placed == 0
	_begin_button.tooltip_text = UiText.wrap(
		"Place at least one unit — a mission cannot start with no one to command."
		if placed == 0 else "Start the mission with the force you have placed.")


# --- actions -------------------------------------------------------------------------------------

func _on_deploy_toggled(unit: Unit) -> void:
	if unit.get_parent() == _controller.game.units_root:
		_controller.game.undeploy_unit(unit)
	else:
		var open_cells: Array[Vector2i] = _controller.open_deployment_cells()
		if open_cells.is_empty() or not _controller.can_deploy_another():
			return   # the card's own button is disabled for both; this is the belt
		_controller.game.deploy_unit(unit, open_cells[0])
	refresh()


func _on_begin() -> void:
	_controller.confirm_and_commit()
