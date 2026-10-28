# What the loadout says about a piece before it is moved (#962): what each weapon hits for in each
# unit's hands, what it scales off, and -- with a piece in hand -- a ghost of it in the slot a click
# on every other card would fill, at that unit's number. The rune half: a stash rune draws each
# carving's recipe as the rune card's bars, and its tooltip says what each carving asks for.
#
# Reads the RENDERED rows, never the builders in isolation (tests/ui/test_gear_hover_text.gd's
# precedent), and picks up through the real row click: the ghost is drawn by a deferred redraw, so a
# case that set the screen's selection by hand could not see a refresh path that forgot to tell the
# cards.
#
# THE CONTENT RAZOR: every piece here is built in code and pushed into the live loadout, and every
# expected number is derived from the seam that prints it (WeaponInstance.held_damage, scaling_of),
# so neither the shipped roster's kit nor its stats can red this suite.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const SCRATCH := "user://__loadout_damage_962.tres"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const ROW_WIDTH := 10
const ZONE_CELLS := 6

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
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


# --- the phase, borrowed from tests/ui/test_gear_hover_text.gd ---

func _enter_phase() -> bool:
	var names: Array[String] = RosterCatalog.saved_rosters()
	if names.is_empty():
		push_warning("no rosters are shipped, so the screen cannot be exercised")
		return false
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	sm.current_roster = names[0]
	sm.current_deployment_cap = 2
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT]
	mc.set_objectives(objectives)
	assert_int(ResourceSaver.save(sm.capture_scenario("loadout_damage_962", true), SCRATCH)).is_equal(OK)
	mc.begin_mission(SCRATCH)
	await await_idle_frame()
	return _screen() != null


func _screen() -> PreMissionScreen:
	for child in game.card_layer.get_children():
		if child is PreMissionScreen:
			return child
	return null


static func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


func _cards() -> Array[PreMissionCard]:
	var cards: Array[PreMissionCard] = []
	for node in _walk(_screen()):
		var card := node as PreMissionCard
		if card != null:
			cards.append(card)
	return cards


func _card_for(unit: Unit) -> PreMissionCard:
	for card in _cards():
		if card.unit == unit:
			return card
	return null


func _row_for(root: Node, item: Item) -> GearRow:
	for node in _walk(root):
		var row := node as GearRow
		if row != null and row.item == item:
			return row
	return null


func _stash_row_for(item: Item) -> GearRow:
	for node in _walk(_screen()):
		var row := node as GearRow
		if row != null and row.holder == null and row.item == item:
			return row
	return null


# A ghost is an EMPTY row (it carries nothing, so its click is the empty slot's own put-down) wearing
# the piece's name.
func _ghosts(card: PreMissionCard, piece: Item) -> Array[GearRow]:
	var found: Array[GearRow] = []
	for node in _walk(card):
		var row := node as GearRow
		if row == null or row.item != null:
			continue
		if _texts(row).has(PreMissionCard.GHOST_PREFIX + piece.shown_name()):
			found.append(row)
	return found


static func _texts(root: Node) -> Array[String]:
	var out: Array[String] = []
	for node in _walk(root):
		var label := node as Label
		if label != null:
			out.append(label.text)
	return out


func _redraw() -> void:
	_screen().refresh()
	await await_idle_frame()


# The real click: a press and a release on the row, the way GearRow tells a click from a drag (#789).
func _click(row: GearRow) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.position = Vector2(4, 4)
		row._gui_input(event)
	await await_idle_frame()


# ...and the realer one, for what lies ON a row: into the window at the control's centre, so the
# viewport's own hit test decides who gets it (tests/ui/test_cards_outrank_live_surfaces.gd's helper).
func _screen_point(control: Control) -> Vector2:
	var view := control.get_viewport()
	var in_view: Vector2 = (view.get_final_transform() * control.get_global_transform_with_canvas()) \
			* (control.size * 0.5)
	var container := _main.get_node("GameContainer") as Control
	return container.get_global_rect().position + in_view


func _click_through_window(control: Control) -> void:
	var at := _screen_point(control)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	Input.parse_input_event(motion)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = at
		event.global_position = at
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		Input.parse_input_event(event)
	await await_idle_frame()
	await await_idle_frame()


# --- fixtures ---

# A two-stat blend, lopsided, so the lit keys are a strict subset of the card's stats and a weapon
# reading the wrong stat cannot coincide with the right one.
func _weapon() -> WeaponInstance:
	var main := WeaponAttackData.new()
	main.power = 4
	var blend: Dictionary[Stats.Stat, int] = {}
	blend[Stats.Stat.DEX] = 40
	blend[Stats.Stat.PER] = 60
	main.scaling_blend = blend
	var template := WeaponData.new()
	template.display_name = "Test Carbine"
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = main
	return WeaponInstance.make(template)


