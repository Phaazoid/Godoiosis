# Where gas comes from (#508): an attack that AUTHORS a gas leaves it on every tile it strikes, and a
# terrain reaction may release one -- water dousing fire, fire boiling water -- and since #1329 so may a
# reaction on a UNIT, fire drying a wet body. All of them
# arrive on the one cell-effect channel the resolver already fills, so the queue previews them and
# both executors play them.
#
# Resolver-level, test_douse.gd's board (kinds authored directly, no TileSet headlessly). The
# reaction cases run against the AUTHORED catalog and read every level off it, never a literal: the
# levels are the dev's to tune. The wire into the live store is test_gas_in_play.gd.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const PLAYER := Team.Faction.PLAYER
const TARGET_CELL := Vector2i(1, 0)
const STEAM := Gas.Kind.STEAM

class _KindBoard extends BoardContext:
	var kinds: Dictionary
	func _init(states: TerrainStateManager, k: Dictionary, grid_layer: TileMapLayer = null) -> void:
		var no_units: Array[Unit] = []
		super(grid_layer, no_units, null, states)
		kinds = k
	func terrain_kind_at(cell: Vector2i) -> Terrain.Kind:
		return kinds.get(cell, Terrain.Kind.NONE)


# Ground everywhere, standable nowhere: a field of wall tiles.
class _WallBoard extends _KindBoard:
	func has_ground(_cell: Vector2i) -> bool:
		return true
	func is_walkable(_cell: Vector2i) -> bool:
		return false


# Open, unburnable ground everywhere and every cell standable, so a shove has somewhere to land. A
# headless BoardContext with no grid otherwise reads every cell as a wall (test_soaking.gd's reason).
class _OpenBoard extends BoardContext:
	func _init(unit_list: Array[Unit]) -> void:
		super(null, unit_list, null, null)
	func terrain_kind_at(_cell: Vector2i) -> Terrain.Kind:
		return Terrain.Kind.DIRT
	func is_walkable(_cell: Vector2i) -> bool:
		return true


func _attacker(element: Elemental.Element, targets: EquippableData.TargetMode) -> Unit:
	var u: Unit = H.spawn_unit(self, PLAYER, Vector2i(0, 0))
	var attack := (u.get_equipped_weapon() as WeaponInstance).template.main_attack
	attack.elemental_damage_type = element
	attack.targets = targets
	return u


func _store_with(state: Terrain.TileState) -> TerrainStateManager:
	var tsm: TerrainStateManager = auto_free(TerrainStateManager.new())
	add_child(tsm)
	var seed_effect := ResolvedCellEffect.new()
	seed_effect.cell = TARGET_CELL
	seed_effect.states_added.assign([state])
	tsm.apply(seed_effect)
	return tsm


func _aim(attacker: Unit, struck: Array[Vector2i]) -> AttackAction:
	var aim := AttackAction.create(attacker, attacker.movement.cell, null, TARGET_CELL)
	aim.fired_attack = attacker.get_fired_attack()
	aim.struck_cells = struck   # what the volley builder stamps (#1057); the deposit reads only this
	return aim


func _one(aim: AttackAction) -> Array[AttackAction]:
	var attacks: Array[AttackAction] = [aim]
	return attacks


func _resolve(attacks: Array[AttackAction], board: BoardContext) -> ResolvedPlan:
	var plan := ResolvedPlan.new()
	plan.attacks = attacks
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions, board, TerrainReactionCatalog.get_all())
	return plan


func _steam_on(plan: ResolvedPlan, cell: Vector2i) -> int:
	var total := 0
	for effect in plan.cell_effects:
		if effect.cell == cell:
			var amount: int = effect.gas_added.get(STEAM, 0)
			total += amount
	return total


# The one authored reaction matching `pick`, failing loudly when the catalog has none: a case about a
# reaction the content no longer carries is vacuous, not passing.
func _authored(pick: Callable, what: String) -> TerrainReaction:
	for reaction in TerrainReactionCatalog.get_all():
		if pick.call(reaction):
			return reaction
	assert_bool(false).override_failure_message("no authored reaction %s -- point this case at one the catalog has" % what).is_true()
	return null


# --- an attack's own gas -------------------------------------------------------------------------

