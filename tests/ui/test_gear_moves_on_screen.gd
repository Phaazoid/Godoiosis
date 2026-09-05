# #741's two input paths on the real screen. Both ask the SAME Loadout judge and act through the same
# move -- a drag that decided for itself would be a second answer to "may this move", the shape #744
# collapsed one layer down -- so what these cases pin is that each path reaches that one rule.
#
# WHAT A HEADLESS SUITE CANNOT SEE, said out loud: this is the project's first drag-and-drop outside
# vendored addons, and nothing here proves Godot DECIDES to call _get_drag_data/_can_drop_data/
# _drop_data from a real mouse gesture. The three callbacks are driven directly. The closest honest
# proxy for the wire is that every source and target is mouse-reachable at all, which is the last
# assertion below and catches the likeliest way it breaks (a row left MOUSE_FILTER_IGNORE).
extends GdUnitTestSuite

const SCRATCH := "user://__gear_moves_741.tres"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const ROW_WIDTH := 10
const ZONE_CELLS := 6

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController


func before_test() -> void:
	_main = (load("res://Scenes/Main.tscn") as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	mc = game.mission_controller
	sm = game.scenario_manager
	mc._close_mission_select()
	sm.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


func _enter_phase() -> bool:
	var names: Array[String] = RosterCatalog.saved_rosters()
	if names.is_empty():
		return false
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	sm.current_roster = names[0]
	sm.current_deployment_cap = 2
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT]
	mc.set_objectives(objectives)
	assert_int(ResourceSaver.save(sm.capture_scenario("gear_741", true), SCRATCH)).is_equal(OK)
	mc.begin_mission(SCRATCH)
	await await_idle_frame()
	if mc.loadout().stash.is_empty():
		push_warning("the shipped roster carries no stash, so neither input path can be walked")
		return false
	return mc.is_deploying()


func _screen() -> PreMissionScreen:
	for child in game.ui_layer.get_children():
		if child is PreMissionScreen:
			return child
	return null


static func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


func _stash_rows() -> Array[GearRow]:
	var rows: Array[GearRow] = []
	for node: Node in _walk(_screen()):
		var row := node as GearRow
		if row != null and row.owner_unit == null and row.item != null:
			rows.append(row)
	return rows


func _card() -> PreMissionCard:
	for node: Node in _walk(_screen()):
		if node is PreMissionCard:
			return node
	return null


# Click to pick up, click to put down -- and Esc to let go. The selection is DATA, never a row: every
# successful move redraws both lists and frees every row in them, so a selection holding a node would
# dangle at the exact moment the feature starts working (#107's shape).
func test_the_click_path_carries_gear_from_the_stash_onto_a_card() -> void:
	if not await _enter_phase():
		return
	var screen := _screen()
	var row := _stash_rows()[0]
	var item := row.item
	var card := _card()
	assert_object(card).is_not_null()

	row.clicked.emit(item, null)
	await await_idle_frame()
	assert_object(screen._selected_item).override_failure_message(
		"clicking a stash row picked nothing up").is_same(item)

	# ...and the rows that were on screen when it was picked up are gone now, which is why the
	# selection cannot be one of them.
	card.gear_clicked.emit(null, card.unit)
	await await_idle_frame()
	assert_bool(card.unit.inventory.has(item)).override_failure_message(
		"the click path did not hand the item over").is_true()
	assert_bool(mc.loadout().stash.has(item)).override_failure_message(
		"the stash kept a copy").is_false()
	assert_object(screen._selected_item).override_failure_message(
		"the selection survived the move that spent it").is_null()


# Esc lets go of what is in hand -- and only then. Answering it unconditionally would evict the
# tenant Esc already has under this screen: the board is locked, so game._input routes it to the bug
# report card, which is the stranger's one complaint door (#131).
func test_escape_drops_the_selection_and_otherwise_leaves_the_key_alone() -> void:
	if not await _enter_phase():
		return
	var screen := _screen()
	assert_bool(screen._on_cancel()).override_failure_message(
		"the screen ate Esc with nothing in hand, so the report card is unreachable here").is_false()

	screen._on_gear_clicked(_stash_rows()[0].item, null)
	await await_idle_frame()
	assert_object(screen._selected_item).is_not_null()
	assert_bool(screen._on_cancel()).override_failure_message(
		"Esc did not take the selection").is_true()
	assert_object(screen._selected_item).is_null()


