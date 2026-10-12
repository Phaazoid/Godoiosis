# A conduit (#1312): carried materia that is never used up, and whose substance is present for its
# CARRIER's casts. Canon: docs/design/alchemy-kit.md -> Materia -> Conduits.
#
# The carving is built in code from the substance a SHOCK hit is made of (SubstanceMap names it), so
# the case reads no authored carving and no authored conduit (tests/README.md rule 9). The substance
# itself has to be the library's, because a substance's id is its file name and that id is what the
# fizzle check compares.
#
# Through the real doors: CellSubstances.fizzle_reason (what every caller asks), the resolver, and the
# queue gate -- the Law #3 chokepoint the menu, the AI and the Play API all go through.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const HERE := Vector2i(8, 8)
const NEXT_DOOR := Vector2i(8, 9)
const FOE_CELL := Vector2i(9, 8)

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _board() -> BoardContext:
	return _sm.board_source.call()


# The library substance a shock hit delivers, or null with a warning when there is none to hold.
func _held() -> Substance:
	var substance := SubstanceCatalog.get_all().get(SubstanceMap.of_element(Elemental.Element.SHOCK)) as Substance
	if substance == null:
		push_warning("the substance map names no shock substance, so there is nothing to hold")
	return substance


func _conduit(holds: Substance) -> ConduitData:
	var conduit := ConduitData.new()
	conduit.display_name = "Test Conduit"
	conduit.substance = holds
	return conduit


# Draws the held substance and pushes it: needs it present and makes nothing that could stand in.
func _draws(holds: Substance) -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = "Draw"
	t.power = 5
	t.targets = EquippableData.TargetMode.BOTH
	t.recipe = "Extract(%s) + Push(%s)" % [holds.formula, holds.formula]
	return t


# An alchemist who can channel `carving` -- aura in every element it demands, so a refusal below is
# the fizzle and never the channel gate.
func _alchemist(cell: Vector2i, carving: TransmutationData) -> Unit:
	var u := H.spawn_solo(self, _sm, PLAYER, cell, { Stats.Stat.MHP: 60 }, false)
	var aura: Dictionary[Elemental.Element, int] = {}
	var affinity: Array[Elemental.Element] = []
	for e: Elemental.Element in carving.distinct_elements():
		aura[e] = 6
		affinity.append(e)
	u.unit_instance.aura = aura
	u.unit_instance.affinity = affinity
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	assert_bool(rune.inscribe(carving)).override_failure_message("fixture carving failed to inscribe").is_true()
	u.equipped_weapon = rune
	assert_bool(u.is_attack_fireable(carving)).override_failure_message(
			"fixture: the carving must be channelable, or the fizzle is not what is measured").is_true()
	return u


func test_a_carving_needing_what_a_conduit_holds_fizzles_without_it_and_holds_with_it() -> void:
	var holds := _held()
	if holds == null:
		return
	var carving := _draws(holds)
	var caster := _alchemist(HERE, carving)

	assert_str(CellSubstances.fizzle_reason(carving, HERE, _board(), caster)).override_failure_message(
			"the fixture's board offers the held substance already, so the conduit is not what is measured"
			).is_not_empty()

	assert_bool(caster.add_item(_conduit(holds))).is_true()
	assert_str(CellSubstances.fizzle_reason(carving, HERE, _board(), caster)).override_failure_message(
			"a carried conduit did not make its substance present for its carrier").is_empty()


# Carrier only: a vial is the carrier's too, and "stand by your source" is about the ground.
func test_a_conduit_in_a_neighbours_pack_does_not_count() -> void:
	var holds := _held()
	if holds == null:
		return
	var carving := _draws(holds)
	var caster := _alchemist(HERE, carving)
	var neighbour := H.spawn_solo(self, _sm, PLAYER, NEXT_DOOR, {}, false)
	assert_bool(neighbour.add_item(_conduit(holds))).is_true()

	assert_str(CellSubstances.fizzle_reason(carving, HERE, _board(), caster)).override_failure_message(
			"a conduit counted for the unit standing beside its carrier").is_not_empty()


func test_through_the_resolver_the_cast_lands_and_spends_nothing() -> void:
	var holds := _held()
	if holds == null:
		return
	var carving := _draws(holds)
	var caster := _alchemist(HERE, carving)
	var conduit := _conduit(holds)
	assert_bool(caster.add_item(conduit)).is_true()
	var foe := H.spawn_solo(self, _sm, ENEMY, FOE_CELL, { Stats.Stat.MHP: 60 })

	caster.active_attack = carving
	var aim := AttackAction.declare(caster, caster.get_projected_destination(), foe.movement.cell)
	caster.active_attack = null
	caster.squad._queue_action(aim)
	_sm.active_squad = caster.squad
	var plan := _sm.resolve_plan(caster.squad, _board(), ReactionCatalog.get_all())

	assert_int(plan.attacks.size()).override_failure_message("the aim was not expanded").is_equal(1)
	var hit: AttackAction = plan.attacks[0]
	assert_bool(hit.resolved.fizzled).override_failure_message(
			"the resolver fizzled a cast its caster's conduit supplies").is_false()
	assert_int(hit.resolved.damage).is_greater(0)
	assert_object(hit.resolved.burned_vial).override_failure_message(
			"the cast burned something: a conduit is never used up").is_null()
	assert_bool(caster.inventory.has(conduit)).is_true()
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
	for ctr in plan.counters:
		ctr.volley = empty


# The chokepoint every door queues through (Law #3): refused without the conduit, in the fizzle's
# words, and queued with it.
func test_the_queue_gate_refuses_without_the_conduit_and_queues_with_it() -> void:
	var holds := _held()
	if holds == null:
		return
	var carving := _draws(holds)
	var caster := _alchemist(HERE, carving)
	var foe := H.spawn_solo(self, _sm, ENEMY, FOE_CELL, { Stats.Stat.MHP: 60 })

	caster.active_attack = carving
	var refused := AttackAction.declare(caster, caster.get_projected_destination(), foe.movement.cell)
	var reason := _sm.try_queue_action(caster.squad, refused)
	assert_str(reason).override_failure_message("the gate queued a cast with nothing to draw on").is_not_empty()

	assert_bool(caster.add_item(_conduit(holds))).is_true()
	var allowed := AttackAction.declare(caster, caster.get_projected_destination(), foe.movement.cell)
	caster.active_attack = null
	assert_str(_sm.try_queue_action(caster.squad, allowed)).override_failure_message(
			"the gate refused a cast its caster's conduit supplies").is_empty()


# Unusable by construction: every door that spends a carried thing asks for a vial.
func test_a_conduit_cannot_be_used_like_a_vial() -> void:
	var holds := _held()
	if holds == null:
		return
	var carrier := H.spawn_solo(self, _sm, PLAYER, HERE, {}, false)
	assert_bool(carrier.add_item(_conduit(holds))).is_true()
	var at := carrier.inventory.find(carrier.inventory.filter(func(i: Item) -> bool: return i is ConduitData)[0])

	assert_str(carrier.use_vial(at)).is_not_empty()
	assert_bool(carrier.inventory[at] is ConduitData).override_failure_message(
			"using the conduit took it out of the pack").is_true()
