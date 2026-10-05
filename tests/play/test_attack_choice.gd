# CHOOSING WHICH ATTACK TO FIRE, headlessly (#615) -- and the watch half #590 broke unnoticed.
#
# The fixture weapon is the SHIPPED Carbine's shape, and that is the point of it: a fire main, fire
# secondaries, and a watch that is an extra attack of its own. The suite that pinned headless
# overwatch before this built a weapon whose MAIN was the watch -- a shape no shipped weapon has --
# so it stayed green while play_session.overwatch refused every real Carbine.
#
# The stamp on the queued order is what each case asks, never the summary text: declare() stamps
# the live pick, so the stamp is the one place a pick that went astray cannot hide.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")
const BoardView := preload("res://play/board_view.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sess
var _hero: Unit
var _jab: WeaponAttackData
var _lob: WeaponAttackData
var _burst: WeaponAttackData
var _watch: WeaponAttackData


func before_test() -> void:
	var b := BoardBuilder.build(self, "AttackChoiceRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-2, -2, 12, 12))
	_hero = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))   # -> A
	BoardBuilder.spawn(b, _data("Near", ENEMY), Vector2i(1, 0))            # in Jab's reach alone
	BoardBuilder.spawn(b, _data("Far", ENEMY), Vector2i(3, 0))             # in Lob's reach alone
	_hero.add_item(_weapon())
	_sess = PlaySession.new(b)


func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)


func _attack(attack_name: String, power: int, max_range: int, min_range: int) -> WeaponAttackData:
	var a := WeaponAttackData.new()
	a.display_name = attack_name
	a.power = power
	P.point(a, max_range, min_range)
	return a


func _weapon() -> WeaponInstance:
	_jab = _attack("Jab", 4, 1, 1)
	_lob = _attack("Lob", 2, 3, 2)
	_burst = _attack("Burst", 6, 1, 1)
	_burst.requires_readiness = true   # the mace's charge gate, and a fresh mace holds none
	_watch = _attack("Watch", 3, 2, 1)
	_watch.can_overwatch = true        # watch-ONLY since #590: never in the fire view
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.KINETIC_MACE
	t.main_attack = _jab
	t.extra_attacks.assign([_lob, _burst, _watch])
	return WeaponInstance.make(t)


func _queued(type: BaseAction.ActionType) -> Array[BaseAction]:
	var out: Array[BaseAction] = []
	for action: BaseAction in _hero.squad.action_queue:
		if action.action_type == type:
			out.append(action)
	return out


