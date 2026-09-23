# PAYLOADS (#1058, slice D of #1054): an attack names another authored attack, which it DROPS where
# it hits and which then resolves in full with the thrower still the actor. The rulings under test
# are #1058's 31-46.
#
# Through the REAL resolve wherever the rule lives there -- SquadManager.resolve_plan for aims and
# counters, PlanResolver.fire_watch_on_arm for a watch shot -- because where a payload goes off, what
# list it joins and what it spends are all decided by the walk, not by drop_payloads alone.
#
# Every attack and board is BUILT here (the content razor). Units are tough (MHP 60) unless a case
# needs a fall, so a hit never changes who is standing where by accident.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const UNIT := EquippableData.TargetMode.UNIT
const MAP := EquippableData.TargetMode.MAP
const BOTH := EquippableData.TargetMode.BOTH
const ORIGIN := Vector2i(0, 0)
const TOUGH := {Stats.Stat.MHP: 60}

var _sm: SquadManager
var _plans: Array[ResolvedPlan] = []


func before_test() -> void:
	_sm = H.make_manager(self)
	_plans.clear()


# A volley is a self-referential array (a RefCounted cycle, #35), so every plan is broken apart.
func after_test() -> void:
	var empty: Array[AttackAction] = []
	for plan in _plans:
		for list: Array in [plan.attacks, plan.counters, plan.watch_shots]:
			for atk: AttackAction in list:
				atk.volley = empty
				atk.dropped_by = null
				atk.source_aim = null
	_plans.clear()


# ==============================================================================
#  Builders
# ==============================================================================

# A single-target attack at range 1: no shape, so it covers the aimed cell alone.
func _attack(named: String, targets := UNIT, max_range := 1) -> WeaponAttackData:
	var a := WeaponAttackData.new()
	a.display_name = named
	a.power = 1
	a.targets = targets
	P.point(a, max_range)
	return a


# A self-anchored one-cell stamp straight ahead: whatever way it faces is the one cell it covers,
# which is what makes a payload's FACING readable off its footprint.
func _pointer(targets := MAP) -> WeaponAttackData:
	var a := WeaponAttackData.new()
	a.display_name = "Pointer"
	a.power = 1
	a.targets = targets
	P.stamped(a, 0, [Vector2i(0, -1)] as Array[Vector2i])
	a.swing = false
	return a


func _thrower(carrier: WeaponAttackData, cell := ORIGIN) -> Unit:
	var unit := H.spawn_solo(self, _sm, PLAYER, cell, TOUGH)
	(unit.get_equipped_weapon() as WeaponInstance).template.main_attack = carrier
	return unit


func _foe(cell: Vector2i, overrides: Dictionary = TOUGH) -> Unit:
	return H.spawn_solo(self, _sm, ENEMY, cell, overrides)


func _board() -> BoardContext:
	return _sm.board_source.call()


func _resolve(thrower: Unit, aim: Vector2i) -> ResolvedPlan:
	thrower.squad._queue_action(AttackAction.declare(thrower, thrower.movement.cell, aim))
	var plan := _sm.resolve_plan(thrower.squad, _board(), [] as Array[ElementalReaction], [] as Array[TerrainReaction])
	_plans.append(plan)
	return plan


func _dropped(list: Array) -> Array[AttackAction]:
	var found: Array[AttackAction] = []
	for atk: AttackAction in list:
		if atk.dropped_by != null:
			found.append(atk)
	return found


func _origins(actions: Array[AttackAction]) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for atk in actions:
		cells.append(atk.origin_cell)
	return cells


# ==============================================================================
#  Where it goes off
# ==============================================================================

