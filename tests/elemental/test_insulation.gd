# Armor elemental immunity (the Insulated Weave). Canon lane: elemental effects are mitigated by
# TARGETED gear, never a catch-all RES stat (alchemy-kit.md); jobs are explicitly fenced OUT of
# immunity (job-ideas.md). The model is "the element is erased from the hit" -- canon's own phrase
# for this shape is "immune to SHOCK reactions" (elemental-interactions.md's GROUNDED state).
#
# The load-bearing distinction, and the reason this suite exists: insulation strips the ELEMENT --
# the effect never fires, no reaction keys on it -- and NOTHING ELSE. The damage still lands as an
# ordinary hit of its kind, for DEF to answer (#424, dev 2026-09-05: "immune to shock damage" is
# spelled as armour covering SHOCK). Until #424 a carving whose damage WAS the element was turned
# aside entirely -- a hit that never arrived -- and that outcome is REPEALED; see the arrival cases.
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


func _ability(id: Abilities.Id) -> AbilityData:
	var a := AbilityData.new()
	a.id = id
	a.kind = AbilityData.AbilityKind.PASSIVE
	return a


# Insulation arrives as a granted ABILITY since #90, not an element list on the armor -- so this
# fixture now walks the same path real content does: gear -> the live ability kit -> is_immune_to.
# Indexed, not .get()'d, on purpose: an element with no insulation ability authored yet is a loud
# test failure rather than silently inert armor that would make its case pass for the wrong reason.
func _insulated_against(element: Elemental.Element) -> ArmorData:
	var weave := ArmorData.new()
	weave.display_name = "Test Weave"
	weave.granted_abilities = [_ability(Abilities.INSULATION[element])]
	return weave


# Armor that grants a real ability which is NOT insulation — the control for "it's the matching
# insulation that protects you, not merely wearing something that grants an ability."
func _armor_granting(id: Abilities.Id) -> ArmorData:
	var armor := ArmorData.new()
	armor.display_name = "Test Armor"
	armor.granted_abilities = [_ability(id)]
	return armor


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


# --- the carving half: the effect is stripped, the damage lands ---

func test_an_insulated_carving_lands_its_damage_and_none_of_its_effect() -> void:
	# The Weave has no DEF, so the bolt's whole number lands -- and nothing keyed on SHOCK can fire.
	var alch: Unit = _alchemist({ Elemental.Element.FIRE: 4 })
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	foe.worn_armor = _insulated_against(Elemental.Element.SHOCK)

	var atk := H.stamped_attack(alch, foe)
	atk.fired_attack = _lightning_bolt(5)
	var plan := ResolvedPlan.new()
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	assert_int(atk.resolved.damage).is_equal(9)   # power 5 + fire aura 4 -- NOT turned aside (#424)
	assert_array(atk.resolved.elements).is_empty()   # SHOCK never reached the target
	assert_bool(atk.resolved.insulated).is_true()


func test_the_same_carving_reaches_an_unarmored_target() -> void:
	# Control: the NUMBER is the same either way now, so what separates the two is whether the
	# element arrived -- the rail, the reactions and the states all key on that.
	var alch: Unit = _alchemist({ Elemental.Element.FIRE: 4 })
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})

	var atk := H.stamped_attack(alch, foe)
	atk.fired_attack = _lightning_bolt(5)
	var plan := ResolvedPlan.new()
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	assert_int(atk.resolved.damage).is_equal(9)
	assert_array(atk.resolved.elements).contains([Elemental.Element.SHOCK])
	assert_bool(atk.resolved.insulated).is_false()


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


# --- an insulated hit still ARRIVES (#424 repealed the 2026-07-24 turn-aside) ---

func test_an_insulated_bolt_still_finishes_a_downed_unit() -> void:
	# The sharpest consequence of the repeal: insulation is not a shield. A downed unit in the Weave
	# takes the bolt's number like any other hit, so the ordinary downed rule applies to it.
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

	assert_int(atk.resolved.damage).is_equal(9)
	assert_int(atk.resolved.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)


func test_an_unblocked_bolt_still_finishes_a_downed_unit() -> void:
	# Control: armor that grants an unrelated ability (TAUNT rather than IRON_WILL, so no damage cap
	# confounds the number) -- the same downed rule, the same answer.
	var alch: Unit = _alchemist({ Elemental.Element.FIRE: 4 })
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	foe.worn_armor = _armor_granting(Abilities.Id.TAUNT)
	foe.lifecycle_state = Unit.LifecycleState.DOWNED

	var atk := H.stamped_attack(alch, foe)
	atk.fired_attack = _lightning_bolt(5)
	var plan := ResolvedPlan.new()
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	assert_int(atk.resolved.lethality).is_equal(ResolvedOutcome.Lethality.KILLED)


func test_an_insulated_carving_still_arrives_and_shoves() -> void:
	# "Arrives" asserted on the thing the old branch withheld: the displacement stage runs, so a bolt
	# carrying knockback moves an insulated target -- while its effect is still stripped. A mutant
	# restoring the old early return reds this on the shove alone.
	var alch: Unit = _alchemist({ Elemental.Element.FIRE: 4 })
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50})
	foe.worn_armor = _insulated_against(Elemental.Element.SHOCK)
	var board := _sm.board_source.call() as BoardContext
	var no_reactions: Array[ElementalReaction] = []

	var bolt := H.stamped_attack(alch, foe)
	var carving := _lightning_bolt(5)
	carving.knockback = 1
	bolt.fired_attack = carving
	var plan := ResolvedPlan.new()
	plan.attacks.append(bolt)
	PlanResolver.resolve(plan, no_reactions, board)

	assert_int(bolt.resolved.damage).is_equal(9)
	assert_bool(bolt.resolved.knockback_applied).is_true()
	assert_array(bolt.resolved.states_added).is_empty()
	assert_int(bolt.resolved.target_hp_after).is_equal(foe.get_current_hp() - 9)


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
	# The Weave grants no DEF (that is its whole cost): an insulated bolt pays no mitigation at all, and
	# an unblocked element still pays full price. Immunity to the DAMAGE is DEF covering SHOCK (#424).
	var weave := _insulated_against(Elemental.Element.SHOCK)
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 50, Stats.Stat.CON: 9})
	foe.worn_armor = weave
	assert_int(foe.get_effective_def()).is_equal(0)
