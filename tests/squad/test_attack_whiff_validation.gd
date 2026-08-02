# Whiff validation — "does this aim still hit anyone?" — asked from its TWO declared sources.
#
# An attack aims at a CELL and derives its victims at resolve time (#47/#15), so an aim can end up
# swinging at bare ground. `AttackData.targets` decides whether that matters: a MAP or BOTH attack
# still deposits terrain effects (#50) and stays legal, a UNIT-only one does nothing.
#
# Rewritten 2026-08-02. The rule used to be re-derived by the validator from each unit's END-OF-PLAN
# projected cell, which folded in shoves the plan had not applied yet at that aim's turn — so every
# attack that knocked its target back went hunting for a victim on the cell it had just cleared, and
# a single Blowback dulled Execute. The positional fact now comes from whoever actually knows it:
#
#   a STORED aim  -> the resolve that expanded it (SquadPlanValidator.validate with a plan)
#   a CANDIDATE   -> SquadPlanValidator.aim_finds_a_target, via SquadManager.queue_action's gate
#
# Section A drives the gate through the real queue_action, so a refusal means the order never lands.
# Section B drives stored-aim revalidation through a real resolve on a real board — the ORDERING is
# the whole bug, and a test that hand-stamps knockback instead of letting a resolve publish it
# cannot see it.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BoardBuilder := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const INVALID_TINT := Color(1, .25, .25, 1)   # BaseAction.get_ui_modulate's refused colour

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# Equip `healer` with a heal-authored weapon, the way the #122 reactive-heal work does.
func _make_healer(healer: Unit) -> void:
	var weapon := H.make_weapon(4)
	weapon.template.main_attack.heals = true
	weapon.template.main_attack.hits_allies = true
	healer.equipped_weapon = weapon

# Offer an aim to the gate. Returns whether the order actually landed in the queue.
func _try_aim(attacker: Unit, cell: Vector2i) -> bool:
	return _sm.queue_action(attacker.squad, AttackAction.declare(attacker, attacker.movement.cell, cell))

# Queue a move DIRECTLY, bypassing the gate — the only way to build a plan holding an already-broken
# order, which is exactly the state the require_valid cases are about.
func _force_move(unit: Unit, destination: Vector2i) -> MoveAction:
	var move := MoveAction.new()
	var path: Array[Vector2i] = [unit.movement.cell, destination]
	move.init(unit, path, null)
	unit.squad._queue_action(move)
	return move

# ==============================================================================
#  Section A — the CANDIDATE gate (queue_action)
# ==============================================================================

func test_a_heal_on_an_ally_standing_there_is_queueable() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	_sm.join_squad(ally, healer.squad)
	_make_healer(healer)

	assert_bool(_try_aim(healer, ally.movement.cell)).is_true()

func test_a_unit_only_attack_aimed_at_bare_ground_is_refused() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))

	assert_bool(_try_aim(attacker, Vector2i(1, 0))).is_false()
	assert_array(attacker.squad.action_queue).is_empty()   # refused means it never landed

func test_a_map_attack_aimed_at_bare_ground_is_queueable() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	attacker.equipped_weapon.template.main_attack.targets = EquippableData.TargetMode.MAP

	assert_bool(_try_aim(attacker, Vector2i(1, 0))).is_true()

# BOTH behaves like MAP here: it has a map job, so an empty footprint is not a whiff.
func test_a_both_attack_aimed_at_bare_ground_is_queueable() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	attacker.equipped_weapon.template.main_attack.targets = EquippableData.TargetMode.BOTH

	assert_bool(_try_aim(attacker, Vector2i(1, 0))).is_true()

# A null stamp is bare fists — no attack resource to ask, unit-only by definition. Exempting it
# would leave exactly one way to queue a whiff.
func test_bare_fists_aimed_at_bare_ground_are_refused() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {}, false)
	var punch := AttackAction.declare(attacker, attacker.movement.cell, Vector2i(1, 0))

	assert_object(punch.fired_attack).is_null()            # the setup's own premise
	assert_bool(_sm.queue_action(attacker.squad, punch)).is_false()