# Ruling 43: a unit payload is a STICKY BOMB -- it goes off where the hit leaves its victim.
func test_a_payload_goes_off_where_the_victim_lands() -> void:
	var carrier := _attack("Shove")
	carrier.knockback = 2
	carrier.payload = _attack("Bomb", MAP)
	var thrower := _thrower(carrier)
	var victim := _foe(Vector2i(0, -1))
	var dropped := _dropped(_resolve(thrower, Vector2i(0, -1)).attacks)
	assert_int(dropped.size()).is_equal(1)
	assert_that(dropped[0].origin_cell).override_failure_message(
			"the payload went off at %s -- where the victim was hit, not where the shove left them"
			% dropped[0].origin_cell).is_equal(Vector2i(0, -3))
	assert_object(dropped[0].target).is_same(victim)


func test_without_a_shove_it_goes_off_where_the_victim_stands() -> void:
	var carrier := _attack("Tap")
	carrier.payload = _attack("Bomb", MAP)
	var thrower := _thrower(carrier)
	_foe(Vector2i(0, -1))
	assert_array(_origins(_dropped(_resolve(thrower, Vector2i(0, -1)).attacks))).is_equal([Vector2i(0, -1)])


func test_a_unit_attack_that_misses_drops_nothing() -> void:
	var carrier := _attack("Tap")
	carrier.payload = _attack("Bomb", MAP)
	var thrower := _thrower(carrier)
	var plan := _resolve(thrower, Vector2i(0, -1))
	assert_array(_dropped(plan.attacks)).is_empty()


# Ruling 31: a tile attack drops on every tile it strikes, whether or not anyone is there.
func test_a_tile_attack_on_empty_ground_drops_one() -> void:
	var carrier := _attack("Lob", MAP)
	carrier.payload = _attack("Bomb", MAP)
	var thrower := _thrower(carrier)
	assert_array(_origins(_dropped(_resolve(thrower, Vector2i(0, -1)).attacks))).is_equal([Vector2i(0, -1)])


func test_a_shaped_tile_attack_drops_one_per_struck_tile() -> void:
	var carrier := WeaponAttackData.new()
	carrier.display_name = "Line"
	carrier.targets = MAP
	P.line(carrier, 3)
	carrier.payload = _attack("Bomb", MAP)
	var thrower := _thrower(carrier)
	assert_array(_origins(_dropped(_resolve(thrower, Vector2i(0, -1)).attacks))) \
		.contains_exactly_in_any_order([Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -3)])


# ...and a unit/tile attack is a tile attack for this: a victim's tile never gets a second one.
func test_a_unit_and_tile_attack_gives_a_victims_tile_one_payload() -> void:
	var carrier := WeaponAttackData.new()
	carrier.display_name = "Line"
	carrier.targets = BOTH
	P.line(carrier, 2)
	carrier.payload = _attack("Bomb", MAP)
	var thrower := _thrower(carrier)
	_foe(Vector2i(0, -1))
	assert_array(_origins(_dropped(_resolve(thrower, Vector2i(0, -1)).attacks))) \
		.contains_exactly_in_any_order([Vector2i(0, -1), Vector2i(0, -2)])


# Ruling 45: a unit the CURRENT caught was not hit by the attack itself, and drops nothing.
class _WaterBoard extends BoardContext:
	var water: Dictionary = {}
	func _init(g: TileMapLayer, u: Array[Unit], m: SquadManager, wet: Array[Vector2i]) -> void:
		super(g, u, m)
		for cell in wet:
			water[cell] = true
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return Terrain.Kind.WATER if water.has(cell) else Terrain.Kind.GRASS


