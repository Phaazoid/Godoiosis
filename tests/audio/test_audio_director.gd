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
var _levels_were: Dictionary[PlayerSettings.Setting, float] = {}


func before_test() -> void:
	for setting: PlayerSettings.Setting in AudioDirector.BUS_FOR_SETTING:
		_levels_were[setting] = PlayerSettings.level_of(setting)
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
	# A volume row is a process-wide static, so a case that moved one would otherwise ride into every
	# suite after this in the shard. The BUS is left where it is deliberately: the next director
	# re-applies from the restored rows on its own first frame.
	for setting: PlayerSettings.Setting in _levels_were:
		PlayerSettings.set_level(setting, _levels_were[setting])
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


# A stream the TEST owns, built rather than loaded: the content razor forbids asserting on authored
# content, and identity is only assertable against something this file made.
func _own_stream() -> AudioStream:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = 22050
	var d := PackedByteArray()
	d.resize(22050)
	wav.data = d
	return wav


# A plain damaging swing at range, on the volley_struck suite's own fixture shape.
func _swinger(heals := false, no_damage := false, sound: AudioStream = null) -> WeaponData:
	var swing := WeaponAttackData.new()
	swing.display_name = "Test Swing"
	swing.power = 4
	swing.heals = heals
	swing.deals_no_damage = no_damage
	swing.hits_allies = heals
	swing.sound = sound
	var offsets: Array[Vector2i] = [Vector2i(0, 0)]
	P.stamped(swing, 3, offsets)

	var template := WeaponData.new()
	# REQUIRED: make() has no subclass for the default type, so it push_errors and returns null --
	# and a push_error reds no case, leaving a bare-fisted unit that proves nothing.
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = swing
	return template


func _arm(hero: Unit, heals := false, no_damage := false, sound: AudioStream = null) -> void:
	hero.equipped_weapon = WeaponInstance.make(_swinger(heals, no_damage, sound))


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


# --- the attack's OWN voice (#136 slice 2) --------------------------------------------------------

func test_an_attack_that_authors_a_sound_plays_THAT_one_through_a_real_pass() -> void:
	# THE CASE THIS SLICE EXISTS FOR, and it has to assert IDENTITY: a per-weapon sound that
	# silently fell back to the generic impact is indistinguishable from working, because a sound
	# still plays. Making cue_for ignore fired.sound reds this and test_authored_beats_the_default
	# and nothing else.
	var mine := _own_stream()
	var hero := _spawn(Team.Faction.PLAYER, Vector2i(0, 2))
	_arm(hero, false, false, mine)
	var victim := _spawn(Team.Faction.ENEMY, Vector2i(1, 2))
	victim.unit_instance.stats[Stats.Stat.MHP] = 200
	victim.set_current_hp(200)
	await await_idle_frame()

	await _fire_at(hero, Vector2i(1, 2))

	var live := _director().streams_playing()
	assert_int(live.size()).override_failure_message(
		"a blow landed and nothing played").is_greater(0)
	assert_bool(live.has(mine)).override_failure_message(
		"the blow played the generic impact rather than the attack's own authored sound").is_true()


func test_a_heal_that_authors_a_sound_plays_it() -> void:
	# The deliberate narrowing: the damage gate governs the DEFAULT, not the authored voice. A
	# generic punch is wrong on a heal; an authored chime is not. Nothing authors one today, so
	# this moves no live behaviour -- it pins what the rule MEANS.
	var mine := _own_stream()
	var medic := _spawn(Team.Faction.PLAYER, Vector2i(0, 2))
	_arm(medic, true, false, mine)
	var patient := _spawn(Team.Faction.PLAYER, Vector2i(1, 2))
	patient.unit_instance.stats[Stats.Stat.MHP] = 200
	patient.set_current_hp(100)
	await await_idle_frame()

	await _fire_at(medic, Vector2i(1, 2))

	assert_bool(_director().streams_playing().has(mine)).override_failure_message(
		"an authored heal sound was swallowed by the generic damage gate").is_true()