func test_an_enemy_on_the_aimed_cell_makes_a_damage_attack_queueable() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))

	assert_bool(_try_aim(attacker, foe.movement.cell)).is_true()

# An ALLY standing there is not a victim unless the attack splashes — the same hits_allies rule
# gather_attack_victims applies, so gate and resolve agree on what counts as a target.
func test_an_ally_does_not_rescue_a_non_splashing_attack() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	_sm.join_squad(ally, attacker.squad)

	assert_bool(attacker.get_fired_attack().hits_allies).is_false()   # the setup's own premise
	assert_bool(_try_aim(attacker, ally.movement.cell)).is_false()

# Aim at the cell a squadmate is walking TO. Occupancy is read from the projected position, so a
# moving ally is targetable; live cells here would mean you could only ever heal units standing still.
func test_an_aim_at_a_squadmates_move_destination_is_queueable() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	_sm.join_squad(ally, healer.squad)
	_make_healer(healer)
	assert_bool(_sm.queue_action(ally.squad, _built_move(ally, Vector2i(1, 1)))).is_true()

	assert_bool(_try_aim(healer, Vector2i(1, 1))).is_true()

# Aim at the cell a shove will DROP someone on (#84/#105). At gate time the published knockback is
# the ALREADY-QUEUED aims' shoves, which is exactly the prefix a new aim lands after.
func test_an_aim_at_a_knockback_landing_cell_is_queueable() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	foe.set_projected_knockback(Vector2i(3, 0))   # what a resolved shove publishes

	assert_bool(_try_aim(attacker, Vector2i(3, 0))).is_true()

# Falsifies the test above — it must be the knockback keeping the aim alive, not a stray pass.
func test_the_same_aim_is_refused_with_no_shove_projected() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))

	assert_bool(_try_aim(attacker, Vector2i(3, 0))).is_false()

# require_valid = true: an out-of-leader-range move is refused, so the ally is not going there.
# Aiming at that destination would be choosing an order that rests on an already-invalid one.
func test_an_aim_at_the_destination_of_an_INVALID_move_is_refused() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	_sm.join_squad(ally, healer.squad)
	_make_healer(healer)
	var move := _force_move(ally, Vector2i(20, 20))   # far outside the leader's cohesion range

	assert_bool(_try_aim(healer, Vector2i(20, 20))).is_false()
	assert_bool(move.is_valid).is_false()             # the setup's own premise

# The flip side, and why this cannot read require_valid = false: with the move refused the ally
# stays put, so an aim at the cell it is STILL standing on is live.
func test_an_aim_at_the_origin_of_an_invalid_move_is_queueable() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	_sm.join_squad(ally, healer.squad)
	_make_healer(healer)
	_force_move(ally, Vector2i(20, 20))

	assert_bool(_try_aim(healer, ally.movement.cell)).is_true()

# The scan is over the whole board, not the acting squad: an ally in a DIFFERENT squad is a legal
# heal target and cannot be re-planned by this plan.
func test_a_heal_on_an_ally_outside_the_squad_is_queueable() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var bystander := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	_make_healer(healer)

	assert_bool(_try_aim(healer, bystander.movement.cell)).is_true()

func _built_move(unit: Unit, destination: Vector2i) -> MoveAction:
	var move := MoveAction.new()
	var path: Array[Vector2i] = [unit.movement.cell, destination]
	move.init(unit, path, null)
	return move

# ==============================================================================
#  Section B — a STORED aim, revalidated against a real resolve
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
	(unit.get_equipped_weapon() as KineticMaceWeaponInstance).charge = 1
	unit.active_attack = unit.get_equipped_weapon().template.extra_attacks[0]

func _units_of(board: Dictionary) -> Array[Unit]:
	var result: Array[Unit] = []
	for child in board.units_root.get_children():
		result.append(child as Unit)
	return result

