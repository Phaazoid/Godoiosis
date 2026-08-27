# #166: a menu LISTS what the unit owns and greys what it can't use, with a reason on every
# greyed row and a readout on every row.
#
# This suite asserts on WHAT THE MENU DREW, not on the lists behind it, and that is the whole point
# of it existing. `get_transmutation_choices()` returning three carvings tells you nothing about
# whether the menu drew three slices, greyed two, or attached a single word of explanation — and the
# row-building path (MainActionMenu._entry -> build_tree -> the ring's live level) is where every one
# of those decisions actually happens. Same lesson as #114, #126 and #131: a test that stops short of
# the thing the player looks at is blind to bugs in the thing the player looks at.
#
# Re-pointed by #467 from the dropdown's Buttons to the ring's live level, and the DRILL-DOWN is
# driven by ANGLE (aim_at + commit) rather than by calling a pick — the ring compacts, so which
# slice an angle lands on is exactly the thing that can break.
#
# Fixture is tests/squad/test_downed_ejection.gd's real game scene — see tests/README.md ->
# Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const MD := preload("res://tests/support/menu_drive.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

const FIRE := Elemental.Element.FIRE

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	assert_object(unit).is_not_null()
	return unit


func _carving(sigils: Array[Elemental.Element], name: String) -> TransmutationData:
	var t: TransmutationData = TransmutationData.new()
	t.display_name = name
	t.power = 5
	t.sigils.assign(sigils)
	return t


# An alchemist wielding a three-carving rune with a mixed verdict — #157's partial case, which is
# precisely why this readout is owed: the rune equips legally and the dead carving still needs to
# explain itself. At fire-1 under the wildcard model (2026-08-10): Ember covered, Pyre channels
# via the universal +1, Inferno's deficit of 2 is past any pool.
func _alchemist_with_a_partial_rune() -> Unit:
	var alch := _spawn(Vector2i(1, 0))
	alch.unit_instance.aura = { FIRE: 1 }
	alch.unit_instance.affinity = [FIRE]

	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	rune.display_name = "Test Rune"
	assert_bool(rune.inscribe(_carving([FIRE], "Ember"))).is_true()              # deficit 0
	assert_bool(rune.inscribe(_carving([FIRE, FIRE], "Pyre"))).is_true()         # deficit 1 — wildcarded
	assert_bool(rune.inscribe(_carving([FIRE, FIRE, FIRE], "Inferno"))).is_true()# deficit 2 — dead
	alch.add_item(rune)
	assert_object(alch.get_equipped_weapon()).override_failure_message("fixture failed to equip the rune").is_same(rune)
	return alch


# The open ring. MainActionMenu parents its controller to Game and there is only ever one now --
# a category grows a ring on the SAME controller rather than opening a second menu (#467).
func _controller() -> ActionMenuController:
	var controller: ActionMenuController = null
	for child in game.get_children():
		if child is ActionMenuController:
			controller = child
	assert_object(controller).override_failure_message("no menu was opened at all").is_not_null()
	return controller


# What the LIVE ring is drawing. Still the widget's own display list rather than the data behind
# it, which is this suite's whole reason for existing.
func _open_rows() -> Array:
	return _controller().level_nodes()


func _row_named(rows: Array, text: String) -> Dictionary:
	for row: Dictionary in rows:
		if String(row.get("name", "")) == text:
			return row
	return {}


func _disabled(row: Dictionary) -> bool:
	return bool(row.get("disabled", false))


func _tooltip(row: Dictionary) -> String:
	return String(row.get("tooltip", ""))


# Which slice on the LIVE ring carries this name, or -1. One lookup, so the gesture below and the
# depth check above it cannot disagree about which row they mean.
func _slice_index(controller: ActionMenuController, label: String) -> int:
	var rows: Array = controller.level_nodes()
	for i in range(rows.size()):
		if String(rows[i].get("name", "")) == label:
			return i
	return -1


