# Projected position — the ONE derivation and its inverse (#105).
#
# "Where will this unit be when the plan resolves?" used to have three independent answers
# (Unit.get_projected_destination, SquadPlanValidator.projected_cell_for, and a reverse index in
# SquadManager that scanned MOVE orders). They disagreed on two axes and the reverse one couldn't
# see a knockback at all. Everything now routes through Unit.projected_cell / Unit.projected_unit_at,
# and the two axes are arguments each caller states.
#
# This suite exists because the #104 sweep asserted a fix that had never been run inside
# resolve_plan, and it shipped broken. The board-backed half below is the part that catches that:
# the axes can be unit-tested, but the ORDER resolve_plan does things in cannot.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var manager: SquadManager

func before_test() -> void:
	manager = H.make_manager(self)

# ==============================================================================
#  The two axes — require_valid and use_knockback
# ==============================================================================

# Both forward callers agree whenever a move is valid and nothing has been shoved. That agreement
# is the whole point: they may only differ on the axes they declare.
func test_forward_answers_agree_on_a_valid_move() -> void:
	var unit := H.spawn_solo(self, manager, PLAYER, Vector2i(0, 0))
	var move := MoveAction.new()
	move.init(unit, [Vector2i(0, 0), Vector2i(0, 1)], null)
	unit.squad._queue_action(move)
	manager.validate_squad_plan(unit.squad)

	assert_bool(move.is_valid).is_true()
	assert_that(unit.get_projected_destination()).is_equal(Vector2i(0, 1))
	assert_that(SquadPlanValidator.projected_cell_for(unit, unit.squad.get_actions())).is_equal(Vector2i(0, 1))

# require_valid: the live reading skips an invalid move; validation deliberately does NOT, because
# it runs inside the fixed-point loop that computes is_valid. This is the ONE case where the two
# answers may differ, and it is declared on both sides.
func test_require_valid_is_the_declared_divergence() -> void:
	var leader := H.spawn_solo(self, manager, PLAYER, Vector2i(0, 0))
	var member := H.spawn_unit(self, PLAYER, Vector2i(1, 0))
	manager.create_squad(member)
	manager.join_squad(member, leader.squad)

	# Both aim at the same cell -> _check_destination_conflicts invalidates both.
	var m1 := MoveAction.new()
	m1.init(leader, [Vector2i(0, 0), Vector2i(0, 1)], null)
	var m2 := MoveAction.new()
	m2.init(member, [Vector2i(1, 0), Vector2i(0, 1)], null)
	leader.squad._queue_action(m1)
	leader.squad._queue_action(m2)
	manager.validate_squad_plan(leader.squad)
	assert_bool(m1.is_valid).is_false()

	var actions := leader.squad.get_actions()
	assert_that(Unit.projected_cell(leader, actions, true, true)).is_equal(Vector2i(0, 0))
	assert_that(Unit.projected_cell(leader, actions, false, true)).is_equal(Vector2i(0, 1))
	# ...and each caller picks the one it declared.
	assert_that(leader.get_projected_destination()).is_equal(Vector2i(0, 0))
	assert_that(SquadPlanValidator.projected_cell_for(leader, actions)).is_equal(Vector2i(0, 1))

func test_use_knockback_is_the_other_declared_divergence() -> void:
	var unit := H.spawn_solo(self, manager, PLAYER, Vector2i(3, 3))
	unit.set_projected_knockback(Vector2i(5, 3))
	var actions := unit.squad.get_actions()

	assert_that(Unit.projected_cell(unit, actions, true, true)).is_equal(Vector2i(5, 3))
	assert_that(Unit.projected_cell(unit, actions, true, false)).is_equal(Vector2i(3, 3))
	assert_that(unit.get_projected_destination()).is_equal(Vector2i(5, 3))
	assert_that(SquadPlanValidator.projected_cell_for(unit, actions)).is_equal(Vector2i(3, 3))

func test_clearing_the_shove_restores_the_live_cell() -> void:
	var unit := H.spawn_solo(self, manager, PLAYER, Vector2i(3, 3))
	unit.set_projected_knockback(Vector2i(5, 3))
	unit.clear_projected_knockback()
	assert_that(unit.get_projected_destination()).is_equal(Vector2i(3, 3))

