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
var _stash_zone: GearDropZone
var _stash_hint: Label
# THE SELECTION IS DATA, NEVER A ROW (#741). Every successful move redraws both lists and frees every
# row in them, so a selection holding a node would dangle on the first move that worked -- #107's
# shape, arriving at the exact moment the feature starts functioning. Owner null means the stash.
var _selected_item: EquippableData
var _selected_owner: Unit
var _last_refusal := ""
# What a hover is currently saying, kept apart from _last_refusal so a preview cannot erase the
# reason the last move failed -- and written straight to the label, never through a redraw.
var _hover_note := ""
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
#
# IT TAKES THE CONTENT rather than handing back a parent to add to, and that is the whole fix for a
# bug that shipped: **a ScrollContainer stretches its child to its own width only when that child's
# horizontal flags carry SIZE_EXPAND.** Control's default is SIZE_FILL, which does NOT, and a child
# without it is laid out at its COMBINED MINIMUM instead. Every label on this screen is clip_text --
# minimum width zero, deliberately, so no long name can widen a region -- so "forgot the flag"
# renders as rows a pixel or two wide rather than as anything that reads like a mistake in the code.
# Three of the four regions set it at the call site and the stash did not; now none of them can.
func _scroller(parent: Container, content: Control) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
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
	_scroller(parts[1], _grid)
	return panel


func _build_stash() -> Control:
	var parts := _region("STASH", STASH_WIDTH)
	var panel: PanelContainer = parts[0]
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# The whole list is one drop zone, not just its rows: an empty stash still has to be a place a
	# player can aim at, and dropping into the gap under the last row is the same gesture.
	_stash_zone = GearDropZone.new()
	_stash_zone.add_theme_stylebox_override("panel", QueueStyle.section_box())
	_stash_zone.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_stash_zone.wire(null, _judge_move, _perform_move)   # null owner IS the stash
	_stash_zone.clicked.connect(_on_gear_clicked)
	_scroller(parts[1], _stash_zone)

	_stash_box = VBoxContainer.new()
	_stash_box.add_theme_constant_override("separation", 4)
	_stash_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stash_zone.add_child(_stash_box)

	_stash_hint = Label.new()
	_stash_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stash_hint.add_theme_font_size_override("font_size", 10)
	_stash_hint.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
	parts[1].add_child(_stash_hint)
	return panel


func _build_band() -> Control:
	var band := HBoxContainer.new()
	band.add_theme_constant_override("separation", REGION_GAP)
	band.custom_minimum_size.y = BAND_HEIGHT

	var force := _region("DEPLOYED FORCE")
	_squads_row = HFlowContainer.new()
	_squads_row.add_theme_constant_override("h_separation", 14)
	_squads_row.add_theme_constant_override("v_separation", 10)
	_scroller(force[1], _squads_row)
	_force_strip_count = force[2]
	band.add_child(force[0])

	band.add_child(_build_contract())
	return band



func _build_contract() -> Control:
	var parts := _region("CONTRACT", CONTRACT_WIDTH)

	_objectives_box = VBoxContainer.new()
	_scroller(parts[1], _objectives_box)

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
			var card := PreMissionCard.build(unit, _controller, _judge_move, _perform_move)
			card.deploy_toggled.connect(_on_deploy_toggled)
			card.gear_clicked.connect(_on_gear_clicked)
			card.gear_hovered.connect(_on_gear_hovered)
			card.gear_unhovered.connect(_on_gear_unhovered)
			card.job_picked.connect(_on_job_picked)
			card.mouse_entered.connect(_on_card_hovered.bind(card))
			card.mouse_exited.connect(_on_gear_unhovered.bind(card))
			card.selected_item = _selected_item if _selected_owner == unit else null
			_cards.append(card)
			_grid.add_child(card)
		return
	for card in _cards:
		card.selected_item = _selected_item if _selected_owner == card.unit else null
		card.refresh()


func _refresh_stash() -> void:
	for child in _stash_box.get_children():
		_stash_box.remove_child(child)
		child.free()
	# The LIVE stash, off the controller -- never RosterCatalog.resolve(), which hands back the cached
	# authored Roster and would have had the first move out of here deplete it for the session (#741).
	for item: EquippableData in _controller.loadout().stash:
		if item == null:
			continue
		var row := GearRow.new()
		var selected := item == _selected_item and _selected_owner == null
		row.add_theme_stylebox_override("panel", QueueStyle.row_box(false, selected))
		row.custom_minimum_size.y = 22
		row.carry(item)
		row.wire(null, _judge_move, _perform_move)
		row.clicked.connect(_on_gear_clicked)
		# NO BLOCK REASON HERE, and that is the design: can_equip_reason takes a wielder and the stash
		# has nobody to validate against, so the marking lives on the unit card (dev, 2026-09-05). What
		# a piece DEMANDS is the other question, and the one a list of loose gear can answer -- so the
		# armor gate rides the tooltip, through the same _gate_text spelling the card's sentence uses.
		var tip := item.describe() if item.describe() != "" else item.display_name
		var armor := item as ArmorData
		if armor != null and armor.requirement_text() != "":
			tip += "
Requires: %s" % armor.requirement_text()
		row.tooltip_text = UiText.wrap(tip)
		var label := Label.new()
		label.text = item.display_name
		label.clip_text = true
		label.add_theme_font_size_override("font_size", 11)
		row.add_child(label)
		_stash_box.add_child(row)
	_refresh_hint()


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
	if _controller.game.is_deployed(unit):
		_controller.game.undeploy_unit(unit)
	else:
		var open_cells: Array[Vector2i] = _controller.open_deployment_cells()
		if open_cells.is_empty() or not _controller.can_deploy_another():
			return   # the card's own button is disabled for both; this is the belt
		_controller.game.deploy_unit(unit, open_cells[0])
	refresh()