func test_a_unit_only_the_current_caught_drops_nothing() -> void:
	var carrier := _attack("Zap")
	carrier.elemental_damage_type = Elemental.Element.SHOCK
	carrier.payload = _attack("Bomb", MAP)
	var thrower := _thrower(carrier)
	var victim := _foe(Vector2i(0, -1))
	var bystander := _foe(Vector2i(1, -1))
	thrower.squad._queue_action(AttackAction.declare(thrower, ORIGIN, Vector2i(0, -1)))
	var units: Array[Unit] = [thrower, victim, bystander]
	var board := _WaterBoard.new(_sm.grid, units, _sm, [Vector2i(0, -1), Vector2i(1, -1)] as Array[Vector2i])
	var plan := _sm.resolve_plan(thrower.squad, board, [] as Array[ElementalReaction], [] as Array[TerrainReaction])
	_plans.append(plan)
	var hit: Array[Unit] = []
	for atk in plan.attacks:
		if atk.dropped_by == null:
			hit.append(atk.target)
	assert_array(hit).override_failure_message("fixture: the current did not catch the bystander") \
		.contains_exactly_in_any_order([victim, bystander])
	assert_array(_origins(_dropped(plan.attacks))).is_equal([Vector2i(0, -1)])


# ==============================================================================
#  Which way it faces (rulings 35-38)
# ==============================================================================

func _footprint_of(plan: ResolvedPlan) -> Array[Vector2i]:
	var dropped := _dropped(plan.attacks)
	assert_int(dropped.size()).override_failure_message("fixture: expected exactly one payload") \
		.is_equal(1)
	return dropped[0].footprint if not dropped.is_empty() else ([] as Array[Vector2i])


# A carrier with no shape turns its payload ONWARD while the tick is on...
func test_a_shapeless_carrier_turns_its_payload_onward() -> void:
	var carrier := _attack("Tap")
	carrier.payload = _pointer()
	var thrower := _thrower(carrier)
	_foe(Vector2i(1, 0))
	assert_array(_footprint_of(_resolve(thrower, Vector2i(1, 0)))).is_equal([Vector2i(2, 0)])


# ...and to board north with it off.
func test_a_shapeless_carrier_with_the_tick_off_faces_it_north() -> void:
	var carrier := _attack("Tap")
	carrier.payload = _pointer()
	carrier.payload_turns = false
	var thrower := _thrower(carrier)
	_foe(Vector2i(1, 0))
	assert_array(_footprint_of(_resolve(thrower, Vector2i(1, 0)))).is_equal([Vector2i(1, -1)])


# Ruling 38: a PLACED payload turns too -- its stamp lands on the drop cell turned onward.
func test_a_placed_payload_turns_too() -> void:
	var carrier := _attack("Tap")
	var placed := WeaponAttackData.new()
	placed.display_name = "Placed"
	placed.targets = MAP
	P.stamped(placed, 1, [Vector2i(0, -1)] as Array[Vector2i])
	placed.swing = false
	carrier.payload = placed
	var thrower := _thrower(carrier)
	_foe(Vector2i(1, 0))
	assert_array(_footprint_of(_resolve(thrower, Vector2i(1, 0)))).is_equal([Vector2i(2, 0)])


# A SHAPED carrier always turns its payloads onward -- the tick is not asked of it. A self-anchored
# swing's onward is its facing.
func test_a_self_anchored_swing_turns_its_payloads_along_its_facing_whatever_the_tick() -> void:
	var carrier := WeaponAttackData.new()
	carrier.display_name = "Thrust"
	P.line(carrier, 1)
	carrier.payload = _pointer()
	carrier.payload_turns = false
	var thrower := _thrower(carrier)
	_foe(Vector2i(1, 0))
	assert_array(_footprint_of(_resolve(thrower, Vector2i(1, 0)))).is_equal([Vector2i(2, 0)])


# ...and a placed one's is OUTWARD from where it landed.
func test_a_placed_swing_turns_its_payloads_outward_from_the_impact() -> void:
	var carrier := WeaponAttackData.new()
	carrier.display_name = "Burst"
	P.stamped(carrier, 2, [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0)] as Array[Vector2i])
	carrier.payload = _pointer()
	var thrower := _thrower(carrier)
	_foe(Vector2i(1, -2))
	assert_array(_footprint_of(_resolve(thrower, Vector2i(0, -2)))).is_equal([Vector2i(2, -2)])