# ==============================================================================
#  Hold-position moves vs a shove
# ==============================================================================

# A hold move means "not going anywhere under my own power" — a shove still moves you. Squad
# activation gives EVERY member a hold move, so before #105 this silently swallowed the shove for
# any unit in the acting squad.
func test_a_hold_move_does_not_swallow_a_shove() -> void:
	var unit := H.spawn_solo(self, manager, PLAYER, Vector2i(3, 3))
	unit.set_projected_knockback(Vector2i(5, 3))
	manager.setup_hold_move_actions(unit.squad)
	manager.validate_squad_plan(unit.squad)

	assert_that(unit.get_projected_destination()).is_equal(Vector2i(5, 3))

# ...but a REAL move beats the shove: the unit walked out from under it.
func test_a_real_move_beats_a_shove() -> void:
	var unit := H.spawn_solo(self, manager, PLAYER, Vector2i(3, 3))
	unit.set_projected_knockback(Vector2i(5, 3))
	var move := MoveAction.new()
	move.init(unit, [Vector2i(3, 3), Vector2i(3, 4)], null)
	unit.squad._queue_action(move)
	manager.validate_squad_plan(unit.squad)

	assert_that(unit.get_projected_destination()).is_equal(Vector2i(3, 4))

# ==============================================================================
#  The inverse
# ==============================================================================

func test_reverse_index_is_the_inverse_of_the_forward_answer() -> void:
	var a := H.spawn_solo(self, manager, PLAYER, Vector2i(0, 0))
	var b := H.spawn_solo(self, manager, PLAYER, Vector2i(4, 4))
	var move := MoveAction.new()
	move.init(a, [Vector2i(0, 0), Vector2i(0, 1)], null)
	a.squad._queue_action(move)
	manager.validate_squad_plan(a.squad)

	# Every unit is findable at exactly the cell its forward answer names, and nowhere else.
	for unit in [a, b]:
		assert_object(manager.get_projected_unit_from_cell(unit.get_projected_destination())).is_same(unit)
	assert_object(manager.get_projected_unit_from_cell(Vector2i(0, 0))).is_null()   # a has vacated it

# The old reverse index scanned MOVE orders, so a unit whose only projection was a shove was
# invisible to it — which is what made a shoved unit un-clickable at the cell its ghost stood on.
func test_reverse_index_finds_a_shoved_unit() -> void:
	var unit := H.spawn_solo(self, manager, PLAYER, Vector2i(3, 3))
	manager.active_squad = unit.squad
	unit.set_projected_knockback(Vector2i(5, 3))

	assert_object(manager.get_projected_unit_from_cell(Vector2i(5, 3))).is_same(unit)
	assert_object(manager.get_projected_unit_from_cell(Vector2i(3, 3))).is_null()

# ==============================================================================
#  Pointer resolution (#107) — the inverse IS the answer game.unit_at_pointer gives
# ==============================================================================

# "Which unit is the pointer over?" had three hand-written formulas (a click resolver in game.gd,
# a hover-card one in HoverPresenter, and a raw cell scan feeding hovered_unit_changed), each
# combining a cell scan with this index differently. They are one call now, because the board
# draws exactly one sprite per unit AT its projected cell — redraw_projected_units and
# show_knockback_preview both hide the real sprite when they put a ghost somewhere else. The two
# cases below are the ones the old formulas disagreed on, so a reintroduced formula fails here.

# The old hover formula nulled any unit with a MOVE queued before consulting this index, so a unit
# whose move was REFUSED went un-hoverable while staying clickable. An invalid move moves nobody:
# require_valid skips it, the sprite never left, and the pointer finds it where it stands.
func test_a_refused_move_leaves_the_unit_findable_where_it_stands() -> void:
	var leader := H.spawn_solo(self, manager, PLAYER, Vector2i(0, 0))
	var member := H.spawn_unit(self, PLAYER, Vector2i(1, 0))
	manager.create_squad(member)
	manager.join_squad(member, leader.squad)

	# Both aim at the same cell -> _check_destination_conflicts invalidates both.
	var m1 := MoveAction.new()
	m1.init(leader, [Vector2i(0, 0), Vector2i(0, 1)], null)
	var m2 := MoveAction.new()
	m2.init(member, [Vector2i(1, 0), Vector2i(0, 1)], null)
	leader.squad._queue_action(m1)
	leader.squad._queue_action(m2)
	manager.validate_squad_plan(leader.squad)
	assert_bool(m1.is_valid).is_false()

	assert_object(manager.get_projected_unit_from_cell(Vector2i(0, 0))).is_same(leader)
	assert_object(manager.get_projected_unit_from_cell(Vector2i(1, 0))).is_same(member)
	assert_object(manager.get_projected_unit_from_cell(Vector2i(0, 1))).is_null()