func _main_of(weapon: WeaponInstance, unit: Unit) -> WeaponAttackData:
	return weapon.default_attack(UnitState.of(unit)) as WeaponAttackData


func _badge_for(weapon: WeaponInstance, unit: Unit) -> String:
	var main := _main_of(weapon, unit)
	return main.hit_badge(weapon.held_damage(unit.state, main))


# Built like tests/ui/test_rune_detail_card.gd's: two fire-tempered carvings, one of them asking for
# two elements, so a bar drawn in the wrong element or the wrong carving's group cannot coincide.
func _rune() -> RuneData:
	var rune := RuneData.new()
	rune.display_name = "Test Rune"
	rune.size = RuneData.Size.LARGE
	for spec: Array in [["Break(F, E) + Push(F)", "Cinder"], ["Push(F2)", "Ember"]]:
		var carving := TransmutationData.new()
		carving.display_name = spec[1]
		carving.power = 4
		carving.recipe = spec[0]
		assert_bool(rune.inscribe(carving)).override_failure_message(
			"fixture carving %s failed to inscribe" % spec[1]).is_true()
	return rune


# One group per carving: an HBox holding nothing but bars.
static func _bar_groups(row: Control) -> Array[HBoxContainer]:
	var out: Array[HBoxContainer] = []
	for node in _walk(row):
		var group := node as HBoxContainer
		if group == null or group.get_child_count() == 0:
			continue
		var only_bars := true
		for child in group.get_children():
			only_bars = only_bars and child is Panel
		if only_bars:
			out.append(group)
	return out


# A card with a free slot, or null -- the shipped roster's kit decides, so a case needing one says so.
func _card_with_room(piece: Item) -> PreMissionCard:
	for card in _cards():
		if card.unit.add_block_reason(piece) == "":
			return card
	return null


# --- at rest ---

func test_a_carried_weapon_row_shows_what_it_hits_for_in_these_hands() -> void:
	if not await _enter_phase():
		return
	var weapon := _weapon()
	var card := _card_with_room(weapon)
	if card == null:
		push_warning("every card is full, so there is nowhere to carry the fixture weapon")
		return
	mc.loadout().stash.append(weapon)
	assert_str(mc.loadout().move(weapon, null, card.unit)).is_empty()
	await _redraw()

	var row := _row_for(card, weapon)
	assert_object(row).override_failure_message("the card drew no row for the carried weapon").is_not_null()
	assert_array(_texts(row)).override_failure_message(
		"the row does not print what the weapon hits for in this unit's hands").contains(
			[_badge_for(weapon, card.unit)])


func test_a_stash_weapon_row_shows_what_it_scales_off() -> void:
	if not await _enter_phase():
		return
	var weapon := _weapon()
	mc.loadout().stash.append(weapon)
	await _redraw()

	var row := _stash_row_for(weapon)
	assert_object(row).override_failure_message("the stash drew no row for the weapon").is_not_null()
	assert_array(_texts(row)).override_failure_message(
		"the stash row does not say what the weapon scales off").contains(
			[Stats.blend_text(weapon.scaling_of(null, _main_of(weapon, null)))])


# The half the rows leave to the popup (dev, 2026-10-28): what the weapon scales off, with the number.
func test_a_carried_weapon_row_pops_up_its_blend_and_number() -> void:
	if not await _enter_phase():
		return
	var weapon := _weapon()
	var card := _card_with_room(weapon)
	if card == null:
		push_warning("every card is full, so there is nowhere to carry the fixture weapon")
		return
	mc.loadout().stash.append(weapon)
	assert_str(mc.loadout().move(weapon, null, card.unit)).is_empty()
	await _redraw()

	var main := _main_of(weapon, card.unit)
	var tip := _row_for(card, weapon).tooltip_text
	assert_str(tip).contains(Stats.blend_text(weapon.scaling_of(card.unit.state, main)))
	assert_str(tip).contains("%d" % weapon.held_damage(card.unit.state, main))


# --- in hand: the ghost ---