# Ruling 7 through a payload: two paths onto one unit are two hits and drop two, and each payload
# faces the way ITS OWN path arrived -- per hit, never per tile.
func test_two_paths_onto_one_unit_drop_two_each_facing_its_own_path() -> void:
	var left: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(-1, -2), Vector2i(0, -2)]
	var right: Array[Vector2i] = [Vector2i(1, -1), Vector2i(1, -2), Vector2i(0, -2)]
	var carrier := WeaponAttackData.new()
	carrier.display_name = "Pincer"
	carrier.max_range = 0
	carrier.attack_shape = P.pathed([left, right] as Array[Array])
	carrier.swing = true
	carrier.payload = _pointer()
	var thrower := _thrower(carrier)
	_foe(Vector2i(0, -2))
	var dropped := _dropped(_resolve(thrower, Vector2i(0, -1)).attacks)
	assert_int(dropped.size()).is_equal(2)
	var feet: Array[Vector2i] = []
	for atk in dropped:
		assert_int(atk.footprint.size()).is_equal(1)
		feet.append(atk.footprint[0])
	assert_array(feet).override_failure_message(
			"the two payloads faced %s -- each should face the way its own path arrived" % [feet]) \
		.contains_exactly_in_any_order([Vector2i(1, -2), Vector2i(-1, -2)])


# ==============================================================================
#  Chains (ruling 46: to any depth, never a loop)
# ==============================================================================

func test_a_chain_resolves_level_by_level() -> void:
	var c := _attack("C", MAP)
	var b := _attack("B", MAP)
	b.payload = c
	var carrier := _attack("A", MAP)
	carrier.payload = b
	var thrower := _thrower(carrier)
	var dropped := _dropped(_resolve(thrower, Vector2i(0, -1)).attacks)
	assert_int(dropped.size()).is_equal(2)
	assert_object(dropped[0].fired_attack).is_same(b)
	assert_int(dropped[0].payload_depth).is_equal(1)
	assert_object(dropped[1].fired_attack).is_same(c)
	assert_int(dropped[1].payload_depth).is_equal(2)
	assert_object(dropped[1].dropped_by).is_same(dropped[0])


func test_the_chain_walks_to_its_end() -> void:
	var c := _attack("C")
	var b := _attack("B")
	b.payload = c
	var a := _attack("A")
	a.payload = b
	assert_array(a.payload_chain()).is_equal([b, c])
	assert_array(c.payload_chain()).is_empty()


# A loop cannot exist on disk, but one can be built in memory; the walk ends it rather than hanging.
func test_an_in_memory_loop_ends_at_the_first_repeat() -> void:
	var b := _attack("B")
	var a := _attack("A")
	a.payload = b
	b.payload = a
	assert_array(a.payload_chain()).is_equal([b])


# The picker's exclusion: an attack itself, and anything whose chain leads back to it.
func test_an_attack_may_not_drop_itself_or_anything_that_leads_back() -> void:
	var b := _attack("B")
	var a := _attack("A")
	a.payload = b
	var other := _attack("Other")
	assert_bool(a.payload_would_loop(a)).is_true()
	assert_bool(b.payload_would_loop(a)).override_failure_message(
			"B may drop A, whose chain leads straight back to B").is_true()
	assert_bool(a.payload_would_loop(other)).is_false()


func test_the_fanout_multiplies_down_the_chain() -> void:
	var c := _attack("C", MAP)
	var b := WeaponAttackData.new()
	b.targets = MAP
	P.line(b, 3)
	b.payload = c
	var a := WeaponAttackData.new()
	a.targets = MAP
	P.line(a, 2)
	a.payload = b
	assert_array(a.payload_fanout()).is_equal([2, 6])


# ==============================================================================
#  Counters
# ==============================================================================