# Point at a row by NAME and click it, the way a player does. Pointing rather than calling a pick is
# the whole point: selection is the ANGLE, so a case that set an index directly would not exercise
# the thing that can break.
func _aim_and_click(controller: ActionMenuController, label: String) -> void:
	var index := _slice_index(controller, label)
	assert_int(index).override_failure_message("the ring offered no '%s' slice" % label).is_greater(-1)
	controller.aim_at(controller.point_in_slice(index))
	controller.commit()


# A CATEGORY row: the ring GROWS. A terminal row uses _aim_and_click alone, where this assertion
# would be exactly wrong -- the menu ends there instead of opening anything.
func _drill(controller: ActionMenuController, label: String) -> void:
	var depth := controller.level_count()
	_aim_and_click(controller, label)
	assert_int(controller.level_count()).override_failure_message(
			"committing '%s' did not open a ring" % label).is_equal(depth + 1)


# Open the unit's ring and drill into the KIT slice. Carvings AND weapon secondaries both live
# there since #467 -- the #88 separation was overturned with the rework.
func _enter_attack_ring(unit: Unit) -> void:
	game.main_action_menu.show_main_menu(unit, Vector2i(400, 300))
	await await_idle_frame()
	_drill(_controller(), MD.kit_category(game, unit))


# ==============================================================================

# THE readout, as one sequence: open the category, and every carving the rune holds has a row —
# the two that can't be paid for greyed rather than missing.
func test_the_submenu_lists_every_carving_and_greys_the_unaffordable_ones() -> void:
	var alch := _alchemist_with_a_partial_rune()

	await _enter_attack_ring(alch)
	var rows := _open_rows()

	# Named rows rather than a count: since #467 the ATTACK verb shares this ring with the carvings,
	# so a total would be a claim about the grouping rather than about the catalogue.
	for carving: String in ["Ember", "Pyre", "Inferno"]:
		assert_bool(_row_named(rows, carving).is_empty()) \
			.override_failure_message("the catalogue did not list '%s'" % carving).is_false()
	assert_bool(_disabled(_row_named(rows, "Ember"))) \
		.override_failure_message("the covered carving was greyed").is_false()
	assert_bool(_disabled(_row_named(rows, "Pyre"))) \
		.override_failure_message("a wildcard-covered carving was greyed").is_false()
	assert_bool(_disabled(_row_named(rows, "Inferno"))) \
		.override_failure_message("an unchannelable carving was left pickable").is_true()


# A greyed row that doesn't say why is the bug this ticket exists to fix — the reported symptom was
# a menu that silently showed nothing, and silently showing a dead row instead is no better.
func test_every_greyed_row_says_what_it_needs() -> void:
	var alch := _alchemist_with_a_partial_rune()

	await _enter_attack_ring(alch)
	var rows := _open_rows()

	var inferno := _row_named(rows, "Inferno")
	assert_str(_tooltip(inferno)).override_failure_message("a greyed row explained nothing").is_not_empty()
	assert_str(_tooltip(inferno)).contains("wildcard")   # names the shortfall in the model's currency
	assert_str(_tooltip(inferno)).contains("2")


# The descriptions half of #166: a row you CAN pick still says what it does. Blocked by the old
# controller, which attached a tooltip only when a row was disabled.
func test_an_enabled_row_still_carries_its_readout() -> void:
	var alch := _alchemist_with_a_partial_rune()

	await _enter_attack_ring(alch)
	var rows := _open_rows()

	var ember := _row_named(rows, "Ember")
	assert_bool(_disabled(ember)).is_false()
	assert_str(_tooltip(ember)) \
		.override_failure_message("an enabled row has no hover readout").is_not_empty()
	assert_str(_tooltip(ember)).contains("Damage")


