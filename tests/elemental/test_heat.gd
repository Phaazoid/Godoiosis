# HEAT (Deep Alchemy, 2026-10-12, dev + codev): free heat, a lone F, is a hit element that WARMS and
# never ignites. It answers to the authored reactions that list it in also_triggered_by -- drying,
# temperature shock, melting, boiling -- and to none of the ignitions.
#
# The reaction cases run against the AUTHORED catalogs, test_quickdry's and test_gas_deposits' lane:
# every number is read off the reaction that fired, never a literal, and each finds its reaction by
# the rule it asks (fires_for), so a reaction retuned or renamed moves nothing here. The two-element
# case is the mechanism half: one reaction fires ONCE for a hit carrying both of its elements.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const BASE := 4
const TARGET_CELL := Vector2i(1, 0)
const HEAT := Elemental.Element.HEAT
const FIRE := Elemental.Element.FIRE

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)


class _KindBoard extends BoardContext:
	var kinds: Dictionary
	func _init(states: TerrainStateManager, k: Dictionary) -> void:
		var no_units: Array[Unit] = []
		super(null, no_units, null, states)
		kinds = k
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return kinds.get(cell, Terrain.Kind.NONE)


static func _only(e: Elemental.Element) -> Array[Elemental.Element]:
	var one: Array[Elemental.Element] = [e]
	return one


# The authored unit reaction a hit of `element` sets off on a target holding `state`.
func _authored(element: Elemental.Element, state: Elemental.State) -> ElementalReaction:
	for r in ReactionCatalog.get_all():
		if r.required_state == state and r.fires_for(_only(element)):
			return r
	assert_bool(false).override_failure_message(
			"no authored reaction answers %s on a %s target" % [Elemental.display_name(element),
			Elemental.state_display_name(state)]).is_true()
	return null


func _authored_tile(pick: Callable, what: String) -> TerrainReaction:
	for r in TerrainReactionCatalog.get_all():
		if pick.call(r):
			return r
	assert_bool(false).override_failure_message("no authored terrain reaction %s" % what).is_true()
	return null


func _attacker(element: Elemental.Element, targets := EquippableData.TargetMode.UNIT) -> Unit:
	var u := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 0}, true, BASE)
	var attack := (u.get_equipped_weapon() as WeaponInstance).template.main_attack
	attack.elemental_damage_type = element
	attack.targets = targets
	return u


func _hit(attacker: Unit, target: Unit) -> AttackAction:
	var attack := H.stamped_attack(attacker, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)   # default reactions = the authored catalog
	return attack


func _store_with(state: Terrain.TileState) -> TerrainStateManager:
	var tsm: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(tsm)
	var seed_effect := ResolvedCellEffect.new()
	seed_effect.cell = TARGET_CELL
	seed_effect.states_added.assign([state])
	tsm.apply(seed_effect)
	return tsm


func _hit_tile(element: Elemental.Element, board: BoardContext) -> ResolvedPlan:
	var attacker := _attacker(element, EquippableData.TargetMode.MAP)
	var aim := AttackAction.create(attacker, attacker.movement.cell, null, TARGET_CELL)
	aim.fired_attack = attacker.get_fired_attack()
	var struck: Array[Vector2i] = [TARGET_CELL]
	aim.struck_cells = struck
	var plan := ResolvedPlan.new()
	plan.attacks.append(aim)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions, board, TerrainReactionCatalog.get_all())
	return plan


func _adds_burning(plan: ResolvedPlan) -> bool:
	for effect in plan.cell_effects:
		if effect.states_added.has(Terrain.TileState.BURNING):
			return true
	return false


# --- on units ------------------------------------------------------------------------------------

func test_heat_dries_a_wet_target() -> void:
	var target := H.spawn_solo(self, _sm, ENEMY, TARGET_CELL, {Stats.Stat.MHP: 50})
	target.add_element_state(Elemental.State.WET)

	var attack := _hit(_attacker(HEAT), target)

	var r := _authored(HEAT, Elemental.State.WET)
	assert_bool(attack.resolved.states_removed.has(Elemental.State.WET)).is_true()
	assert_int(attack.resolved.damage).is_equal(int(round(BASE * r.damage_mult)) + r.damage_bonus)


func test_heat_on_a_chilled_target_is_a_temperature_shock() -> void:
	var target := H.spawn_solo(self, _sm, ENEMY, TARGET_CELL, {Stats.Stat.MHP: 50})
	target.add_element_state(Elemental.State.CHILLED)

	var attack := _hit(_attacker(HEAT), target)

	var r := _authored(HEAT, Elemental.State.CHILLED)
	assert_array(attack.resolved.fired_reactions).contains([r])
	assert_bool(attack.resolved.states_removed.has(Elemental.State.CHILLED)).is_true()


