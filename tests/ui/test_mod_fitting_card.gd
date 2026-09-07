# The mod fitting card (#732), on the real screen it opens from.
#
# WHAT A HEADLESS SUITE CANNOT SEE, said out loud: nothing here proves Godot decides to call the drag
# callbacks from a real gesture -- that is #741's declared blind spot and it has not moved. The three
# are driven directly, and the honest proxy for the wire is that every source and target is
# mouse-reachable at all, which is the last case below.
#
# The plate cases at the end need no phase: what they pin is arithmetic about the box, and building a
# card to ask it would only make them slower and flakier.
extends GdUnitTestSuite

const SCRATCH := "user://__mod_card_732.tres"
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
	assert_int(ResourceSaver.save(sm.capture_scenario("mods_732", true), SCRATCH)).is_equal(OK)
	mc.begin_mission(SCRATCH)
	await await_idle_frame()
	return mc.is_deploying()


static func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


func _screen() -> PreMissionScreen:
	for child in game.ui_layer.get_children():
		if child is PreMissionScreen:
			return child
	return null


# A weapon with spaces, from wherever the phase happens to have one. Prefers the stash, which is also
# the wielder-less case the card has to survive.
func _weapon() -> WeaponInstance:
	for item: Item in mc.loadout().stash:
		var weapon := item as WeaponInstance
		if weapon != null and weapon.space_count() > 0:
			return weapon
	for unit: Unit in mc.roster_units():
		for item: Item in unit.inventory:
			var weapon := item as WeaponInstance
			if weapon != null and weapon.space_count() > 0:
				return weapon
	return null


func _open(weapon: WeaponInstance, wielder: Unit = null) -> ModFittingCard:
	var card := ModFittingCard.open(game, weapon, wielder)
	await await_idle_frame()
	return card


func _library_rows(card: ModFittingCard) -> Array[GearRow]:
	var rows: Array[GearRow] = []
	for node: Node in _walk(card):
		var row := node as GearRow
		if row != null and row.holder == null:
			rows.append(row)
	return rows


func _space_zones(card: ModFittingCard) -> Array[GearDropZone]:
	var zones: Array[GearDropZone] = []
	for node: Node in _walk(card):
		if node is GearRow:
			continue
		var zone := node as GearDropZone
		if zone != null and zone.holder != null:
			zones.append(zone)
	return zones


# An empty space that would take a mod from the library, and the mod -- so a case can fit something
# without asserting anything about which shipped mod it happened to be.
func _fittable(weapon: WeaponInstance) -> Array:
	for key in WeaponModCatalog.offerable_for(weapon.template.weapon_type):
		var mod: WeaponModData = WeaponModCatalog.offerable_for(weapon.template.weapon_type)[key]
		for i in range(weapon.space_count()):
			if weapon.can_fit(i, mod):
				return [i, mod]
	return []


# --- the card over the screen --------------------------------------------------------------------

# Compared against the LIVE screen rather than against UiLayers itself: the claim is a relationship
# between two surfaces, and pinning both ends to the same table would pass however that table was
# rewritten. #798's lesson, one card further in.
func test_the_card_out_ranks_the_screen_it_was_opened_from() -> void:
	if not await _enter_phase():
		return
	var weapon := _weapon()
	if weapon == null:
		push_warning("no shipped weapon in this roster carries a mod space")
		return
	var card := await _open(weapon)
	assert_int(card.z_index).override_failure_message(
		"the card draws under the menu it was opened from").is_greater(_screen().z_index)
	card.free()


# The lock is why Tab cannot swap the board in behind an open card: game.gd gates both that key and
# the commit key on ModalLock.any_open.
func test_the_card_freezes_the_board_while_it_is_up() -> void:
	if not await _enter_phase():
		return
	var weapon := _weapon()
	if weapon == null:
		return
	assert_bool(ModalLock.any_open(get_tree())).override_failure_message(
		"the pre-mission screen deliberately claims no lock").is_false()
	var card := await _open(weapon)
	assert_bool(ModalLock.any_open(get_tree())).is_true()
	card.free()
	await await_idle_frame()
	assert_bool(ModalLock.any_open(get_tree())).override_failure_message(
		"the lock outlived the card that claimed it").is_false()