# The tooltip law (visual-clarity #1): Godot tooltips don't autowrap, so every rendered one must
# already be in wrapped form. Valid as an equality check because UiText.wrap is idempotent.
func test_every_rendered_tooltip_is_wrapped() -> void:
	var alch := _alchemist_with_a_partial_rune()

	await _enter_attack_ring(alch)

	for row: Dictionary in _open_rows():
		if _tooltip(row) != "":
			assert_str(_tooltip(row)) \
				.override_failure_message("an unwrapped tooltip reached the screen: '%s'" % _tooltip(row)) \
				.is_equal(UiText.wrap(_tooltip(row)))


# The generalization, proven on the OTHER kind: the reason a weapon row gives is now the family's
# own words rather than one string the menu kept for every weapon in the game.
func test_a_weapon_row_greys_with_its_familys_own_words() -> void:
	var unit := _spawn(Vector2i(2, 0))
	var spear := _sprung_springspear()
	unit.add_item(spear)
	assert_object(unit.get_equipped_weapon()).is_same(spear)

	await _enter_attack_ring(unit)
	var rows := _open_rows()

	var stab := _row_named(rows, "Spring Stab")
	assert_bool(stab.is_empty()).override_failure_message("the secondary attack was not listed").is_false()
	assert_bool(_disabled(stab)).is_true()
	assert_str(_tooltip(stab)) \
		.override_failure_message("the row fell back to the generic reason instead of the family's") \
		.contains("Spring Load")


# #135: the MAIN menu joined the readout law — every rendered row carries its glossary short
# text as hover text, wrapped. On the rendered buttons, same reason as everything above: the
# term keys living in ACTION_DATA proves nothing about what show_main_menu actually drew.
func test_every_main_menu_row_carries_its_glossary_readout() -> void:
	var unit := _spawn(Vector2i(3, 0))
	game.main_action_menu.show_main_menu(unit, Vector2i.ZERO)
	await await_idle_frame()

	var rows := _open_rows()
	assert_int(rows.size()).override_failure_message("the main menu opened with no rows").is_greater(0)
	for row: Dictionary in rows:
		assert_str(_tooltip(row)) \
			.override_failure_message("main-menu row '%s' has no hover readout" % row["name"]) \
			.is_not_empty()
		assert_str(_tooltip(row)) \
			.override_failure_message("main-menu row '%s' rendered an unwrapped tooltip: '%s'" % [row["name"], _tooltip(row)]) \
			.is_equal(UiText.wrap(_tooltip(row)))


# #135 round 2: every attack row's readout ends with its targeting channel, in the concise
# paren form the dev picked — both kinds compose it through AttackData.targets_text, and both
# fixtures' attacks default to TargetMode.UNIT, so "(unit)" is the data-derived expectation.
func test_attack_rows_name_their_targeting_channel() -> void:
	var alch := _alchemist_with_a_partial_rune()
	await _enter_attack_ring(alch)
	var ember := _row_named(_open_rows(), "Ember")
	assert_bool(ember.is_empty()).override_failure_message("row not found on the ring").is_false()
	assert_str(_tooltip(ember)) \
		.override_failure_message("a carving row's readout has no targeting channel: '%s'" % _tooltip(ember)) \
		.contains("(unit)")

	var unit := _spawn(Vector2i(4, 0))
	var spear := _sprung_springspear()
	unit.add_item(spear)
	await _enter_attack_ring(unit)
	var stab := _row_named(_open_rows(), "Spring Stab")
	assert_bool(stab.is_empty()).override_failure_message("row not found on the ring").is_false()
	assert_str(_tooltip(stab)) \
		.override_failure_message("a weapon row's readout has no targeting channel: '%s'" % _tooltip(stab)) \
		.contains("(unit)")


