# #30 slice B1: a rune-fired transmutation resolves through PlanResolver. The chosen carving
# rides on the AttackAction (action.transmutation); the resolver reads it as the attack SOURCE
# instead of the equipped weapon -- aura-scaled damage, its elements, and (targets MAP/BOTH) a
# terrain deposit. Proves a rune CAN fire end to end at the resolver layer, before any UI flow.
#
# Units are spawned via spawn_solo (each in its own squad) because the resolver's per-target
# hypothetical reads target.get_projected_destination(), which walks the squad's action queue.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const TREE_CELL := Vector2i(1, 0)

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# Terrain kinds authored directly -- the fixture grid has no TileSet to paint.
class _StubBoard extends BoardContext:
	var kinds: Dictionary
	func _init(g: TileMapLayer, u: Array[Unit], m: SquadManager, k: Dictionary) -> void:
		super(g, u, m)
		kinds = k
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return kinds.get(cell, Terrain.Kind.NONE)

func _alchemist(aura: Dictionary) -> Unit:
	var u: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	u.unit_instance.aura = aura
	return u

func _fireball(power: int, mode: EquippableData.TargetMode) -> TransmutationData:
	var t: TransmutationData = TransmutationData.new()
	t.power = power
	t.sigils.assign([Elemental.Element.FIRE])
	t.targets = mode
	return t

func _fire_burns_tree() -> TerrainReaction:
	var tr: TerrainReaction = TerrainReaction.new()
	tr.incoming_element = Elemental.Element.FIRE
	tr.required_kind = Terrain.Kind.TREE
	tr.add_tile_states.assign([Terrain.TileState.BURNING])
	return tr

# A fired transmutation scales off the wielder's AURA, not the equipped weapon's stat.
func test_transmutation_damage_scales_off_aura() -> void:
	var attacker: Unit = _alchemist({ Elemental.Element.FIRE: 4 })
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var atk: AttackAction = AttackAction.create(attacker, attacker.movement.cell, foe, Vector2i(1, 0))
	atk.transmutation = _fireball(5, EquippableData.TargetMode.UNIT)

	var plan: ResolvedPlan = ResolvedPlan.new()
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	assert_int(atk.resolved.damage).is_equal(9)   # power 5 + fire aura 4

# A fire transmutation flagged to hit the map ignites a tree -- the rune -> #50 loop.
func test_fire_transmutation_ignites_a_tree() -> void:
	var attacker: Unit = _alchemist({ Elemental.Element.FIRE: 4 })
	var atk: AttackAction = AttackAction.create(attacker, attacker.movement.cell, null, TREE_CELL)
	atk.transmutation = _fireball(5, EquippableData.TargetMode.BOTH)

	var plan: ResolvedPlan = ResolvedPlan.new()
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	var no_units: Array[Unit] = []
	var reactions: Array[TerrainReaction] = [_fire_burns_tree()]
	var board: _StubBoard = _StubBoard.new(null, no_units, null, { TREE_CELL: Terrain.Kind.TREE })
	PlanResolver.resolve(plan, no_reactions, board, reactions)

	assert_int(plan.cell_effects.size()).is_equal(1)
	assert_bool(plan.cell_effects[0].states_added.has(Terrain.TileState.BURNING)).is_true()

# A null transmutation falls back to the equipped weapon -- existing attacks are unchanged.
func test_no_transmutation_uses_the_weapon() -> void:
	var attacker: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))   # fixture weapon, power 3
	var foe: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var atk: AttackAction = AttackAction.create(attacker, attacker.movement.cell, foe, Vector2i(1, 0))

	var plan: ResolvedPlan = ResolvedPlan.new()
	plan.attacks.append(atk)
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions)

	assert_int(atk.resolved.damage).is_equal((attacker.get_equipped_weapon() as WeaponInstance).base_damage(attacker))

# --- B2: the in-game firing path (auto-select + resolve_plan propagation) ---

func _make_rune(carving: TransmutationData) -> RuneData:
	var rune: RuneData = RuneData.new()
	rune.size = RuneData.Size.MEDIUM
	rune.inscribe(carving)
	return rune

# A rune-wielder auto-selects its first channelable carving as what it would fire.
func test_get_fired_transmutation_auto_picks_first_channelable() -> void:
	var alch: Unit = _alchemist({ Elemental.Element.FIRE: 3 })
	var fireball: TransmutationData = _fireball(5, EquippableData.TargetMode.BOTH)
	alch.equipped_weapon = _make_rune(fireball)
	assert_object(alch.get_fired_transmutation()).is_same(fireball)