static func _cells(res: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for aim: Dictionary in res.aims:
		out.append(aim.cell)
	return out


# ==============================================================================
#  attack: the name picks, the stamp proves it
# ==============================================================================

func test_naming_an_attack_fires_that_attack() -> void:
	var r: Dictionary = _sess.queue_attack("A", Vector2i(3, 0), "Lob")
	assert_bool(r.ok).override_failure_message(str(r.get("error", ""))).is_true()
	var orders := _queued(BaseAction.ActionType.ATTACK)
	assert_int(orders.size()).is_equal(1)
	if orders.size() != 1:
		return
	assert_object((orders[0] as AttackAction).fired_attack).is_same(_lob)
	# The readback a driver sees names it too, off the resolved stamp.
	assert_str(BoardView.render_preview(_sess)).contains("(Lob)")


func test_no_name_fires_the_default() -> void:
	assert_bool((_sess.queue_attack("A", Vector2i(1, 0)) as Dictionary).ok).is_true()
	var orders := _queued(BaseAction.ActionType.ATTACK)
	assert_int(orders.size()).is_equal(1)
	if orders.size() != 1:
		return
	assert_object((orders[0] as AttackAction).fired_attack).is_same(_jab)


func test_an_unknown_name_is_refused_and_says_what_exists() -> void:
	var r: Dictionary = _sess.queue_attack("A", Vector2i(1, 0), "Nope")
	assert_bool(r.ok).is_false()
	assert_str(str(r.error)).contains("Jab").contains("Lob")
	assert_int(_queued(BaseAction.ActionType.ATTACK).size()).is_equal(0)


func test_an_attack_that_cannot_fire_is_refused_in_the_menus_own_words() -> void:
	var reason := _hero.attack_block_reason(_burst)
	assert_str(reason).override_failure_message(
		"fixture: Burst can fire, so this case proves nothing").is_not_empty()
	var r: Dictionary = _sess.queue_attack("A", Vector2i(1, 0), "Burst")
	assert_bool(r.ok).is_false()
	assert_str(str(r.error)).contains(reason)
	assert_int(_queued(BaseAction.ActionType.ATTACK).size()).is_equal(0)


# NOTHING TO FIRE, NOTHING FIRED (#1215). A rune whose wielder cannot channel any carving has no
# default attack, the ring offers it no row, and attack_block_reason(null) answers "" -- so the
# unnamed pick used to sail through as a null stamp, which the resolver reads as a bare-fist punch.
func test_a_rune_with_nothing_channelable_fires_nothing() -> void:
	var carving := TransmutationData.new()
	carving.display_name = "Spark"
	carving.power = 3
	carving.sigils.assign([Elemental.Element.FIRE])
	carving.targets = EquippableData.TargetMode.UNIT
	var rune := RuneData.new()
	rune.size = RuneData.Size.MEDIUM
	rune.inscribe(carving)
	_hero.equipped_weapon = rune
	_hero.unit_instance.aura = {}   # no aura at all, so the carving cannot be channelled
	assert_bool(_hero.can_fire_default_attack()).override_failure_message(
		"fixture: the hero can still fire, so this case proves nothing").is_false()

	var r: Dictionary = _sess.queue_attack("A", Vector2i(1, 0))
	assert_bool(r.ok).override_failure_message("a dry rune fired a null pick headlessly").is_false()
	assert_int(_queued(BaseAction.ActionType.ATTACK).size()).is_equal(0)
	assert_bool((_sess.legal_targets("A") as Dictionary).ok).override_failure_message(
		"legal_targets listed aims for a unit with nothing to fire").is_false()


# #590's split, from the fire side: a watch-only attack is not something `attack` can fire.
func test_a_watch_cannot_be_fired_as_an_attack() -> void:
	assert_bool((_sess.queue_attack("A", Vector2i(1, 0), "Watch") as Dictionary).ok).is_false()
	assert_int(_queued(BaseAction.ActionType.ATTACK).size()).is_equal(0)


# THE PICK DIES WITH THE COMMAND, as exit_current_mode kills the menu's. Left standing it would be
# what the next unnamed aim fires, and what a rune counters with. The refusal is the half that
# matters: Lob is ARMED before it is refused for being unable to reach an adjacent cell.
func test_the_pick_never_outlives_the_command() -> void:
	assert_bool((_sess.queue_attack("A", Vector2i(3, 0), "Lob") as Dictionary).ok).is_true()
	assert_object(_hero.active_attack).is_null()
	_sess.cancel("A")
	assert_bool((_sess.queue_attack("A", Vector2i(1, 0), "Lob") as Dictionary).ok).is_false()
	assert_object(_hero.active_attack).is_null()
	_sess.legal_targets("A", "Lob")
	assert_object(_hero.active_attack).is_null()


# ==============================================================================
#  legal_targets answers for the attack it is asked about (test_affordances' law, named)
# ==============================================================================

func test_every_aim_offered_for_a_named_attack_is_one_it_accepts() -> void:
	var offered: Dictionary = _sess.legal_targets("A", "Lob")
	assert_bool(offered.ok).is_true()
	assert_str(str(offered.attack)).is_equal("Lob")
	assert_int(offered.aims.size()).override_failure_message(
		"nothing was offered, so this case proves nothing").is_greater(0)
	var refused: Array[String] = []
	for aim: Dictionary in offered.aims:
		var r: Dictionary = _sess.queue_attack("A", aim.cell, "Lob")
		if not r.ok:
			refused.append("%s: %s" % [str(aim.cell), str(r.error)])
		_sess.cancel("A")
	assert_array(refused).override_failure_message(
		"legal_targets offered aims queue_attack then refused:\n  %s" % "\n  ".join(refused)).is_empty()


func test_and_every_aim_it_withholds_is_one_it_refuses() -> void:
	var allowed := {}
	for cell: Vector2i in _cells(_sess.legal_targets("A", "Lob")):
		allowed[cell] = true
	var accepted: Array[String] = []
	for y in range(-2, 10):
		for x in range(-2, 10):
			var cell := Vector2i(x, y)
			if allowed.has(cell):
				continue
			if (_sess.queue_attack("A", cell, "Lob") as Dictionary).ok:
				accepted.append(str(cell))
				_sess.cancel("A")
	assert_array(accepted).override_failure_message(
		"queue_attack accepted Lob aims legal_targets never offered: %s" % ", ".join(accepted)).is_empty()


# Non-vacuity for the pair above: if BOTH sides ignored the name they would still agree, about the
# default. On this fixture the two attacks' aims share no cell, so the answers must differ.
# A watch attack's name is answered too (#46): where the watch may be set, by overwatch's own gate,
# each spot with the cells it watches and the hostiles standing in them now -- who it fires on when
# armed. It used to be refused as an unknown attack, the fire view never holding a watch (#590).
func test_legal_targets_answers_for_a_watch_attack() -> void:
	var offered: Dictionary = _sess.legal_targets("A", "Watch")
	assert_bool(offered.ok).override_failure_message("a watch attack was refused: %s" % str(offered)).is_true()
	assert_int(offered.aims.size()).override_failure_message(
		"nothing was offered, so this case proves nothing").is_greater(0)
	var near: Unit = null
	for unit: Unit in _sess.live_units():
		if unit.get_unit_name() == "Near":
			near = unit
	var refused: Array[String] = []
	var over_near := {}
	for aim: Dictionary in offered.aims:
		if (aim.footprint as Array).has(near.movement.cell):
			over_near = aim
		var r: Dictionary = _sess.overwatch("A", aim.cell, "Watch")
		if not r.ok:
			refused.append("%s: %s" % [str(aim.cell), str(r.error)])
		_sess.cancel("A")
	assert_array(refused).override_failure_message(
		"legal_targets offered watch spots overwatch then refused:\n  %s" % "\n  ".join(refused)).is_empty()
	assert_bool(over_near.is_empty()).override_failure_message(
		"no offered spot watches the cell an enemy stands on").is_false()
	assert_bool((over_near.standing as Array).has(_sess.handle_for(near))).override_failure_message(
		"the spot over an enemy did not name it: %s" % str(over_near)).is_true()


# A directional aim is a facing, and each is labelled by it (#46).
func test_a_directional_aim_is_named_by_its_facing() -> void:
	var b := BoardBuilder.build(self, "FacingRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-3, -3, 7, 7))
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	BoardBuilder.spawn(b, _data("East", ENEMY), Vector2i(2, 0))
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = P.line(_attack("Thrust", 3, 0, 0), 2)
	hero.add_item(WeaponInstance.make(t))
	var sess = PlaySession.new(b)

	var res: Dictionary = sess.legal_targets(sess.handle_for(hero))

	assert_int(res.aims.size()).override_failure_message("fixture: no aim reaches the enemy").is_greater(0)
	for aim: Dictionary in res.aims:
		assert_str(str(aim.get("facing", ""))).override_failure_message(
				"an aim at the enemy to the east was not labelled E: %s" % str(aim)).is_equal("E")
	var text: String = BoardView.render_legal_targets(sess, sess.handle_for(hero))
	assert_str(text).contains("facing E hits")
	# Every cell of a facing fires the same stamp, so the facing prints once with a count.
	assert_int(text.count("facing E")).override_failure_message("a facing printed once per cell:\n%s" % text) \
		.is_equal(1)


# An aim that lands on the map and hits nobody says so, rather than "hits " and a blank (#46).
func test_an_aim_at_open_ground_says_it_hits_only_the_ground() -> void:
	var b := BoardBuilder.build(self, "GroundAimRoot")
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-3, -3, 7, 7))
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	BoardBuilder.spawn(b, _data("Far", ENEMY), Vector2i(3, 3))
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	t.main_attack = _attack("Scorch", 3, 1, 1)
	t.main_attack.targets = EquippableData.TargetMode.MAP
	hero.add_item(WeaponInstance.make(t))
	var sess = PlaySession.new(b)

	var res: Dictionary = sess.legal_targets(sess.handle_for(hero))

	assert_int(res.aims.size()).override_failure_message("fixture: a map attack offered no aim").is_greater(0)
	assert_bool(bool(res.aims[0].ground_only)).is_true()
	assert_str(BoardView.render_legal_targets(sess, sess.handle_for(hero))).contains("only the ground")


