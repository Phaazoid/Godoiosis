# DEF mitigation (#84): DEF finally reduces damage in the resolver. Before this it was a
# display-only readout (Unit.get_effective_def fed the inspect panel and nothing else) — the
# resolver never subtracted it. Now a flat gear+terrain reduction subtracts AFTER elemental
# scaling and BEFORE the 0-floor (Law: 0-damage hits are legal), with Iron Will still the last
# clamp. A revved Chainsword attacker pierces it entirely — the payload of the family's Rev
# mechanic.
#
# BOTH terms are live as of Burrow: armor (gear) and Cover (a Burrow-dug COVER tile). They are
# summed in exactly ONE place, RulesService.def_breakdown, which the inspect panel's DEF readout
# also calls — so the number shown can't drift from the number subtracted. That shared
# itemization is pinned here too, alongside the damage math it feeds.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager


func before_test() -> void:
	_sm = H.make_manager(self)


func _make_armor(def_power: int) -> ArmorData:
	var armor := ArmorData.new()
	armor.def_power = def_power
	return armor


# A board whose only feature is a COVER tile at `cell` — enough for the DEF path, which reads
# terrain_states and nothing else. The grid stays null deliberately: a plain weapon attack doesn't
# hit the map, so the cell-effect stage early-returns before any tile lookup.
func _board_with_cover(cell: Vector2i) -> BoardContext:
	var states: TerrainStateManager = auto_free(TerrainStateManager.new())
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.append(Terrain.TileState.COVER)
	states.apply(effect)
	var units: Array[Unit] = []
	return BoardContext.new(null, units, _sm, states)


# A plain physical attack, base = power + STR. make_weapon() yields a Chainsword instance (#82),
# so the same helper covers both the mitigated and the revved-pierce cases.
func _attack(attacker: Unit, target: Unit) -> AttackAction:
	attacker.equipped_weapon = H.make_weapon(6)
	return H.stamped_attack(attacker, target)


func test_def_subtracts_from_damage() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20, Stats.Stat.CON: 5})
	target.worn_armor = _make_armor(4)

	var attack := _attack(attacker, target)   # base 10 (power 6 + STR 4)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	# Expected DEF through the readout seam, never a literal (2026-08-10 sweep): the armor term
	# rides CON_DEF_FACTOR, which is playtest-tunable. Readout == subtraction is this file's own
	# doctrine (see the header + test_def_breakdown_total_is_what_the_resolver_subtracts).
	assert_int(attack.resolved.damage).is_equal(10 - target.get_effective_def())
	assert_int(target.get_effective_def()).is_greater(0)   # premise: the piece pays out at all


func test_naked_target_takes_full_damage() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20})

	var attack := _attack(attacker, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.damage).is_equal(10)   # no armor -> no mitigation


func test_revved_chainsword_pierces_def() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20, Stats.Stat.CON: 5})
	target.worn_armor = _make_armor(4)

	var attack := _attack(attacker, target)
	(attacker.equipped_weapon as ChainswordWeaponInstance).rev()
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.damage).is_equal(10)   # DEF ignored entirely while revved


func test_def_never_drives_damage_below_zero() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20, Stats.Stat.CON: 5})
	target.worn_armor = _make_armor(40)   # DEF far above the incoming hit
	# The premise stated rather than assumed: if a factor retune ever drops this below the base 10,
	# this fails HERE as a fixture problem, not below as a phantom mechanism bug.
	assert_int(target.get_effective_def()).is_greater_equal(10)

	var attack := _attack(attacker, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.damage).is_equal(0)   # floored at 0, never negative, never a heal
	assert_that(attack.resolved.lethality).is_equal(ResolvedOutcome.Lethality.NONE)


# --- terrain Cover: the second live DEF term (Burrow, #84) ---

func test_terrain_cover_mitigates_like_armor() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20})
	var board := _board_with_cover(Vector2i(1, 0))   # the target stands in its own entrenchment

	var attack := _attack(attacker, target)   # base 10, no armor
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan, ReactionCatalog.get_all(), board)

	assert_int(attack.resolved.damage).is_equal(10 - Terrain.COVER_DEF)


