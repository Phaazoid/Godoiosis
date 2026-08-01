# Whiff re-validation (SquadPlanValidator._revalidate_unit_attacks). An attack aims at a CELL and
# derives its victims at resolve time (#47/#15), so a re-planned move can leave a queued order
# pointing at bare ground. `AttackData.targets` decides whether that matters: a MAP or BOTH attack
# still deposits terrain effects (#50) and stays legal, a UNIT-only one does nothing and invalidates.
#
# The two cases that must NOT invalidate are the whole point of reading PROJECTED positions rather
# than live ones -- aiming where a squadmate is walking to, and aiming where a shove will put
# someone. Without them you could only ever target units that are standing still.
#
# The counterweight is require_valid = true (dev, 2026-07-31): a move that will not happen moves
# nobody, so an aim at its destination is a whiff. Reading validity here is what stops the strict
# queue-time gate from accepting an order built on another order that is already refused.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _sm: SquadManager

func before_test() -> void:
	_sm = H.make_manager(self)

# Equip `healer` with a heal-authored weapon and queue an aim at `cell` the way the
# ATTACK_TARGETING click does — declare() stamps the pick, target stays null.
func _queue_heal(healer: Unit, cell: Vector2i) -> AttackAction:
	var weapon := H.make_weapon(4)
	weapon.template.main_attack.heals = true
	weapon.template.main_attack.hits_allies = true
	healer.equipped_weapon = weapon
	return _queue_aim(healer, cell)

func _queue_aim(attacker: Unit, cell: Vector2i) -> AttackAction:
	var aim := AttackAction.declare(attacker, attacker.movement.cell, cell)
	attacker.squad._queue_action(aim)
	return aim

func _queue_move(unit: Unit, destination: Vector2i) -> MoveAction:
	var move := MoveAction.new()
	var path: Array[Vector2i] = [unit.movement.cell, destination]
	move.init(unit, path, null)
	unit.squad._queue_action(move)
	return move

# ==============================================================================
#  The reported bug
# ==============================================================================

func test_heal_is_valid_while_the_ally_is_still_on_the_aimed_cell() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	_sm.join_squad(ally, healer.squad)
	var heal := _queue_heal(healer, ally.movement.cell)

	_sm.validate_squad_plan(healer.squad)

	assert_bool(heal.is_valid).is_true()

# Re-planning the target's move empties the aimed cell, so the heal is left healing nothing and
# must invalidate rather than sit in the queue as a silent no-op.
func test_heal_invalidated_when_the_target_moves_off_the_aimed_cell() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	_sm.join_squad(ally, healer.squad)
	var heal := _queue_heal(healer, ally.movement.cell)
	_queue_move(ally, Vector2i(2, 0))

	_sm.validate_squad_plan(healer.squad)

	assert_bool(heal.is_valid).is_false()

# ...and cancelling that move brings the heal back: validity is recomputed from scratch every
# pass, never latched. This is why a broken aim is INVALIDATED and not deleted from the queue.
func test_heal_revalidates_when_the_move_is_taken_back() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	_sm.join_squad(ally, healer.squad)
	var heal := _queue_heal(healer, ally.movement.cell)
	var move := _queue_move(ally, Vector2i(2, 0))
	_sm.validate_squad_plan(healer.squad)
	assert_bool(heal.is_valid).is_false()

	_sm.remove_action(healer.squad, move)
	_sm.validate_squad_plan(healer.squad)

	assert_bool(heal.is_valid).is_true()

# ==============================================================================
#  Aiming where someone WILL be — the cases that must stay valid
# ==============================================================================

# Vital case 1: heal the cell a squadmate is walking TO. Occupancy is read from the projected
# position, so a moving ally is targetable; reading live cells here would mean you could only ever
# heal squadmates who stand still.
func test_heal_aimed_at_a_squadmates_move_destination_is_valid() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	_sm.join_squad(ally, healer.squad)
	_queue_move(ally, Vector2i(1, 1))
	var heal := _queue_heal(healer, Vector2i(1, 1))

	_sm.validate_squad_plan(healer.squad)

	assert_bool(heal.is_valid).is_true()

# Vital case 2: aim at the cell a shove will DROP someone on (#84/#105). The validator reads
# projected knockback for this question specifically — resolve_plan publishes it, and an attack's
# validity is a leaf, so nothing loops.
func test_an_attack_aimed_at_a_knockback_landing_cell_is_valid() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	foe.set_projected_knockback(Vector2i(3, 0))   # what a resolved shove publishes
	var aim := _queue_aim(attacker, Vector2i(3, 0))

	_sm.validate_squad_plan(attacker.squad)

	assert_bool(aim.is_valid).is_true()

# The negative twin of the case above: with no shove projected, that same cell is bare ground.
# Falsifies the test above — it must be the knockback that keeps the aim alive, not a stray pass.
func test_the_same_aim_is_invalid_with_no_shove_projected() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var aim := _queue_aim(attacker, Vector2i(3, 0))

	_sm.validate_squad_plan(attacker.squad)

	assert_bool(aim.is_valid).is_false()

# ==============================================================================
#  require_valid = true — a move that will not happen moves nobody
# ==============================================================================

