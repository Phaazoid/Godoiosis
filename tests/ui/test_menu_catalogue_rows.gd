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
const WATER_ATLAS := Vector2i(5, 6)   # play/board_builder.gd's: terrain_type WATER in TestTiles.tres

# The partial rune is carved in AETHER because free aether is in every cell's air: no carving of it
# can FIZZLE (Deep Alchemy Phase 2), so these cases measure channeling alone. Free fire is in nobody's.
const AETHER := Elemental.Element.AETHER
const WATER := Elemental.Element.WATER

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


func _carving(recipe: String, name: String) -> TransmutationData:
	var t: TransmutationData = TransmutationData.new()
	t.display_name = name
	t.power = 5
	t.recipe = recipe
	return t


# An alchemist wielding a three-carving rune with a mixed verdict — #157's partial case, which is
# precisely why this readout is owed: the rune equips legally and the dead carving still needs to
# explain itself. At aether-1 under the wildcard model (2026-08-10): Ember covered, Pyre channels
# via the universal +1, Inferno's deficit of 2 is past any pool.
func _alchemist_with_a_partial_rune() -> Unit:
	var alch := _spawn(Vector2i(1, 0))
	alch.unit_instance.aura = { AETHER: 1 }
	alch.unit_instance.affinity = [AETHER]

	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	rune.display_name = "Test Rune"
	# One, two and three verbs asking Aether 1, 2 and 3 -- six verbs, the LARGE rune's whole capacity.
	assert_bool(rune.inscribe(_carving("Push(Q)", "Ember"))).is_true()                            # deficit 0
	assert_bool(rune.inscribe(_carving("Focus(Q) + Push(Q)", "Pyre"))).is_true()                  # deficit 1 — wildcarded
	assert_bool(rune.inscribe(_carving("Focus(Q) + Spread(Q) + Push(Q)", "Inferno"))).is_true()   # deficit 2 — dead
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
# The case DRIVES the path instead of reading the tree, and here that is not a preference: the bug
# is unreadable from the tree (see the note in the body). It pins four things a reshuffle would
# break silently -- the top ring staying clear (a rung of its own is what this replaced), the row
# opening NO submenu, the VERB it opens, and the attack it chooses.
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

	# #590 is INVISIBLE to a row count, and that is the trap worth naming: _append_unique
	# guarantees at most one node per name in a bucket, so a watch attack that kept its firing twin
	# does not show up as two rows -- it shows up as ONE row that fires. Counting rows here passes
	# against the bug (measured). The only tell from the menu side is which verb the row opens,
	# which is what the drive below asserts, and the data-layer half is
	# tests/weapons/test_overwatch_is_exclusive.gd.

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


# ==============================================================================
#  #1045: a weapon's live count on its attack rows
# ==============================================================================

# The label the ring DRAWS for a row, run for run -- slice_label_parts is the only path
# _draw_slice_label takes, so this is the text on screen rather than the data behind it.
func _drawn_label(row: Dictionary) -> String:
	assert_bool(row.is_empty()).override_failure_message("row not found on the ring").is_false()
	var text := ""
	for part: Array in ActionMenuController.slice_label_parts(row):
		text += String(part[0])
	return text


# A Carbine whose main and whose watch both spend rounds -- the shipped family's shape, built here so
# nothing below leans on authored content.
func _carbine() -> CarbineWeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CARBINE
	template.display_name = "Carbine"
	template.main_attack = WeaponAttackData.new()
	template.main_attack.display_name = "Shot"
	template.main_attack.power = 4
	template.main_attack.requires_readiness = true
	template.main_attack.consumes_readiness = true
	var watch := WeaponAttackData.new()
	watch.display_name = "Overwatch"
	watch.can_overwatch = true
	watch.requires_readiness = true
	watch.consumes_readiness = true
	template.extra_attacks = [watch]
	return WeaponInstance.make(template) as CarbineWeaponInstance