# An aim carrying a carving survives resolve_plan: the derived cell attack keeps it and fires
# aura-scaled, igniting the tree through the real terrain-reaction catalog (Burning.tres). The
# full firing path minus the UI click.
func test_rune_aim_fires_through_resolve_plan() -> void:
	var alch: Unit = _alchemist({ Elemental.Element.FIRE: 4 })
	var fireball: TransmutationData = _fireball(5, EquippableData.TargetMode.BOTH)
	alch.equipped_weapon = _make_rune(fireball)
	_sm.active_squad = alch.squad

	var aim: AttackAction = AttackAction.create(alch, alch.movement.cell, null, TREE_CELL)
	aim.transmutation = alch.get_fired_transmutation()
	alch.squad._queue_action(aim)

	var units: Array[Unit] = [alch]
	var board: _StubBoard = _StubBoard.new(_sm.grid, units, _sm, { TREE_CELL: Terrain.Kind.TREE })
	var plan: ResolvedPlan = _sm.resolve_plan(alch.squad, board)

	assert_int(plan.attacks.size()).is_equal(1)
	assert_object(plan.attacks[0].transmutation).is_same(fireball)   # propagated to the derived attack
	assert_int(plan.cell_effects.size()).is_equal(1)
	assert_bool(plan.cell_effects[0].states_added.has(Terrain.TileState.BURNING)).is_true()

# --- a rune-wielder counters by FIRING a channelable carving (TransmutationData.can_counter) ---

# The carving permits a counter, so the rune-wielder counters -- and the DERIVED counter carries
# the carving, so it hits aura-scaled, not as an unarmed punch. (Gate + stamping, end to end.)
func test_rune_wielder_counters_with_its_carving() -> void:
	var attacker: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var alch: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), { Stats.Stat.MHP: 50 })
	alch.unit_instance.aura = { Elemental.Element.FIRE: 4 }
	var fireball: TransmutationData = _fireball(5, EquippableData.TargetMode.UNIT)
	fireball.can_counter = true
	alch.equipped_weapon = _make_rune(fireball)
	_sm.active_squad = attacker.squad

	attacker.squad._queue_action(AttackAction.create(attacker, attacker.movement.cell, alch, alch.movement.cell))
	var units: Array[Unit] = [attacker, alch]
	var plan: ResolvedPlan = _sm.resolve_plan(attacker.squad, _StubBoard.new(_sm.grid, units, _sm, {}))

	assert_int(plan.counters.size()).is_equal(1)
	assert_object(plan.counters[0].transmutation).is_same(fireball)   # the counter fires the carving
	assert_int(plan.counters[0].resolved.damage).is_equal(9)          # aura-scaled (5 + fire 4), not a punch

# The same carving with can_counter = false: no counter. Proves the gate reads the CARVING's flag
# (a rune has no weapon to consult), the rune-side mirror of test_counters' C6 weapon case.
func test_rune_carving_can_counter_false_blocks_the_counter() -> void:
	var attacker: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var alch: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), { Stats.Stat.MHP: 50 })
	alch.unit_instance.aura = { Elemental.Element.FIRE: 4 }
	var fireball: TransmutationData = _fireball(5, EquippableData.TargetMode.UNIT)
	fireball.can_counter = false
	alch.equipped_weapon = _make_rune(fireball)
	_sm.active_squad = attacker.squad

	attacker.squad._queue_action(AttackAction.create(attacker, attacker.movement.cell, alch, alch.movement.cell))
	var units: Array[Unit] = [attacker, alch]
	var plan: ResolvedPlan = _sm.resolve_plan(attacker.squad, _StubBoard.new(_sm.grid, units, _sm, {}))

	assert_int(plan.counters.size()).is_equal(0)

# A rune AoE carving with hits_allies splashes a friendly in the blast -- the carving's flag is
# honored exactly like a weapon's, because gather_attack_victims reads the unified source. The
# AoE mirror of the counter symmetry above. #30.
func test_rune_carving_hits_allies_includes_a_friendly() -> void:
	var alch: Unit = _alchemist({ Elemental.Element.FIRE: 4 })
	var ally: Unit = H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 1))
	var fireball: TransmutationData = _fireball(5, EquippableData.TargetMode.UNIT)
	fireball.hits_allies = true
	alch.equipped_weapon = _make_rune(fireball)

	var units: Array[Unit] = [alch, ally]
	var victims := RulesService.gather_attack_victims(alch, [Vector2i(0, 1)], _StubBoard.new(_sm.grid, units, _sm, {}))
	assert_array(victims).contains([ally])