func _board(root_name: String, painted: Rect2i = Rect2i(-4, -4, 14, 14)) -> Dictionary:
	var b := BoardBuilder.build(self, root_name)
	auto_free(b.root)
	BoardBuilder.paint_rect(b.grid, painted)
	b["context"] = BoardContext.new(b.grid, _units_of(b), b.squad_manager, b.terrain_states)
	return b

# game.refresh_action_queue's exact order: resolve, then validate WITH the plan.
func _refresh(b: Dictionary, squad: Squad) -> ResolvedPlan:
	b["context"] = BoardContext.new(b.grid, _units_of(b), b.squad_manager, b.terrain_states)
	var plan: ResolvedPlan = b.squad_manager.resolve_plan(squad, b.context)
	b.squad_manager.validate_squad_plan(squad, plan)
	return plan

# THE regression. The aim that CAUSES a shove must not be judged against its own result: it aims at
# the cell the target is standing on now, and the resolve moves them one tile off it.
func test_a_single_blowback_survives_its_own_shove() -> void:
	var b := _board("WhiffShoveOne")
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(1, 0))
	_arm_mace(hero)

	var aim := AttackAction.declare(hero, Vector2i(0, 0), Vector2i(1, 0))
	assert_bool(b.squad_manager.queue_action(hero.squad, aim)).is_true()
	_refresh(b, hero.squad)

	assert_that(foe.get_projected_destination()).is_equal(Vector2i(2, 0))   # the shove really happened
	assert_array(aim.validation_errors).is_empty()
	assert_bool(b.squad_manager.squad_has_invalid_actions(hero.squad)).is_false()

# ...and the reported case: two shoves on one enemy in a single squad phase. The second aims at the
# cell the FIRST one puts them on, so both must be judged against their own moment in the order.
func test_two_blowbacks_on_one_enemy_both_survive() -> void:
	var b := _board("WhiffShoveTwo")
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(0, 0))
	var ally: Unit = BoardBuilder.spawn(b, _data("Ally", PLAYER), Vector2i(2, 1))
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(1, 0))
	_arm_mace(hero)
	_arm_mace(ally)
	b.squad_manager.join_squad(ally, hero.squad)

	var first := AttackAction.declare(hero, Vector2i(0, 0), Vector2i(1, 0))
	assert_bool(b.squad_manager.queue_action(hero.squad, first)).is_true()
	_refresh(b, hero.squad)   # publishes the first shove, as the game does between orders
	var second := AttackAction.declare(ally, Vector2i(2, 1), Vector2i(2, 0))
	assert_bool(b.squad_manager.queue_action(ally.squad, second)).is_true()
	_refresh(b, hero.squad)

	# Each shove pushes directly away from ITS attacker: hero is left of the foe, ally is below the
	# cell the first shove lands on, so the second pushes up rather than continuing right.
	assert_that(foe.get_projected_destination()).is_equal(Vector2i(2, -1))
	assert_array(first.validation_errors).is_empty()
	assert_array(second.validation_errors).is_empty()
	assert_bool(b.squad_manager.squad_has_invalid_actions(hero.squad)).is_false()

# A shove that cannot land (wall/edge/occupied) publishes nothing, so this is the case the OLD
# end-state read got right — it has to keep working.
func test_a_blocked_shove_leaves_the_aim_valid() -> void:
	var b := _board("WhiffShoveBlocked", Rect2i(0, 0, 5, 5))
	var hero: Unit = BoardBuilder.spawn(b, _data("Hero", PLAYER), Vector2i(3, 2))
	var foe: Unit = BoardBuilder.spawn(b, _data("Foe", ENEMY), Vector2i(4, 2))
	_arm_mace(hero)

	var aim := AttackAction.declare(hero, Vector2i(3, 2), Vector2i(4, 2))
	assert_bool(b.squad_manager.queue_action(hero.squad, aim)).is_true()
	_refresh(b, hero.squad)

	assert_that(foe.get_projected_destination()).is_equal(Vector2i(4, 2))   # nowhere to go
	assert_bool(aim.is_valid).is_true()

