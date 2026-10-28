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


# Open ground everywhere but `walls`, on a real (empty) grid so GasSpread judges where gas may go: a
# gridless board waves every crossing through (#1332).
class _RoomBoard extends _KindBoard:
	var walls: Array[Vector2i] = []
	func has_ground(_cell: Vector2i) -> bool:
		return true
	func is_void_at(_cell: Vector2i) -> bool:
		return false
	func is_walkable(cell: Vector2i) -> bool:
		return not walls.has(cell)


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
	attacker.get_fired_attack().gases = {STEAM: Gas.Level.MEDIUM}
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
	attacker.get_fired_attack().gases = {STEAM: Gas.Level.MEDIUM}
	var struck: Array[Vector2i] = [TARGET_CELL]
	var plan := _resolve(_one(_aim(attacker, struck)), _KindBoard.new(null, {}, bare))
	assert_int(plan.cell_effects.size()).is_equal(0)


func test_a_tile_a_unit_could_not_stand_on_takes_no_gas() -> void:
	# A wall tile has ground, but gas travels only where a unit could walk or over water (ruling 6), so
	# it is never laid there either (GasSpread.holds_gas).
	var bare: TileMapLayer = auto_free(TileMapLayer.new())
	add_child(bare)
	var attacker := _attacker(Elemental.Element.NONE, EquippableData.TargetMode.UNIT)
	attacker.get_fired_attack().gases = {STEAM: Gas.Level.MEDIUM}
	var struck: Array[Vector2i] = [TARGET_CELL]
	var plan := _resolve(_one(_aim(attacker, struck)), _WallBoard.new(null, {}, bare))
	assert_int(plan.cell_effects.size()).is_equal(0)


func test_a_volley_leaves_its_gas_once_not_once_per_victim() -> void:
	# THIN, so a second deposit would read MEDIUM rather than vanish under the cap at thick.
	var attacker := _attacker(Elemental.Element.NONE, EquippableData.TargetMode.UNIT)
	attacker.get_fired_attack().gases = {STEAM: Gas.Level.THIN}
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
			and r.required_tile_state == Terrain.TileState.BURNING and not Gas.released(r.gases).is_empty(),
		"puts out fire and releases gas")
	var attacker := _attacker(Elemental.Element.WATER, EquippableData.TargetMode.MAP)
	var struck: Array[Vector2i] = [TARGET_CELL]
	var board := _KindBoard.new(_store_with(Terrain.TileState.BURNING), { TARGET_CELL: Terrain.Kind.GRASS })
	var plan := _resolve(_one(_aim(attacker, struck)), board)
	assert_int(plan.cell_effects.size()).is_equal(1)
	assert_bool(plan.cell_effects[0].states_removed.has(Terrain.TileState.BURNING)).is_true()
	_assert_releases(plan.cell_effects[0], douse.gases)


func test_fire_on_open_water_boils_it() -> void:
	var boils := _authored(func(r: TerrainReaction) -> bool:
		return r.incoming_element == Elemental.Element.FIRE \
			and r.required_kind == Terrain.Kind.WATER and not Gas.released(r.gases).is_empty(),
		"boils water")
	var attacker := _attacker(Elemental.Element.FIRE, EquippableData.TargetMode.MAP)
	var struck: Array[Vector2i] = [TARGET_CELL]
	var plan := _resolve(_one(_aim(attacker, struck)), _KindBoard.new(null, { TARGET_CELL: Terrain.Kind.WATER }))
	assert_int(plan.cell_effects.size()).is_equal(1)
	_assert_releases(plan.cell_effects[0], boils.gases)


func _melt() -> TerrainReaction:
	return _authored(func(r: TerrainReaction) -> bool:
		return r.incoming_element == Elemental.Element.FIRE \
			and r.required_tile_state == Terrain.TileState.FROZEN,
		"melts ice")


func _melt_frozen_water() -> ResolvedPlan:
	var attacker := _attacker(Elemental.Element.FIRE, EquippableData.TargetMode.MAP)
	var struck: Array[Vector2i] = [TARGET_CELL]
	var board := _KindBoard.new(_store_with(Terrain.TileState.FROZEN), { TARGET_CELL: Terrain.Kind.WATER })
	return _resolve(_one(_aim(attacker, struck)), board)