# The old CLICK formula fell back to "the unit standing here, if it has no VALID move queued" —
# which is exactly a unit about to be shoved. Its real sprite is hidden and its ghost is on the
# landing cell, so the vacated cell must answer with nobody even though a unit stands on it.
func test_a_refused_move_plus_a_shove_answers_only_at_the_landing_cell() -> void:
	var leader := H.spawn_solo(self, manager, PLAYER, Vector2i(0, 0))
	var member := H.spawn_unit(self, PLAYER, Vector2i(1, 0))
	manager.create_squad(member)
	manager.join_squad(member, leader.squad)

	var m1 := MoveAction.new()
	m1.init(leader, [Vector2i(0, 0), Vector2i(0, 1)], null)
	var m2 := MoveAction.new()
	m2.init(member, [Vector2i(1, 0), Vector2i(0, 1)], null)
	leader.squad._queue_action(m1)
	leader.squad._queue_action(m2)
	manager.validate_squad_plan(leader.squad)
	assert_bool(m1.is_valid).is_false()

	leader.set_projected_knockback(Vector2i(-1, 0))

	assert_object(manager.get_projected_unit_from_cell(Vector2i(-1, 0))).is_same(leader)
	assert_object(manager.get_projected_unit_from_cell(Vector2i(0, 0))).is_null()

# A unit spawned but not yet squadded (game.spawn_unit's one-line window) must not crash the scan.
func test_a_squadless_unit_answers_with_its_live_cell() -> void:
	var loose := H.spawn_unit(self, PLAYER, Vector2i(7, 7))   # no create_squad
	assert_object(loose.squad).is_null()
	assert_that(loose.get_projected_destination()).is_equal(Vector2i(7, 7))

# ==============================================================================
#  Inside resolve_plan — the ordering the axes alone cannot pin
# ==============================================================================

func _data(unit_name: String, fac: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), unit_name, fac)

func _mace() -> WeaponInstance:
	var blowback := WeaponAttackData.new()
	blowback.display_name = "Blowback"
	blowback.knockback = 1
	blowback.requires_readiness = true
	blowback.consumes_readiness = true
	var t := WeaponData.new()
	t.weapon_type = WeaponData.WeaponType.KINETIC_MACE
	var smash := WeaponAttackData.new()
	smash.display_name = "Smash"
	smash.power = 1
	smash.builds_readiness = true
	t.main_attack = smash
	var extras: Array[WeaponAttackData] = [blowback]
	t.extra_attacks = extras
	return WeaponInstance.make(t)

func _arm_mace(unit: Unit) -> void:
	unit.add_item(_mace())
	var mace := unit.get_equipped_weapon() as KineticMaceWeaponInstance
	mace.charge = 1
	unit.active_attack = mace.template.extra_attacks[0]

func _units_of(board: Dictionary) -> Array[Unit]:
	var result: Array[Unit] = []
	for child in board.units_root.get_children():
		result.append(child as Unit)
	return result

func _board_with_room(root_name: String) -> Dictionary:
	var b := BoardBuilder.build(self, root_name)
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, Rect2i(-4, -4, 14, 14))
	return b