# The dev's fork (2026-08-02): a queued MOVE is never refused for breaking an attack — the attack
# falls into invalid instead. A planned heal does not lock the ally in place.
func test_a_heal_falls_invalid_when_the_ally_walks_off_the_cell() -> void:
	var b := _board("WhiffHealMove")
	var healer: Unit = BoardBuilder.spawn(b, _data("Healer", PLAYER), Vector2i(0, 0))
	var ally: Unit = BoardBuilder.spawn(b, _data("Ally", PLAYER), Vector2i(1, 0))
	b.squad_manager.join_squad(ally, healer.squad)
	_make_healer(healer)

	var heal := AttackAction.declare(healer, Vector2i(0, 0), Vector2i(1, 0))
	assert_bool(b.squad_manager.queue_action(healer.squad, heal)).is_true()
	_refresh(b, healer.squad)
	assert_bool(heal.is_valid).is_true()

	var move := MoveAction.new()
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1)]
	move.init(ally, path, null)
	assert_bool(b.squad_manager.queue_action(ally.squad, move)).is_true()   # the move is NOT refused
	_refresh(b, healer.squad)

	assert_bool(heal.is_valid).is_false()
	assert_array(heal.validation_errors).contains(["Nothing left to hit on that cell"])

	# ...and taking the move back brings it home: validity is recomputed from scratch every pass,
	# never latched. This is why a broken aim is INVALIDATED and not deleted from the queue.
	b.squad_manager.remove_action(healer.squad, move)
	_refresh(b, healer.squad)

	assert_bool(heal.is_valid).is_true()

# The declared rule: no plan means attacks are left ALONE, not guessed at. Guessing from the settled
# end state is the whole bug, and validate is called from a dozen places with no plan in hand.
func test_a_validate_with_no_plan_leaves_attacks_untouched() -> void:
	var b := _board("WhiffNoPlan")
	var healer: Unit = BoardBuilder.spawn(b, _data("Healer", PLAYER), Vector2i(0, 0))
	var ally: Unit = BoardBuilder.spawn(b, _data("Ally", PLAYER), Vector2i(1, 0))
	b.squad_manager.join_squad(ally, healer.squad)
	_make_healer(healer)
	var heal := AttackAction.declare(healer, Vector2i(0, 0), Vector2i(1, 0))
	b.squad_manager.queue_action(healer.squad, heal)

	var move := MoveAction.new()
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1)]
	move.init(ally, path, null)
	b.squad_manager.queue_action(ally.squad, move)
	_refresh(b, healer.squad)
	assert_bool(heal.is_valid).is_false()   # the plan-aware pass condemned it

	b.squad_manager.validate_squad_plan(healer.squad)   # ...and a bare pass must not re-judge it

	assert_bool(heal.is_valid).is_true()

# The queue panel draws the resolver's COPIES, which carry no validation of their own — so a refused
# aim shows red only because the derived row reads its source_aim. Without this the bug was silent:
# a dark Execute button over an all-white queue.
func test_a_derived_row_shows_its_aims_validity() -> void:
	var b := _board("WhiffRowTint")
	var healer: Unit = BoardBuilder.spawn(b, _data("Healer", PLAYER), Vector2i(0, 0))
	var ally: Unit = BoardBuilder.spawn(b, _data("Ally", PLAYER), Vector2i(1, 0))
	b.squad_manager.join_squad(ally, healer.squad)
	_make_healer(healer)
	var heal := AttackAction.declare(healer, Vector2i(0, 0), Vector2i(1, 0))
	b.squad_manager.queue_action(healer.squad, heal)

	var move := MoveAction.new()
	var path: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1)]
	move.init(ally, path, null)
	b.squad_manager.queue_action(ally.squad, move)
	var plan := _refresh(b, healer.squad)

	assert_bool(heal.is_valid).is_false()
	assert_array(plan.attacks).is_not_empty()
	for derived: AttackAction in plan.attacks:
		assert_object(derived.source_aim).is_same(heal)
		assert_bool(derived.is_valid).is_true()                       # its own flag is never stamped
		assert_that(derived.get_ui_modulate()).is_equal(INVALID_TINT) # ...it borrows the aim's