# An out-of-leader-range move is refused, so the ally is not going there. Aiming at that
# destination would be choosing an order that rests on an already-invalid one.
func test_an_aim_at_the_destination_of_an_INVALID_move_is_a_whiff() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	_sm.join_squad(ally, healer.squad)
	var move := _queue_move(ally, Vector2i(20, 20))   # far outside the leader's cohesion range
	var heal := _queue_heal(healer, Vector2i(20, 20))

	_sm.validate_squad_plan(healer.squad)

	assert_bool(move.is_valid).is_false()   # the setup's own premise
	assert_bool(heal.is_valid).is_false()

# The flip side, and why this cannot read require_valid = false: with the move refused the ally
# stays put, so an aim at the cell it is STILL standing on is live.
func test_an_aim_at_the_origin_of_an_invalid_move_stays_valid() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	_sm.join_squad(ally, healer.squad)
	var move := _queue_move(ally, Vector2i(20, 20))
	var heal := _queue_heal(healer, ally.movement.cell)

	_sm.validate_squad_plan(healer.squad)

	assert_bool(move.is_valid).is_false()
	assert_bool(heal.is_valid).is_true()

# ==============================================================================
#  Scope of the rule
# ==============================================================================

# The scan is over the whole board, not the acting squad: an ally in a DIFFERENT squad is a legal
# heal target and cannot be re-planned by this plan, so the order stays valid.
func test_heal_on_an_ally_outside_the_squad_stays_valid() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var bystander := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	var heal := _queue_heal(healer, bystander.movement.cell)

	_sm.validate_squad_plan(healer.squad)

	assert_bool(heal.is_valid).is_true()

# The footprint is measured from the actor's PROJECTED origin, so the healer walking away does not
# by itself break the aim — the aimed cell is unchanged and still occupied.
func test_the_healers_own_move_does_not_invalidate_a_still_occupied_cell() -> void:
	var healer := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	_sm.join_squad(ally, healer.squad)
	var heal := _queue_heal(healer, ally.movement.cell)
	_queue_move(healer, Vector2i(0, 1))

	_sm.validate_squad_plan(healer.squad)

	assert_bool(heal.is_valid).is_true()

# The generalization: this is keyed on `targets`, not on `heals`. A UNIT-only damage attack aimed
# at bare ground is the same whiff and invalidates identically.
func test_a_unit_only_damage_attack_aimed_at_an_empty_cell_invalidates() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var aim := _queue_aim(attacker, Vector2i(1, 0))

	_sm.validate_squad_plan(attacker.squad)

	assert_bool(aim.is_valid).is_false()

# ...and the other side of that same flag: a MAP attack has business on empty ground (#47/#50),
# so it is never a whiff. This is the guard that keeps the rule keyed on `targets`.
func test_a_map_attack_aimed_at_an_empty_cell_stays_valid() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	attacker.equipped_weapon.template.main_attack.targets = EquippableData.TargetMode.MAP
	var aim := _queue_aim(attacker, Vector2i(1, 0))

	_sm.validate_squad_plan(attacker.squad)

	assert_bool(aim.is_valid).is_true()

# BOTH behaves like MAP for this rule: it has a map job, so an empty footprint is not a whiff.
func test_a_both_attack_aimed_at_an_empty_cell_stays_valid() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	attacker.equipped_weapon.template.main_attack.targets = EquippableData.TargetMode.BOTH
	var aim := _queue_aim(attacker, Vector2i(1, 0))

	_sm.validate_squad_plan(attacker.squad)

	assert_bool(aim.is_valid).is_true()

# A null stamp is bare fists — no attack resource to ask, unit-only by definition. Exempting it
# would leave exactly one way to queue a whiff.
func test_bare_fists_aimed_at_an_empty_cell_is_a_whiff() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0), {}, false)
	var punch := _queue_aim(attacker, Vector2i(1, 0))

	assert_object(punch.fired_attack).is_null()   # the setup's own premise
	_sm.validate_squad_plan(attacker.squad)

	assert_bool(punch.is_valid).is_false()

# ==============================================================================
#  Eligibility comes from RulesService.is_attack_victim — the real gather's own rule
# ==============================================================================

func test_an_enemy_on_the_aimed_cell_makes_a_damage_attack_valid() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var foe := H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	var aim := _queue_aim(attacker, foe.movement.cell)

	_sm.validate_squad_plan(attacker.squad)

	assert_bool(aim.is_valid).is_true()

# An ALLY standing there is not a victim unless the attack splashes. Same hits_allies rule
# gather_attack_victims applies, so the preview and the resolve agree on what counts as a target.
func test_an_ally_on_the_cell_does_not_rescue_a_non_splashing_attack() -> void:
	var attacker := H.spawn_solo(self, _sm, PLAYER, Vector2i(0, 0))
	var ally := H.spawn_solo(self, _sm, PLAYER, Vector2i(1, 0))
	_sm.join_squad(ally, attacker.squad)
	var aim := _queue_aim(attacker, ally.movement.cell)

	assert_bool(aim.fired_attack.hits_allies).is_false()   # the setup's own premise
	_sm.validate_squad_plan(attacker.squad)

	assert_bool(aim.is_valid).is_false()