func test_an_attack_leaves_its_gas_on_every_tile_it_strikes_whatever_its_targets() -> void:
	# A unit-only, elementless attack: neither half of the old deposit gate would let it touch the map.
	var attacker := _attacker(Elemental.Element.NONE, EquippableData.TargetMode.UNIT)
	attacker.get_fired_attack().gas_level = Gas.Level.MEDIUM
	var struck: Array[Vector2i] = [Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)]
	var plan := _resolve(_one(_aim(attacker, struck)), _KindBoard.new(null, {}))
	assert_int(plan.cell_effects.size()).is_equal(struck.size())
	for cell in struck:
		assert_int(_steam_on(plan, cell)).override_failure_message("no steam on struck %s" % [cell]).is_equal(Gas.Level.MEDIUM)
	for effect in plan.cell_effects:
		assert_bool(effect.states_added.is_empty() and effect.states_removed.is_empty()).is_true()


func test_an_attack_with_no_gas_leaves_none() -> void:
	var attacker := _attacker(Elemental.Element.NONE, EquippableData.TargetMode.BOTH)
	var struck: Array[Vector2i] = [TARGET_CELL]
	var plan := _resolve(_one(_aim(attacker, struck)), _KindBoard.new(null, {}))
	assert_int(plan.cell_effects.size()).is_equal(0)


func test_gas_never_lands_where_there_is_no_ground() -> void:
	# A bare TileMapLayer holds no tiles, so every cell on it is groundless: the store would refuse the
	# gas, and the preview must not promise it.
	var bare: TileMapLayer = auto_free(TileMapLayer.new())
	add_child(bare)
	var attacker := _attacker(Elemental.Element.NONE, EquippableData.TargetMode.UNIT)
	attacker.get_fired_attack().gas_level = Gas.Level.MEDIUM
	var struck: Array[Vector2i] = [TARGET_CELL]
	var plan := _resolve(_one(_aim(attacker, struck)), _KindBoard.new(null, {}, bare))
	assert_int(plan.cell_effects.size()).is_equal(0)


func test_a_tile_a_unit_could_not_stand_on_takes_no_gas() -> void:
	# A wall tile has ground, but gas travels only where a unit could walk or over water (ruling 6), so
	# it is never laid there either (GasSpread.holds_gas).
	var bare: TileMapLayer = auto_free(TileMapLayer.new())
	add_child(bare)
	var attacker := _attacker(Elemental.Element.NONE, EquippableData.TargetMode.UNIT)
	attacker.get_fired_attack().gas_level = Gas.Level.MEDIUM
	var struck: Array[Vector2i] = [TARGET_CELL]
	var plan := _resolve(_one(_aim(attacker, struck)), _WallBoard.new(null, {}, bare))
	assert_int(plan.cell_effects.size()).is_equal(0)


func test_a_volley_leaves_its_gas_once_not_once_per_victim() -> void:
	# THIN, so a second deposit would read MEDIUM rather than vanish under the cap at thick.
	var attacker := _attacker(Elemental.Element.NONE, EquippableData.TargetMode.UNIT)
	attacker.get_fired_attack().gas_level = Gas.Level.THIN
	var struck: Array[Vector2i] = [TARGET_CELL]
	var lead := _aim(attacker, struck)
	var second := _aim(attacker, struck)
	second.is_secondary_hit = true
	var volley: Array[AttackAction] = [lead, second]
	lead.volley = volley
	second.volley = volley
	var plan := _resolve(volley, _KindBoard.new(null, {}))
	assert_int(_steam_on(plan, TARGET_CELL)).is_equal(Gas.Level.THIN)


# --- reactions release it ------------------------------------------------------------------------

func test_water_dousing_a_fire_releases_steam() -> void:
	var douse := _authored(func(r: TerrainReaction) -> bool:
		return r.incoming_element == Elemental.Element.WATER \
			and r.required_tile_state == Terrain.TileState.BURNING and r.gas_level != Gas.Level.NONE,
		"puts out fire and releases gas")
	var attacker := _attacker(Elemental.Element.WATER, EquippableData.TargetMode.MAP)
	var struck: Array[Vector2i] = [TARGET_CELL]
	var board := _KindBoard.new(_store_with(Terrain.TileState.BURNING), { TARGET_CELL: Terrain.Kind.GRASS })
	var plan := _resolve(_one(_aim(attacker, struck)), board)
	assert_int(plan.cell_effects.size()).is_equal(1)
	assert_bool(plan.cell_effects[0].states_removed.has(Terrain.TileState.BURNING)).is_true()
	assert_int(plan.cell_effects[0].gas_added.get(douse.gas, 0)).is_equal(douse.gas_level)


