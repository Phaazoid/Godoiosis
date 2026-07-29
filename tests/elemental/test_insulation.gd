# Armor elemental immunity (the Insulated Weave). Canon lane: elemental effects are mitigated by
# TARGETED gear, never a catch-all RES stat (alchemy-kit.md); jobs are explicitly fenced OUT of
# immunity (job-ideas.md). The model is "the element is erased from the hit" -- canon's own phrase
# for this shape is "immune to SHOCK reactions" (elemental-interactions.md's GROUNDED state).
#
# The load-bearing distinction, and the reason this suite exists: a weapon merely TAGGED with a
# blocked element still lands its physical swing (insulation, not a force field), but a carving
# whose damage IS the element -- it scales off the wielder's AURA, not their body -- is stopped
# outright. PlanResolver tells them apart by whether fired_attack is a TransmutationData.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const TREE_CELL := Vector2i(1, 0)

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)


class _StubBoard extends BoardContext:
	var kinds: Dictionary
	func _init(g: TileMapLayer, u: Array[Unit], m: SquadManager, k: Dictionary) -> void:
		super(g, u, m)
		kinds = k
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return kinds.get(cell, Terrain.Kind.NONE)


func _insulated_against(element: Elemental.Element) -> ArmorData:
	var weave := ArmorData.new()
	weave.item_name = "Test Weave"
	weave.immune_elements.append(element)
	return weave


func _shock_electrocute(bonus: int = 5) -> ElementalReaction:
	var r := ElementalReaction.new()
	r.incoming_element = Elemental.Element.SHOCK
	r.required_state = Elemental.State.WET
	r.damage_bonus = bonus
	var removes: Array[Elemental.State] = [Elemental.State.WET]
	r.remove_states = removes
	r.popup = "Electrocuted!"
	return r


# A lightning bolt: FIRE aura QUICKENED into SHOCK (SHOCK is a derived exotic, never a sigil).
func _lightning_bolt(power: int, mode: EquippableData.TargetMode = EquippableData.TargetMode.UNIT) -> TransmutationData:
	var t := TransmutationData.new()
	t.power = power
	t.sigils.assign([Elemental.Element.FIRE])
	t.flourishes.assign([Flourish.Type.QUICKENING])
	t.targets = mode
	return t


func _alchemist(aura: Dictionary[Elemental.Element, int]) -> Unit:
	var u: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	u.unit_instance.aura = aura
	var affinity: Array[Elemental.Element] = []
	for element in aura:
		affinity.append(element)
	u.unit_instance.affinity = affinity
	return u


func _shock_mech() -> Unit:
	var mech: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 0}, true, 4)
	(mech.get_equipped_weapon() as WeaponInstance).template.main_attack.elemental_damage_type = Elemental.Element.SHOCK
	return mech


func _attack(attacker: Unit, target: Unit) -> AttackAction:
	return H.stamped_attack(attacker, target)


# --- the carving half: damage that IS elemental is stopped outright ---

func test_a_lightning_carving_is_nullified_entirely() -> void:
	var alch: Unit = _alchemist({ Elemental.Element.FIRE: 4 })
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	foe.worn_armor = _insulated_against(Elemental.Element.SHOCK)

	var atk := H.stamped_attack(alch, foe)
	atk.fired_attack = _lightning_bolt(5)
	var plan := ResolvedPlan.new()
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	assert_int(atk.resolved.damage).is_equal(0)   # would have been power 5 + fire aura 4


func test_the_same_carving_hurts_an_unarmored_target() -> void:
	# Control for the test above -- proves the 0 comes from the armor, not a broken fixture.
	var alch: Unit = _alchemist({ Elemental.Element.FIRE: 4 })
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})

	var atk := H.stamped_attack(alch, foe)
	atk.fired_attack = _lightning_bolt(5)
	var plan := ResolvedPlan.new()
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	assert_int(atk.resolved.damage).is_equal(9)