func test_cover_stacks_with_armor() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20, Stats.Stat.CON: 5})
	target.worn_armor = _make_armor(4)
	var board := _board_with_cover(Vector2i(1, 0))

	var attack := _attack(attacker, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan, ReactionCatalog.get_all(), board)

	assert_int(attack.resolved.damage).is_equal(10 - target.get_effective_def() - Terrain.COVER_DEF)


func test_cover_only_shelters_the_covered_cell() -> void:
	# Cover is a property of the TILE, not the unit — an entrenchment the target isn't standing in
	# does nothing for it.
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20})
	var board := _board_with_cover(Vector2i(5, 5))   # entrenchment somewhere else entirely

	var attack := _attack(attacker, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan, ReactionCatalog.get_all(), board)

	assert_int(attack.resolved.damage).is_equal(10)


func test_revved_chainsword_pierces_terrain_cover_too() -> void:
	# ignores_def() zeroes the WHOLE mitigation sum, not just the armor term — digging in is no
	# defense against a running chainsaw.
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20, Stats.Stat.CON: 5})
	target.worn_armor = _make_armor(4)
	var board := _board_with_cover(Vector2i(1, 0))

	var attack := _attack(attacker, target)
	(attacker.equipped_weapon as ChainswordWeaponInstance).rev()
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan, ReactionCatalog.get_all(), board)

	assert_int(attack.resolved.damage).is_equal(10)


# --- the shared itemization the inspect panel reads ---

func test_def_breakdown_itemizes_armor_and_cover() -> void:
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.CON: 5})
	target.worn_armor = _make_armor(4)
	var board := _board_with_cover(Vector2i(1, 0))

	# The armor term derived independently through the stat doctrine (Stats.armor_def), so this
	# case genuinely cross-checks the breakdown rather than echoing get_effective_def back at
	# itself -- and no literal rides CON_DEF_FACTOR (playtest-tunable, 2026-08-10 sweep).
	var armor_term: int = Stats.armor_def(4, target.get_effective_stat(Stats.Stat.CON))
	var def := RulesService.def_breakdown(target, Vector2i(1, 0), board)
	assert_int(def["armor"]).is_equal(armor_term)
	assert_int(def["cover"]).is_equal(Terrain.COVER_DEF)
	assert_int(def["total"]).is_equal(armor_term + Terrain.COVER_DEF)


func test_def_breakdown_without_a_board_is_armor_only() -> void:
	# The panel can be asked for a breakdown before a board exists; degrade to gear, never crash.
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.CON: 5})
	target.worn_armor = _make_armor(4)

	var def := RulesService.def_breakdown(target, Vector2i(1, 0), null)
	assert_int(def["cover"]).is_equal(0)
	assert_int(def["total"]).is_equal(Stats.armor_def(4, target.get_effective_stat(Stats.Stat.CON)))


func test_def_breakdown_total_is_what_the_resolver_subtracts() -> void:
	# The anti-drift pin: whatever the panel would display is exactly the mitigation applied.
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20, Stats.Stat.CON: 5})
	target.worn_armor = _make_armor(4)
	var board := _board_with_cover(Vector2i(1, 0))

	var attack := _attack(attacker, target)   # base 10
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan, ReactionCatalog.get_all(), board)

	var shown := RulesService.def_breakdown(target, Vector2i(1, 0), board)
	assert_int(attack.resolved.damage).is_equal(10 - shown["total"])


# --- damage kinds (#424): armour answers only the kinds it covers ---
#
# A piece that lists kinds stops ONLY those; a piece that lists none stops everything, which is what
# every piece authored before kinds existed still does. Cover is kind-blind. The kind and the
# subtraction are stamped on the outcome so the queue row explains the number it shows (Law #2).

func _armor_covering(def_power: int, kinds: Array[AttackData.Kind]) -> ArmorData:
	var armor := _make_armor(def_power)
	armor.covered_kinds = kinds
	return armor