# Both doors an attack row comes through carry the count -- the main through _attack_entry, the watch
# through _overwatch_rows -- and the verb beside them carries none. Re-opened after a round is spent,
# because a count frozen at the first build is exactly what one open cannot see.
func test_a_carbines_rows_carry_the_live_magazine_to_the_ring() -> void:
	var unit := _spawn(Vector2i(2, 0))
	var carbine := _carbine()
	unit.add_item(carbine)
	assert_object(unit.get_equipped_weapon()).is_same(carbine)

	await _enter_attack_ring(unit)
	var rows := _open_rows()
	var full := carbine.gauge().label()
	assert_str(_drawn_label(_row_named(rows, "Shot"))).is_equal("Shot " + full)
	assert_str(_drawn_label(_row_named(rows, "Overwatch"))) \
		.override_failure_message("the watch row lost the count the fire row carries") \
		.is_equal("Overwatch " + full)
	assert_str(_drawn_label(_row_named(rows, "Reload"))).is_equal("Reload")

	carbine.consume_readiness_for(carbine.template.main_attack)
	_controller().dismiss()
	await await_idle_frame()
	await _enter_attack_ring(unit)
	var after := _drawn_label(_row_named(_open_rows(), "Shot"))
	assert_str(after).is_equal("Shot " + carbine.gauge().label())
	assert_str(after).override_failure_message("the ring kept the full magazine after a shot").is_not_equal("Shot " + full)


# The rev timer rides the Chainsword's attack as a TIMER -- the kind the ring tints -- and an idle sword
# prints nothing at all. Slash authors no readiness flag, so the flag rule alone would miss it.
func test_a_revved_chainswords_attack_carries_a_timer() -> void:
	var unit := _spawn(Vector2i(3, 0))
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.display_name = "Slash"
	var sword := WeaponInstance.make(template) as ChainswordWeaponInstance
	unit.add_item(sword)

	await _enter_attack_ring(unit)
	assert_str(_drawn_label(_row_named(_open_rows(), "Slash"))).is_equal("Slash")
	_controller().dismiss()
	await await_idle_frame()

	sword.rev()
	await _enter_attack_ring(unit)
	var slash := _row_named(_open_rows(), "Slash")
	assert_str(_drawn_label(slash)).is_equal("Slash " + sword.gauge().label())
	var gauge := slash.get("gauge") as WeaponGauge
	assert_object(gauge).override_failure_message("the revved sword's row reached the ring with no gauge").is_not_null()
	if gauge == null:
		return
	assert_int(gauge.kind).override_failure_message("the rev timer reached the ring as a stock").is_equal(WeaponGauge.Kind.TIMER)


# ==============================================================================
#  #1083: whether an attack hits allies
# ==============================================================================

# A three-cell row around the aimed cell -- a footprint an ally can stand in.
func _row_shape() -> AttackShape:
	var stamp: Array[Vector2i] = [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0)]
	var shape := AttackShape.new()
	shape.stamp = stamp
	return shape


func _swing(name: String, splashes: bool, shape: AttackShape) -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.display_name = name
	attack.power = 3
	attack.hits_allies = splashes
	attack.attack_shape = shape
	return attack


func _sword(main: WeaponAttackData, extras: Array[WeaponAttackData]) -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.display_name = "Test Sword"
	template.main_attack = main
	template.extra_attacks = extras
	return WeaponInstance.make(template)


# The ruled pair and the ruled silence, on the readout the ring draws (#1083): an area attack says
# Splashes or Spares, and a one-cell attack says neither. Jab authors hits_allies on purpose -- it is
# the state a rule that forgot the footprint would print "Splashes allies" for.
func test_an_attack_row_says_whether_it_hits_allies_only_when_its_footprint_can_hold_one() -> void:
	var unit := _spawn(Vector2i(2, 0))
	var extras: Array[WeaponAttackData] = [_swing("Cleave", false, _row_shape()), _swing("Jab", true, null)]
	unit.add_item(_sword(_swing("Sweep", true, _row_shape()), extras))

	await _enter_attack_ring(unit)
	var rows := _open_rows()
	assert_str(_tooltip(_row_named(rows, "Sweep"))).contains("Splashes allies")
	assert_str(_tooltip(_row_named(rows, "Cleave"))).contains("Spares allies")
	var jab_row := _row_named(rows, "Jab")
	assert_bool(jab_row.is_empty()).override_failure_message(
		"no Jab row on the ring -- the silence below would pass for want of a row").is_false()
	var jab := _tooltip(jab_row)
	assert_str(jab).override_failure_message(
		"a one-cell attack's row still speaks about allies:\n%s" % jab).not_contains("allies")