# Ruling 32: a payload hit is counter-bait like any hit -- here the ONLY hit on the second squad,
# so its reaction is the payload's doing -- and the C4 ledger still answers the first squad once.
func test_a_payload_hit_draws_the_counter_a_hit_would() -> void:
	var blast := WeaponAttackData.new()
	blast.display_name = "Blast"
	var square: Array[Vector2i] = []
	for x in range(-1, 2):
		for y in range(-1, 2):
			square.append(Vector2i(x, y))
	P.stamped(blast, 1, square)
	blast.swing = false
	var carrier := _attack("Tap")
	carrier.payload = blast
	var thrower := _thrower(carrier)
	var hit_first := _foe(Vector2i(0, -1))
	var hit_by_payload := _foe(Vector2i(1, 0))
	var plan := _resolve(thrower, Vector2i(0, -1))
	var reactors: Array[Unit] = []
	for ctr in plan.counters:
		if ctr.dropped_by == null and not ctr.is_secondary_hit:
			reactors.append(ctr.actor)
	assert_array(reactors).contains_exactly_in_any_order([hit_first, hit_by_payload])


# A counter's payload joins plan.counters right behind its counter, so it draws no counter of its own.
func test_a_counters_payload_sits_right_behind_it_among_the_counters() -> void:
	var tap := _attack("Tap")
	var thrower := _thrower(tap)
	var foe := _foe(Vector2i(0, -1))
	var counter := _attack("Riposte")
	counter.payload = _attack("Bomb", MAP)
	(foe.get_equipped_weapon() as WeaponInstance).template.main_attack = counter
	var plan := _resolve(thrower, Vector2i(0, -1))
	assert_array(_dropped(plan.attacks)).is_empty()
	assert_int(plan.counters.size()).is_equal(2)
	assert_object(plan.counters[1].dropped_by).is_same(plan.counters[0])


# A counter's shove is never PUBLISHED, so a counter's payload finds its victim only because a
# payload gathers against the pass's threaded positions -- the sticky bomb, one list over.
func test_a_counters_payload_sticks_to_the_unit_its_counter_shoved() -> void:
	var tap := _attack("Tap")
	var thrower := _thrower(tap)
	var foe := _foe(Vector2i(0, -1))
	var counter := _attack("Riposte")
	counter.knockback = 2
	counter.payload = _attack("Bomb", MAP)
	(foe.get_equipped_weapon() as WeaponInstance).template.main_attack = counter
	var plan := _resolve(thrower, Vector2i(0, -1))
	assert_int(plan.counters.size()).is_equal(2)
	var bomb := plan.counters[1]
	assert_that(bomb.origin_cell).override_failure_message(
			"fixture: the riposte did not throw the thrower to (0, 2)").is_equal(Vector2i(0, 2))
	assert_object(bomb.target).override_failure_message(
			"the payload went off where the thrower landed and found nobody there").is_same(thrower)


# A payload plays right behind the hit that dropped it, and the list IS the playback order: a
# payload appended after every aim would resolve in one place and play in another (Law #2).
func test_a_payload_sits_in_the_attack_list_right_behind_its_parent() -> void:
	var carrier := _attack("Lob", MAP)
	carrier.payload = _attack("Bomb", MAP)
	var first := _thrower(carrier)
	var second := H.spawn_unit(self, PLAYER, Vector2i(2, 0), TOUGH)
	_sm.join_squad(second, first.squad)
	(second.get_equipped_weapon() as WeaponInstance).template.main_attack = _attack("Tap")
	_foe(Vector2i(2, -1))
	first.squad._queue_action(AttackAction.declare(first, ORIGIN, Vector2i(0, -1)))
	second.squad._queue_action(AttackAction.declare(second, Vector2i(2, 0), Vector2i(2, -1)))
	var plan := _sm.resolve_plan(first.squad, _board(), [] as Array[ElementalReaction], [] as Array[TerrainReaction])
	_plans.append(plan)
	var order: Array[String] = []
	for atk in plan.attacks:
		order.append(atk.fired_attack.display_name)
	assert_array(order).is_equal(["Lob", "Bomb", "Tap"])