func _on_begin() -> void:
	_controller.confirm_and_commit()


# The card offers the job; the screen performs it, the same division every gear move keeps. Deferred
# like every other mutation here so that one place decides when the screen redraws -- and the redraw
# is real work either way: the ability chips, the stat grid and the derived strip all follow a job.
func _on_job_picked(target: Unit, job_id: String) -> void:
	_last_refusal = target.set_sole_job(job_id)
	_hover_note = ""
	_redraw()


# --- moving gear (#741) --------------------------------------------------------------------------

# The two callables every row and zone is wired with, click path and drag path alike. They are thin
# on purpose: Loadout owns the rule, and a surface that judged for itself would be a second answer.
func _judge_move(item: EquippableData, from: Unit, to: Unit) -> String:
	return _controller.loadout().move_block_reason(item, from, to)


# A REDRAW NEVER RUNS INSIDE THE CLICK THAT CAUSED IT. Every handler below is reached from a row's
# own signal -- clicked, or _drop_data -- and refresh() frees every row in both lists to rebuild
# them, the emitting one included. Godot refuses that outright ("Attempted to free a locked object"),
# so the first move a player made would have errored rather than happened. Deferring hands the
# emission back first; the rows are freed on the next idle frame, when nobody is standing on them.
func _redraw() -> void:
	refresh.call_deferred()


func _perform_move(item: EquippableData, from: Unit, to: Unit) -> String:
	var refusal := _controller.loadout().move(item, from, to)
	_last_refusal = refusal
	if refusal == "":
		_selected_item = null
		_selected_owner = null
	_redraw()
	return refusal


# Click to pick up, click again to put down -- the same gesture the drag makes, for a player who
# would rather not drag one. Clicking the selection itself lets go of it.
func _on_gear_clicked(item: EquippableData, owner_unit: Unit) -> void:
	if _selected_item != null:
		if item == _selected_item and owner_unit == _selected_owner:
			_clear_selection()
			return
		_perform_move(_selected_item, _selected_owner, owner_unit)
		return
	if item == null:
		return   # an empty slot with nothing in hand is not a selection
	_last_refusal = ""
	_selected_item = item
	_selected_owner = owner_unit
	_redraw()


func _clear_selection() -> void:
	_selected_item = null
	_selected_owner = null
	_last_refusal = ""
	_redraw()


# The stash's own line: what is in hand, or why the last move did not happen. It sits under the stash
# rather than by the cards because that is the one place on screen both ends of a move can see.
func _refresh_hint() -> void:
	if _stash_hint == null:
		return
	# A hover speaks over the last refusal, and neither redraws anything: this writes one label.
	if _hover_note != "":
		_stash_hint.text = _hover_note
		_stash_hint.add_theme_color_override("font_color",
			QueueStyle.ink(QueueStyle.Role.ROW_REFUSED_BORDER))
		return
	if _last_refusal != "":
		_stash_hint.text = _last_refusal
		_stash_hint.add_theme_color_override("font_color",
			QueueStyle.ink(QueueStyle.Role.ROW_REFUSED_BORDER))
		return
	_stash_hint.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
	if _selected_item == null:
		_stash_hint.text = "Click a piece of gear, then click where it should go. Or drag it."
		return
	var holder := "the stash" if _selected_owner == null else _selected_owner.get_unit_name()
	_stash_hint.text = "%s, from %s. Click a unit or the stash to place it." % [
		_selected_item.display_name, holder]


# Esc lets go of what is in hand -- and ONLY then. Answering it unconditionally would evict the
# tenant that key already has: under this screen the board is locked, so game._input routes Esc to
# the bug report card, which is the stranger's one complaint door (#131).
func _on_cancel() -> bool:
	if _selected_item == null:
		return false
	_clear_selection()
	return true


# --- preview-at-decision (#745) --------------------------------------------------------------------

# Hovering a card WITH SOMETHING IN HAND is the decision this screen exists for -- should this go to
# Torv or to Bram -- and it is the one the stash cannot answer on its own, since can_equip_reason
# takes a wielder. The row hover below answers the smaller question, re-arranging what a unit already
# carries.
func _on_card_hovered(card: PreMissionCard) -> void:
	if _selected_item == null or _selected_owner == card.unit:
		return
	_preview(card, _selected_item, true)


# ...and with EMPTY hands, hovering a carried row previews equipping it in place. Deferring to the
# card-level preview while something is held is deliberate: what the player is deciding then is where
# the held thing goes, not what the row under the cursor would do.
func _on_gear_hovered(item: EquippableData, card: PreMissionCard) -> void:
	if _selected_item != null:
		return
	_preview(card, item, false)


func _on_gear_unhovered(card: PreMissionCard) -> void:
	card.clear_preview()
	_hover_note = ""
	_refresh_hint()


# A PREVIEW OF A PIECE THE UNIT CANNOT USE IS A LIE, so #744's gate decides whether there are numbers
# at all -- and the sentence takes their place rather than leaving the hover silent, since finding out
# at the click is exactly the nasty surprise that ticket exists to prevent.
func _preview(card: PreMissionCard, item: EquippableData, incoming: bool) -> void:
	if item == null:
		return
	var refusal := item.can_equip_reason(card.unit)
	if refusal != "":
		card.clear_preview()
		_hover_note = "%s: %s" % [card.unit.get_unit_name(), refusal]
	else:
		card.show_preview(item, incoming)
		_hover_note = ""
	_refresh_hint()
