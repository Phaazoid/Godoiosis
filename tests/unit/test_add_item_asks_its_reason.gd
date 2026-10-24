# Unit.add_item's bare false is DERIVED from add_block_reason (#1412). The door used to run its own
# free-slot loop and took a loose mod the reason refused, so "may this be carried" had two answers.
# Every item kind is asked on both sides of both refusals (the mod clause, with room; a full
# inventory), and each seeding door that reaches add_item is shown dropping an authored mod.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


# One of each kind a door may be handed, fresh per call: a carried object has exactly one owner.
static func _every_kind() -> Array[Item]:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	var kinds: Array[Item] = [Item.new(), template, H.make_weapon(), ArmorData.new(), RuneData.new(),
			VialData.new(), ConduitData.new(), WeaponModData.new()]
	return kinds


static func _kind(item: Item) -> String:
	return item.get_script().get_global_name()


func _bare_unit() -> Unit:
	return H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)


# The reason is asked FIRST, since add_item acts on a yes; a no must leave no trace in the inventory.
func _assert_door_agrees(unit: Unit, item: Item, side: String) -> String:
	var reason := unit.add_block_reason(item)
	var took := unit.add_item(item)
	assert_bool(took).override_failure_message("%s, %s: add_item answered %s but add_block_reason said '%s'"
			% [_kind(item), side, took, reason]).is_equal(reason == "")
	assert_bool(unit.inventory.has(item)).override_failure_message("%s, %s: carried is not what add_item answered"
			% [_kind(item), side]).is_equal(took)
	return reason


func test_with_room_the_door_and_its_reason_agree_on_every_kind() -> void:
	var refused: Array[String] = []
	for item: Item in _every_kind():
		if _assert_door_agrees(_bare_unit(), item, "with room") != "":
			refused.append(_kind(item))
	# Non-vacuity: the mod clause is the one refusal on this side, and nothing else tripped it.
	assert_array(refused).contains_exactly(["WeaponModData"])


func test_a_full_unit_refuses_every_kind_with_its_reason() -> void:
	var unit := _bare_unit()
	for i in Unit.MAX_INVENTORY_SIZE:
		assert_bool(unit.add_item(Item.new())).override_failure_message("fixture: slot %d did not fill" % i).is_true()
	for item: Item in _every_kind():
		assert_str(_assert_door_agrees(unit, item, "full")).is_not_empty()


func test_the_starting_kit_drops_an_authored_mod_and_seeds_the_rest() -> void:
	var data := H.make_unit_data({}, Team.Faction.PLAYER)
	data.starting_inventory = [WeaponModData.new(), H.make_weapon()]
	var unit: Unit = auto_free(H.UNIT_SCENE.instantiate())
	unit.unit_data = data
	add_child(unit)   # _ready -> _seed_starting_kit

	_assert_carries_the_weapon_and_no_mod(unit)


func test_a_scenario_entry_drops_an_authored_mod_and_loads_the_rest() -> void:
	var source := _bare_unit()
	assert_bool(source.add_item(H.make_weapon())).is_true()
	var entry := ScenarioUnitEntry.new()
	entry.capture_unit_state(source)
	entry.inventory.append(WeaponModData.new())   # appended, so the captured indices still hold

	var loaded := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(5, 5), {}, false)
	entry.apply_unit_state(loaded)

	_assert_carries_the_weapon_and_no_mod(loaded)


func _assert_carries_the_weapon_and_no_mod(unit: Unit) -> void:
	var weapons := 0
	for item: Item in unit.inventory:
		assert_bool(item is WeaponModData).override_failure_message("a loose mod was carried").is_false()
		if item is WeaponInstance:
			weapons += 1
	assert_int(weapons).override_failure_message("the refusal cost the item beside it").is_equal(1)