# Frozen water MELTS and does not also boil: whatever steam the cell gets is the melt's own. Since
# #508 ruling 22 that is none -- the ice leaves water, and only a second fire hit boils it.
func test_fire_on_frozen_water_melts_it_and_does_not_boil_it() -> void:
	var melt := _melt()
	var plan := _melt_frozen_water()
	assert_int(plan.cell_effects.size()).is_equal(1)
	assert_bool(plan.cell_effects[0].states_removed.has(Terrain.TileState.FROZEN)).is_true()
	assert_int(_steam_on(plan, TARGET_CELL)).override_failure_message(
			"frozen water gave more steam than the melt alone -- it boiled as well") \
			.is_equal(int(melt.gases.get(STEAM, Gas.Level.NONE)))


# The melt releases what its equation makes (#1324): the essence the ice held, `F2 + 2QW -> Q2 + ...`.
func test_melting_ice_releases_the_melts_own_gas_on_the_thawed_tile() -> void:
	var melt := _melt()
	assert_bool(Gas.released(melt.gases).is_empty()).override_failure_message("fixture: the authored melt releases no gas").is_false()
	var plan := _melt_frozen_water()
	_assert_releases(plan.cell_effects[0], melt.gases)


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
				and reaction.remove_states.has(Elemental.State.WET) and not Gas.released(reaction.gases).is_empty():
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
	_assert_gas_on(plan, TARGET_CELL, release.gases)

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
	_assert_gas_on(plan, TARGET_CELL, release.gases)
	for kind: Gas.Kind in Gas.released(release.gases):
		assert_int(_gas_on(plan, landed, kind)).is_equal(0)


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
	_assert_gas_on(plan, TARGET_CELL, release.gases)
	_assert_gas_on(plan, second_cell, release.gases)


func test_a_unit_reaction_that_releases_gas_says_so_in_its_line() -> void:
	var reaction := ElementalReaction.new()
	reaction.incoming_element = Elemental.Element.FIRE
	reaction.required_state = Elemental.State.WET
	reaction.gases = {STEAM: Gas.Level.THIN}
	assert_str(Glossary.reaction_line(reaction)).contains(Gas.display_name(STEAM))
	reaction.gases = {}
	assert_str(Glossary.reaction_line(reaction)).not_contains(Gas.display_name(STEAM))


# Every gas a holder's `gases` releases, at its authored level, on one effect.
func _assert_releases(effect: ResolvedCellEffect, gases: Dictionary[Gas.Kind, Gas.Level]) -> void:
	for kind: Gas.Kind in Gas.released(gases):
		assert_int(effect.gas_added.get(kind, 0)).is_equal(gases[kind])


# The same, summed over a plan's effects on one cell.
func _assert_gas_on(plan: ResolvedPlan, cell: Vector2i, gases: Dictionary[Gas.Kind, Gas.Level]) -> void:
	for kind: Gas.Kind in Gas.released(gases):
		assert_int(_gas_on(plan, cell, kind)).is_equal(gases[kind])


# --- an Air hit disperses it (#1335) ---------------------------------------------------------------

func _disperse() -> TerrainReaction:
	return _authored(func(r: TerrainReaction) -> bool:
		return r.in_the_air and r.disperses_gas, "disperses gas in the air")


func _gassy_board() -> _KindBoard:
	var board := _KindBoard.new(null, {})
	board.gas = GasField.new()
	board.gas.set_level(TARGET_CELL, STEAM, Gas.Level.MEDIUM)
	board.gas.set_level(TARGET_CELL, Gas.Kind.SMOKE, Gas.Level.THICK)
	return board