# ==============================================================================
#  A watch shot's payload
# ==============================================================================

func test_a_watch_shots_payload_plays_right_behind_the_shot() -> void:
	var shot := _attack("Shot")
	shot.payload = _attack("Bomb", MAP)
	var watcher := _thrower(shot)
	var entrant := _foe(Vector2i(0, -2))
	var plan := ResolvedPlan.new()
	_plans.append(plan)
	var lane: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, -2)]
	var watch := Watch.make(watcher, ORIGIN, Vector2i(0, -1), lane, shot)
	plan.watches.append(watch)
	var no_reactions: Array[ElementalReaction] = []
	var no_terrain: Array[TerrainReaction] = []
	PlanResolver.fire_watch_on_arm(watch, plan, plan.hypo, no_reactions, _board(), no_terrain, null)
	assert_int(plan.watch_shots.size()).is_equal(2)
	var bomb := plan.watch_shots[1]
	assert_object(bomb.dropped_by).is_same(plan.watch_shots[0])
	assert_object(bomb.triggered_by).is_same(entrant)
	assert_int(bomb.triggered_at_step).is_equal(plan.watch_shots[0].triggered_at_step)
	assert_bool(plan.attacks.is_empty()).override_failure_message(
			"a watch shot's payload must never be counter-bait").is_true()


# ==============================================================================
#  Costs, liveness and who it can hit
# ==============================================================================

# A thrower the pass fells after the throw still has the payload go off: it is already in flight.
func test_a_thrower_the_pass_fells_still_has_the_payload_go_off() -> void:
	var carrier := WeaponAttackData.new()
	carrier.display_name = "Self Blast"
	carrier.targets = MAP
	carrier.hits_self = true
	carrier.power = 200
	var square: Array[Vector2i] = []
	for x in range(-1, 2):
		for y in range(-1, 2):
			square.append(Vector2i(x, y))
	P.stamped(carrier, 1, square)
	carrier.swing = false
	carrier.payload = _attack("Bomb", MAP)
	var thrower := H.spawn_solo(self, _sm, PLAYER, ORIGIN)
	(thrower.get_equipped_weapon() as WeaponInstance).template.main_attack = carrier
	var plan := _resolve(thrower, Vector2i(0, -1))
	assert_bool(PlanResolver.actor_is_live(thrower, plan.hypo)).override_failure_message(
			"fixture: the blast did not fell its own thrower").is_false()
	var dropped := _dropped(plan.attacks)
	assert_int(dropped.size()).is_equal(9)
	for atk in dropped:
		assert_bool(atk.resolved.skipped).override_failure_message(
				"a payload in flight was stopped by its thrower falling").is_false()


func test_the_thrower_is_hit_by_their_own_payload_only_when_it_hits_self() -> void:
	var blast := WeaponAttackData.new()
	blast.display_name = "Blast"
	var square: Array[Vector2i] = []
	for x in range(-1, 2):
		for y in range(-1, 2):
			square.append(Vector2i(x, y))
	P.stamped(blast, 1, square)
	blast.swing = false
	var carrier := _attack("Tap")
	carrier.payload = blast
	var thrower := _thrower(carrier)
	_foe(Vector2i(0, -1))
	var victims: Array[Unit] = []
	for atk in _dropped(_resolve(thrower, Vector2i(0, -1)).attacks):
		victims.append(atk.target)
	assert_array(victims).not_contains([thrower])

	blast.hits_self = true
	thrower.squad.action_queue.clear()
	victims.clear()
	for atk in _dropped(_resolve(thrower, Vector2i(0, -1)).attacks):
		victims.append(atk.target)
	assert_array(victims).contains([thrower])