func test_fire_on_open_water_boils_it() -> void:
	var boils := _authored(func(r: TerrainReaction) -> bool:
		return r.incoming_element == Elemental.Element.FIRE \
			and r.required_kind == Terrain.Kind.WATER and r.gas_level != Gas.Level.NONE,
		"boils water")
	var attacker := _attacker(Elemental.Element.FIRE, EquippableData.TargetMode.MAP)
	var struck: Array[Vector2i] = [TARGET_CELL]
	var plan := _resolve(_one(_aim(attacker, struck)), _KindBoard.new(null, { TARGET_CELL: Terrain.Kind.WATER }))
	assert_int(plan.cell_effects.size()).is_equal(1)
	assert_int(plan.cell_effects[0].gas_added.get(boils.gas, 0)).is_equal(boils.gas_level)


# Frozen water MELTS and does not also boil: whatever steam the cell gets is the melt's own. Since
# #508 ruling 22 that is none -- the ice leaves water, and only a second fire hit boils it.
func test_fire_on_frozen_water_melts_it_and_does_not_boil_it() -> void:
	var melt := _authored(func(r: TerrainReaction) -> bool:
		return r.incoming_element == Elemental.Element.FIRE \
			and r.required_tile_state == Terrain.TileState.FROZEN,
		"melts ice")
	var attacker := _attacker(Elemental.Element.FIRE, EquippableData.TargetMode.MAP)
	var struck: Array[Vector2i] = [TARGET_CELL]
	var board := _KindBoard.new(_store_with(Terrain.TileState.FROZEN), { TARGET_CELL: Terrain.Kind.WATER })
	var plan := _resolve(_one(_aim(attacker, struck)), board)
	assert_int(plan.cell_effects.size()).is_equal(1)
	assert_bool(plan.cell_effects[0].states_removed.has(Terrain.TileState.FROZEN)).is_true()
	assert_int(plan.cell_effects[0].gas_added.get(melt.gas, 0)).override_failure_message(
			"frozen water gave more steam than the melt alone -- it boiled as well").is_equal(melt.gas_level)


func test_a_reaction_that_only_releases_gas_still_names_itself_on_the_tile_card() -> void:
	# Glossary.terrain_reactions_for skips a reaction with nothing to say; releasing gas is something.
	var lines := Glossary.terrain_reactions_for(Terrain.Kind.WATER, [] as Array[Terrain.TileState])
	var named := false
	for line in lines:
		if line.contains(Gas.display_name(STEAM)):
			named = true
	assert_bool(named).override_failure_message("water's interactions never mention steam: %s" % [lines]).is_true()


# --- a reaction on a UNIT releases it (#1329) ------------------------------------------------------

# The authored reaction that dries a wet unit with fire and releases gas, failing loudly when the
# catalog has none (the _authored rule above, for the unit catalog).
func _unit_release() -> ElementalReaction:
	var fire: Array[Elemental.Element] = [Elemental.Element.FIRE]
	for reaction in ReactionCatalog.get_all():
		if reaction.fires_for(fire) and reaction.required_state == Elemental.State.WET \
				and reaction.remove_states.has(Elemental.State.WET) and reaction.gas_level != Gas.Level.NONE:
			return reaction
	assert_bool(false).override_failure_message("no authored reaction dries a wet unit and releases gas -- point this case at one the catalog has").is_true()
	return null


func _fire_at(target_cell: Vector2i, wet: bool) -> Array[Unit]:
	var attacker := _attacker(Elemental.Element.FIRE, EquippableData.TargetMode.UNIT)
	var target: Unit = H.spawn_unit(self, Team.Faction.ENEMY, target_cell, {Stats.Stat.MHP: 50})
	if wet:
		target.add_element_state(Elemental.State.WET)
	var pair: Array[Unit] = [attacker, target]
	return pair