func test_a_weapon_in_hand_ghosts_onto_every_card_with_room() -> void:
	if not await _enter_phase():
		return
	var weapon := _weapon()
	mc.loadout().stash.append(weapon)
	# One card filled to the brim through the loadout's own door, so "no room, no ghost" is asked too.
	var full: PreMissionCard = null
	if _cards().size() > 1:
		full = _cards()[0]
		while full.unit.add_block_reason(weapon) == "":
			var filler := VialData.new()
			filler.display_name = "Test Filler"
			mc.loadout().stash.append(filler)
			assert_str(mc.loadout().move(filler, null, full.unit)).is_empty()
	await _redraw()

	await _click(_stash_row_for(weapon))
	assert_object(_screen()._selected_item).override_failure_message(
		"the click picked nothing up").is_same(weapon)

	var ghosted := 0
	for card in _cards():
		var ghosts := _ghosts(card, weapon)
		if card.unit.add_block_reason(weapon) != "":
			assert_int(ghosts.size()).override_failure_message(
				"%s has no room and still shows a ghost" % card.unit.get_unit_name()).is_equal(0)
			continue
		assert_int(ghosts.size()).override_failure_message(
			"%s has room and shows %d ghosts" % [card.unit.get_unit_name(), ghosts.size()]).is_equal(1)
		if ghosts.size() != 1:
			continue
		ghosted += 1
		assert_array(_texts(ghosts[0])).override_failure_message(
			"%s's ghost does not say what the weapon would hit for there" % card.unit.get_unit_name()
			).contains([_badge_for(weapon, card.unit)])
		# The popup, on the ghost too: what it scales off for this unit, and the number.
		var main := _main_of(weapon, card.unit)
		assert_str(ghosts[0].tooltip_text).contains(Stats.blend_text(weapon.scaling_of(card.unit.state, main)))
		assert_str(ghosts[0].tooltip_text).contains("%d" % weapon.held_damage(card.unit.state, main))
	assert_int(ghosted).override_failure_message(
		"no card had room for a ghost, so this case asked nothing").is_greater(0)
	if full != null:
		assert_int(_ghosts(full, weapon).size()).is_equal(0)


func test_clicking_a_ghost_puts_the_weapon_there() -> void:
	if not await _enter_phase():
		return
	var weapon := _weapon()
	mc.loadout().stash.append(weapon)
	await _redraw()
	var card := _card_with_room(weapon)
	if card == null:
		push_warning("every card is full, so there is no ghost to click")
		return

	await _click(_stash_row_for(weapon))
	var ghosts := _ghosts(card, weapon)
	assert_int(ghosts.size()).is_equal(1)
	if ghosts.is_empty():
		return
	await _click(ghosts[0])

	assert_bool(card.unit.inventory.has(weapon)).override_failure_message(
		"clicking the ghost did not hand the weapon over").is_true()
	assert_bool(mc.loadout().stash.has(weapon)).is_false()
	for other in _cards():
		assert_int(_ghosts(other, weapon).size()).override_failure_message(
			"a ghost outlived the move that spent the selection").is_equal(0)


func test_putting_the_weapon_down_clears_every_ghost() -> void:
	if not await _enter_phase():
		return
	var weapon := _weapon()
	mc.loadout().stash.append(weapon)
	await _redraw()
	if _card_with_room(weapon) == null:
		push_warning("every card is full, so no ghost is ever drawn")
		return

	await _click(_stash_row_for(weapon))
	await _click(_stash_row_for(weapon))   # the same row again: put it back down
	assert_object(_screen()._selected_item).is_null()
	for card in _cards():
		assert_int(_ghosts(card, weapon).size()).override_failure_message(
			"a ghost outlived the selection").is_equal(0)


# A blank rune is a gate nobody clears, so the case cannot go vacuous on a roster that suits it.
func test_a_piece_a_unit_refuses_ghosts_with_the_refusal_mark() -> void:
	if not await _enter_phase():
		return
	var rune := RuneData.new()
	rune.display_name = "Test Blank Rune"
	mc.loadout().stash.append(rune)
	await _redraw()
	var card := _card_with_room(rune)
	if card == null:
		push_warning("every card is full, so no ghost is ever drawn")
		return
	var reason := card.equip_block_reason(rune)
	assert_str(reason).override_failure_message("fixture: the blank rune refuses nobody").is_not_empty()

	await _click(_stash_row_for(rune))
	var ghosts := _ghosts(card, rune)
	assert_int(ghosts.size()).is_equal(1)
	if ghosts.is_empty():
		return
	assert_array(_texts(ghosts[0])).override_failure_message(
		"the ghost of a refused piece carries no refusal mark").contains(["!"])
	assert_str(ghosts[0].tooltip_text).contains(reason)


# --- in hand: the lit stat keys ---