# The resolver never stamps a charge spend for a payload, even when the payload IS the tank's form.
func test_a_payload_never_spends_the_tank() -> void:
	var charged := _attack("Pressurised")
	var spray := _attack("Spray")
	spray.empowered_form = charged
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHEMICAL_SPITTER
	template.main_attack = spray
	var carrier := _attack("Lob", MAP)
	carrier.payload = charged
	var thrower := H.spawn_solo(self, _sm, PLAYER, ORIGIN, TOUGH)
	var spitter := WeaponInstance.make(template) as ChemicalSpitterWeaponInstance
	spitter.charges = 2
	thrower.equipped_weapon = spitter
	# Somebody to hit: an empty tile resolves no damage at all, so the spend would never be asked.
	_foe(Vector2i(0, -1))
	# Fired directly: the carrier is stamped by hand, since the spitter's own main is the spray.
	var aim := AttackAction.create(thrower, ORIGIN, null, Vector2i(0, -1))
	aim.fired_attack = carrier
	thrower.squad._queue_action(aim)
	var plan := _sm.resolve_plan(thrower.squad, _board(), [] as Array[ElementalReaction], [] as Array[TerrainReaction])
	_plans.append(plan)
	var dropped := _dropped(plan.attacks)
	assert_int(dropped.size()).is_equal(1)
	assert_bool(dropped[0].resolved.charge_spent).is_false()


# Execution skips what FIRING costs (#1058): the lunge, and the readiness spend. Executed directly --
# the play path never calls execute(), so its twin has its own case in tests/play. The same action
# fired rather than dropped is the control that says the fixture could have lunged and spent at all.
func test_a_payload_neither_lunges_nor_spends_readiness_at_execute() -> void:
	var spring := _attack("Spring", MAP)
	spring.consumes_readiness = true
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.SPRINGSPEAR
	template.main_attack = _attack("Stab")
	var thrower := H.spawn_solo(self, _sm, PLAYER, ORIGIN, TOUGH)
	var spear := WeaponInstance.make(template) as SpringspearWeaponInstance
	thrower.equipped_weapon = spear
	var parent := AttackAction.create(thrower, ORIGIN, null, Vector2i(0, -1))
	var bomb := AttackAction.create(thrower, Vector2i(0, -2), null, Vector2i(0, -2))
	bomb.fired_attack = spring
	bomb.dropped_by = parent
	bomb.resolved = ResolvedOutcome.new()

	await bomb.execute()
	assert_object(thrower.visuals.visual_tween).override_failure_message(
			"the thrower lunged at a payload going off two tiles away").is_null()
	assert_bool(spear.ready).override_failure_message("a payload spent the spear's readiness").is_true()

	bomb.dropped_by = null
	await bomb.execute()
	assert_object(thrower.visuals.visual_tween).override_failure_message(
			"fixture: a fired attack did not lunge either, so the case above proves nothing").is_not_null()
	assert_bool(spear.ready).override_failure_message(
			"fixture: a fired Spring did not spend the spear either").is_false()


# ==============================================================================
#  The queue panel
# ==============================================================================

func _chain_plan() -> Dictionary:
	var c := _attack("C", MAP)
	var b := _attack("B", MAP)
	b.payload = c
	var carrier := WeaponAttackData.new()
	carrier.display_name = "Line"
	P.line(carrier, 2)
	carrier.payload = b
	var thrower := _thrower(carrier)
	_foe(Vector2i(0, -1))
	_foe(Vector2i(0, -2))
	return {"thrower": thrower, "plan": _resolve(thrower, Vector2i(0, -1))}


