# Law #2 across a strip (#1480 stage 3, the cases #1455 left): a lost limb can strip gear mid-pass,
# and every later read of that body in the same pass must see the body execution will have. Each case
# resolves, executes, and asserts the two agree.
#
# The stripping piece is built here, gated on the stat the target's NEXT limb carries, because no
# shipped piece strips on a sever. Every swing is sized off the knobs, so retuning them reds nothing.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const FIRE := Vector2i(1, 0)

var _sm: SquadManager
var _limb_loss := 0
var _limb_loss_wounded := 0


func before_test() -> void:
	_sm = H.make_manager(self)
	_limb_loss = LethalityRules.LIMB_LOSS_DAMAGE
	_limb_loss_wounded = LethalityRules.LIMB_LOSS_DAMAGE_WOUNDED


func after_test() -> void:
	LethalityRules.LIMB_LOSS_DAMAGE = _limb_loss
	LethalityRules.LIMB_LOSS_DAMAGE_WOUNDED = _limb_loss_wounded


# An attacker whose swing deals exactly `damage` before DEF.
func _attacker_dealing(damage: int, cell: Vector2i, faction := PLAYER) -> Unit:
	var a := H.spawn_solo(self, _sm, faction, cell, {}, true, 0)
	var weapon := a.get_equipped_weapon() as WeaponInstance
	var main: WeaponAttackData = weapon.template.main_attack
	main.power = damage - weapon.base_damage(a.state, main)
	return a


func _healer(cell: Vector2i, amount: int) -> Unit:
	var healer := _attacker_dealing(amount, cell)
	var main: WeaponAttackData = (healer.get_equipped_weapon() as WeaponInstance).template.main_attack
	main.heals = true
	main.hits_allies = true
	return healer


# A target at the top of the middle CON band, with STR and DEX to spare.
func _target(cell: Vector2i, mhp: int, faction := ENEMY) -> Unit:
	return H.spawn_solo(self, _sm, faction, cell, {Stats.Stat.MHP: mhp, Stats.Stat.STR: 6,
			Stats.Stat.DEX: 6, Stats.Stat.CON: Stats.BAND_MID_MAX}, false)


# Worn `piece`, gated on the stat the target's next limb carries: the blow that takes that limb strips it.
func _wear_gated(target: Unit, piece: ArmorData) -> void:
	var slot: int = target.unit_instance.maim_order()[0]
	var arm := slot == UnitInstance.LimbSlot.ARM_L or slot == UnitInstance.LimbSlot.ARM_R
	var carried: Stats.Stat = Stats.Stat.STR if arm else Stats.Stat.DEX
	piece.stat_minimums = {carried: target.get_body_stat(carried)}
	target.add_item(piece)
	assert_bool(target.wear_armor(target.inventory.find(piece))) \
		.override_failure_message("fixture: the piece would not go on").is_true()
	target.set_current_hp(target.get_max_hp())


func _granting(id: Abilities.Id) -> ArmorData:
	var piece := ArmorData.new()
	var ability := AbilityData.new()
	ability.id = id
	ability.kind = AbilityData.AbilityKind.PASSIVE
	var grants: Array[AbilityData] = [ability]
	piece.granted_abilities = grants
	return piece


# One CON point: lifts the wearer into the top max-HP band, so the strip drops max HP.
func _con_plate() -> ArmorData:
	var piece := ArmorData.new()
	piece.stat_modifiers = {Stats.Stat.CON: 1}
	return piece


func _resolve(attacks: Array[AttackAction], board: BoardContext = null) -> ResolvedPlan:
	var plan := ResolvedPlan.new()
	plan.attacks = attacks
	var no_reactions: Array[ElementalReaction] = []
	PlanResolver.resolve(plan, no_reactions, board)
	return plan


func _assert_severs(atk: AttackAction) -> void:
	assert_int(atk.resolved.severed_limb) \
		.override_failure_message("fixture: the first blow took no limb").is_not_equal(-1)


func _assert_stripped(target: Unit) -> void:
	assert_object(target.worn_armor) \
		.override_failure_message("fixture: the lost limb did not strip the piece").is_null()


# ==============================================================================
#  Reads of the body later in the pass
# ==============================================================================

# The second hit is mitigated by the DEF the body has once the first hit's limb is gone.
func test_a_second_hit_meets_the_stripped_def() -> void:
	var target := _target(Vector2i(1, 0), 200)
	var plate := ArmorData.new()
	plate.flat_def = 3
	_wear_gated(target, plate)
	var def := target.get_effective_def()
	assert_int(def).override_failure_message("fixture: the plate gives no DEF").is_greater(0)
	var first := H.stamped_attack(_attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE + def, Vector2i(0, 0)), target)
	var second := H.stamped_attack(_attacker_dealing(def + 2, Vector2i(2, 0)), target)
	_resolve([first, second])
	_assert_severs(first)

	assert_int(second.resolved.mitigation) \
		.override_failure_message("the hit after the strip was mitigated by the plate the strip took") \
		.is_equal(0)

	await first.execute()
	await second.execute()

	_assert_stripped(target)
	assert_int(target.get_current_hp()).is_equal(second.resolved.target_hp_after)


# A heal after the strip clamps at the max HP the body has once the CON piece is gone.
func test_a_heal_after_a_strip_clamps_at_the_stripped_max_hp() -> void:
	var target := _target(Vector2i(1, 0), 60)
	_wear_gated(target, _con_plate())
	var max_struck_at := target.get_max_hp()
	var blow := H.stamped_attack(_attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE, Vector2i(0, 0)), target)
	var heal := H.stamped_attack(_healer(Vector2i(2, 0), LethalityRules.LIMB_LOSS_DAMAGE * 2), target)
	_resolve([blow, heal])
	_assert_severs(blow)

	await blow.execute()
	await heal.execute()

	_assert_stripped(target)
	assert_int(target.get_max_hp()) \
		.override_failure_message("fixture: the strip moved no max HP; nothing to clamp").is_less(max_struck_at)
	assert_int(target.get_current_hp()) \
		.override_failure_message("the queue clamped the heal at the max HP the strip took") \
		.is_equal(heal.resolved.target_hp_after)