func test_insulation_is_element_specific() -> void:
	# A SHOCK weave does nothing about a fireball -- targeted gear, not blanket resistance.
	var alch: Unit = _alchemist({ Elemental.Element.FIRE: 4 })
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	foe.worn_armor = _insulated_against(Elemental.Element.SHOCK)

	var fireball := TransmutationData.new()
	fireball.power = 5
	fireball.sigils.assign([Elemental.Element.FIRE])   # no quickening -> stays FIRE
	var atk := H.stamped_attack(alch, foe)
	atk.fired_attack = fireball
	var plan := ResolvedPlan.new()
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	assert_int(atk.resolved.damage).is_equal(9)


# --- the weapon half: a tagged swing still lands ---

func test_a_shock_tagged_weapon_still_lands_its_physical_swing() -> void:
	# The wearer is insulated, not shielded: the chainsword still hits for its base damage.
	var mech := _shock_mech()
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {Stats.Stat.MHP: 50})
	foe.worn_armor = _insulated_against(Elemental.Element.SHOCK)
	foe.element_states.append(Elemental.State.WET)   # primed to be electrocuted

	var plan := ResolvedPlan.new()
	var shock := _attack(mech, foe)
	plan.attacks.append(shock)
	var reactions: Array[ElementalReaction] = [_shock_electrocute(5)]
	PlanResolver.resolve(plan, reactions)

	assert_int(shock.resolved.damage).is_equal(4)   # base only -- the +5 never fired


func test_insulation_stops_the_reactions_state_change_too() -> void:
	# "Damage AND effects": the electrocution must not consume the target's WET either, or the
	# armor would still be paying a hidden cost for a reaction that never happened.
	var mech := _shock_mech()
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {Stats.Stat.MHP: 50})
	foe.worn_armor = _insulated_against(Elemental.Element.SHOCK)
	foe.element_states.append(Elemental.State.WET)

	var plan := ResolvedPlan.new()
	var shock := _attack(mech, foe)
	plan.attacks.append(shock)
	var reactions: Array[ElementalReaction] = [_shock_electrocute(5)]
	PlanResolver.resolve(plan, reactions)

	assert_bool(shock.resolved.states_removed.has(Elemental.State.WET)).is_false()
	assert_array(shock.resolved.popups).not_contains(["Electrocuted!"])


func test_an_unarmored_target_still_gets_electrocuted() -> void:
	var mech := _shock_mech()
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {Stats.Stat.MHP: 50})
	foe.element_states.append(Elemental.State.WET)

	var plan := ResolvedPlan.new()
	var shock := _attack(mech, foe)
	plan.attacks.append(shock)
	var reactions: Array[ElementalReaction] = [_shock_electrocute(5)]
	PlanResolver.resolve(plan, reactions)

	assert_int(shock.resolved.damage).is_equal(9)
	assert_bool(shock.resolved.states_removed.has(Elemental.State.WET)).is_true()


# --- a turned-aside attack is not a 0-damage hit (dev call 2026-07-24) ---

func test_a_downed_insulated_unit_survives_a_lightning_bolt() -> void:
	# The exemption that makes insulation mean something. Normally ANY hit finishes a downed unit,
	# 0-damage ones included (stats.md, ratified). But a fully-blocked carving never ARRIVED --
	# it isn't a hit that did nothing, it's an attack that didn't land -- so it can't finish them.
	var alch: Unit = _alchemist({ Elemental.Element.FIRE: 4 })
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	foe.worn_armor = _insulated_against(Elemental.Element.SHOCK)
	foe.lifecycle_state = Unit.LifecycleState.DOWNED

	var atk := H.stamped_attack(alch, foe)
	atk.fired_attack = _lightning_bolt(5)
	var plan := ResolvedPlan.new()
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	assert_int(atk.resolved.damage).is_equal(0)
	assert_int(atk.resolved.lethality).is_equal(ResolvedOutcome.Lethality.NONE)