# --- fitting, both ways --------------------------------------------------------------------------

func test_a_drop_fits_a_mod_into_the_space_it_was_dropped_on() -> void:
	if not await _enter_phase():
		return
	var weapon := _weapon()
	if weapon == null:
		return
	var pick := _fittable(weapon)
	if pick.is_empty():
		push_warning("nothing in the catalog fits this weapon, so no drop can be walked")
		return
	var index: int = pick[0]
	var mod: WeaponModData = pick[1]

	var card := await _open(weapon)
	var zones := _space_zones(card)
	assert_int(zones.size()).is_equal(weapon.space_count())
	var payload := {GearDropZone.PAYLOAD_ITEM: mod, GearDropZone.PAYLOAD_FROM: null}
	assert_bool(zones[index]._can_drop_data(Vector2.ZERO, payload)).is_true()
	zones[index]._drop_data(Vector2.ZERO, payload)
	assert_bool(weapon.space(index).has(mod)).is_true()
	card.free()


# The SAME rule through the other input: pick a mod up in the library, click the space. Both paths
# ask fit_block_reason and act through fit, which is what stops a second answer growing.
func test_a_click_then_a_click_fits_the_same_mod_the_same_way() -> void:
	if not await _enter_phase():
		return
	var weapon := _weapon()
	if weapon == null:
		return
	var pick := _fittable(weapon)
	if pick.is_empty():
		return
	var index: int = pick[0]
	var mod: WeaponModData = pick[1]

	var card := await _open(weapon)
	card._on_library_clicked(mod, null)
	await await_idle_frame()
	card._on_space_clicked(null, weapon, index)
	assert_bool(weapon.space(index).has(mod)).is_true()
	card.free()


func test_taking_a_mod_off_gives_the_space_back() -> void:
	if not await _enter_phase():
		return
	var weapon := _weapon()
	if weapon == null:
		return
	var pick := _fittable(weapon)
	if pick.is_empty():
		return
	var index: int = pick[0]
	var mod: WeaponModData = pick[1]
	assert_bool(weapon.fit(index, mod)).is_true()
	var before := weapon.used_capacity(index)

	var card := await _open(weapon)
	card._on_space_clicked(mod, weapon, index)   # pick the fitted one up
	await await_idle_frame()
	card._on_library_clicked(null, null)         # ...and put it back in the library
	assert_bool(weapon.space(index).has(mod)).is_false()
	assert_int(weapon.used_capacity(index)).is_less(before)
	card.free()


# A refusal is the MODEL'S sentence, never a second wording -- the shape #166 spent a ticket on and
# the reason fit_block_reason answers with a string at all.
func test_a_refused_fit_puts_the_models_own_sentence_on_the_card() -> void:
	if not await _enter_phase():
		return
	var weapon := _weapon()
	if weapon == null:
		return
	var pick := _fittable(weapon)
	if pick.is_empty():
		return
	var index: int = pick[0]
	var mod: WeaponModData = pick[1]
	if weapon.space_count() < 2:
		push_warning("this weapon has one space, so there is no OTHER space to be refused from")
		return
	assert_bool(weapon.fit(index, mod)).is_true()
	# A DIFFERENT space, deliberately. Dropping a fitted mod back into the space it already sits in is
	# the no-op branch rather than a refusal -- so aiming this case there would have asked the card for
	# a sentence it is right not to have.
	var other := (index + 1) % weapon.space_count()

	var card := await _open(weapon)
	var expected := weapon.fit_block_reason(other, mod)
	assert_str(expected).is_not_empty()
	card._on_library_clicked(mod, null)
	await await_idle_frame()
	card._on_space_clicked(null, weapon, other)
	await await_idle_frame()
	assert_str(card._hint.text).is_equal(expected)
	card.free()