# In the AIR, so a UNIT-only attack clears the cells it strikes too, and only where there is gas: the
# clear second cell takes nothing, not an empty effect. This hit shoves nobody, so nothing is blown.
func test_an_air_hit_that_shoves_nobody_disperses_every_gas_on_the_cells_it_strikes_whatever_its_targets() -> void:
	var disperse := _disperse()
	var attacker := _attacker(disperse.incoming_element, EquippableData.TargetMode.UNIT)
	assert_int(attacker.get_attack_knockback(attacker.get_fired_attack())).override_failure_message(
			"fixture: this hit shoves, so it would blow the gas rather than disperse it").is_equal(0)
	var clear_cell := TARGET_CELL + Vector2i(1, 0)
	var struck: Array[Vector2i] = [TARGET_CELL, clear_cell]
	var board := _gassy_board()
	var plan := _resolve(_one(_aim(attacker, struck)), board)
	assert_int(plan.cell_effects.size()).is_equal(1)
	assert_that(plan.cell_effects[0].cell).is_equal(TARGET_CELL)
	assert_bool(plan.cell_effects[0].gas_cleared).is_true()
	# The preview, the forecast's fold and the store all say the same thing (Law #2).
	assert_bool(plan.pending_deposits().has({"cell": TARGET_CELL, "clears_gas": true})).override_failure_message(
			"the board would not show the gas going before Execute").is_true()
	assert_int(board.planned(plan.tiles).gas_at(TARGET_CELL)).is_equal(0)
	board.gas.apply(plan.cell_effects[0])
	assert_int(board.gas.packed_at(TARGET_CELL)).is_equal(0)


func test_an_element_the_air_reaction_does_not_answer_clears_nothing() -> void:
	var attacker := _attacker(Elemental.Element.EARTH, EquippableData.TargetMode.UNIT)
	assert_bool(_disperse().fires_for([Elemental.Element.EARTH] as Array[Elemental.Element])).override_failure_message(
			"fixture: earth disperses gas now -- pick an element that does not").is_false()
	var struck: Array[Vector2i] = [TARGET_CELL]
	var plan := _resolve(_one(_aim(attacker, struck)), _gassy_board())
	assert_int(plan.cell_effects.size()).is_equal(0)


# EVERY kind goes, the ones that move the air included, and the cell then reads the board's own air: a
# cleared cell returns to the level's normal reading (Phaazoid@, #1427). The gas goes, never the air
# reading itself (c3potheds@, #1335).
func test_an_air_hit_clears_every_kind_and_the_cell_reads_the_boards_own_air_again() -> void:
	var disperse := _disperse()
	var attacker := _attacker(disperse.incoming_element, EquippableData.TargetMode.UNIT)
	assert_int(attacker.get_attack_knockback(attacker.get_fired_attack())).override_failure_message(
			"fixture: this hit shoves, so it would blow the gas rather than disperse it").is_equal(0)
	var board := _KindBoard.new(null, {})
	board.gas = GasField.new()
	for kind: Gas.Kind in Gas.Kind.values():
		board.gas.set_level(TARGET_CELL, kind, Gas.Level.THICK)
	assert_array(Atmosphere.differs(board.air_at(TARGET_CELL), board.atmosphere)).override_failure_message(
			"fixture: no gas moves the air, so the reading half is unchecked").is_not_empty()
	var struck: Array[Vector2i] = [TARGET_CELL]
	var plan := _resolve(_one(_aim(attacker, struck)), board)
	assert_int(plan.cell_effects.size()).is_equal(1)
	board.gas.apply(plan.cell_effects[0])
	assert_array(Gas.kinds_in(board.gas.packed_at(TARGET_CELL))).override_failure_message(
			"an Air hit left these kinds behind").is_empty()
	assert_dict(board.air_at(TARGET_CELL)).is_equal(board.atmosphere)


# Cleared FIRST: what the same effect releases lands after, so dispersal never eats its own hit's gas.
func test_a_cleared_cell_keeps_the_gas_its_own_effect_releases() -> void:
	var field := GasField.new()
	field.set_level(TARGET_CELL, Gas.Kind.SMOKE, Gas.Level.THICK)
	var effect := ResolvedCellEffect.new()
	effect.cell = TARGET_CELL
	effect.gas_cleared = true
	effect.add_gas(STEAM, Gas.Level.THIN)
	var want := Gas.with_level(0, STEAM, Gas.Level.THIN)
	assert_int(GasField.fold(field.packed_at(TARGET_CELL), effect)).is_equal(want)
	field.apply(effect)
	assert_int(Gas.level_in(field.packed_at(TARGET_CELL), Gas.Kind.SMOKE)).is_equal(0)
	assert_int(Gas.level_in(field.packed_at(TARGET_CELL), STEAM)).is_equal(Gas.Level.THIN)


# --- a hit that shoves blows it instead (#1332) ----------------------------------------------------