# THE regression: a second aim at the cell the first one shoves its target onto must find that
# target. resolve_plan expands each aim and resolves it before expanding the next; expanding the
# whole batch first put every victim lookup strictly before every shove, so this found nobody.
func test_a_later_aim_hits_the_cell_an_earlier_shove_lands_on() -> void:
	var b := _board_with_room("ProjChainRoot")
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var ally: Unit = BoardBuilder.spawn(b, _data("Ally", PLAYER), Vector2i(2, 1))
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(1, 0))
	_arm_mace(hero)
	ally.add_item(H.make_weapon(3))
	ally.active_attack = null
	b.squad_manager.join_squad(ally, hero.squad)
	var board := BoardContext.new(b.grid, _units_of(b), b.squad_manager, b.terrain_states)

	b.squad_manager.queue_action(hero.squad, AttackAction.declare(hero, Vector2i(0, 0), Vector2i(1, 0)))
	b.squad_manager.queue_action(ally.squad, AttackAction.declare(ally, Vector2i(2, 1), Vector2i(2, 0)))

	var plan: ResolvedPlan = b.squad_manager.resolve_plan(hero.squad, board)
	var ally_hit: AttackAction = null
	for atk in plan.attacks:
		if atk.actor == ally:
			ally_hit = atk
	assert_object(ally_hit).is_not_null()
	assert_object(ally_hit.target).is_same(foe)

# The mirror image: a unit shoved OUT of a later blast's footprint is missed by it.
func test_a_shove_moves_the_target_out_of_a_later_blast() -> void:
	var b := _board_with_room("ProjEvadeRoot")
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var ally: Unit = BoardBuilder.spawn(b, _data("Ally", PLAYER), Vector2i(1, 1))
	BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(1, 0))
	_arm_mace(hero)
	ally.add_item(H.make_weapon(3))
	ally.active_attack = null
	b.squad_manager.join_squad(ally, hero.squad)
	var board := BoardContext.new(b.grid, _units_of(b), b.squad_manager, b.terrain_states)

	b.squad_manager.queue_action(hero.squad, AttackAction.declare(hero, Vector2i(0, 0), Vector2i(1, 0)))
	# Ally aims at the foe's CURRENT cell — which the shove empties.
	b.squad_manager.queue_action(ally.squad, AttackAction.declare(ally, Vector2i(1, 1), Vector2i(1, 0)))

	var plan: ResolvedPlan = b.squad_manager.resolve_plan(hero.squad, board)
	for atk in plan.attacks:
		if atk.actor == ally:
			assert_object(atk.target).is_null()   # a cell attack: nobody is standing there any more

# Each shove records its OWN start cell. The preview used to reconstruct it from the target's live
# board cell, which for a second shove is two tiles away — a "direction" the arrow atlas has no
# texture for, so it drew the error sprite.
func test_each_shove_records_its_own_start_cell() -> void:
	var b := _board_with_room("ProjArrowRoot")
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var ally: Unit = BoardBuilder.spawn(b, _data("Ally", PLAYER), Vector2i(2, 1))
	BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(1, 0))
	_arm_mace(hero)
	_arm_mace(ally)
	b.squad_manager.join_squad(ally, hero.squad)
	var board := BoardContext.new(b.grid, _units_of(b), b.squad_manager, b.terrain_states)

	b.squad_manager.queue_action(hero.squad, AttackAction.declare(hero, Vector2i(0, 0), Vector2i(1, 0)))
	b.squad_manager.queue_action(ally.squad, AttackAction.declare(ally, Vector2i(2, 1), Vector2i(2, 0)))

	var plan: ResolvedPlan = b.squad_manager.resolve_plan(hero.squad, board)
	var first: AttackAction = null
	var second: AttackAction = null
	for atk in plan.attacks:
		if atk.actor == hero:
			first = atk
		elif atk.actor == ally:
			second = atk

	assert_bool(first.resolved.knockback_applied).is_true()
	assert_bool(second.resolved.knockback_applied).is_true()
	assert_that(first.resolved.knockback_from).is_equal(Vector2i(1, 0))
	assert_that(first.resolved.knockback_to).is_equal(Vector2i(2, 0))
	assert_that(second.resolved.knockback_from).is_equal(Vector2i(2, 0))   # where the FIRST one left it
	assert_that(second.resolved.knockback_to).is_equal(Vector2i(2, -1))

	# What the arrow atlas needs: every hit's own from->to is a unit cardinal.
	for hit in [first, second]:
		var dir := GridUtils.cardinal_direction_i_between(hit.resolved.knockback_from, hit.resolved.knockback_to)
		assert_bool(dir == Vector2i.UP or dir == Vector2i.DOWN or dir == Vector2i.LEFT or dir == Vector2i.RIGHT).is_true()