# --- what the list offers, and what the readout follows -------------------------------------------

# The card and the Item Editor's picker ask ONE function now, so this pins the card against that
# function rather than against a count of shipped files.
func test_the_list_offers_exactly_what_the_family_allows() -> void:
	if not await _enter_phase():
		return
	var weapon := _weapon()
	if weapon == null:
		return
	var offerable := WeaponModCatalog.offerable_for(weapon.template.weapon_type)
	if offerable.is_empty():
		push_warning("nothing authored fits this family, so the list has nothing to check")
		return
	var card := await _open(weapon)
	assert_int(_library_rows(card).size()).is_equal(offerable.size())
	card.free()


# THE CASE WITH TEETH FOR THE READOUT: a mod that replaces the main must move what the card is
# describing. A plate reading template.main_attack instead of effective_main would pass every other
# case in this file and be wrong exactly here.
func test_fitting_a_main_replacer_moves_the_readout_onto_the_new_main() -> void:
	if not await _enter_phase():
		return
	var weapon := _weapon()
	if weapon == null:
		return
	var swapped := WeaponAttackData.new()
	swapped.display_name = "Probe Swing"
	var replacer := WeaponModData.new()
	replacer.display_name = "Probe Replacer"
	replacer.replaces_main = swapped
	# A space that is FREE, not the one lowest_space_for names -- that answers what a mod NEEDS and
	# ignores fill by design, so on a weapon whose first space is already occupied this guard skipped
	# the whole case. It did, silently, until a mutant that should have reddened it passed.
	var index := -1
	for i in range(weapon.space_count()):
		if weapon.can_fit(i, replacer):
			index = i
			break
	if index == -1:
		push_warning("every space on this weapon is full, so the swap cannot be walked")
		return

	var card := await _open(weapon)
	assert_object(card._attack).is_not_same(swapped)
	card._perform_fit(replacer, null, weapon, index)
	await await_idle_frame()
	assert_object(card._attack).override_failure_message(
		"the readout still describes the template's main, not the one fitted").is_same(swapped)
	card.free()


# A weapon nobody holds has nobody's proficiency to be reduced by, and the card is the only surface
# that can ask about one -- it opens on stash gear. Zero was the other reading of active_space_count
# for a null wielder, and it would print every space of a stash weapon as inactive, teaching that
# fitting one does nothing at all.
func test_a_weapon_with_no_carrier_marks_no_space_inactive() -> void:
	if not await _enter_phase():
		return
	var weapon := _weapon()
	if weapon == null:
		return
	var card := await _open(weapon)
	assert_str(card._proficiency.text).is_not_empty()
	for node: Node in _walk(card):
		var label := node as Label
		if label != null:
			assert_str(label.text).override_failure_message(
				"a weapon nobody holds had a space marked inactive").is_not_equal("inactive")
	card.free()


# The closest honest proxy for a wire no headless suite can drive: every place the player has to
# reach is reachable at all. IGNORE on a zone is how "click a space to put it there" dies silently.
func test_every_space_and_every_row_is_mouse_reachable() -> void:
	if not await _enter_phase():
		return
	var weapon := _weapon()
	if weapon == null:
		return
	var card := await _open(weapon)
	for zone in _space_zones(card):
		assert_int(zone.mouse_filter).override_failure_message(
			"a space out of the mouse's reach can never be clicked into").is_equal(Control.MOUSE_FILTER_STOP)
	for row in _library_rows(card):
		assert_int(row.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)

	# ...and nothing INSIDE a space may eat the press on its way to the zone, or "click a space to put
	# it there" dies wherever that space has no row to click. Containers default to PASS and are fine;
	# what this guards against is a Panel or a PanelContainer added in for decoration, which default to
	# STOP (measured, 2026-09-06). The rows are the exception -- they are meant to stop.
	for zone in _space_zones(card):
		for node: Node in _walk(zone):
			var control := node as Control
			if control == null or control is GearRow:
				continue
			var why := "%s inside a space eats the click before the zone sees it" % control.get_class()
			assert_int(control.mouse_filter).override_failure_message(why) \
					.is_not_equal(Control.MOUSE_FILTER_STOP)
	card.free()