# A Springspear whose secondary requires readiness, already spent.
func _sprung_springspear() -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.SPRINGSPEAR
	template.display_name = "Springspear"
	template.main_attack = WeaponAttackData.new()
	template.main_attack.display_name = "Jab"
	template.main_attack.power = 3
	var lunge := WeaponAttackData.new()
	lunge.display_name = "Spring Stab"
	lunge.power = 6
	lunge.requires_readiness = true
	template.extra_attacks = [lunge]

	var spear := WeaponInstance.make(template) as SpringspearWeaponInstance
	spear.ready = false   # spent: the secondary is gated, the family has words for it
	return spear
# Overwatch is a WEAPON ACTION and ONE ROW (dev, 2026-08-26: "Overwatch should be a weapon action,
# not it's own top rung on the menu" / "The Carbine will get 1 Overwatch action as a special weapon
# action. That's it. There will be no sub menu."), so it sits in the kit slice beside Reload and
# clicking it picks the attack.
#
# The watch attack is a NON-MAIN one, which is #590's whole shape: the row was labelled with the
# attack's display_name whenever it was not the weapon's default, i.e. with the same name its own
# fire row already wore, so build_tree's duplicate-name guard silently dropped one of the two and
# the fire row -- listed first -- is the one that survived. Authoring it on the main hid that
# entirely, which is how the case that used to live here passed over the bug for a fortnight.
#
# The case DRIVES the path instead of reading the tree, because both ends can be right while nothing
# joins them: the row exists, `enter_overwatch_mode` works, and the leaf's own pick is the wire. It
# pins four things a reshuffle would break silently -- the top ring staying clear (a rung of its own
# is what this replaced), the row opening NO submenu, the attack it chooses, and the absence of a
# fire row for a watch-only attack.
func test_a_watch_attack_gets_one_reachable_row_and_no_fire_row() -> void:
	var watcher := _spawn(Vector2i(2, 0))
	var weapon := H.make_weapon(4)
	weapon.template.main_attack.display_name = "Shot"
	var watch := WeaponAttackData.new()
	watch.display_name = "Overwatch"
	watch.can_overwatch = true
	weapon.template.extra_attacks = [watch]
	watcher.equipped_weapon = weapon

	game.main_action_menu.show_main_menu(watcher, Vector2i(400, 300))
	await await_idle_frame()
	var controller := _controller()
	assert_bool(_row_named(controller.level_nodes(), "Overwatch").is_empty()).override_failure_message(
			"Overwatch took a top rung of its own -- it is a weapon action").is_true()

	_drill(controller, MD.kit_category(game, watcher))
	var rows: Array = controller.level_nodes()
	var row := _row_named(rows, "Overwatch")
	assert_bool(row.is_empty()).override_failure_message(
			"the kit slice drew no Overwatch row").is_false()
	var children: Array = row.get("children", [])
	assert_bool(children.is_empty()).override_failure_message(
			"the Overwatch row opened a submenu -- it is one row that picks its own attack").is_true()

	# #590: exactly ONE row wears that name. Two would mean the watch attack kept a firing twin,
	# which is the collision the exclusivity rule exists to make impossible -- and which the menu
	# resolves by DROPPING one, so the count is the only place it is visible.
	var named := 0
	for node: Dictionary in rows:
		if String(node.get("name", "")) == "Overwatch":
			named += 1
	assert_int(named).override_failure_message(
			"the watch attack was offered twice -- it kept a fire row, so one of the two is eaten").is_equal(1)

	# The WIRE, not the two ends.
	_aim_and_click(controller, "Overwatch")
	await await_idle_frame()
	var state: int = game.game_state
	var targeting: int = game.GameState.ATTACK_TARGETING
	assert_int(state).override_failure_message(
			"picking Overwatch opened no targeting at all").is_equal(targeting)
	var intent: int = game.aim_intent
	var watching: int = game.AimIntent.WATCH
	assert_int(intent).override_failure_message(
			"the row opened an ordinary shot's aim, not a watch").is_equal(watching)
	assert_object(watcher.active_attack).override_failure_message(
			"the row aimed no attack -- clicking Overwatch is what chooses it").is_same(watch)
