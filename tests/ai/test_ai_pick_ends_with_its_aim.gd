# #1598: the AI's pick ends with its aim, as a player's does at exit_current_mode. A rune counters
# with its live pick (the #30 quirk, RuneData.counter_attack) and nothing saves a pick, so a pick the
# AI left standing made the same rune answer with its last cast on a live board and with its default
# after a load.
#
# The fixture rune carries two carvings built here, Near (the default: inscribed first) and Far, and
# only Far reaches the target, so the AI's real turn must cast the one that is not the default.
#
# What it cannot see: a windowed play of the turn. Outside an aim the pick is read only by the counter
# (SquadManager.can_counter and the counter volley), which is what both cases ask.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const SCRATCH := "user://__ai_pick_ends_with_its_aim.tres"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)   # walkable=true in the shipped tileset
const WIDTH := 6
const ATTACK_ONLY: Array = [BaseAction.ActionType.ATTACK]
const CASTER_CELL := Vector2i(0, 0)
const TARGET_CELL := Vector2i(2, 0)   # two cells out: Far reaches it, Near does not

var _main: Node
var game: Node2D
var sm: ScenarioManager


func before_test() -> void:
	AIProfiles.use_fixtures({"": AIProfile.new()})   # #1230: this suite owns its AI profile
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	sm = game.scenario_manager
	game.mission_controller._close_mission_select()
	sm.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	AIProfiles.clear_fixtures()
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


# Makes its flame out of the air, so it fires anywhere (the chooser suite's fireball).
static func _carving(carving_name: String, reach: int) -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = carving_name
	t.power = 5
	t.recipe = "Break(F, A) + Push(F2)"
	t.targets = EquippableData.TargetMode.UNIT
	t.min_range = reach
	t.max_range = reach
	return t


# An AI rune-wielder that holds its ground, with the target two cells out on a strip of grass.
func _board() -> Array[Unit]:
	for x in range(WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	var caster: Unit = game.spawn_unit(H.make_unit_data({}, Team.Faction.ENEMY), CASTER_CELL)
	caster.unit_instance.aura = { Elemental.Element.FIRE: 4 }
	var affinity: Array[Elemental.Element] = [Elemental.Element.FIRE]
	caster.unit_instance.affinity = affinity
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	assert_bool(rune.inscribe(_carving("Near", 1))).override_failure_message("fixture: Near would not inscribe").is_true()
	assert_bool(rune.inscribe(_carving("Far", 2))).override_failure_message("fixture: Far would not inscribe").is_true()
	assert_bool(caster.add_item(rune)).override_failure_message("fixture: the rune would not go in the pack").is_true()
	assert_object(caster.equipped_weapon).override_failure_message("fixture: the rune is not in hand").is_same(rune)
	caster.squad.archetype = AIArchetype.Type.HOLD
	var target: Unit = game.spawn_unit(H.make_unit_data({ Stats.Stat.MHP: 50 }, Team.Faction.PLAYER), TARGET_CELL)
	assert_str(caster.get_counter_attack().display_name).override_failure_message(
			"fixture: the rune's default carving is not Near").is_equal("Near")
	var both: Array[Unit] = [caster, target]
	return both


static func _counter_name(units: Array[Unit]) -> String:
	for unit: Unit in units:
		if unit.get_faction() == Team.Faction.ENEMY:
			var attack := unit.get_counter_attack()
			return "<none>" if attack == null else attack.display_name
	return "<no caster>"


func _game_units() -> Array[Unit]:
	var units: Array[Unit] = []
	for child in game.units_root.get_children():
		if child is Unit:
			units.append(child)
	return units


# The joint pass alone, the door every AI attack is chosen through (#1445).
func test_the_ai_holds_no_pick_once_it_has_queued() -> void:
	var units := _board()
	var caster: Unit = units[0]
	var board: BoardContext = game._board()

	assert_bool(AITactics.queue_main_action(caster, board, game.squad_manager, ATTACK_ONLY)).override_failure_message(
			"fixture: the AI queued no attack").is_true()
	var aim := caster.squad.action_queue[0] as AttackAction
	assert_str(aim.fired_attack.display_name).override_failure_message(
			"fixture: the AI did not choose the carving that is not its default").is_equal("Far")

	assert_object(caster.active_attack).override_failure_message(
			"the AI's pick outlived its aim: %s" % [caster.active_attack]).is_null()
	assert_str(caster.get_counter_attack().display_name).override_failure_message(
			"the rune counters with the AI's last cast instead of its default").is_equal("Near")


# A real AI turn, then a full save loaded by both hosts: every board answers with the same counter.
func test_a_rune_counters_the_same_after_its_ai_turn_on_every_board() -> void:
	var units := _board()
	var caster: Unit = units[0]
	var target: Unit = units[1]
	game.ai_controller.set_ai_factions([Team.Faction.ENEMY] as Array[Team.Faction])
	game.turn_manager.set_active_faction(Team.Faction.ENEMY)
	await await_idle_frame()

	await game.start_faction_turn(Team.Faction.ENEMY)

	assert_int(target.get_current_hp()).override_failure_message(
			"fixture: the AI's turn never cast at the target").is_less(50)
	assert_object(caster.active_attack).override_failure_message(
			"the AI's pick outlived its turn: %s" % [caster.active_attack]).is_null()
	var live := _counter_name(_game_units())
	assert_str(live).override_failure_message("the rune counters with the AI's last cast after its turn").is_equal("Near")

	assert_int(ResourceSaver.save(sm.capture_scenario("ai_pick_ends_with_its_aim"), SCRATCH)).is_equal(OK)
	sm.load_scenario(SCRATCH)
	await await_idle_frame()
	assert_str(_counter_name(_game_units())).override_failure_message(
			"the game's load changed what the rune counters with").is_equal(live)

	var headless := BoardBuilder.build(self, "AiPickHeadless")
	auto_free(headless.root)
	await BoardBuilder.load_scenario(headless, SCRATCH)
	var session = PlaySession.new(headless)
	assert_str(_counter_name(session.live_units())).override_failure_message(
			"the headless load changed what the rune counters with").is_equal(live)