func _resolve_on_units(attacks: Array[AttackAction], units: Array[Unit]) -> ResolvedPlan:
	var plan := ResolvedPlan.new()
	plan.attacks = attacks
	PlanResolver.resolve(plan, ReactionCatalog.get_all(), _OpenBoard.new(units), TerrainReactionCatalog.get_all())
	return plan


func _gas_on(plan: ResolvedPlan, cell: Vector2i, kind: Gas.Kind) -> int:
	var total := 0
	for effect in plan.cell_effects:
		if effect.cell == cell:
			var level: int = effect.gas_added.get(kind, 0)
			total += level
	return total


# The dry twin is what gives it teeth: a release on every fire hit would pass the wet half alone.
func test_fire_drying_a_wet_unit_releases_its_water_on_that_units_cell() -> void:
	var release := _unit_release()
	var wet := _fire_at(TARGET_CELL, true)
	var plan := _resolve_on_units(_one(H.stamped_attack(wet[0], wet[1])), wet)
	assert_bool(plan.attacks[0].resolved.states_removed.has(Elemental.State.WET)).is_true()
	assert_int(_gas_on(plan, TARGET_CELL, release.gas)).is_equal(release.gas_level)

	var dry := _fire_at(TARGET_CELL, false)
	var dry_plan := _resolve_on_units(_one(H.stamped_attack(dry[0], dry[1])), dry)
	assert_int(dry_plan.cell_effects.size()).override_failure_message(
			"a fire hit on a DRY unit released gas").is_equal(0)


# Where the fire met the water, not where the hit throws the body (dev, 2026-10-19). Ordering: the
# release must be read before the shove is threaded into the hypo.
func test_the_steam_rises_where_the_unit_was_hit_not_where_a_shove_lands_it() -> void:
	var release := _unit_release()
	var units := _fire_at(TARGET_CELL, true)
	var shove := H.stamped_attack(units[0], units[1])
	shove.fired_attack.knockback = 2
	var plan := _resolve_on_units(_one(shove), units)
	var landed: Vector2i = shove.resolved.knockback_to
	assert_bool(shove.resolved.knockback_applied and landed != TARGET_CELL).override_failure_message(
			"the shove never moved the target, so this case cannot tell the two cells apart").is_true()
	assert_int(_gas_on(plan, TARGET_CELL, release.gas)).is_equal(release.gas_level)
	assert_int(_gas_on(plan, landed, release.gas)).is_equal(0)


# Each victim's water is its own, so a volley releases once per wet victim -- where an attack's own gas
# lands once per volley (test_a_volley_leaves_its_gas_once_not_once_per_victim).
func test_each_wet_victim_of_one_volley_releases_its_own_steam() -> void:
	var release := _unit_release()
	var units := _fire_at(TARGET_CELL, true)
	var second_cell := TARGET_CELL + Vector2i(0, 1)
	var second_target: Unit = H.spawn_unit(self, Team.Faction.ENEMY, second_cell, {Stats.Stat.MHP: 50})
	second_target.add_element_state(Elemental.State.WET)
	units.append(second_target)
	var lead := H.stamped_attack(units[0], units[1])
	var second := H.stamped_attack(units[0], second_target)
	second.is_secondary_hit = true
	var volley: Array[AttackAction] = [lead, second]
	lead.volley = volley
	second.volley = volley
	var plan := _resolve_on_units(volley, units)
	assert_int(_gas_on(plan, TARGET_CELL, release.gas)).is_equal(release.gas_level)
	assert_int(_gas_on(plan, second_cell, release.gas)).is_equal(release.gas_level)


func test_a_unit_reaction_that_releases_gas_says_so_in_its_line() -> void:
	var reaction := ElementalReaction.new()
	reaction.incoming_element = Elemental.Element.FIRE
	reaction.required_state = Elemental.State.WET
	reaction.gas_level = Gas.Level.THIN
	assert_str(Glossary.reaction_line(reaction)).contains(Gas.display_name(reaction.gas))
	reaction.gas_level = Gas.Level.NONE
	assert_str(Glossary.reaction_line(reaction)).not_contains(Gas.display_name(reaction.gas))
