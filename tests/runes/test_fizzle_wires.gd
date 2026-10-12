# The FIZZLE's wires (Deep Alchemy Phase 2, dev ruling 2026-10-11: a verb whose argument is not
# present fizzles, and the fizzle is visible before the click). What is present is
# CellSubstances' (tests/items/test_cell_substances.gd); what these cases pin is that every caller asks
# it, from the right cell, through the real paths: the queue gate, a stored aim going red after a
# re-plan, the resolver for an aim, a counter and a watch shot. The AI's half is
# tests/ai/test_main_action_chooser.gd's, the menu row's tests/ui/test_menu_catalogue_rows.gd's.
#
# The carving is Pressure Spray's shape, `Focus(W2) + Push(W2)`: it needs water beside the caster. The
# board is the fixture grid with one SPRING of water stubbed in (test_rune_firing.gd's idiom), so a
# caster at DRY has none and one at NEAR has the spring; a WET caster brings its own.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const WATER := Elemental.Element.WATER

const SPRING := Vector2i(8, 8)
const NEAR := Vector2i(8, 7)          # beside the spring
const NEAR_FOE := Vector2i(9, 7)
const DRY := Vector2i(6, 7)           # past Materia.REACH of it
const DRY_FOE := Vector2i(7, 7)

var _sm: SquadManager


class _SpringBoard extends BoardContext:
	var kinds: Dictionary
	func _init(g: TileMapLayer, u: Array[Unit], m: SquadManager, k: Dictionary) -> void:
		super(g, u, m)
		kinds = k
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return kinds.get(cell, Terrain.Kind.NONE)


func before_test() -> void:
	_sm = H.make_manager(self)
	var grid: TileMapLayer = (_sm.board_source.call() as BoardContext).grid
	_sm.board_source = func() -> BoardContext:
		return _SpringBoard.new(grid, _sm._all_units(), _sm, { SPRING: Terrain.Kind.WATER })


func _board() -> BoardContext:
	return _sm.board_source.call()


func _tied(watch := false) -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = "Spray"
	t.power = 5
	t.recipe = "Focus(W2) + Push(W2)"
	t.can_overwatch = watch
	return t


func _alchemist(faction: Team.Faction, cell: Vector2i, carving: TransmutationData) -> Unit:
	var carvings: Array[TransmutationData] = [carving]
	return _alchemist_with(faction, cell, carvings)


func _alchemist_with(faction: Team.Faction, cell: Vector2i, carvings: Array[TransmutationData]) -> Unit:
	var u := H.spawn_solo(self, _sm, faction, cell, { Stats.Stat.MHP: 60 }, false)
	u.unit_instance.aura = { WATER: 4, Elemental.Element.AIR: 1 }
	var affinity: Array[Elemental.Element] = [WATER, Elemental.Element.AIR]
	u.unit_instance.affinity = affinity
	var rune := RuneData.new()
	rune.size = RuneData.Size.MEDIUM
	for carving in carvings:
		assert_bool(rune.inscribe(carving)).override_failure_message("fixture carving failed to inscribe").is_true()
	u.equipped_weapon = rune
	for carving in carvings:
		assert_bool(u.is_attack_fireable(carving)).override_failure_message(
				"fixture: the carving must be channelable, or the fizzle is not what is measured").is_true()
	return u


func _watch(watcher: Unit, carving: TransmutationData, aim: Vector2i) -> OverwatchAction:
	var order := OverwatchAction.new()
	order.init(watcher, aim, carving)
	return order


func _foe(cell: Vector2i) -> Unit:
	return H.spawn_solo(self, _sm, ENEMY, cell, { Stats.Stat.MHP: 60 })


# An aim from where the caster will stand, the player's click: declare() stamps the carving.
func _aim(caster: Unit, carving: TransmutationData, cell: Vector2i) -> AttackAction:
	caster.active_attack = carving
	var aim := AttackAction.declare(caster, caster.get_projected_destination(), cell)
	caster.active_attack = null
	return aim


func _move(unit: Unit, to: Vector2i) -> MoveAction:
	var move := MoveAction.new()
	var path: Array[Vector2i] = [unit.movement.cell, to]
	move.init(unit, path, null)
	return move