# The row of a hit after the strip names no piece the strip took (#1480 stage 5): its armour line is
# the body the hit was judged against, not the live one.
func test_the_row_after_a_strip_names_no_stripped_piece() -> void:
	var target := _target(Vector2i(1, 0), 200)
	var jacket := ArmorData.new()
	jacket.display_name = "Fencing Jacket"
	jacket.covered_kinds = [AttackData.Kind.SLASH]
	_wear_gated(target, jacket)
	var first := H.stamped_attack(_attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE, Vector2i(0, 0)), target)
	var second := H.stamped_attack(_attacker_dealing(2, Vector2i(2, 0)), target)
	_resolve([first, second])
	_assert_severs(first)
	assert_bool(jacket.covers(second.resolved.kind)) \
		.override_failure_message("fixture: the jacket covers the hit; the row names it either way").is_false()

	assert_str(ActionQueueRow.damage_tip(first.resolved)) \
		.override_failure_message("fixture: the severing hit's row does not name the jacket it met") \
		.contains("Fencing Jacket")
	assert_str(ActionQueueRow.damage_tip(second.resolved)) \
		.override_failure_message("the row after the strip named the jacket the strip took") \
		.not_contains("Fencing Jacket")


# The gambit the stripped piece granted is gone for the next would-be-down in the same pass.
func test_crisis_from_a_stripped_piece_is_not_armed_for_a_later_hit() -> void:
	var target := _target(Vector2i(1, 0), 200)
	_wear_gated(target, _granting(Abilities.Id.CRISIS))
	target.set_current_hp(LethalityRules.LIMB_LOSS_DAMAGE * 3)
	var blow := H.stamped_attack(_attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE, Vector2i(0, 0)), target)
	var down := H.stamped_attack(_attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE * 2, Vector2i(2, 0)), target)
	_resolve([blow, down])
	_assert_severs(blow)

	assert_that(down.resolved.lethality) \
		.override_failure_message("the queue armed a Crisis whose piece the first blow stripped") \
		.is_equal(ResolvedOutcome.Lethality.DOWNED)

	await blow.execute()
	await down.execute()

	_assert_stripped(target)
	assert_bool(target.is_downed()).is_true()
	assert_bool(target.in_crisis).is_false()


# The end-of-turn burn reads the body the pass leaves: a stripped Insulation piece no longer spares it.
# The forecast and the pass are two derivations (resolve_tile_hits, TurnBoundary.tile_hits).
func test_the_end_of_turn_burn_meets_the_stripped_insulation() -> void:
	var states: TerrainStateManager = auto_free(TerrainStateManager.new())
	var ignite := ResolvedCellEffect.new()
	ignite.cell = FIRE
	ignite.states_added.assign([Terrain.TileState.BURNING])
	states.apply(ignite)
	var gas := GasField.new()
	var attacker := _attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE, Vector2i(0, 0))
	var mate := _target(FIRE, 60, PLAYER)
	_wear_gated(mate, _granting(Abilities.INSULATION[Elemental.Element.FIRE]))
	var units: Array[Unit] = [attacker, mate]
	var board := BoardContext.new(_sm.grid, units, _sm, states, null, null, gas)
	var blow := H.stamped_attack(attacker, mate)
	var plan := _resolve([blow], board)
	var no_actions: Array[BaseAction] = []
	PlanResolver.resolve_tile_hits(plan, attacker.squad, no_actions, plan.hypo, board)
	_assert_severs(blow)
	var forecast: TileHitAction = null
	for hit in plan.tile_hits:
		if hit.actor == mate:
			forecast = hit

	await blow.execute()

	_assert_stripped(mate)
	var mates: Array[Unit] = [mate]
	var dealt := TurnBoundary.tile_hits(mates, states, gas, Weather.Kind.CLEAR, PLAYER)
	assert_int(dealt.size()).override_failure_message(
			"fixture: the stripped unit takes no burn at the turn end; nothing to forecast").is_equal(1)
	assert_object(forecast).override_failure_message(
			"the queue forecast no burn for a unit whose Insulation the pass strips").is_not_null()
	if forecast != null:
		assert_int(forecast.resolved.damage).is_equal(dealt[0].resolved.damage)


# ==============================================================================
#  The severing hit itself
# ==============================================================================

# A strip that drops max HP below what the blow left re-clamps the body, and the queue shows the
# re-clamped number. Only reachable with a limb threshold under the CON band's span, so it is lowered here.
func test_the_severing_hit_shows_its_own_re_clamp() -> void:
	LethalityRules.LIMB_LOSS_DAMAGE = 1
	var target := _target(Vector2i(1, 0), 60)
	_wear_gated(target, _con_plate())
	var full := target.get_current_hp()
	var blow := H.stamped_attack(_attacker_dealing(LethalityRules.LIMB_LOSS_DAMAGE, Vector2i(0, 0)), target)
	_resolve([blow])
	_assert_severs(blow)

	await blow.execute()

	_assert_stripped(target)
	assert_int(target.get_current_hp()) \
		.override_failure_message("fixture: the strip did not re-clamp the blow's HP; nothing to show") \
		.is_less(full - LethalityRules.LIMB_LOSS_DAMAGE)
	assert_int(blow.resolved.target_hp_after) \
		.override_failure_message("the queue showed the blow's HP, not the re-clamp the strip makes") \
		.is_equal(target.get_current_hp())