# The COMPOSED answer reaches the ring, not the authored one: a fitted mod turning the splash off makes
# the row say Spares, because that is what RulesService.is_attack_victim will then do with an ally.
func test_a_fitted_mod_turning_the_splash_off_reaches_the_rings_readout() -> void:
	var unit := _spawn(Vector2i(2, 0))
	var none: Array[WeaponAttackData] = []
	var sword := _sword(_swing("Sweep", true, _row_shape()), none)
	var mod := WeaponModData.new()
	mod.hits_allies_override = WeaponModData.Override.OFF
	assert_bool(sword.fit(0, mod)).override_failure_message(
		"fixture: the mod must actually fit, or the override reads as absent").is_true()
	unit.add_item(sword)

	await _enter_attack_ring(unit)
	var sweep := _tooltip(_row_named(_open_rows(), "Sweep"))
	assert_str(sweep).override_failure_message(
		"the ring read the authored splash, not the fitted weapon's:\n%s" % sweep).contains("Spares allies")
	assert_str(sweep).not_contains("Splashes allies")


# The watch row is an attack row too: its shot gathers victims by the same rule, so it carries the same
# line under its own explanation.
func test_a_watch_row_says_whether_its_shot_hits_allies() -> void:
	var unit := _spawn(Vector2i(2, 0))
	var carbine := _carbine()
	(carbine.template.extra_attacks[0] as WeaponAttackData).attack_shape = _row_shape()
	unit.add_item(carbine)

	await _enter_attack_ring(unit)
	var watch := _tooltip(_row_named(_open_rows(), "Overwatch"))
	assert_str(watch).contains("Spares allies")
	assert_str(watch).override_failure_message(
		"the ally line replaced the watch's own explanation:\n%s" % watch) \
		.contains(UiText.wrap(Glossary.short(Glossary.Term.OVERWATCH)).split("\n")[0])


# ==============================================================================
#  Deep Alchemy Phase 2: a carving that would FIZZLE greys, with the reason
# ==============================================================================

# Pressure Spray's shape, which needs water beside the caster. Channelable at water-4, so the fizzle is
# the only thing that can grey it.
func _spray_alchemist(cell: Vector2i) -> Unit:
	var alch := _spawn(cell)
	alch.unit_instance.aura = { WATER: 4 }
	alch.unit_instance.affinity = [WATER]
	var rune := RuneData.new()
	rune.size = RuneData.Size.MEDIUM
	rune.display_name = "Spray Rune"
	assert_bool(rune.inscribe(_carving("Focus(W2) + Push(W2)", "Spray"))).is_true()
	alch.add_item(rune)
	assert_object(alch.get_equipped_weapon()).override_failure_message("fixture failed to equip the rune").is_same(rune)
	return alch


# The reason on the row is CellSubstances' own, asked from the cell the queue gate asks it from -- so a
# greyed row and a refused order say the same thing.
func test_a_carving_that_would_fizzle_is_greyed_with_the_reason() -> void:
	var alch := _spray_alchemist(Vector2i(1, 0))
	var spray: AttackData = alch.get_transmutation_choices()[0]
	assert_bool(alch.is_attack_fireable(spray)).override_failure_message(
			"fixture: the carving must be channelable, or channeling is what greys it").is_true()
	var reason := CellSubstances.fizzle_reason(spray, alch.get_projected_destination(), game._board(), alch)
	assert_str(reason).override_failure_message(
			"fixture: the grass row holds no water, so the carving must fizzle").is_not_empty()

	await _enter_attack_ring(alch)
	var row := _row_named(_open_rows(), "Spray")
	assert_bool(row.is_empty()).override_failure_message("the carving was not listed").is_false()
	assert_bool(_disabled(row)).override_failure_message("a carving that fizzles was left pickable").is_true()
	assert_str(_tooltip(row).replace("\n", " ")).override_failure_message(
			"the greyed row did not say why: '%s'" % _tooltip(row)).contains(reason)