func test_a_weapon_in_hand_lights_the_keys_of_the_stats_it_reads() -> void:
	if not await _enter_phase():
		return
	var lit_ink := QueueStyle.ink(QueueStyle.Role.EMPHASIS_TEXT)
	var rest_ink := QueueStyle.ink(QueueStyle.Role.HEADER_TEXT)
	assert_bool(lit_ink != rest_ink).override_failure_message(
		"the lit and resting inks are one colour, so this case cannot see a tint").is_true()
	var weapon := _weapon()
	mc.loadout().stash.append(weapon)
	await _redraw()

	await _click(_stash_row_for(weapon))
	var card := _cards()[0]
	var blend := weapon.scaling_of(card.unit.state, _main_of(weapon, card.unit))
	for stat: Stats.Stat in card._stat_values:
		var key := (card._stat_values[stat] as Label).get_parent().get_child(0) as Label
		var lit: bool = blend.get(stat, 0) > 0
		assert_bool(key.get_theme_color("font_color") == (lit_ink if lit else rest_ink)).override_failure_message(
			"%s's key is %s with the weapon in hand" % [key.text, "unlit" if lit else "lit"]).is_true()

# --- the rune half ---

# THE FULL RECIPE (dev, 2026-10-28: the wildcard mark read too much like the gap between carvings).
# Nobody pays in the stash, so every bar is the rune card's own "asked for, unpaid".
func test_a_stash_rune_row_draws_each_carvings_recipe() -> void:
	if not await _enter_phase():
		return
	var rune := _rune()
	mc.loadout().stash.append(rune)
	await _redraw()

	var groups := _bar_groups(_stash_row_for(rune))
	assert_int(groups.size()).override_failure_message(
		"the stash row draws %d bar groups for %d carvings" % [groups.size(), rune.inscriptions.size()]) \
		.is_equal(rune.inscriptions.size())
	for i in mini(groups.size(), rune.inscriptions.size()):
		var carving := rune.inscriptions[i]
		var expected: Array[Color] = []
		for element: Elemental.Element in carving.distinct_elements():
			for _n in range(carving.demand_of(element)):
				expected.append(QueueStyle.element_ink(element))
		var drawn: Array[Color] = []
		for bar: Node in groups[i].get_children():
			var box := (bar as Panel).get_theme_stylebox("panel") as StyleBoxFlat
			assert_int(box.border_width_left).override_failure_message(
				"%s drew a solid bar with nobody to pay it" % carving.display_name).is_greater(0)
			drawn.append(box.border_color)
		assert_array(drawn).override_failure_message(
			"%s's bars are not its recipe, element by element" % carving.display_name).is_equal(expected)


# A Panel stops the pointer by default, so a bar that kept it would swallow the very click that picks
# the rune up. Through the window, so the viewport's own hit test is what is being asked.
func test_a_click_on_a_recipe_bar_picks_the_rune_up() -> void:
	if not await _enter_phase():
		return
	var rune := _rune()
	mc.loadout().stash.insert(0, rune)   # first, so the stash's scroll cannot hide it
	await _redraw()

	var groups := _bar_groups(_stash_row_for(rune))
	assert_bool(groups.is_empty()).override_failure_message("the stash row drew no bars").is_false()
	if groups.is_empty():
		return
	await _click_through_window(groups[0].get_child(0) as Control)
	assert_object(_screen()._selected_item).override_failure_message(
		"a click on a recipe bar never reached the row").is_same(rune)


func test_a_rune_tooltip_says_what_each_carving_asks_for() -> void:
	if not await _enter_phase():
		return
	var rune := _rune()
	mc.loadout().stash.append(rune)
	await _redraw()

	var stash_tip := _stash_row_for(rune).tooltip_text
	for carving: TransmutationData in rune.inscriptions:
		assert_str(stash_tip).override_failure_message(
			"the stash tooltip does not say what %s asks for:\n%s" % [carving.display_name, stash_tip]) \
			.contains(carving.demand_text())

	# ...and the same on a card: what a carving asks for does not depend on who carries it.
	var card := _card_with_room(rune)
	if card == null:
		push_warning("every card is full, so there is nowhere to carry the fixture rune")
		return
	assert_str(mc.loadout().move(rune, null, card.unit)).is_empty()
	await _redraw()
	var card_tip := _row_for(card, rune).tooltip_text
	for carving: TransmutationData in rune.inscriptions:
		assert_str(card_tip).override_failure_message(
			"the card row's tooltip does not say what %s asks for:\n%s" % [carving.display_name, card_tip]) \
			.contains(carving.demand_text())