func _room(walls: Array[Vector2i] = []) -> _RoomBoard:
	var bare: TileMapLayer = auto_free(TileMapLayer.new())
	add_child(bare)
	var board := _RoomBoard.new(null, {}, bare)
	board.walls = walls
	board.gas = GasField.new()
	return board


# An Air attacker at the origin whose hit shoves `tiles`; _aim points it at TARGET_CELL.
func _blower(tiles: int) -> Unit:
	var attacker := _attacker(_disperse().incoming_element, EquippableData.TargetMode.UNIT)
	attacker.get_fired_attack().knockback = tiles
	assert_int(attacker.get_attack_knockback(attacker.get_fired_attack())).override_failure_message(
			"fixture: the hit does not shove %d" % tiles).is_equal(tiles)
	return attacker


# The way a unit standing on `cell` would be shoved by `attacker`'s hit.
func _away(attacker: Unit, cell: Vector2i) -> Vector2i:
	return GridUtils.cardinal_direction_i_between(attacker.movement.cell, cell)


# A packed cell's levels by kind, so a restarted hold does not read as a difference.
func _levels(packed: int) -> Dictionary:
	var out := {}
	for kind: Gas.Kind in Gas.kinds_in(packed):
		out[kind] = Gas.level_in(packed, kind)
	return out


# The plan's cell effects played into the board's store in order, as both executors play them.
func _play(plan: ResolvedPlan, board: BoardContext) -> void:
	for effect in plan.cell_effects:
		board.gas.apply(effect)


# Every kind on the tile, at its level, as far as the hit shoves and away from the caster -- and the
# preview, the fold every forecast reads and the store all say the same thing (Law #2).
func test_a_shoving_air_hit_blows_every_gas_on_the_tile_as_far_as_it_shoves() -> void:
	var attacker := _blower(2)
	var board := _gassy_board()
	var before := _levels(board.gas.packed_at(TARGET_CELL))
	var landing := TARGET_CELL + _away(attacker, TARGET_CELL) * 2
	var struck: Array[Vector2i] = [TARGET_CELL]
	var plan := _resolve(_one(_aim(attacker, struck)), board)
	var deposits := plan.pending_deposits()
	assert_bool(deposits.has({"cell": TARGET_CELL, "clears_gas": true})).override_failure_message(
			"the board would not show the gas leaving before Execute").is_true()
	for kind: Gas.Kind in before:
		assert_bool(deposits.has({"cell": landing, "gas": kind})).override_failure_message(
				"the board would not show %s landing on %s" % [Gas.name_of(kind), landing]).is_true()
	assert_int(board.planned(plan.tiles).gas_at(TARGET_CELL)).is_equal(0)
	assert_dict(_levels(board.planned(plan.tiles).gas_at(landing))).is_equal(before)
	_play(plan, board)
	assert_int(board.gas.packed_at(TARGET_CELL)).is_equal(0)
	assert_dict(_levels(board.gas.packed_at(landing))).is_equal(before)


# It walks through GasSpread.can_cross, the round's spread rule, and rests on the last tile it reached:
# a wall two tiles on stops a three-tile shove after one.
func test_blown_gas_stops_on_the_last_tile_it_can_cross() -> void:
	var attacker := _blower(3)
	var away := _away(attacker, TARGET_CELL)
	var walls: Array[Vector2i] = [TARGET_CELL + away * 2]
	var board := _room(walls)
	board.gas.set_level(TARGET_CELL, Gas.Kind.SMOKE, Gas.Level.MEDIUM)
	assert_bool(GasSpread.can_cross(TARGET_CELL, TARGET_CELL + away, board)).override_failure_message(
			"fixture: the first step is refused too").is_true()
	assert_bool(GasSpread.can_cross(TARGET_CELL + away, walls[0], board)).override_failure_message(
			"fixture: gas may cross onto the wall").is_false()
	var struck: Array[Vector2i] = [TARGET_CELL]
	_play(_resolve(_one(_aim(attacker, struck)), board), board)
	assert_int(board.gas.packed_at(TARGET_CELL)).is_equal(0)
	assert_int(board.gas.level_at(TARGET_CELL + away, Gas.Kind.SMOKE)).override_failure_message(
			"the gas did not come to rest against the wall").is_equal(Gas.Level.MEDIUM)
	assert_int(board.gas.packed_at(walls[0])).is_equal(0)