# Judged from where the unit will STAND after its queued moves: a walk to the water makes the row live
# while the unit still stands far from it. A menu reading the live cell keeps it greyed.
func test_the_row_is_judged_from_where_the_unit_will_stand() -> void:
	game.grid.set_cell(Vector2i(7, 0), GRASS_SOURCE, WATER_ATLAS)
	var alch := _spray_alchemist(Vector2i(1, 0))
	await _enter_attack_ring(alch)
	assert_bool(_disabled(_row_named(_open_rows(), "Spray"))).override_failure_message(
			"fixture: from (1, 0) the water must be out of reach").is_true()
	_controller().dismiss()
	await await_idle_frame()

	var walk := MoveAction.new()
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(6, 0)]
	walk.init(alch, path, null)
	assert_bool(game.squad_manager.queue_action(alch.squad, walk)).is_true()
	assert_that(alch.get_projected_destination()).is_equal(Vector2i(6, 0))

	await _enter_attack_ring(alch)
	assert_bool(_disabled(_row_named(_open_rows(), "Spray"))).override_failure_message(
			"the row was judged from the live cell, not from where the queued walk ends").is_false()


# Pressure Spray is watch-only, so the WATCH row greys the same way (the one shipped tied carving).
# The control is the same rune on a caster carrying its own water.
func test_a_watch_carving_that_would_fizzle_greys_its_watch_row_with_the_reason() -> void:
	var alch := _spawn(Vector2i(1, 0))
	alch.unit_instance.aura = { WATER: 4, Elemental.Element.AIR: 1 }
	alch.unit_instance.affinity = [WATER, Elemental.Element.AIR]
	var rune := RuneData.new()
	rune.size = RuneData.Size.MEDIUM
	rune.display_name = "Spray Rune"
	assert_bool(rune.inscribe(_carving("Break(A, W) + Push(W2)", "Splash"))).is_true()
	var spray := _carving("Focus(W2) + Push(W2)", "Spray")
	spray.can_overwatch = true
	assert_bool(rune.inscribe(spray)).is_true()
	alch.add_item(rune)
	assert_object(alch.get_equipped_weapon()).override_failure_message("fixture failed to equip the rune").is_same(rune)
	assert_bool(alch.is_attack_fireable(spray)).override_failure_message(
			"fixture: the watch carving must be channelable, or channeling is what greys it").is_true()
	var reason := CellSubstances.fizzle_reason(spray, alch.get_projected_destination(), game._board(), alch)
	assert_str(reason).override_failure_message("fixture: the grass row holds no water").is_not_empty()

	await _enter_attack_ring(alch)
	var row := _row_named(_open_rows(), "Spray")
	assert_bool(row.is_empty()).override_failure_message("the kit slice drew no watch row for the carving").is_false()
	assert_bool(_disabled(row)).override_failure_message("a watch that would fizzle was left pickable").is_true()
	assert_str(_tooltip(row).replace("\n", " ")).override_failure_message(
			"the greyed watch row did not say why: '%s'" % _tooltip(row)).contains(reason)
	_controller().dismiss()
	await await_idle_frame()

	alch.add_element_state(Elemental.State.WET)
	await _enter_attack_ring(alch)
	assert_bool(_disabled(_row_named(_open_rows(), "Spray"))).override_failure_message(
			"a caster carrying its own water still had its watch row greyed").is_false()


# ==============================================================================
#  #1409: an unfireable main lists greyed, and the grey reason is the queue's
# ==============================================================================