func test_an_uncovered_kind_zeroes_the_armor_term_and_not_cover() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20, Stats.Stat.CON: 5})
	target.worn_armor = _armor_covering(4, [AttackData.Kind.SLASH])   # the swing below is BLUNT
	var board := _board_with_cover(Vector2i(1, 0))

	var attack := _attack(attacker, target)   # base 10, the fixture main's kind is the zero: BLUNT
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan, ReactionCatalog.get_all(), board)

	assert_int(attack.resolved.damage).is_equal(10 - Terrain.COVER_DEF)
	var against := RulesService.def_against(target, Vector2i(1, 0), board, AttackData.Kind.BLUNT)
	assert_int(against["armor"]).is_equal(0)
	assert_int(against["cover"]).is_equal(Terrain.COVER_DEF)
	assert_int(against["total"]).is_equal(Terrain.COVER_DEF)


func test_a_covered_kind_is_mitigated_in_full() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20, Stats.Stat.CON: 5})
	target.worn_armor = _armor_covering(4, [AttackData.Kind.SLASH, AttackData.Kind.BLUNT])

	var attack := _attack(attacker, target)
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.damage).is_equal(10 - target.get_effective_def())


func test_a_piece_listing_no_kinds_covers_every_kind() -> void:
	# The storage default: a piece authored before kinds existed keeps stopping a fireball.
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20, Stats.Stat.CON: 5})
	target.worn_armor = _make_armor(4)

	var attack := _attack(attacker, target)
	(attack.fired_attack as WeaponAttackData).damage_kind = AttackData.Kind.FIRE
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_int(attack.resolved.damage).is_equal(10 - target.get_effective_def())


func test_the_outcome_stamps_the_kind_and_the_subtraction_it_made() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20, Stats.Stat.CON: 5})
	target.worn_armor = _make_armor(4)

	var attack := _attack(attacker, target)
	(attack.fired_attack as WeaponAttackData).damage_kind = AttackData.Kind.SLASH
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_that(attack.resolved.kind).is_equal(AttackData.Kind.SLASH)
	assert_int(attack.resolved.mitigation).is_equal(10 - attack.resolved.damage)
	assert_int(attack.resolved.mitigation).is_greater(0)   # premise: something was subtracted


func test_a_fitted_mod_changes_what_armor_answers() -> void:
	# The WIRE from the mod to the mitigation stage: the resolver must read the COMPOSED kind. A
	# mutant reading the authored field passes every other case in this file.
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20, Stats.Stat.CON: 5})
	target.worn_armor = _armor_covering(4, [AttackData.Kind.BLUNT])   # covers the AUTHORED kind

	var attack := _attack(attacker, target)
	attacker.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, 3)
	var spike := WeaponModData.new()
	spike.overrides_kind = true
	spike.kind = AttackData.Kind.PIERCE
	assert_bool((attacker.equipped_weapon as WeaponInstance).fit(0, spike)) \
		.override_failure_message("fixture: the spike must fit, or the override is simply absent") \
		.is_true()
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_that(attack.resolved.kind).is_equal(AttackData.Kind.PIERCE)
	assert_int(attack.resolved.damage).is_equal(10)   # plate covers blunt; the spike made it pierce


func test_bare_fists_are_blunt() -> void:
	# The one attack with no resource to author a kind on; the resolver answers BLUNT for a null stamp.
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.STR: 4})
	var target := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0), {Stats.Stat.MHP: 20, Stats.Stat.CON: 5})
	target.worn_armor = _armor_covering(4, [AttackData.Kind.BLUNT])

	attacker.equipped_weapon = null
	var attack := H.stamped_attack(attacker, target)   # no weapon -> null stamp -> STR damage
	assert_object(attack.fired_attack).is_null()
	var plan := ResolvedPlan.new()
	plan.attacks.append(attack)
	PlanResolver.resolve(plan)

	assert_that(attack.resolved.kind).is_equal(AttackData.Kind.BLUNT)
	assert_int(attack.resolved.damage).is_equal(4 - target.get_effective_def())