# With no room to move at all it disperses, as gas a hit that shoves nobody strikes does: pinned against
# a wall, or on the tile the hit came from, where it has no line to follow.
func test_blown_gas_with_no_room_to_move_disperses() -> void:
	var attacker := _blower(2)
	var walls: Array[Vector2i] = [TARGET_CELL + _away(attacker, TARGET_CELL)]
	var board := _room(walls)
	var origin := attacker.movement.cell
	board.gas.set_level(TARGET_CELL, Gas.Kind.SMOKE, Gas.Level.MEDIUM)
	board.gas.set_level(origin, STEAM, Gas.Level.MEDIUM)
	var struck: Array[Vector2i] = [TARGET_CELL, origin]
	var plan := _resolve(_one(_aim(attacker, struck)), board)
	assert_int(plan.cell_effects.size()).override_failure_message(
			"gas with nowhere to go was laid somewhere").is_equal(struck.size())
	_play(plan, board)
	assert_bool(board.gas.is_empty()).override_failure_message("gas with no room to move survived the hit").is_true()


# The deposit rule where it lands: levels add per kind, capped at thick -- thin onto thin is medium, and
# thick onto medium stays thick. The fold the forecasts read agrees with the store.
func test_blown_gas_adds_to_what_it_lands_on_capped_at_thick() -> void:
	var attacker := _blower(1)
	var landing := TARGET_CELL + _away(attacker, TARGET_CELL)
	var board := _room()
	board.gas.set_level(TARGET_CELL, Gas.Kind.SMOKE, Gas.Level.THIN)
	board.gas.set_level(TARGET_CELL, STEAM, Gas.Level.THICK)
	board.gas.set_level(landing, Gas.Kind.SMOKE, Gas.Level.THIN)
	board.gas.set_level(landing, STEAM, Gas.Level.MEDIUM)
	var struck: Array[Vector2i] = [TARGET_CELL]
	var plan := _resolve(_one(_aim(attacker, struck)), board)
	var projected := board.planned(plan.tiles).gas_at(landing)
	_play(plan, board)
	assert_int(board.gas.level_at(landing, Gas.Kind.SMOKE)).is_equal(Gas.Level.MEDIUM)
	assert_int(board.gas.level_at(landing, STEAM)).is_equal(Gas.Level.THICK)
	assert_int(board.gas.packed_at(landing)).is_equal(projected)


# A cloud across a struck line shifts intact: every tile is read before any gas moves, and a tile's own
# gas leaves before what is blown onto it lands.
func test_a_struck_line_of_gas_shifts_intact() -> void:
	var attacker := _blower(1)
	var away := _away(attacker, TARGET_CELL)
	var near := TARGET_CELL
	var far := TARGET_CELL + away
	var board := _room()
	board.gas.set_level(near, Gas.Kind.SMOKE, Gas.Level.THIN)
	board.gas.set_level(far, STEAM, Gas.Level.MEDIUM)
	var struck: Array[Vector2i] = [near, far]
	_play(_resolve(_one(_aim(attacker, struck)), board), board)
	assert_int(board.gas.packed_at(near)).is_equal(0)
	assert_dict(_levels(board.gas.packed_at(far))).override_failure_message(
			"the far tile lost what the near one blew onto it, or kept its own").is_equal({Gas.Kind.SMOKE: Gas.Level.THIN})
	assert_dict(_levels(board.gas.packed_at(far + away))).is_equal({STEAM: Gas.Level.MEDIUM})


# The gas is read as the PASS leaves it: steam an earlier order in the same plan laid is blown on, which
# is what the batch apply plays.
func test_a_shoving_air_hit_blows_gas_an_earlier_order_in_the_same_plan_left() -> void:
	var steamer := _attacker(Elemental.Element.NONE, EquippableData.TargetMode.UNIT)
	steamer.get_fired_attack().gases = {STEAM: Gas.Level.MEDIUM}
	var attacker := _blower(1)
	var landing := TARGET_CELL + _away(attacker, TARGET_CELL)
	var board := _room()
	var struck: Array[Vector2i] = [TARGET_CELL]
	var attacks: Array[AttackAction] = [_aim(steamer, struck), _aim(attacker, struck)]
	var plan := _resolve(attacks, board)
	assert_int(board.planned(plan.tiles).gas_at(TARGET_CELL)).is_equal(0)
	assert_int(Gas.level_in(board.planned(plan.tiles).gas_at(landing), STEAM)).override_failure_message(
			"the Air hit read the board as it stood, not the steam the order before it left").is_equal(Gas.Level.MEDIUM)
	_play(plan, board)
	assert_int(board.gas.packed_at(TARGET_CELL)).is_equal(0)
	assert_int(board.gas.level_at(landing, STEAM)).is_equal(Gas.Level.MEDIUM)