# The kit row named `label`, asserted LISTED and GREYED with `reason`. The tooltip is wrapped, so it
# is compared with its line breaks flattened, the same as the fizzle cases above.
func _assert_greyed_with(rows: Array, label: String, reason: String) -> void:
	var row := _row_named(rows, label)
	assert_bool(row.is_empty()).override_failure_message(
			"the '%s' row is missing -- an unusable attack greys, it never hides" % label).is_false()
	assert_bool(_disabled(row)).override_failure_message("'%s' was listed live" % label).is_true()
	assert_str(_tooltip(row).replace("\n", " ")).override_failure_message(
			"'%s' greyed without the reason '%s': '%s'" % [label, reason, _tooltip(row)]).contains(reason)


# A Carbine at 0/6 opens its kit slice (Reload and the watch keep it open) and the MAIN must be in it.
# The ATTACK expander used to gate on the main being fireable, so the slice drew no Shot row at all.
func test_a_dry_carbine_lists_its_main_greyed_with_the_reason() -> void:
	var unit := _spawn(Vector2i(2, 0))
	var carbine := _carbine()
	unit.add_item(carbine)
	assert_object(unit.get_equipped_weapon()).is_same(carbine)
	for _shot in CarbineWeaponInstance.MAGAZINE_SIZE:
		carbine.consume_readiness_for(carbine.template.main_attack)
	var reason := AttackAction.fire_block_reason(unit, carbine.template.main_attack)
	assert_str(reason).override_failure_message("fixture: the magazine is not dry").is_not_empty()

	await _enter_attack_ring(unit)
	_assert_greyed_with(_open_rows(), "Shot", reason)


# The same for a spring that gates its main: spent, the main lists greyed in the family's own words.
func test_a_sprung_springspears_main_lists_greyed() -> void:
	var unit := _spawn(Vector2i(2, 0))
	var spear := _sprung_springspear()
	spear.template.main_attack.requires_readiness = true
	unit.add_item(spear)
	assert_object(unit.get_equipped_weapon()).is_same(spear)
	var reason := AttackAction.fire_block_reason(unit, spear.template.main_attack)
	assert_str(reason).override_failure_message("fixture: the spent spring does not gate the main").is_not_empty()

	await _enter_attack_ring(unit)
	_assert_greyed_with(_open_rows(), "Jab", reason)


# A unit missing an arm cannot wield its two-handed weapon, and every row of that weapon says so in
# the words the QUEUE refuses with. The rows used to ask Unit.attack_block_reason alone, which knows
# the economy but not the wield lock, so the secondary and the watch listed live and the click was
# refused. The main lists too: the lock is a reason to grey, not to hide.
func test_a_wield_locked_weapon_greys_every_row_with_the_queues_reason() -> void:
	var unit := _spawn(Vector2i(2, 0))
	var foe: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(3, 0))
	var weapon := H.make_weapon(4)
	weapon.template.display_name = "Greatsword"
	weapon.template.two_handed = true
	weapon.template.main_attack.display_name = "Cleave"
	var sweep := WeaponAttackData.new()
	sweep.display_name = "Sweep"
	sweep.power = 3
	var watch := WeaponAttackData.new()
	watch.display_name = "Overwatch"
	watch.can_overwatch = true
	weapon.template.extra_attacks = [sweep, watch]
	unit.equipped_weapon = weapon
	unit.unit_instance.limbs[UnitInstance.LimbSlot.ARM_L].state = UnitInstance.LimbState.EMPTY
	assert_str(unit.wield_block_reason()).override_failure_message("fixture: the wield lock is not engaged").is_not_empty()

	unit.active_attack = sweep
	var refused: String = game.squad_manager.try_queue_action(unit.squad,
			AttackAction.declare(unit, unit.movement.cell, foe.movement.cell))
	unit.active_attack = null
	assert_str(refused).override_failure_message("the queue accepted a wield-locked secondary").is_not_empty()

	await _enter_attack_ring(unit)
	var rows := _open_rows()
	for label: String in ["Cleave", "Sweep", "Overwatch"]:
		_assert_greyed_with(rows, label, refused)