func test_the_named_answer_is_not_the_defaults() -> void:
	var lob := _cells(_sess.legal_targets("A", "Lob"))
	var jab := _cells(_sess.legal_targets("A"))
	assert_bool(jab.has(Vector2i(1, 0)) and not jab.has(Vector2i(3, 0))).override_failure_message(
		"fixture: the default's aims are not what this case assumes: %s" % str(jab)).is_true()
	assert_bool(lob.has(Vector2i(3, 0)) and not lob.has(Vector2i(1, 0))).override_failure_message(
		"legal_targets answered for the wrong attack: %s" % str(lob)).is_true()
	assert_str(BoardView.render_legal_targets(_sess, "A", "Lob")).contains("with Lob")


# ==============================================================================
#  overwatch: the watch list, never the main
# ==============================================================================

# THE BUG THIS FILE WAS NEEDED FOR. The old overwatch asked whether the MAIN could watch, so a fire
# main beside a separate watch -- the shipped Carbine -- was always refused.
func test_overwatch_watches_with_the_weapons_watch_attack() -> void:
	var r: Dictionary = _sess.overwatch("A", Vector2i(1, 0))
	assert_bool(r.ok).override_failure_message(str(r.get("error", ""))).is_true()
	var watches := _queued(BaseAction.ActionType.OVERWATCH)
	assert_int(watches.size()).is_equal(1)
	if watches.size() != 1:
		return
	assert_object((watches[0] as OverwatchAction).fired_attack).is_same(_watch)


func test_overwatch_takes_a_name_and_refuses_one_it_cannot_watch_with() -> void:
	assert_bool((_sess.overwatch("A", Vector2i(1, 0), "Watch") as Dictionary).ok).is_true()
	_sess.cancel("A")
	var r: Dictionary = _sess.overwatch("A", Vector2i(1, 0), "Lob")   # a fire attack, not a watch
	assert_bool(r.ok).is_false()
	assert_str(str(r.error)).contains("Watch")
	assert_int(_queued(BaseAction.ActionType.OVERWATCH).size()).is_equal(0)


# ==============================================================================
#  The view: the names the verbs take are on the board a driver reads
# ==============================================================================

# The template's extra COUNT used to stand here, which advertised the watch as a second thing to fire.
func test_the_unit_line_names_every_other_attack() -> void:
	var text := BoardView.render_overview(_sess)
	assert_str(text).contains("; Lob pow2").contains("; watch: Watch pow3").not_contains("+3atk")
	assert_str(text).contains("Burst pow6").contains("(blocked: ")