# The drag's three callbacks, driven directly -- see the header for what this cannot see. The refusal
# half is the one that matters: _can_drop_data must read the SAME judge the click path does, or a
# drag becomes a way around a rule the click path enforces.
func test_the_drag_path_offers_judges_and_performs_the_same_move() -> void:
	if not await _enter_phase():
		return
	var row := _stash_rows()[0]
	var card := _card()
	var item := row.item

	# Asked INSIDE a real drag, which is the only state set_drag_preview() will accept a Control in:
	# called cold it refuses, and the preview plus its label are left unparented and unreferenced --
	# two orphan nodes, and gdUnit4 reds a whole run for that (verdict 101). force_drag opens the
	# drag, gui_cancel_drag closes it and takes the preview with it.
	row.force_drag({}, null)
	var payload := row._get_drag_data(Vector2.ZERO) as Dictionary
	get_viewport().gui_cancel_drag()
	await await_idle_frame()
	assert_bool(payload.is_empty()).override_failure_message(
		"a stash row offered nothing to drag").is_false()
	assert_object(payload[GearDropZone.PAYLOAD_ITEM]).is_same(item)
	assert_object(payload[GearDropZone.PAYLOAD_FROM]).override_failure_message(
		"the payload does not say the stash is where it came from").is_null()

	# A slot on the card accepts it...
	var slot: GearRow = null
	for node: Node in _walk(card):
		var candidate := node as GearRow
		if candidate != null and candidate.owner_unit == card.unit:
			slot = candidate
	assert_object(slot).is_not_null()
	assert_bool(slot._can_drop_data(Vector2.ZERO, payload)).override_failure_message(
		"a unit with room refused a legal drop").is_true()

	# ...and a full one refuses it, through the unit's own sentence rather than the drag's opinion.
	for i in range(Unit.MAX_INVENTORY_SIZE):
		if card.unit.inventory[i] == null:
			card.unit.inventory[i] = WeaponInstance.new()
	assert_bool(slot._can_drop_data(Vector2.ZERO, payload)).override_failure_message(
		"the drag path let an item into a full inventory the click path would refuse").is_false()

	# Make room, then drop for real: the same move the click path makes.
	card.unit.remove_item(0)
	slot._drop_data(Vector2.ZERO, payload)
	await await_idle_frame()
	assert_bool(card.unit.inventory.has(item)).override_failure_message(
		"the drop did not move anything").is_true()
	assert_bool(mc.loadout().stash.has(item)).is_false()


# The wire proxy, and the honest limit of it: a source or target left MOUSE_FILTER_IGNORE is
# invisible to Godot's drag machinery, and that is the one half of the wire a headless run can check.
func test_every_row_and_zone_is_reachable_by_the_mouse() -> void:
	if not await _enter_phase():
		return
	var zones := 0
	for node: Node in _walk(_screen()):
		var zone := node as GearDropZone
		if zone == null:
			continue
		zones += 1
		assert_int(zone.mouse_filter).override_failure_message(
			"a gear zone is out of the mouse's reach, so neither clicking nor dragging can find it"
			).is_not_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(zones).override_failure_message(
		"no gear zones were rendered, so this case pins nothing").is_greater(0)


# --- preview-at-decision (#745) ----------------------------------------------------------------

# THE decision this screen exists for: something in hand, hovering a card, asking "should it go to
# THIS one". The stash cannot answer it alone -- can_equip_reason takes a wielder -- which is why the
# preview hangs off the card's hover rather than the row's.
#
# Nothing here rebuilds: a hover routed through refresh() would free the row the cursor is on, and
# mouse_exited never fires on a freed node, so the preview would stick for ever one frame after it
# appeared (#741's law, arriving from the other direction).
func test_holding_gear_over_a_card_previews_what_it_would_do() -> void:
	if not await _enter_phase():
		return
	var screen := _screen()
	var card := _card()

	# Gear built here rather than picked out of the shipped stash: the case needs a piece that MOVES a
	# number, and "equippable" does not mean that -- a weapon with no stat_modifiers previews as a row
	# of unchanged values and the assertion below would be measuring the fixture. Authored content is
	# not pinnable anyway (the content razor).
	var wearable := ArmorData.new()
	wearable.display_name = "Test Vest"
	wearable.def_power = 3
	wearable.stat_modifiers[Stats.Stat.DEX] = -2
	mc.loadout().stash.append(wearable)
	assert_str(wearable.can_equip_reason(card.unit)).override_failure_message(
		"fixture: the vest refuses this unit, so the preview would show a reason instead").is_empty()

	var before: Array[String] = []
	for stat: Stats.Stat in card._stat_values:
		before.append((card._stat_values[stat] as Label).text)

	screen._on_gear_clicked(wearable, null)
	await await_idle_frame()
	screen._on_card_hovered(card)

	var arrows := 0
	for stat: Stats.Stat in card._stat_values:
		if (card._stat_values[stat] as Label).text.contains("→"):
			arrows += 1
	assert_int(arrows).override_failure_message(
		"hovering a card with gear in hand promised the player nothing").is_greater(0)

	screen._on_gear_unhovered(card)
	var after: Array[String] = []
	for stat: Stats.Stat in card._stat_values:
		after.append((card._stat_values[stat] as Label).text)
	assert_array(after).override_failure_message(
		"the preview outlived the hover that opened it").is_equal(before)


# A preview of a piece the unit cannot use is a LIE, so #744's sentence takes the numbers' place
# rather than the hover going silent -- finding out at the click is the nasty surprise both tickets
# exist to prevent.
func test_a_piece_the_unit_cannot_use_shows_its_reason_instead_of_numbers() -> void:
	if not await _enter_phase():
		return
	var screen := _screen()
	var card := _card()

	# A gate nobody clears, so the case cannot go vacuous on a roster whose stats happen to suit
	# whatever the shipped stash holds.
	var blocked := ArmorData.new()
	blocked.display_name = "Test Slab"
	blocked.def_power = 9
	blocked.stat_minimums[Stats.Stat.CON] = 99
	mc.loadout().stash.append(blocked)
	assert_str(blocked.can_equip_reason(card.unit)).override_failure_message(
		"fixture: the slab does not actually refuse anybody").is_not_empty()

	screen._on_gear_clicked(blocked, null)
	await await_idle_frame()
	screen._on_card_hovered(card)

	for stat: Stats.Stat in card._stat_values:
		assert_bool((card._stat_values[stat] as Label).text.contains("→")).override_failure_message(
			"a piece the unit cannot wear still promised it numbers").is_false()
	assert_str(screen._stash_hint.text).override_failure_message(
		"the hover said nothing at all: %s" % screen._stash_hint.text
		).contains(blocked.can_equip_reason(card.unit))
