# The dev Duplicate verb (#1367): the copy is built through ScenarioUnitEntry's capture/apply pair,
# the one answer for copying a unit's state, rather than by hand. The hand copy overwrote a spawned
# unit's inventory while its limb fittings, worn armour and equip still pointed at the SEEDED kit,
# so a character with starting_prosthetics duplicated into a unit whose limbs were orphans outside
# its inventory -- and a save of it recorded -1 for each, reloading as limbs with no item.
#
# Every case goes through the real dev path (arm_duplicate -> resolve_pending), off a source spawned
# through game.spawn_unit from a test-built character, so the copy's spawn seeds a real kit first.
# The source is then changed the ways the hand copy missed: a lost limb, an edited aura and stat, an
# element state, a wound.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const SOURCE_CELL := Vector2i(0, 0)
const COPY_CELL := Vector2i(3, 0)

# Fields compared as objects below rather than by value.
const OBJECT_FIELDS: Array[String] = ["unit_data", "inventory", "stat_effects", "attunement"]

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


# ---- helpers ----

func _prosthetic(kind: WeaponData.LimbKind) -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.PROSTHETIC
	template.main_attack = WeaponAttackData.new()
	template.built_in_stat = 7
	var item := WeaponInstance.make(template)
	item.limb_kind = kind
	return item


# A character whose kit fits two prosthetics, holds a weapon and wears a vest -- every pointer the
# seeding sets -- then a battle's worth of changes on top.
func _damaged_source() -> Unit:
	var vest := ArmorData.new()
	vest.display_name = "Kit Vest"
	var data := H.make_unit_data({}, Team.Faction.PLAYER)
	data.base_affinity = [Elemental.Element.FIRE]
	data.base_aura = {Elemental.Element.FIRE: 4}
	data.starting_inventory = [_prosthetic(WeaponData.LimbKind.ARM), _prosthetic(WeaponData.LimbKind.LEG),
			H.make_weapon(4), vest]
	data.starting_prosthetics = {UnitInstance.LimbSlot.ARM_R: 0, UnitInstance.LimbSlot.LEG_L: 1}
	data.starting_equipped_index = 2
	data.starting_worn_index = 3
	var source: Unit = game.spawn_unit(data, SOURCE_CELL)
	assert_object(source).override_failure_message("the source could not spawn on the painted row").is_not_null()

	assert_bool(source.unit_instance.sever_next_limb()).is_true()   # a natural limb goes
	source.unit_instance.aura[Elemental.Element.FIRE] = 6           # a Unit Editor aura edit
	source.unit_instance.stats[Stats.Stat.CON] += 2                 # ...and a stat edit
	source.element_states.append(Elemental.State.WET)
	source.wounded = true
	return source


func _duplicate(source: Unit) -> Unit:
	game.dev_controller.arm_duplicate(source)
	game.dev_controller.resolve_pending(COPY_CELL)
	var copy: Unit = game.get_unit_at_cell(COPY_CELL)
	assert_object(copy).override_failure_message("Duplicate placed nothing at %s" % COPY_CELL).is_not_null()
	return copy


func _captured(unit: Unit) -> ScenarioUnitEntry:
	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(unit)
	return entry


func _stored_fields() -> Array[String]:
	var names: Array[String] = []
	for property in ScenarioUnitEntry.new().get_property_list():
		var usage: int = property["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE and usage & PROPERTY_USAGE_STORAGE:
			names.append(property["name"])
	return names


# ---- cases ----

func test_a_duplicate_carries_every_limb_it_has_fitted() -> void:
	var copy := _duplicate(_damaged_source())

	var fitted := 0
	for slot: UnitInstance.LimbSlot in copy.unit_instance.limbs:
		var fitting: UnitInstance.LimbFitting = copy.unit_instance.limbs[slot]
		if fitting.state != UnitInstance.LimbState.PROSTHETIC:
			continue
		fitted += 1
		assert_bool(copy.inventory.has(fitting.prosthetic_item)) \
			.override_failure_message("the copy's %s fitting holds an item outside its inventory" \
				% UnitInstance.LimbSlot.keys()[slot]) \
			.is_true()
	assert_int(fitted).override_failure_message("the copy came out with no prosthetic fitted").is_equal(2)

	var saved := _captured(copy)
	assert_int(saved.limb_prosthetic_items.size()).is_equal(2)
	for slot: UnitInstance.LimbSlot in saved.limb_prosthetic_items:
		assert_int(saved.limb_prosthetic_items[slot]) \
			.override_failure_message("a save of the copy lost the %s prosthetic (-1)" \
				% UnitInstance.LimbSlot.keys()[slot]) \
			.is_greater_equal(0)


# What a save of the source would write, a save of the copy writes too -- every stored field, so a
# field added to the capture later is compared without touching this case.
func test_a_duplicate_is_the_source_captured_again() -> void:
	var source := _damaged_source()
	var copy := _duplicate(source)
	var want := _captured(source)
	var got := _captured(copy)

	var fields := _stored_fields()
	assert_bool(fields.has("limb_states")).override_failure_message("no stored fields were found to compare").is_true()
	for field in fields:
		if OBJECT_FIELDS.has(field):
			continue
		assert_bool(got.get(field) == want.get(field)) \
			.override_failure_message("'%s' differs: source %s, copy %s" \
				% [field, var_to_str(want.get(field)), var_to_str(got.get(field))]) \
			.is_true()

	assert_int(got.inventory.size()).is_equal(want.inventory.size())
	for i in want.inventory.size():
		assert_object(got.inventory[i].get_script()).is_same(want.inventory[i].get_script())
		assert_str(got.inventory[i].shown_name()).is_equal(want.inventory[i].shown_name())
	assert_int(got.stat_effects.size()).is_equal(want.stat_effects.size())


# A copy is its own unit: no carried object or state dict shared with the source, a squad of its
# own, and no Overwatch -- an armed watch is anchored to the SOURCE's cell, and the copy stands elsewhere.
func test_a_duplicate_shares_nothing_and_takes_no_watch() -> void:
	var source := _damaged_source()
	var aim := SOURCE_CELL + Vector2i(1, 0)
	var watched: Array[Vector2i] = [aim]
	# The capture indexes into overwatch_attacks() (#590): an attack outside that view keeps no watch,
	# and the copy would come out watch-less with nothing dropping it.
	var main := (source.get_equipped_weapon() as WeaponInstance).template.main_attack
	main.can_overwatch = true
	source.arm_watch(SOURCE_CELL, aim, watched, main)
	assert_array(_captured(source).watch_cells) \
		.override_failure_message("the source's watch does not ride a capture, so a copied one is invisible here") \
		.is_not_empty()

	var copy := _duplicate(source)

	for item in copy.inventory:
		if item != null:
			assert_bool(source.inventory.has(item)).override_failure_message(
				"the copy carries the source's own '%s'" % item.shown_name()).is_false()
	copy.unit_instance.aura[Elemental.Element.FIRE] = 1
	assert_int(source.unit_instance.aura[Elemental.Element.FIRE]).is_equal(6)

	assert_object(copy.squad).is_not_same(source.squad)
	assert_int(copy.squad.members.size()).is_equal(1)
	assert_object(copy.watch).is_null()
	assert_object(source.watch).is_not_null()