func test_authored_beats_the_default_and_silence_is_still_silence() -> void:
	var mine := _own_stream()

	var voiced := AttackAction.new()
	voiced.fired_attack = _swinger(false, false, mine).main_attack
	assert_object(AudioDirector.cue_for(voiced)).is_same(mine)

	var plain := AttackAction.new()
	plain.fired_attack = _swinger().main_attack
	assert_object(AudioDirector.cue_for(plain)).is_same(AudioDirector.IMPACT)

	var heal := AttackAction.new()
	heal.fired_attack = _swinger(true).main_attack
	assert_object(AudioDirector.cue_for(heal)).override_failure_message(
		"an unvoiced heal should stay silent").is_null()


# --- the pool ------------------------------------------------------------------------------------

func test_more_cues_than_voices_steals_rather_than_growing_or_dropping() -> void:
	var director := _director()
	var voices := director.pool_size()
	for i in voices + 3:
		director.play(AudioDirector.IMPACT)
	assert_int(director.voices_playing()).override_failure_message(
		"the pool grew or went silent under overload -- it should cap at its own size").is_equal(voices)


# --- the volume rows ------------------------------------------------------------------------------
#
# Slice 1 shipped the bus reconcile with NO case over it at all, so these close a real gap rather
# than pad the count. Asserted as the RELATIONSHIP between a row and its bus, never as a number: the
# levels below are test inputs, and the DEFAULTS in PlayerSettings.DEFS are the dev's to retune.

func test_each_volume_row_moves_ITS_OWN_bus() -> void:
	var director := _director()
	var wanted: Dictionary[PlayerSettings.Setting, float] = {
		PlayerSettings.Setting.SFX_VOLUME: 0.5,
		PlayerSettings.Setting.MUSIC_VOLUME: 0.25,
	}
	for setting: PlayerSettings.Setting in wanted:
		PlayerSettings.set_level(setting, wanted[setting])
	await await_idle_frame()

	var wrong: Array[String] = []
	for setting: PlayerSettings.Setting in wanted:
		var bus := director.bus_of(setting)
		assert_int(bus).override_failure_message(
			"fixture: '%s' resolved no bus" % PlayerSettings.title_of(setting)).is_greater(-1)
		var want_db := linear_to_db(wanted[setting])
		if not is_equal_approx(AudioServer.get_bus_volume_db(bus), want_db):
			wrong.append("%s: bus %s is %.2f dB, wanted %.2f" % [
				PlayerSettings.title_of(setting), AudioServer.get_bus_name(bus),
				AudioServer.get_bus_volume_db(bus), want_db])
	assert_array(wrong).override_failure_message(
		"Rows whose bus did not follow them: %s" % ", ".join(wrong)).is_empty()

	# ...and they are genuinely different buses, or one row silently moves both.
	assert_int(director.bus_of(PlayerSettings.Setting.SFX_VOLUME)).override_failure_message(
		"the two rows resolved to ONE bus, so either slider moves the other's sound") \
		.is_not_equal(director.bus_of(PlayerSettings.Setting.MUSIC_VOLUME))


func test_all_the_way_down_mutes_rather_than_sending_a_bus_to_minus_infinity() -> void:
	var director := _director()
	for setting: PlayerSettings.Setting in AudioDirector.BUS_FOR_SETTING:
		PlayerSettings.set_level(setting, 0.0)
	await await_idle_frame()

	var leaky: Array[String] = []
	for setting: PlayerSettings.Setting in AudioDirector.BUS_FOR_SETTING:
		var bus := director.bus_of(setting)
		if not AudioServer.is_bus_mute(bus):
			leaky.append("%s is not muted" % PlayerSettings.title_of(setting))
		elif is_inf(AudioServer.get_bus_volume_db(bus)):
			leaky.append("%s went to -inf dB" % PlayerSettings.title_of(setting))
	assert_array(leaky).override_failure_message(
		"All the way down should MUTE and leave the number readable: %s" % ", ".join(leaky)) \
		.is_empty()