func test_an_unblocked_bolt_still_finishes_a_downed_unit() -> void:
	# Control: the same downed unit, same bolt, wrong armor -- the ratified downed rule applies.
	var alch: Unit = _alchemist({ Elemental.Element.FIRE: 4 })
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	foe.worn_armor = _insulated_against(Elemental.Element.FIRE)   # insulated against the WRONG thing
	foe.lifecycle_state = Unit.LifecycleState.DOWNED

	var atk := H.stamped_attack(alch, foe)
	atk.fired_attack = _lightning_bolt(5)
	var plan := ResolvedPlan.new()
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	assert_int(atk.resolved.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)


func test_a_zero_damage_physical_hit_still_finishes_a_downed_unit() -> void:
	# The narrowness check. Insulation exempts a TURNED-ASIDE attack, not every harmless one:
	# stats.md's "a 0-damage hit is still a hit" must survive this feature intact.
	var weakling: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 0}, true, 0)
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	foe.worn_armor = _insulated_against(Elemental.Element.SHOCK)
	foe.lifecycle_state = Unit.LifecycleState.DOWNED

	var plan := ResolvedPlan.new()
	var atk := _attack(weakling, foe)
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	assert_int(atk.resolved.damage).is_equal(0)
	assert_int(atk.resolved.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)


func test_a_blocked_bolt_leaves_a_living_target_untouched() -> void:
	# The whole outcome is inert, not just the damage number: no HP change, no lethality.
	var alch: Unit = _alchemist({ Elemental.Element.FIRE: 4 })
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	foe.worn_armor = _insulated_against(Elemental.Element.SHOCK)

	var atk := H.stamped_attack(alch, foe)
	atk.fired_attack = _lightning_bolt(5)
	var plan := ResolvedPlan.new()
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	assert_int(atk.resolved.target_hp_after).is_equal(foe.get_current_hp())
	assert_bool(atk.resolved.knockback_applied).is_false()
	assert_array(atk.resolved.states_added).is_empty()


# --- legibility + the deliberate non-filter ---

func test_a_blocked_hit_says_so() -> void:
	# Law #2's spirit: the queue has to explain the number it shows, so a blocked element
	# announces itself rather than silently deleting damage the player expected.
	var mech := _shock_mech()
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(2, 0), {Stats.Stat.MHP: 50})
	foe.worn_armor = _insulated_against(Elemental.Element.SHOCK)

	var plan := ResolvedPlan.new()
	var shock := _attack(mech, foe)
	plan.attacks.append(shock)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	assert_array(shock.resolved.popups).contains([PlanResolver.INSULATED_POPUP])


func test_the_ground_is_not_insulated() -> void:
	# Deliberate: armor protects its WEARER, not the tile they stand on. A bolt that can't hurt
	# an insulated unit still electrifies the terrain -- cell effects read the UNFILTERED elements.
	var alch: Unit = _alchemist({ Elemental.Element.FIRE: 4 })
	var atk := AttackAction.create(alch, alch.movement.cell, null, TREE_CELL)
	atk.fired_attack = _lightning_bolt(5, EquippableData.TargetMode.BOTH)

	var shock_burns_tree := TerrainReaction.new()
	shock_burns_tree.incoming_element = Elemental.Element.SHOCK
	shock_burns_tree.required_kind = Terrain.Kind.TREE
	shock_burns_tree.add_tile_states.assign([Terrain.TileState.BURNING])

	var plan := ResolvedPlan.new()
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	var no_units: Array[Unit] = []
	var terrain: Array[TerrainReaction] = [shock_burns_tree]
	var board: _StubBoard = _StubBoard.new(null, no_units, null, { TREE_CELL: Terrain.Kind.TREE })
	PlanResolver.resolve(plan, no_reactions, board, terrain)

	assert_int(plan.cell_effects.size()).is_equal(1)
	assert_bool(plan.cell_effects[0].states_added.has(Terrain.TileState.BURNING)).is_true()


func test_insulation_does_not_stack_with_def() -> void:
	# The Weave grants no DEF (that's its whole cost). A blocked hit reads 0 because the element
	# was erased, NOT because mitigation ate it -- so an unblocked element still pays full price.
	var weave := _insulated_against(Elemental.Element.SHOCK)
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50, Stats.Stat.CON: 9})
	foe.worn_armor = weave
	assert_int(foe.get_effective_def()).is_equal(0)