# --- a shock hit makes ozone (#1335) --------------------------------------------------------------

func _ozone() -> TerrainReaction:
	return _authored(func(r: TerrainReaction) -> bool:
		return r.in_the_air and r.fires_for([Elemental.Element.SHOCK] as Array[Elemental.Element]) \
			and Gas.released(r.gases).has(Gas.Kind.OZONE), "makes ozone from a shock in the air")


func _link(from: Vector2i, to: Vector2i, step: int) -> Conduction.Link:
	var link := Conduction.Link.new()
	link.from = from
	link.to = to
	link.step = step
	return link


# In the AIR, so a UNIT-only shock leaves it too: on the cell it struck AND on every cell its stamped
# current ran through -- the volley's own tree, never re-derived. Every gas the reaction releases rides
# it, the heat haze of its `+ F` (#1427) as well as the ozone.
func test_a_shock_leaves_ozone_where_it_struck_and_all_along_its_current() -> void:
	var ozone := _ozone()
	var attacker := _attacker(Elemental.Element.SHOCK, EquippableData.TargetMode.UNIT)
	var struck: Array[Vector2i] = [TARGET_CELL]
	var aim := _aim(attacker, struck)
	var far := TARGET_CELL + Vector2i(1, 0)
	var farther := TARGET_CELL + Vector2i(2, 0)
	var links: Array[Conduction.Link] = [_link(TARGET_CELL, far, 1), _link(far, farther, 2)]
	aim.arc_links = links
	var plan := _resolve(_one(aim), _KindBoard.new(null, {}))
	for kind: Gas.Kind in Gas.released(ozone.gases):
		var level: int = ozone.gases[kind]
		for cell: Vector2i in [TARGET_CELL, far, farther]:
			assert_int(_gas_on(plan, cell, kind)).override_failure_message(
					"no %s on %s" % [Gas.display_name(kind), cell]).is_equal(level)
		assert_int(_gas_on(plan, TARGET_CELL + Vector2i(3, 0), kind)).is_equal(0)


# A MAP-only shock strikes no one and still leaves it.
func test_a_map_only_shock_leaves_ozone_on_the_cells_it_strikes() -> void:
	var attacker := _attacker(Elemental.Element.SHOCK, EquippableData.TargetMode.MAP)
	var struck: Array[Vector2i] = [TARGET_CELL, TARGET_CELL + Vector2i(0, 1)]
	var plan := _resolve(_one(_aim(attacker, struck)), _KindBoard.new(null, {}))
	for cell in struck:
		assert_int(_gas_on(plan, cell, Gas.Kind.OZONE)).override_failure_message(
				"a map-only shock left no ozone on %s" % [cell]).is_greater(0)


# Only the AIR reaches the current's cells: an attack's own gas and the ground's reactions stay on what
# it struck.
func test_the_current_carries_the_air_half_only() -> void:
	var attacker := _attacker(Elemental.Element.SHOCK, EquippableData.TargetMode.UNIT)
	attacker.get_fired_attack().gases = {STEAM: Gas.Level.THIN}
	var struck: Array[Vector2i] = [TARGET_CELL]
	var aim := _aim(attacker, struck)
	var far := TARGET_CELL + Vector2i(1, 0)
	var links: Array[Conduction.Link] = [_link(TARGET_CELL, far, 1)]
	aim.arc_links = links
	var plan := _resolve(_one(aim), _KindBoard.new(null, {}))
	assert_int(_steam_on(plan, TARGET_CELL)).is_equal(Gas.Level.THIN)
	assert_int(_steam_on(plan, far)).override_failure_message(
			"the attack's own gas rode the current past what it struck").is_equal(0)
	assert_int(_gas_on(plan, far, Gas.Kind.OZONE)).is_greater(0)
