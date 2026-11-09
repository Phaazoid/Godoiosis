# The aim's source outline (#699), on the real game scene: while a carving is AIMED, the materia sources
# it would draw on, on or beside a cell the unit could stand on this turn, are outlined in their
# element's colour. Never while moving, at rest, or for a weapon attack (dev, 2026-11-08).
#
# The aim is opened by picking the carving's row on the real ring, and F goes through game._input
# (test_aim_cycle's way): a pick runs clear_selection BEFORE it opens the aim, and the outline is cleared
# there, so only the real order shows it survives. Veins stand in for every source kind: which cells
# OFFER what is Materia's (test_materia_sources).
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const MD := preload("res://tests/support/menu_drive.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const WIDTH := 16
const HEIGHT := 6

const FIRE := Elemental.Element.FIRE
const WATER := Elemental.Element.WATER
const AIR := Elemental.Element.AIR

const CASTER := Vector2i(1, 2)
const FIRE_VEIN := Vector2i(1, 1)    # beside where the caster stands
const WATER_VEIN := Vector2i(2, 3)

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	await await_idle_frame()
	game.mission_controller._close_mission_select()
	game.scenario_manager.clear_board()
	game.scenario_director.disarm()
	game.turn_manager.set_active_faction(Team.Faction.PLAYER)
	game.game_state = game.GameState.IDLE
	for x in range(WIDTH):
		for y in range(HEIGHT):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	game.scenario_manager.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


# --- fixture -------------------------------------------------------------------------------------

# Carvings that make their own material out of the air (test_vial_empowerment's), so neither fizzles
# on grass: what is measured is the outline alone. Both deal damage, so a source would empower them.
static func _carving(carving_name: String, recipe: String) -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = carving_name
	t.power = 3
	t.recipe = recipe
	t.targets = EquippableData.TargetMode.UNIT
	return t


func _alchemist(carvings: Array[TransmutationData]) -> Unit:
	var u: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, Team.Faction.PLAYER), CASTER)
	assert_object(u).override_failure_message("fixture: nothing would spawn").is_not_null()
	var elements: Array[Elemental.Element] = [FIRE, WATER, AIR]
	u.unit_instance.aura = {FIRE: 4, WATER: 4, AIR: 4}
	u.unit_instance.affinity = elements
	# One rune per carving: a rune is tempered to its first carving's element, so a fire rune holds no wave.
	var runes: Array[RuneData] = []
	for carving: TransmutationData in carvings:
		var rune := RuneData.new()
		rune.size = RuneData.Size.LARGE
		assert_bool(rune.inscribe(carving)).override_failure_message("fixture: the carving did not inscribe").is_true()
		assert_bool(u.add_item(rune)).override_failure_message("fixture: the rune did not fit").is_true()
		runes.append(rune)
	assert_bool(u.set_equipped_weapon(runes[0])).override_failure_message("fixture: could not equip").is_true()
	return u


# The ring's own pick: it opens on the unit, and the named leaf is chosen the way the control does,
# `cancelled` (clear_selection) BEFORE `action_selected` (the aim) -- the order the outline must survive.
func _aim(unit: Unit, attack: AttackData) -> void:
	game._on_left_click(unit.movement.cell)
	game.main_action_menu.show_main_menu(unit, Vector2i.ZERO)
	var controller := MD.controller_of(game)
	assert_object(controller).override_failure_message("fixture: no action menu opened").is_not_null()
	var leaf := _leaf_named(controller.level_nodes(), attack.display_name)
	assert_bool(leaf.is_empty()).override_failure_message(
			"fixture: the ring offers no %s" % attack.display_name).is_false()
	controller.cancelled.emit(controller)
	controller.action_selected.emit(int(leaf.get("id", 0)), unit)
	assert_int(game.game_state).override_failure_message("fixture: the pick opened no aim") \
		.is_equal(game.GameState.ATTACK_TARGETING)


static func _leaf_named(nodes: Array, label: String) -> Dictionary:
	for node: Dictionary in nodes:
		var children: Array = node.get("children", [])
		if children.is_empty():
			if String(node.get("name", "")) == label:
				return node
			continue
		var found := _leaf_named(children, label)
		if not found.is_empty():
			return found
	return {}


func _press_f() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F
	key.pressed = true
	game._input(key)


# What the outline marks: element -> its cells.
func _outlined() -> Dictionary:
	var out := {}
	for group: Dictionary in game.overlay_manager.source_edges:
		var cells := []
		cells.assign(group["cells"])
		cells.sort()
		out[group["element"]] = cells
	return out


# A cell no stand this turn reaches within Materia.REACH -- derived from Move's own answer, not guessed.
func _beyond_the_walk(unit: Unit) -> Vector2i:
	var stands: Array = game.compute_move_range(unit).reachable.keys()
	stands.append(unit.movement.cell)
	for x in range(WIDTH - 1, -1, -1):
		for y in range(HEIGHT):
			var cell := Vector2i(x, y)
			var near := false
			for stand: Vector2i in stands:
				if absi(stand.x - cell.x) + absi(stand.y - cell.y) <= Materia.REACH:
					near = true
					break
			if not near:
				return cell
	return GridUtils.NO_CELL


