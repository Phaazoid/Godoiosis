# #15 regression: AoE victims are DERIVED at resolve time from CURRENT projected positions,
# never frozen at queue time. Re-planning a squadmate's move after the attack is queued must
# change who the blast hits — the same "derive, don't store" rule counters already follow.
#
# Updated for #47 (attacks target CELLS): an empty blast now resolves to ONE cell attack
# (target == null), not to zero attacks — the aim survives; units are a consequence of it.
#
# Setup uses a friendly-fire weapon (hits_allies) so a squadmate standing in / walking into
# the blast counts as a victim, and a pattern-less weapon (affected == [aim cell]) so the
# blast is the single aimed cell. The attacker's squad is the active one, so squadmate moves
# project (get_projected_unit_from_cell reads the active squad).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# A squadmate who walks INTO the blast after the attack is queued becomes a victim.
func test_resolve_retargets_when_a_squadmate_moves_into_the_blast() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	(attacker.get_equipped_weapon() as WeaponInstance).template.main_attack.hits_allies = true
	var mate := H.spawn_solo(self, _sm, PLAYER, Vector2i(3, 0), {Stats.Stat.LDR: 3})
	_sm.join_squad(mate, attacker.squad)
	_sm.active_squad = attacker.squad

	attacker.squad._queue_action(AttackAction.create(attacker, attacker.movement.cell, null, Vector2i(1, 0)))
	var board := _board_with([attacker, mate])

	# Before the move: (1,0) is empty, so the aim resolves to a CELL attack (#47 — no victim,
	# target null), not nothing.
	var before := _sm.resolve_plan(attacker.squad, board)
	assert_int(before.attacks.size()).is_equal(1)
	assert_object(before.attacks[0].target).is_null()
	_break_volleys(before)

	# The squadmate re-plans a move INTO the blast cell.
	var move := MoveAction.new()
	move.init(mate, [Vector2i(1, 0)], null)
	mate.squad._queue_action(move)
	_sm.validate_squad_plan(attacker.squad)   # so the move is_valid -> counts as projected

	var after := _sm.resolve_plan(attacker.squad, board)
	assert_int(after.attacks.size()).is_equal(1)
	assert_object(after.attacks[0].target).is_same(mate)
	_break_volleys(after)

# A target who walks OUT of the blast after the attack is queued is dropped.
func test_resolve_drops_a_target_who_moves_out_of_the_blast() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {Stats.Stat.LDR: 3})
	(attacker.get_equipped_weapon() as WeaponInstance).template.main_attack.hits_allies = true
	var mate := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0), {Stats.Stat.LDR: 3})  # starts IN the blast
	_sm.join_squad(mate, attacker.squad)
	_sm.active_squad = attacker.squad

	attacker.squad._queue_action(AttackAction.create(attacker, attacker.movement.cell, null, Vector2i(1, 0)))
	var board := _board_with([attacker, mate])

	# Before the move: the squadmate is standing in the blast.
	var before := _sm.resolve_plan(attacker.squad, board)
	assert_int(before.attacks.size()).is_equal(1)
	assert_object(before.attacks[0].target).is_same(mate)
	_break_volleys(before)

	# The squadmate walks OUT of the blast.
	var move := MoveAction.new()
	move.init(mate, [Vector2i(2, 0)], null)
	mate.squad._queue_action(move)
	_sm.validate_squad_plan(attacker.squad)

	# The squadmate left the blast, so the aim resolves to a CELL attack (#47 — target null).
	var after := _sm.resolve_plan(attacker.squad, board)
	assert_int(after.attacks.size()).is_equal(1)
	assert_object(after.attacks[0].target).is_null()
	_break_volleys(after)

func _board_with(units_in: Array) -> BoardContext:
	var units: Array[Unit] = []
	units.assign(units_in)
	return BoardContext.new(_sm.grid, units, _sm)

# create_volley links siblings into a shared self-referential array (a RefCounted cycle, see
# #35). The derived volley is owned by nothing after the test, so break it to avoid a leak.
func _break_volleys(plan: ResolvedPlan) -> void:
	var empty: Array[AttackAction] = []
	for atk in plan.attacks:
		atk.volley = empty