# The chip is a Button inside a 20px row, and a Button's minimum height comes from its font and its
# stylebox -- so it is the one thing on the card that could cost a gear slot. It does not, and the
# reason is MEASURED rather than argued: the card GROWS. CARD_HEIGHT is a minimum, the roster region
# expands, and the grid row takes the tallest card -- so a 40px chip changes the card's height and
# clips nothing (mutant, 2026-09-06). An assertion about the card's rect would have been inert, and an
# earlier draft of this case asserting CARD_HEIGHT failed on main for the same reason.
#
# What is left has teeth: six slots, drawn, whatever the chip does to the rows they sit in.
func test_the_card_still_draws_every_gear_slot_with_the_chip_on_it() -> void:
	if not await _enter_phase():
		return
	var screen := _screen()
	assert_object(screen).is_not_null()
	await await_idle_frame()
	var seen := 0
	for node: Node in _walk(screen):
		var card := node as PreMissionCard
		if card == null:
			continue
		var rows := 0
		for inner: Node in _walk(card):
			if inner is GearRow:
				rows += 1
		if rows == 0:
			continue
		seen += 1
		assert_int(rows).override_failure_message(
			"the card stopped drawing one row per inventory place").is_equal(Unit.MAX_INVENTORY_SIZE)
	assert_int(seen).is_greater(0)


# --- the plate ------------------------------------------------------------------------------------

func _attack(min_range: int, max_range: int) -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.min_range = min_range
	attack.max_range = max_range
	return attack


# The span follows what has to be drawn: a range-1 attack needs one ring, a range-3 attack three.
func test_the_plate_grows_with_the_range_it_is_drawing() -> void:
	var plate: ShapePlate = auto_free(ShapePlate.new())
	plate.show_attack(_attack(1, 1))
	var small := plate.get_child(0).get_child_count()
	plate.show_attack(_attack(1, 3))
	assert_int(plate.get_child(0).get_child_count()).is_greater(small)
	assert_int(small).is_equal(3 * 3)


# ...and stops at the box, so a long-ranged attack cannot widen the card it sits in.
func test_the_plate_never_grows_past_its_own_box() -> void:
	var plate: ShapePlate = auto_free(ShapePlate.new())
	plate.show_attack(_attack(1, 40))
	var span := ShapePlate.max_span()
	assert_int(plate.get_child(0).get_child_count()).is_equal(span * span)


# The aim the plate DRAWS is pulled in to the plate's edge when the range outruns it. Without this
# the footprint of a long shot lands off-grid and the one ink that says what the attack HITS
# disappears exactly when the range is most worth showing.
func test_the_drawn_aim_is_pulled_in_when_the_range_outruns_the_plate() -> void:
	var half := (ShapePlate.max_span() - 1) / 2
	assert_int(ShapePlate.drawn_reach(_attack(1, 2))).is_equal(2)
	assert_int(ShapePlate.drawn_reach(_attack(1, 40))).is_equal(half)


# ...and the clip is DECLARED. A ring cut off at the plate's edge with no word for it would be a lie
# about where the attack stops.
func test_a_clipped_plate_says_how_far_it_actually_drew() -> void:
	var plate: ShapePlate = auto_free(ShapePlate.new())
	plate.show_attack(_attack(1, 2))
	var caption: Label = plate.get_child(1)
	assert_str(caption.text).not_contains("shown to")
	plate.show_attack(_attack(1, 40))
	assert_str(caption.text).contains("shown to %d" % ((ShapePlate.max_span() - 1) / 2))
