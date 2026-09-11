# THE SOUND WIRE (#136), on a real Main.tscn board through the real OrderExecutor.
#
# WHAT A GREEN SUITE WOULD MISS WITHOUT THIS. A signal with no listener is legal GDScript and a
# listener nobody connects is a silent no-op; both ends can be perfectly written while nothing joins
# them (#103's thirteen-month gap). The director's own rules are testable in isolation and its
# CONNECTION is not -- only a real pass can see that, which is why the first case drives one.
#
# A HEADLESS SUITE CANNOT HEAR ANYTHING. What it can see is that a player was told to play, which is
# measurably observable: under the Dummy driver AudioStreamPlayer.playing reads back true after
# play() (measured 2026-09-11, the same probe that established the PROCESS_MODE_ALWAYS rule). Whether
# the cue SOUNDS right is the dev's play-check and is claimed nowhere here.
#
# The gate is the other half: volley_struck fires for heals and pure-utility attacks too, so an
# ungated director punches every time somebody is patched up.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const P := preload("res://tests/support/shape_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

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
		for y in range(3):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()


func _director() -> AudioDirector:
	var director: AudioDirector = game.audio_director
	assert_object(director).override_failure_message(
		"fixture: game built no audio_director").is_not_null()
	return director


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({Stats.Stat.LDR: 10}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


# A plain damaging swing at range, on the volley_struck suite's own fixture shape.
func _swinger(heals := false, no_damage := false) -> WeaponData:
	var swing := WeaponAttackData.new()
	swing.display_name = "Test Swing"
	swing.power = 4
	swing.heals = heals
	swing.deals_no_damage = no_damage
	swing.hits_allies = heals
	var offsets: Array[Vector2i] = [Vector2i(0, 0)]
	P.stamped(swing, 3, offsets)

	var template := WeaponData.new()
	# REQUIRED: make() has no subclass for the default type, so it push_errors and returns null --
	# and a push_error reds no case, leaving a bare-fisted unit that proves nothing.
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = swing
	return template


func _arm(hero: Unit, heals := false, no_damage := false) -> void:
	hero.equipped_weapon = WeaponInstance.make(_swinger(heals, no_damage))


func _fire_at(hero: Unit, cell: Vector2i) -> void:
	var action := AttackAction.declare(hero, hero.movement.cell, cell)
	assert_object(action.fired_attack).override_failure_message(
		"fixture: nothing was stamped to fire, so this is a bare-fisted swing").is_not_null()
	assert_bool(game.squad_manager.queue_action(hero.squad, action)).override_failure_message(
		"fixture: the attack never queued (%s), so nothing was executed"
		% ", ".join(action.validation_errors)).is_true()
	await game.order_executor.execute_orders(hero.squad.get_leader())


# --- the wire ------------------------------------------------------------------------------------

func test_a_landed_blow_reaches_the_director_and_plays() -> void:
	# THE CASE THIS FILE EXISTS FOR. Deleting AudioDirector's volley_struck.connect leaves every
	# other case here green -- the gate still classifies, the pool still plays when called by hand --
	# and the game goes silent.
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 2))
	_arm(hero)
	var victim := _spawn(Team.Faction.ENEMY, Vector2i(1, 2))
	victim.unit_instance.stats[Stats.Stat.MHP] = 200
	victim.set_current_hp(200)
	await await_idle_frame()

	assert_int(_director().voices_playing()).override_failure_message(
		"fixture: something was already playing before the blow").is_equal(0)

	await _fire_at(hero, Vector2i(1, 2))

	assert_int(_director().voices_playing()).override_failure_message(
		"a blow landed and nothing played -- the volley_struck wire is cut").is_greater(0)


func test_a_heal_lands_in_silence() -> void:
	# volley_struck publishes a heal exactly as it publishes a blow, so without the gate the game
	# plays a punch every time somebody is patched up.
	var medic := _spawn(Team.Faction.PLAYER, Vector2i(0, 2))
	_arm(medic, true)
	var patient := _spawn(Team.Faction.PLAYER, Vector2i(1, 2))
	patient.unit_instance.stats[Stats.Stat.MHP] = 200
	patient.set_current_hp(100)
	await await_idle_frame()

	await _fire_at(medic, Vector2i(1, 2))

	assert_int(_director().voices_playing()).override_failure_message(
		"a heal played the impact cue -- the damage gate is not being consulted").is_equal(0)


# --- the gate's own vocabulary -------------------------------------------------------------------
#
# Static, so these say what the rule IS without a board. They cannot see whether the rule is
# CONSULTED -- that is the heal case above, and the split is deliberate.

func test_a_null_attack_still_plays_because_bare_fists_damage() -> void:
	# fired_attack is null for the bare-fists fallback. A gate that read .heals off it without a
	# guard would take the frame down the first time an unarmed unit swung.
	var punch := AttackAction.new()
	punch.fired_attack = null
	assert_bool(AudioDirector.plays_impact(punch)).override_failure_message(
		"a bare-fisted punch was classified as silent").is_true()


func test_a_damaging_attack_plays_and_the_two_silent_kinds_do_not() -> void:
	var damaging := AttackAction.new()
	damaging.fired_attack = _swinger().main_attack
	assert_bool(AudioDirector.plays_impact(damaging)).is_true()

	var heal := AttackAction.new()
	heal.fired_attack = _swinger(true).main_attack
	assert_bool(AudioDirector.plays_impact(heal)).is_false()

	var utility := AttackAction.new()
	utility.fired_attack = _swinger(false, true).main_attack
	assert_bool(AudioDirector.plays_impact(utility)).is_false()


# --- the pool ------------------------------------------------------------------------------------

func test_more_cues_than_voices_steals_rather_than_growing_or_dropping() -> void:
	var director := _director()
	var voices := director.pool_size()
	for i in voices + 3:
		director.play(AudioDirector.IMPACT)
	assert_int(director.voices_playing()).override_failure_message(
		"the pool grew or went silent under overload -- it should cap at its own size").is_equal(voices)
