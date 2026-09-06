# #697's two UI halves, on the real scene:
#
#   1. THE VERB. A vial is carried and never slotted, so the inspect panel offers Use where it
#      offers Equip for a weapon -- and the refusal, when there is one, is the gate's own sentence
#      (#744's shape, which test_equip_reason_surfaces.gd pins for the equip side).
#
#   2. THE LAW #2 WIRE, which is the half that would have shipped broken. The panel's verbs mutate
#      the unit ON THE SPOT -- they are not queued -- and until #697 nothing in that path re-resolved
#      the plan. So a Use with a cast already queued left the row previewing the UNEMPOWERED number
#      while execution would have played the empowered one. That is the queue lying, and it was
#      already true of Equip before a vial existed.
extends GdUnitTestSuite

const P := preload("res://tests/support/pattern_fixtures.gd")

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
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
	game.mission_controller._close_mission_select()
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		game.grid.set_cell(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	game.scenario_manager.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


static func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


static func _button_starting(root: Node, prefix: String) -> Button:
	for node: Node in _walk(root):
		var button := node as Button
		if button != null and button.text.begins_with(prefix):
			return button
	return null


func _vial(element := FIRE) -> VialData:
	var v := VialData.new()
	v.element = element
	v.display_name = "Vial of Sulfur" if element == FIRE else "Vial of Mercury"
	return v


func _alchemist(cell := Vector2i(1, 0)) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.PLAYER), cell)
	unit.unit_instance.aura = { FIRE: 4 }
	var affinity: Array[Elemental.Element] = [FIRE]
	unit.unit_instance.affinity = affinity
	return unit


func _fireball() -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = "Fireball"
	t.power = 4
	t.sigils.assign([FIRE])
	t.targets = EquippableData.TargetMode.UNIT
	t.attack_pattern = P.point(3)
	return t


func _open_popup_on(unit: Unit, item: Item) -> Node:
	game.unit_info_panel.set_unit(unit, true, game._board())
	await await_idle_frame()
	var panel = game.unit_info_panel.inventory_panel
	panel._show_action_popup(unit.inventory.find(item))
	await await_idle_frame()
	return panel


# --- the verb -----------------------------------------------------------------------------------

func test_a_carried_vial_offers_Use() -> void:
	var unit: Unit = _alchemist()
	var vial := _vial()
	assert_bool(unit.add_item(vial)).is_true()

	var panel = await _open_popup_on(unit, vial)
	var use := _button_starting(panel, "Use")
	assert_object(use).override_failure_message(
			"the inspect panel offered no Use button for a carried vial").is_not_null()
	assert_bool(use.disabled).is_false()


# A vial is not gear: offering Equip for one would be the panel claiming a slot that does not exist.
func test_a_carried_vial_does_not_offer_Equip() -> void:
	var unit: Unit = _alchemist()
	var vial := _vial()
	unit.add_item(vial)

	var panel = await _open_popup_on(unit, vial)
	assert_object(_button_starting(panel, "Equip")).override_failure_message(
			"the panel offered to EQUIP a vial -- it fills no slot").is_null()


# #744's shape, one kind over: the button wears the gate's own sentence rather than wording a
# refusal of its own.
func test_a_refused_Use_carries_the_gates_own_words() -> void:
	var unit: Unit = _alchemist()
	unit.attunement = _vial()
	var second := _vial()
	unit.add_item(second)

	var reason: String = second.use_block_reason(unit)
	assert_str(reason).override_failure_message(
			"fixture: this vial does not actually refuse, so the case pins nothing").is_not_empty()

	var panel = await _open_popup_on(unit, second)
	var use := _button_starting(panel, "Use")
	assert_object(use).is_not_null()
	assert_bool(use.disabled).is_true()
	assert_str(use.text).override_failure_message(
			"the Use button words its own refusal instead of reading the gate: %s" % use.text
			).contains(reason)


# An overwrite is allowed, and the trade has to be readable BEFORE the item is spent.
func test_an_overwriting_Use_names_what_it_replaces() -> void:
	var unit: Unit = _alchemist()
	unit.attunement = _vial(FIRE)
	var water := _vial(Elemental.Element.WATER)
	unit.add_item(water)

	var panel = await _open_popup_on(unit, water)
	var use := _button_starting(panel, "Use")
	assert_object(use).is_not_null()
	assert_bool(use.disabled).is_false()
	assert_str(use.text).contains(unit.attunement.display_name)


# --- the Law #2 wire ----------------------------------------------------------------------------

# Queue a cast, THEN pop a vial, and touch the queue in no other way. The row's number has to move,
# because execution's number moved. The mutant is deleting game.gd's loadout_changed wire.
func test_using_a_vial_re_resolves_a_queued_cast() -> void:
	var unit: Unit = _alchemist()
	var foe: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(3, 0))
	foe.unit_instance.stats[Stats.Stat.MHP] = 200
	foe.set_current_hp(200)

	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	rune.inscriptions.assign([_fireball()])
	unit.add_item(rune)

	var vial := _vial()
	unit.add_item(vial)

	var cast := AttackAction.create(unit, unit.movement.cell, foe, foe.movement.cell)
	cast.fired_attack = unit.get_fired_attack()
	assert_object(cast.fired_attack).override_failure_message(
			"fixture: the alchemist cannot channel its carving, so nothing is queued").is_not_null()
	game.squad_manager.active_squad = unit.squad
	game.squad_manager.queue_action(unit.squad, cast)
	game.refresh_action_queue(unit.squad)
	await await_idle_frame()

	# Read the RENDERED row, which is what the player actually sees. The queue holds the aim;
	# refresh_action_queue resolves it into per-victim actions and builds the rows from those, so
	# the row's own action is the one carrying the outcome.
	var row := _attack_row()
	assert_object(row).override_failure_message("no attack row was rendered, so this case pins nothing").is_not_null()
	var before: int = row.action.resolved.damage
	assert_int(before).override_failure_message("fixture: the queued cast resolved no damage").is_greater(0)
	assert_object(_attack_row().action.resolved.burned_vial).override_failure_message(
			"fixture: the cast already shows a burn before any vial was used").is_null()

	# The Use verb, through the real button path -- no queue edit anywhere.
	var panel = await _open_popup_on(unit, vial)
	var use := _button_starting(panel, "Use")
	assert_object(use).is_not_null()
	use.pressed.emit()
	await await_idle_frame()

	assert_object(unit.attunement).override_failure_message(
			"the Use button did not actually attune the unit").is_not_null()

	var after := _attack_row()
	assert_int(after.action.resolved.damage).override_failure_message(
			"the queued cast still previews %d after a vial was popped -- the queue is showing a " % before
			+ "number execution will not play (Law #2)").is_equal(before + 1)
	assert_object(after.action.resolved.burned_vial).override_failure_message(
			"the row does not record the burn, so the player spends a vial unannounced").is_same(vial)
	assert_object(unit.attunement).override_failure_message(
			"previewing the burn SPENT it -- the resolver must mutate nothing").is_same(vial)


# The one rendered attack row in the queue dock.
func _attack_row() -> ActionQueueRow:
	var rows: Array[ActionQueueRow] = []
	_collect(game.squad_action_queue_control, rows)
	for r in rows:
		if r.action is AttackAction:
			return r
	return null


func _collect(node: Node, out: Array[ActionQueueRow]) -> void:
	if node is ActionQueueRow:
		out.append(node as ActionQueueRow)
		return
	for child in node.get_children():
		_collect(child, out)
