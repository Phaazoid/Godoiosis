# A carving's ingredients include what NEARBY UNITS carry (a Wet unit lends water), and every fizzle
# check reads those units where the plan puts them (#1480 stage 4, dev ruling 2026-10-24): before a
# pass, at their queued destination with their current states; inside one, as the pass has left them.
# Until then the caster was read where the plan put it and its neighbours where they stood, so a Wet
# ally walking in beside the caster was looked for at its old cell, and a neighbour an earlier hit
# soaked still read dry.
#
# The carving and the caster are tests/runes/test_fizzle_wires.gd's: `Focus(W2) + Push(W2)` needs water
# beside the caster, and the ground here offers none, so the only water is what a neighbour carries.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const WATER := Elemental.Element.WATER

var _sm: SquadManager


# No ground offers anything: every cell reads as no terrain at all.
class _BareBoard extends BoardContext:
	func terrain_kind_at(_cell: Vector2i) -> Terrain.Kind:
		return Terrain.Kind.NONE


func before_test() -> void:
	_sm = H.make_manager(self)
	var grid: TileMapLayer = (_sm.board_source.call() as BoardContext).grid
	_sm.board_source = func() -> BoardContext:
		return _BareBoard.new(grid, _sm._all_units(), _sm)


func _board() -> BoardContext:
	return _sm.board_source.call()


func _tied() -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = "Spray"
	t.power = 5
	t.recipe = "Focus(W2) + Push(W2)"
	t.targets = EquippableData.TargetMode.BOTH
	return t


func _alchemist(faction: Team.Faction, cell: Vector2i, carving: TransmutationData) -> Unit:
	var u := H.spawn_solo(self, _sm, faction, cell, { Stats.Stat.MHP: 60 }, false)
	u.unit_instance.aura = { WATER: 4, Elemental.Element.AIR: 1 }
	var affinity: Array[Elemental.Element] = [WATER, Elemental.Element.AIR]
	u.unit_instance.affinity = affinity
	var rune := RuneData.new()
	rune.size = RuneData.Size.MEDIUM
	assert_bool(rune.inscribe(carving)).override_failure_message("fixture carving failed to inscribe").is_true()
	u.equipped_weapon = rune
	assert_bool(u.is_attack_fireable(carving)).override_failure_message(
			"fixture: the carving must be channelable, or the fizzle is not what is measured").is_true()
	return u


func _aim(caster: Unit, carving: TransmutationData, cell: Vector2i) -> AttackAction:
	caster.active_attack = carving
	var aim := AttackAction.declare(caster, caster.get_projected_destination(), cell)
	caster.active_attack = null
	return aim


func _walk_west(unit: Unit, to: Vector2i) -> MoveAction:
	var move := MoveAction.new()
	var path: Array[Vector2i] = []
	for x in range(unit.movement.cell.x, to.x - 1, -1):
		path.append(Vector2i(x, to.y))
	move.init(unit, path, null)
	return move


func _water_sets_wet() -> Array[ElementalReaction]:
	var reaction := ElementalReaction.new()
	reaction.incoming_element = WATER
	reaction.add_states.assign([Elemental.State.WET])
	var out: Array[ElementalReaction] = [reaction]
	return out


func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for ctr in plan.counters:
		ctr.volley = empty
	for shot in plan.watch_shots:
		shot.volley = empty


# A Wet ally queued to walk in beside the caster, and the caster's carving queued after it.
func _walk_in() -> Dictionary:
	var carving := _tied()
	var caster := _alchemist(PLAYER, Vector2i(0, 0), carving)
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 1), { Stats.Stat.MHP: 60 })
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(3, 0), { Stats.Stat.MHP: 60 }, false)
	ally.add_element_state(Elemental.State.WET)
	assert_str(CellSubstances.fizzle_reason(carving, caster.movement.cell, _board(), caster.state)) \
		.override_failure_message("fixture: the caster must find water nowhere but on the ally").is_not_empty()
	assert_bool(_sm.queue_action(ally.squad, _walk_west(ally, Vector2i(1, 0)))) \
		.override_failure_message("fixture failed to queue the ally's walk").is_true()
	return { "carving": carving, "caster": caster, "foe": foe, "ally": ally }


# The queue gate asks before any pass: the ally counts where its walk ends.
func test_the_gate_takes_a_carving_whose_water_walks_in_beside_the_caster() -> void:
	var f := _walk_in()
	var caster: Unit = f["caster"]
	var refusal := _sm.try_queue_action(caster.squad, _aim(caster, f["carving"], (f["foe"] as Unit).movement.cell))
	assert_str(refusal).override_failure_message(
			"the gate looked for the ally where it stands, not where its walk ends: %s" % refusal).is_empty()


# ...and the pass lands it, reading the ally where the plan put it.
func test_the_pass_lands_a_carving_whose_water_walked_in_beside_the_caster() -> void:
	var f := _walk_in()
	var caster: Unit = f["caster"]
	caster.squad._queue_action(_aim(caster, f["carving"], (f["foe"] as Unit).movement.cell))   # past the gate
	_sm.active_squad = caster.squad
	var plan := _sm.resolve_plan(caster.squad, _board())

	assert_int(plan.attacks.size()).override_failure_message("the aim was not expanded").is_equal(1)
	var hit: AttackAction = plan.attacks[0]
	assert_bool(hit.resolved.fizzled).override_failure_message(
			"the pass looked for the ally where it stands, not where the plan put it").is_false()
	assert_int(hit.resolved.damage).is_greater(0)
	_break_volleys(plan)


# An enemy's water hit soaks the unit beside the caster; the caster's counter draws that water.
func test_a_counter_draws_on_a_neighbour_an_earlier_hit_soaked() -> void:
	var carving := _tied()
	carving.max_range = 2   # the counter reaches the attacker across the soaked neighbour
	var caster := _alchemist(PLAYER, Vector2i(0, 1), carving)
	var neighbour := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), { Stats.Stat.MHP: 60 }, false)
	_sm.join_squad(neighbour, caster.squad)
	assert_object(neighbour.squad).override_failure_message("fixture: the neighbour must answer with the caster's party") \
		.is_same(caster.squad)
	var soaker := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), { Stats.Stat.MHP: 60 })
	(soaker.get_equipped_weapon() as WeaponInstance).template.main_attack.elemental_damage_type = WATER
	assert_str(CellSubstances.fizzle_reason(carving, caster.movement.cell, _board(), caster.state)) \
		.override_failure_message("fixture: before the hit, the caster must find no water").is_not_empty()

	soaker.squad._queue_action(H.stamped_attack(soaker, neighbour))
	_sm.active_squad = soaker.squad
	var plan := _sm.resolve_plan(soaker.squad, _board(), _water_sets_wet())

	assert_bool(PlanResolver.projected_states(neighbour, plan.hypo).has(Elemental.State.WET)) \
		.override_failure_message("fixture: the hit did not soak the neighbour").is_true()
	var counters := plan.counters.filter(func(c: CounterAttackAction) -> bool: return c.actor == caster)
	assert_int(counters.size()).override_failure_message(
			"the caster drew no counter: the neighbour it would draw water from still read dry").is_equal(1)
	if counters.size() == 1:
		var counter: CounterAttackAction = counters[0]
		assert_bool(counter.resolved.fizzled).is_false()
		assert_int(counter.resolved.damage).is_greater(0)
	_break_volleys(plan)