# Any terrain the water lands on takes a mark -- the fixture's own reaction, so a deposit is visible.
func _water_marks_the_ground() -> Array[TerrainReaction]:
	var tr := TerrainReaction.new()
	tr.incoming_element = WATER
	tr.add_tile_states.assign([Terrain.TileState.SCORCHED])
	var out: Array[TerrainReaction] = [tr]
	return out


func _has_attack(squad: Squad) -> bool:
	return squad.action_queue.any(func(a: BaseAction) -> bool: return a is AttackAction)


func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for ctr in plan.counters:
		ctr.volley = empty
	for shot in plan.watch_shots:
		shot.volley = empty


# ==============================================================================
#  The queue gate: a candidate is refused in the menu's own words
# ==============================================================================

func test_the_queue_gate_refuses_a_carving_that_fizzles_and_says_why() -> void:
	var carving := _tied()
	var caster := _alchemist(PLAYER, DRY, carving)
	var foe := _foe(DRY_FOE)
	var expected := CellSubstances.fizzle_reason(carving, DRY, _board(), caster)
	assert_str(expected).override_failure_message("fixture: the carving must fizzle at DRY").is_not_empty()

	var refusal := _sm.try_queue_action(caster.squad, _aim(caster, carving, foe.movement.cell))
	assert_str(refusal).override_failure_message("a fizzling carving was queued").contains(expected)
	assert_bool(_has_attack(caster.squad)).is_false()


func test_beside_its_material_the_same_carving_queues() -> void:
	var carving := _tied()
	var caster := _alchemist(PLAYER, NEAR, carving)
	var foe := _foe(NEAR_FOE)
	assert_str(_sm.try_queue_action(caster.squad, _aim(caster, carving, foe.movement.cell))).is_empty()
	assert_bool(_has_attack(caster.squad)).is_true()


# The gate judges from where the caster will STAND: a queued walk to the spring makes the cast legal
# from a dry cell, which a gate reading the live cell would refuse.
func test_the_gate_reads_the_cell_a_queued_move_ends_on() -> void:
	var carving := _tied()
	var caster := _alchemist(PLAYER, DRY, carving)
	var foe := _foe(NEAR_FOE)
	assert_bool(_sm.queue_action(caster.squad, _move(caster, NEAR))).is_true()
	assert_str(_sm.try_queue_action(caster.squad, _aim(caster, carving, foe.movement.cell))).is_empty()


# ==============================================================================
#  A stored aim goes RED when a re-plan walks its caster away (one-way validity)
# ==============================================================================

func test_a_stored_aim_goes_red_when_its_caster_is_planned_away_from_the_material() -> void:
	var carving := _tied()
	var caster := _alchemist(PLAYER, DRY, carving)
	var foe := _foe(DRY_FOE)
	assert_bool(_sm.queue_action(caster.squad, _move(caster, NEAR))).is_true()
	var aim := _aim(caster, carving, foe.movement.cell)
	assert_bool(_sm.queue_action(caster.squad, aim)).override_failure_message(
			"fixture: the aim must be legal while the walk to the spring stands").is_true()

	_sm.cancel_move_for_unit(caster)   # the re-plan: the caster now casts from DRY
	var plan := _sm.resolve_plan(caster.squad, _board())
	_sm.validate_squad_plan(caster.squad, plan)

	assert_bool(caster.squad.action_queue.has(aim)).override_failure_message(
			"the aim was dropped -- validity is one-way, it goes red and stays").is_true()
	assert_bool(plan.attacks.any(func(a: AttackAction) -> bool: return a.source_aim == aim and a.resolved.fizzled)) \
		.override_failure_message("the resolve did not mark the aim fizzled from DRY").is_true()
	assert_bool(aim.is_valid).override_failure_message("a fizzling stored aim stayed valid").is_false()
	assert_array(aim.validation_errors).is_not_empty()
	_break_volleys(plan)


# ==============================================================================
#  The resolver: a fizzle lands NOTHING
# ==============================================================================

func _resolve_one_aim(caster: Unit, carving: TransmutationData, foe: Unit) -> ResolvedPlan:
	carving.targets = EquippableData.TargetMode.BOTH
	caster.squad._queue_action(_aim(caster, carving, foe.movement.cell))   # past the gate on purpose
	_sm.active_squad = caster.squad
	return _sm.resolve_plan(caster.squad, _board(), ReactionCatalog.get_all(), _water_marks_the_ground())