# The double-fire guard, and the reason the extras are a LIST on one reaction rather than a second
# file: a hit carrying fire AND heat dries a wet target once. Fired twice it would compound the
# multiplier (x0.25 for Quick Dry), which is what the damage assert would see.
func test_a_hit_carrying_fire_and_heat_sets_each_reaction_off_once() -> void:
	var attacker := _attacker(FIRE)
	attacker.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)
	var mod := WeaponModData.new()
	mod.added_element = HEAT
	assert_bool((attacker.get_equipped_weapon() as WeaponInstance).fit(0, mod)) \
		.override_failure_message("fixture: the heat mod must fit, or the hit carries fire alone").is_true()
	var target := H.spawn_solo(self, _sm, ENEMY, TARGET_CELL, {Stats.Stat.MHP: 50})
	target.add_element_state(Elemental.State.WET)

	var attack := _hit(attacker, target)

	var r := _authored(HEAT, Elemental.State.WET)
	assert_array(attack.resolved.elements).contains([FIRE, HEAT])
	assert_int(attack.resolved.fired_reactions.count(r)).is_equal(1)
	assert_int(attack.resolved.damage).is_equal(int(round(BASE * r.damage_mult)) + r.damage_bonus)


func test_heat_insulation_strips_heat_and_leaves_the_target_wet() -> void:
	var target := H.spawn_solo(self, _sm, ENEMY, TARGET_CELL, {Stats.Stat.MHP: 50})
	target.add_element_state(Elemental.State.WET)
	var weave := ArmorData.new()
	var ability := AbilityData.new()
	ability.id = Abilities.INSULATION[HEAT]
	ability.kind = AbilityData.AbilityKind.PASSIVE
	weave.granted_abilities = [ability]
	target.worn_armor = weave

	var attack := _hit(_attacker(HEAT), target)

	assert_bool(attack.resolved.insulated).is_true()
	assert_bool(attack.resolved.states_removed.has(Elemental.State.WET)).is_false()


# --- on the ground -------------------------------------------------------------------------------

func test_heat_melts_frozen_water() -> void:
	var board := _KindBoard.new(_store_with(Terrain.TileState.FROZEN), { TARGET_CELL: Terrain.Kind.WATER })
	var plan := _hit_tile(HEAT, board)
	assert_int(plan.cell_effects.size()).is_equal(1)
	assert_bool(plan.cell_effects[0].states_removed.has(Terrain.TileState.FROZEN)).is_true()


func test_heat_boils_open_water() -> void:
	var boils := _authored_tile(func(r: TerrainReaction) -> bool:
		return r.fires_for(_only(HEAT)) and r.required_kind == Terrain.Kind.WATER \
			and not Gas.released(r.gases).is_empty(), "that heat boils water with")
	var plan := _hit_tile(HEAT, _KindBoard.new(null, { TARGET_CELL: Terrain.Kind.WATER }))
	assert_int(plan.cell_effects.size()).is_equal(1)
	for kind: Gas.Kind in Gas.released(boils.gases):
		assert_int(plan.cell_effects[0].gas_added.get(kind, 0)).is_equal(boils.gases[kind])


# Heat warms and never ignites; fire on the same ground is the control, so a board on which nothing
# could ever burn cannot pass this for the wrong reason.
func test_heat_sets_no_grass_alight_where_fire_does() -> void:
	var grass := { TARGET_CELL: Terrain.Kind.GRASS }
	assert_bool(_adds_burning(_hit_tile(FIRE, _KindBoard.new(null, grass)))) \
		.override_failure_message("control: fire did not light the grass, so this board proves nothing").is_true()
	assert_bool(_adds_burning(_hit_tile(HEAT, _KindBoard.new(null, grass)))).is_false()


# --- the rule and its words ----------------------------------------------------------------------

func test_a_reaction_answers_its_primary_and_every_extra_and_nothing_else() -> void:
	var r := ElementalReaction.new()
	r.incoming_element = FIRE
	r.also_triggered_by.assign([HEAT])
	assert_bool(r.fires_for(_only(FIRE))).is_true()
	assert_bool(r.fires_for(_only(HEAT))).is_true()
	assert_bool(r.fires_for(_only(Elemental.Element.WATER))).is_false()


func test_the_glossary_names_every_element_a_reaction_answers() -> void:
	var r := ElementalReaction.new()
	r.incoming_element = FIRE
	r.also_triggered_by.assign([HEAT])
	r.required_state = Elemental.State.WET
	assert_str(Glossary.reaction_line(r)).starts_with("Fire or Heat vs a Wet target")


# The queue's combo chip wears the element that SET THE REACTION OFF: a heat hit's dry-off is Heat's.
func test_a_combo_chip_wears_the_element_that_set_it_off() -> void:
	var r := ElementalReaction.new()
	r.incoming_element = FIRE
	r.also_triggered_by.assign([HEAT])
	var outcome := ResolvedOutcome.new()
	outcome.elements.assign([HEAT])
	assert_int(ActionQueueRow._setter_of(r, outcome)).is_equal(HEAT)