# Each payload row hangs one step per drop under the hit that dropped it.
func test_the_queue_indents_each_payload_by_its_depth() -> void:
	var made := _chain_plan()
	var plan: ResolvedPlan = made["plan"]
	var thrower: Unit = made["thrower"]
	var checked := 0
	for entry in ActionQueueDisplayEntry.build_for(thrower.squad, plan):
		var atk := entry.action as AttackAction
		if atk == null or atk is CounterAttackAction:
			continue
		assert_int(entry.indent_level).override_failure_message(
				"%s at depth %d drew at indent %d" % [atk.fired_attack.display_name, atk.payload_depth, entry.indent_level]) \
			.is_equal(atk.payload_depth)
		checked += 1
	assert_int(checked).override_failure_message(
			"fixture: expected two hits, two level-1 and two level-2 payloads, drew %d rows" % checked).is_equal(6)


# A payload keeps its thrower as the actor and sits right behind its parent, so a volley header
# grouping rows by ACTOR swallowed the payload hits and counted them as the parent's.
func test_a_volley_header_counts_only_its_own_hits() -> void:
	var made := _chain_plan()
	var panel: SquadActionQueueControl = auto_free(SquadActionQueueControl.new())
	panel._last_entries = ActionQueueDisplayEntry.build_for((made["thrower"] as Unit).squad, made["plan"])
	var first := -1
	for i in panel._last_entries.size():
		var atk := panel._last_entries[i].action as AttackAction
		if atk != null and atk.dropped_by == null:
			first = i
			break
	assert_int(panel._collect_volley_group(first).size()).is_equal(2)


# ==============================================================================
#  How hard it hits (ruling 42: as if the thrower fired it)
# ==============================================================================

func test_a_carving_payload_scales_off_the_throwers_aura() -> void:
	var carving := TransmutationData.new()
	carving.display_name = "Spark"
	carving.power = 2
	carving.sigils.assign([Elemental.Element.FIRE])
	carving.targets = MAP
	P.point(carving, 1)
	var carrier := _attack("Lob", MAP)
	carrier.payload = carving
	var thrower := _thrower(carrier)
	thrower.unit_instance.aura = {Elemental.Element.FIRE: 4}
	_foe(Vector2i(0, -1))   # a hit on nobody resolves no damage at all
	var dropped := _dropped(_resolve(thrower, Vector2i(0, -1)).attacks)
	var none: Array[Elemental.Element] = []
	assert_int(dropped[0].resolved.base_damage).is_equal(carving.base_damage(thrower, none))


# A weapon attack thrown with no weapon in hand is still a real hit: its own blend over the
# thrower's stats, and its own element -- the bare-fists reading would strip both.
func test_a_weapon_payload_thrown_with_no_weapon_keeps_its_blend_and_its_element() -> void:
	var fire := _attack("Firebomb")
	fire.power = 4
	fire.scaling_blend = {Stats.Stat.DEX: 100}
	fire.elemental_damage_type = Elemental.Element.FIRE
	var carrier := _attack("Tap")
	carrier.payload = fire
	var thrower := H.spawn_solo(self, _sm, PLAYER, ORIGIN, {Stats.Stat.MHP: 60, Stats.Stat.DEX: 11}, false)
	assert_int(4 + thrower.get_effective_stat(Stats.Stat.DEX)).override_failure_message(
			"fixture: the blend and the bare-STR fallback would give the same number") \
		.is_not_equal(thrower.get_effective_stat(Stats.Stat.STR))
	var foe := _foe(Vector2i(0, -1))
	var aim := AttackAction.create(thrower, ORIGIN, null, Vector2i(0, -1))
	aim.fired_attack = carrier
	thrower.squad._queue_action(aim)
	var plan := _sm.resolve_plan(thrower.squad, _board(), [] as Array[ElementalReaction], [] as Array[TerrainReaction])
	_plans.append(plan)
	var dropped := _dropped(plan.attacks)
	assert_int(dropped.size()).override_failure_message("fixture: the carrier missed %s" % foe).is_equal(1)
	assert_int(dropped[0].resolved.base_damage).is_equal(4 + thrower.get_effective_stat(Stats.Stat.DEX))
	assert_array(dropped[0].resolved.elements).contains([Elemental.Element.FIRE])