func test_a_carving_that_fizzles_in_the_pass_deals_nothing_deposits_nothing_and_draws_no_counter() -> void:
	var carving := _tied()
	var caster := _alchemist(PLAYER, DRY, carving)
	var foe := _foe(DRY_FOE)   # armed and adjacent: it would counter a real hit
	var plan := _resolve_one_aim(caster, carving, foe)

	assert_int(plan.attacks.size()).override_failure_message("the aim was not expanded").is_equal(1)
	var hit: AttackAction = plan.attacks[0]
	assert_object(hit.target).override_failure_message(
			"expand then mark: the fizzled volley still names its victim (R7's rule)").is_same(foe)
	assert_bool(hit.resolved.fizzled).is_true()
	assert_bool(hit.resolved.skipped).is_true()
	assert_int(hit.resolved.damage).is_equal(0)
	assert_array(hit.resolved.popups).contains([PlanResolver.FIZZLED_POPUP])
	assert_int(PlanResolver.projected_hp(foe, plan.hypo)).is_equal(foe.get_current_hp())
	assert_array(plan.cell_effects).override_failure_message("a fizzle left a deposit").is_empty()
	assert_array(plan.counters).override_failure_message("a fizzle drew a counter").is_empty()
	_break_volleys(plan)


# The control: the same order beside the spring lands, deposits and draws its counter -- so the empty
# lists above are the fizzle's doing, not the fixture's.
func test_beside_its_material_the_same_order_lands_deposits_and_draws_a_counter() -> void:
	var carving := _tied()
	var caster := _alchemist(PLAYER, NEAR, carving)
	var foe := _foe(NEAR_FOE)
	var plan := _resolve_one_aim(caster, carving, foe)

	var hit: AttackAction = plan.attacks[0]
	assert_bool(hit.resolved.fizzled).is_false()
	assert_int(hit.resolved.damage).is_greater(0)
	assert_array(plan.cell_effects).is_not_empty()
	assert_array(plan.counters).is_not_empty()
	_break_volleys(plan)


# A COUNTER fizzles the same way, from where the counter-er stands in the pass.
func test_a_counter_whose_carving_fizzles_lands_nothing() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, DRY, { Stats.Stat.MHP: 60 })
	var carving := _tied()
	var counterer := _alchemist(ENEMY, DRY_FOE, carving)
	attacker.squad._queue_action(H.stamped_attack(attacker, counterer))
	_sm.active_squad = attacker.squad
	var plan := _sm.resolve_plan(attacker.squad, _board())

	assert_int(plan.counters.size()).override_failure_message("no counter was derived at all").is_equal(1)
	assert_object(plan.counters[0].fired_attack).is_same(carving)
	assert_bool(plan.counters[0].resolved.fizzled).is_true()
	assert_int(plan.counters[0].resolved.damage).is_equal(0)
	assert_int(PlanResolver.projected_hp(attacker, plan.hypo)).is_equal(attacker.get_current_hp())

	# ...and a counter-er carrying its own water counters for real.
	counterer.add_element_state(Elemental.State.WET)
	var wet := _sm.resolve_plan(attacker.squad, _board())
	assert_bool(wet.counters[0].resolved.fizzled).is_false()
	assert_int(wet.counters[0].resolved.damage).is_greater(0)
	_break_volleys(plan)
	_break_volleys(wet)


# A WATCH SHOT fizzles too -- Pressure Spray is a watch-only carving -- from the watcher's anchor.
func test_a_watch_shot_whose_carving_fizzles_lands_nothing() -> void:
	var watched: Array[Vector2i] = [Vector2i(2, 0)]
	var carving := _tied(true)
	var watcher := _alchemist(ENEMY, Vector2i(2, 3), carving)
	watcher.arm_watch(watcher.movement.cell, watched[0], watched, carving)
	var crosser := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), { Stats.Stat.MHP: 60 }, false)
	var path: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)]
	var walk := MoveAction.new()
	walk.init(crosser, path, null)
	crosser.squad._queue_action(walk)

	var plan := _sm.resolve_plan(crosser.squad, _board())
	assert_int(plan.watch_shots.size()).override_failure_message("the watch never fired").is_equal(1)
	assert_bool(plan.watch_shots[0].resolved.fizzled).is_true()
	assert_int(plan.watch_shots[0].resolved.damage).is_equal(0)
	assert_int(PlanResolver.projected_hp(crosser, plan.hypo)).is_equal(crosser.get_current_hp())

	# ...and a watcher carrying its own water shoots for real.
	watcher.arm_watch(watcher.movement.cell, watched[0], watched, carving)
	watcher.add_element_state(Elemental.State.WET)
	var wet := _sm.resolve_plan(crosser.squad, _board())
	assert_int(wet.watch_shots.size()).is_equal(1)
	assert_bool(wet.watch_shots[0].resolved.fizzled).is_false()
	assert_int(wet.watch_shots[0].resolved.damage).is_greater(0)
	_break_volleys(plan)
	_break_volleys(wet)