# ------------------------------------------------------------------------------
#  The outline
# ------------------------------------------------------------------------------

func test_aiming_a_fire_carving_outlines_the_fire_vein_and_not_the_water() -> void:
	game.vein_field.set_kind(FIRE_VEIN, Vein.Kind.FIRE)
	game.vein_field.set_kind(WATER_VEIN, Vein.Kind.WATER)
	var fireball := _carving("Fireball", "Break(F, A) + Push(F2)")
	var unit := _alchemist([fireball])

	_aim(unit, fireball)

	assert_dict(_outlined()).is_equal({FIRE: [FIRE_VEIN]})
	# Four edges round one cell, in both views' store.
	assert_int((game.overlay_manager.source_edges[0]["segments"] as Array).size()).is_equal(4)


func test_aiming_a_water_carving_outlines_the_water_vein_alone() -> void:
	game.vein_field.set_kind(FIRE_VEIN, Vein.Kind.FIRE)
	game.vein_field.set_kind(WATER_VEIN, Vein.Kind.WATER)
	var wave := _carving("Wave", "Break(A, W) + Push(W2)")
	var unit := _alchemist([wave])

	_aim(unit, wave)

	assert_dict(_outlined()).is_equal({WATER: [WATER_VEIN]})


# Only where the unit could walk: a vein no stand this turn is beside is not outlined.
func test_a_vein_beyond_the_walk_is_not_outlined() -> void:
	var fireball := _carving("Fireball", "Break(F, A) + Push(F2)")
	var unit := _alchemist([fireball])
	var far := _beyond_the_walk(unit)
	assert_that(far).override_failure_message(
			"fixture: every cell of the board is within a walk, so this case proves nothing").is_not_equal(GridUtils.NO_CELL)
	game.vein_field.set_kind(FIRE_VEIN, Vein.Kind.FIRE)
	game.vein_field.set_kind(far, Vein.Kind.FIRE)

	_aim(unit, fireball)

	assert_dict(_outlined()).is_equal({FIRE: [FIRE_VEIN]})


# F steps to the next carving through the same door, and the outline follows it.
func test_f_to_another_carving_repaints_the_outline() -> void:
	game.vein_field.set_kind(FIRE_VEIN, Vein.Kind.FIRE)
	game.vein_field.set_kind(WATER_VEIN, Vein.Kind.WATER)
	var fireball := _carving("Fireball", "Break(F, A) + Push(F2)")
	var wave := _carving("Wave", "Break(A, W) + Push(W2)")
	var unit := _alchemist([fireball, wave])
	_aim(unit, fireball)
	assert_dict(_outlined()).is_equal({FIRE: [FIRE_VEIN]})

	_press_f()

	assert_object(unit.active_attack).override_failure_message("fixture: F did not step to the wave") \
		.is_same(wave)
	assert_dict(_outlined()).is_equal({WATER: [WATER_VEIN]})


func test_leaving_the_aim_clears_the_outline_in_the_store_and_the_flat_view() -> void:
	game.vein_field.set_kind(FIRE_VEIN, Vein.Kind.FIRE)
	var fireball := _carving("Fireball", "Break(F, A) + Push(F2)")
	var unit := _alchemist([fireball])
	_aim(unit, fireball)
	assert_array(game.overlay_manager.source_edges).override_failure_message(
			"fixture: the aim outlined nothing, so its clearing proves nothing").is_not_empty()

	game.exit_current_mode()

	assert_array(game.overlay_manager.source_edges).is_empty()
	var flat: SourceEdges2D = game.overlay_manager.get_node("SourceEdges2D")
	assert_array(flat.groups).is_empty()


# Never while moving, at rest, or for a weapon attack: the outline answers an aim at a carving alone.
func test_moving_resting_and_a_weapon_aim_outline_nothing() -> void:
	game.vein_field.set_kind(FIRE_VEIN, Vein.Kind.FIRE)
	var fireball := _carving("Fireball", "Break(F, A) + Push(F2)")
	var unit := _alchemist([fireball])
	game.select_unit(unit, unit.movement.cell)
	assert_array(game.overlay_manager.source_edges).is_empty()
	game.enter_move_mode(unit)
	assert_array(game.overlay_manager.source_edges).is_empty()
	game.exit_current_mode()

	var slash := WeaponAttackData.new()
	slash.display_name = "Slash"
	slash.power = 3
	var template := WeaponData.new()
	template.display_name = "Sword"
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = slash
	var sword := WeaponInstance.make(template)
	var swordsman: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, Team.Faction.PLAYER), Vector2i(1, 0))
	assert_bool(swordsman.add_item(sword)).is_true()
	assert_bool(swordsman.set_equipped_weapon(sword)).is_true()
	_aim(swordsman, slash)

	assert_array(game.overlay_manager.source_edges).is_empty()
