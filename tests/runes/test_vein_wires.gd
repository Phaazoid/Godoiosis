# The materia veins' WIRES (#696): that a vein painted into the store reaches every board the rules
# read. What a vein empowers and makes present is Materia's and CellSubstances' (test_materia_sources,
# test_cell_substances), asked of boards the tests hand in; these cases pin that the REAL boards carry the
# store -- the game's (game._board, the pass's and every judge's board_source), the Play API's two, and
# the copies a board makes of itself -- so a vein never silently does nothing where a fixture would pass.
#
# Host: tests/squad/test_a_carving_judge_reads_the_prefix_bodies.gd's game, the fixture grid of grass.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const WIDTH := 9
const HEIGHT := 6

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const FIRE := Elemental.Element.FIRE
const AIR := Elemental.Element.AIR

# Two casters alike in everything but the vein beside one of them, each two from its own foe.
const VEINED := Vector2i(1, 1)
const VEINED_FOE := Vector2i(3, 1)
const VEIN := Vector2i(1, 0)        # within Materia.REACH of VEINED
const BARE := Vector2i(6, 4)
const BARE_FOE := Vector2i(8, 4)

var _main: Node
var game: Node2D
var sm: SquadManager


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	sm = game.squad_manager
	game.mission_controller._close_mission_select()
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(WIDTH):
		for y in range(HEIGHT):
			game.grid.paint(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	game.scenario_manager.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.MHP: 200}, faction), cell)
	assert_object(unit).override_failure_message("fixture: nothing would spawn at %s" % cell).is_not_null()
	unit.set_current_hp(unit.get_max_hp())
	return unit


# A fire carving that makes its own fire out of the air (tests/runes/test_vial_empowerment.gd's), so the
# grass's lack of any is no fizzle: what is measured is the empowerment alone.
static func _fireball() -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = "Fireball"
	t.power = 4
	t.recipe = "Break(F, A) + Push(F2)"
	t.targets = EquippableData.TargetMode.UNIT
	P.point(t, 2)
	return t


func _alchemist(cell: Vector2i, carving: TransmutationData) -> Unit:
	var u := _spawn(PLAYER, cell)
	var elements: Array[Elemental.Element] = [FIRE, AIR]
	u.unit_instance.aura = {FIRE: 4, AIR: 4}
	u.unit_instance.affinity = elements
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	assert_bool(rune.inscribe(carving)).override_failure_message("fixture: the carving did not inscribe").is_true()
	assert_bool(u.add_item(rune)).override_failure_message("fixture: the rune did not fit").is_true()
	u.equipped_weapon = rune
	return u


# Queue the cast through the player's own gate and read what the pass resolved it to.
func _cast_damage(caster: Unit, carving: TransmutationData, at: Vector2i) -> int:
	caster.active_attack = carving
	var aim := AttackAction.declare(caster, caster.get_projected_destination(), at)
	caster.active_attack = null
	var refusal := sm.try_queue_action(caster.squad, aim)
	assert_str(refusal).override_failure_message(
			"fixture: the cast was refused (%s), so no pass reads the vein" % refusal).is_equal("")
	game.refresh_action_queue(caster.squad)
	var plan := sm.resolved_plan_for(caster.squad)
	assert_object(plan).override_failure_message("fixture: the queue resolved no plan").is_not_null()
	for attack in plan.attacks:
		if attack.actor == caster:
			return attack.resolved.damage
	assert_bool(false).override_failure_message("fixture: the plan holds no cast by the caster").is_true()
	return -1


# THE wire: a vein in game.vein_field reaches the pass's board (game._board, SquadManager.board_source).
# Materia's empowerment is +1 aura in the delivered element, so the veined cast lands one harder.
func test_a_vein_empowers_a_cast_inside_the_pass() -> void:
	game.vein_field.set_kind(VEIN, Vein.Kind.FIRE)
	assert_int(game.vein_field.kind_at(VEIN)).override_failure_message(
			"fixture: the vein store refused the painted cell").is_equal(Vein.Kind.FIRE)
	var carving := _fireball()
	var veined := _alchemist(VEINED, carving)
	var bare := _alchemist(BARE, carving)
	_spawn(ENEMY, VEINED_FOE)
	_spawn(ENEMY, BARE_FOE)

	var bare_damage := _cast_damage(bare, carving, BARE_FOE)
	var veined_damage := _cast_damage(veined, carving, VEINED_FOE)

	assert_int(veined_damage).override_failure_message(
			"the pass did not see the vein beside the caster (%d vs %d unveined)" % [veined_damage, bare_damage]) \
			.is_equal(bare_damage + 1)


# The Play API's two board doors: the builder's board_source (its pass and judges) and the session's.
func test_the_play_api_boards_carry_the_veins() -> void:
	var b := BoardBuilder.build(self, "VeinWires")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(0, 0, WIDTH, HEIGHT))
	(b.vein_field as VeinField).set_kind(VEIN, Vein.Kind.AETHER)
	var from_source: BoardContext = (b.squad_manager as SquadManager).board_source.call()
	assert_int(from_source.vein_at(VEIN)).is_equal(Vein.Kind.AETHER)
	var sess = PlaySession.new(b)
	var from_session: BoardContext = sess._board()
	assert_int(from_session.vein_at(VEIN)).is_equal(Vein.Kind.AETHER)


# A board's copies of itself -- over a pass's planned tiles, or with other bodies -- are the same ground,
# so they carry the veins as they carry the weather.
func test_a_boards_copies_carry_the_veins() -> void:
	game.vein_field.set_kind(VEIN, Vein.Kind.ALKAHEST)
	var board: BoardContext = game._board()
	assert_int(board.vein_at(VEIN)).is_equal(Vein.Kind.ALKAHEST)
	var tiles := PlannedTiles.new(board.terrain_states, board.gas)
	assert_int(board.planned(tiles).vein_at(VEIN)).is_equal(Vein.Kind.ALKAHEST)
	var nobody: Array[Unit] = []
	assert_int(board.with_units(nobody).vein_at(VEIN)).is_equal(Vein.Kind.ALKAHEST)