# ==============================================================================
#  A WATCH is asked the same question: Pressure Spray is watch-only
# ==============================================================================

func test_the_queue_gate_refuses_a_watch_that_fizzles_and_says_why() -> void:
	var carving := _tied(true)
	var watcher := _alchemist(PLAYER, DRY, carving)
	var expected := CellSubstances.fizzle_reason(carving, DRY, _board(), watcher)
	assert_str(expected).override_failure_message("fixture: the carving must fizzle at DRY").is_not_empty()

	var refusal := _sm.try_queue_action(watcher.squad, _watch(watcher, carving, DRY_FOE))
	assert_str(refusal).override_failure_message("a fizzling watch was armed").contains(expected)
	assert_bool(watcher.squad.action_queue.any(func(a: BaseAction) -> bool: return a is OverwatchAction)).is_false()


func test_beside_its_material_the_same_watch_is_armed() -> void:
	var carving := _tied(true)
	var watcher := _alchemist(PLAYER, NEAR, carving)
	assert_str(_sm.try_queue_action(watcher.squad, _watch(watcher, carving, NEAR_FOE))).is_empty()


# One-way validity for a watch: queued beside the spring, then its watcher planned back to the dry cell.
func test_a_stored_watch_goes_red_when_its_watcher_is_planned_away_from_the_material() -> void:
	var carving := _tied(true)
	var watcher := _alchemist(PLAYER, DRY, carving)
	assert_bool(_sm.queue_action(watcher.squad, _move(watcher, NEAR))).is_true()
	var order := _watch(watcher, carving, DRY_FOE)
	assert_bool(_sm.queue_action(watcher.squad, order)).override_failure_message(
			"fixture: the watch must be legal while the walk to the spring stands").is_true()

	_sm.cancel_move_for_unit(watcher)   # the re-plan: the watch now arms at DRY
	var plan := _sm.resolve_plan(watcher.squad, _board())
	_sm.validate_squad_plan(watcher.squad, plan)

	assert_bool(watcher.squad.action_queue.has(order)).override_failure_message(
			"the watch was dropped -- validity is one-way, it goes red and stays").is_true()
	assert_that(order.resolved_anchor).override_failure_message(
			"fixture: the resolve must arm the watch at DRY").is_equal(DRY)
	assert_bool(order.is_valid).override_failure_message("a watch that would fizzle stayed valid").is_false()
	assert_array(order.validation_errors).is_not_empty()
	_break_volleys(plan)


# The F / Shift+F aim cycle offers no carving that would fizzle where the unit stands, so it never
# lands on an aim whose click the queue gate silently refuses. Without the board it asks nothing.
func test_the_aim_cycle_skips_a_carving_that_fizzles_here() -> void:
	var splash := _tied()
	splash.display_name = "Splash"
	splash.recipe = "Break(A, W) + Push(W2)"   # makes its own water: it never fizzles
	var tied := _tied()
	var carvings: Array[TransmutationData] = [splash, tied]
	var caster := _alchemist_with(PLAYER, DRY, carvings)

	var everything: Array = caster.aim_options(false).map(func(o: Unit.AimOption) -> AttackData: return o.attack)
	assert_bool(everything.has(tied)).override_failure_message(
			"fixture: without a board the tied carving must be offered").is_true()
	var here: Array = caster.aim_options(false, _board()).map(func(o: Unit.AimOption) -> AttackData: return o.attack)
	assert_bool(here.has(splash)).is_true()
	assert_bool(here.has(tied)).override_failure_message(
			"the aim cycle offered a carving that fizzles from where the unit stands").is_false()
