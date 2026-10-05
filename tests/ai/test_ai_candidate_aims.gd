# Where the AI aims (#1220): heals at our own side and never at an enemy, a body stabilised only when
# nobody can rescue it, a directional attack by FACING rather than by the cardinal toward an enemy, a
# placed blast set down beside a target it cannot aim at, and a map-only attack kept for what it does
# this pass -- the current, a payload, ice melted under a hostile. Every case drives the AI's real
# door and asserts on what it queued or what that plan hits.
#
# Rulings on #117 (2026-10-04/05): 3 (heals priced like damage, never at enemies), 16 (a body only
# when nobody can rescue it).
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const ATTACK_ONLY: Array = [BaseAction.ActionType.ATTACK]
const PLUS: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]


func _build_board(size := Rect2i(0, 0, 8, 8)) -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, size)
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i, stats := {}, power := 3) -> Unit:
	var unit: Unit = BB.spawn(board, H.make_unit_data(stats, faction), cell)
	unit.equipped_weapon = H.make_weapon(power)
	return unit


func _ctx(board: Dictionary) -> BoardContext:
	return board.squad_manager.board_source.call()


func _main(unit: Unit) -> WeaponAttackData:
	return (unit.get_equipped_weapon() as WeaponInstance).template.main_attack


func _give_extra(unit: Unit, attack: WeaponAttackData) -> void:
	var extras: Array[WeaponAttackData] = [attack]
	(unit.get_equipped_weapon() as WeaponInstance).template.extra_attacks = extras


func _queued_attack(unit: Unit) -> AttackAction:
	for action in unit.squad.action_queue:
		if action.action_type == BaseAction.ActionType.ATTACK and action.actor == unit:
			return action as AttackAction
	return null


func _hits(board: Dictionary, squad: Squad, victim: Unit) -> bool:
	var plan: ResolvedPlan = board.squad_manager.resolve_plan(squad, _ctx(board))
	for a in plan.attacks:
		if a.target == victim:
			return true
	return false


func _ice(board: Dictionary, cell: Vector2i) -> void:
	BB.paint_cell(board.grid, cell, BB.WATER_ATLAS)
	var freeze := ResolvedCellEffect.new()
	freeze.cell = cell
	freeze.states_added.assign([Terrain.TileState.FROZEN])
	(board.terrain_states as TerrainStateManager).apply(freeze)


func _heal(power: int, reach := 2) -> WeaponAttackData:
	var heal := WeaponAttackData.new()
	heal.power = power
	heal.heals = true
	heal.hits_allies = true   # as every authored heal is
	P.point(heal, reach)
	return heal


# --- Heals (rulings 3 and 16) ---------------------------------------------------------------------

func test_a_healer_mends_a_hurt_ally_over_a_weak_swing() -> void:
	var board := _build_board()
	var healer := _spawn(board, ENEMY, Vector2i(2, 2), {}, 1)   # its main: a weak swing
	var heal := _heal(8)
	_give_extra(healer, heal)
	var ally := _spawn(board, ENEMY, Vector2i(2, 4), {Stats.Stat.MHP: 30})
	ally.set_current_hp(5)
	_spawn(board, PLAYER, Vector2i(3, 2), {Stats.Stat.MHP: 30})
	AITactics.queue_main_action(healer, _ctx(board), board.squad_manager, ATTACK_ONLY)

	var aim := _queued_attack(healer)
	assert_object(aim).override_failure_message("the healer queued nothing").is_not_null()
	if aim == null:
		return
	assert_object(aim.fired_attack).override_failure_message("the healer swung instead of mending its ally").is_same(heal)
	assert_that(aim.target_cell).is_equal(ally.movement.cell)


func test_a_heal_is_never_aimed_at_an_enemy() -> void:
	var board := _build_board()
	var healer := _spawn(board, ENEMY, Vector2i(2, 2))
	(healer.get_equipped_weapon() as WeaponInstance).template.main_attack = _heal(8, 1)
	var foe := _spawn(board, PLAYER, Vector2i(3, 2), {Stats.Stat.MHP: 30})
	foe.set_current_hp(5)
	var queued := AITactics.queue_main_action(healer, _ctx(board), board.squad_manager, ATTACK_ONLY)

	assert_bool(queued).override_failure_message("the healer aimed its heal at a hurt enemy").is_false()


func test_a_heal_ignores_an_ally_at_full_health() -> void:
	var board := _build_board()
	var healer := _spawn(board, ENEMY, Vector2i(2, 2))
	(healer.get_equipped_weapon() as WeaponInstance).template.main_attack = _heal(8, 1)
	_spawn(board, ENEMY, Vector2i(3, 2))
	var queued := AITactics.queue_main_action(healer, _ctx(board), board.squad_manager, ATTACK_ONLY)

	assert_bool(queued).override_failure_message("the healer spent its turn healing nobody").is_false()


# A body with its clock running, beside the healer's reach. Who can rescue it decides the heal.
func _body_board(rescuer: bool) -> Dictionary:
	var board := _build_board()
	var healer := _spawn(board, ENEMY, Vector2i(2, 2))
	(healer.get_equipped_weapon() as WeaponInstance).template.main_attack = _heal(8)
	var body := _spawn(board, ENEMY, Vector2i(2, 4))
	body.force_down()
	if rescuer:
		healer.squad.archetype = AIArchetype.Type.HOLD   # its list carries RESCUE
		var mate := _spawn(board, ENEMY, Vector2i(1, 4))
		board.squad_manager.join_squad(mate, healer.squad)
	return {"board": board, "healer": healer, "body": body}


func test_a_heal_stabilises_a_body_nobody_can_rescue() -> void:
	var s := _body_board(false)
	var healer: Unit = s.healer
	AITactics.queue_main_actions_for_squad(healer.squad, _ctx(s.board), (s.board as Dictionary).squad_manager)

	var aim := _queued_attack(healer)
	assert_object(aim).override_failure_message("the healer left a body to bleed out with nobody to rescue it") \
		.is_not_null()
	if aim == null:
		return
	assert_that(aim.target_cell).is_equal((s.body as Unit).movement.cell)


func test_a_heal_leaves_a_body_a_squadmate_will_rescue() -> void:
	var s := _body_board(true)
	var healer: Unit = s.healer
	var body: Unit = s.body
	AITactics.queue_main_actions_for_squad(healer.squad, _ctx(s.board), (s.board as Dictionary).squad_manager)

	assert_object(_queued_attack(healer)).override_failure_message(
			"the healer spent its turn on a body its squadmate rescues").is_null()
	var rescued := false
	for action in healer.squad.action_queue:
		rescued = rescued or (action is RescueAction and (action as RescueAction).target == body)
	assert_bool(rescued).override_failure_message("fixture: the squadmate must be able to rescue the body").is_true()


# --- Facings, placed blasts and map-only aims ----------------------------------------------------

# A stamp that strikes one cell forward and two to the right. Facing east from (2,2) it covers (3,4);
# the cardinal from (2,2) toward (3,4) is SOUTH, whose turn of the same stamp lands on (0,3).
func test_a_directional_attack_finds_the_facing_that_reaches_a_side_lane() -> void:
	var board := _build_board()
	var attacker := _spawn(board, ENEMY, Vector2i(2, 2))
	var swipe := _main(attacker)
	swipe.power = 40
	var offsets: Array[Vector2i] = [Vector2i(2, -1)]
	P.stamped(swipe, 0, offsets)
	swipe.swing = false
	var foe := _spawn(board, PLAYER, Vector2i(3, 4), {Stats.Stat.MHP: 30})
	AITactics.queue_main_action(attacker, _ctx(board), board.squad_manager, ATTACK_ONLY)

	assert_object(_queued_attack(attacker)).override_failure_message(
			"the AI found no facing for a target in its stamp's side lane").is_not_null()
	assert_bool(_hits(board, attacker.squad, foe)).is_true()


# A blast that may only land two cells away, beside an enemy one cell away: the only way to hit it is
# to drop the blast next to it.
func test_a_placed_blast_lands_beside_a_target_it_cannot_aim_at() -> void:
	var board := _build_board()
	var attacker := _spawn(board, ENEMY, Vector2i(2, 2))
	var blast := _main(attacker)
	blast.power = 40
	P.stamped(blast, 2, PLUS, 2)
	var foe := _spawn(board, PLAYER, Vector2i(3, 2), {Stats.Stat.MHP: 30})
	AITactics.queue_main_action(attacker, _ctx(board), board.squad_manager, ATTACK_ONLY)

	assert_object(_queued_attack(attacker)).override_failure_message(
			"the AI would not drop its blast beside a target too close to aim at").is_not_null()
	assert_bool(_hits(board, attacker.squad, foe)).is_true()


# A map-only shock aimed into water reaches a soaked enemy out of its own range through the current.
func test_a_map_only_shock_aimed_into_water_reaches_a_wet_enemy() -> void:
	var board := _build_board()
	var attacker := _spawn(board, ENEMY, Vector2i(2, 2))
	var zap := _main(attacker)
	zap.power = 10
	zap.elemental_damage_type = Elemental.Element.SHOCK
	zap.targets = EquippableData.TargetMode.MAP
	P.point(zap, 1)
	BB.paint_cell(board.grid, Vector2i(3, 2), BB.WATER_ATLAS)
	var foe := _spawn(board, PLAYER, Vector2i(4, 2), {Stats.Stat.MHP: 30})
	foe.add_element_state(Elemental.State.WET, 2)
	AITactics.queue_main_action(attacker, _ctx(board), board.squad_manager, ATTACK_ONLY)

	var aim := _queued_attack(attacker)
	assert_object(aim).override_failure_message("the AI never aimed its current into the water").is_not_null()
	assert_bool(_hits(board, attacker.squad, foe)).is_true()


# A map-only carrier hits nobody itself; the payload it drops does.
func test_a_map_only_carrier_is_aimed_for_the_payload_it_drops() -> void:
	var board := _build_board()
	var attacker := _spawn(board, ENEMY, Vector2i(2, 2))
	var carrier := _main(attacker)
	carrier.power = 1
	carrier.targets = EquippableData.TargetMode.MAP
	P.point(carrier, 2)
	var bomb := WeaponAttackData.new()
	bomb.power = 30
	P.stamped(bomb, 1, PLUS)
	carrier.payload = bomb
	var foe := _spawn(board, PLAYER, Vector2i(4, 2), {Stats.Stat.MHP: 30})
	AITactics.queue_main_action(attacker, _ctx(board), board.squad_manager, ATTACK_ONLY)

	assert_object(_queued_attack(attacker)).override_failure_message(
			"the AI never threw a carrier whose payload lands on an enemy").is_not_null()
	assert_bool(_hits(board, attacker.squad, foe)).is_true()


# A map-only fire on the ice under an enemy drowns it -- a removal no attack row carries, so only the
# sink can tell the score. A clean shot that removes nobody is the alternative it must beat.
func test_a_map_only_fire_that_drowns_an_enemy_beats_a_clean_shot() -> void:
	var board := _build_board()
	_ice(board, Vector2i(3, 2))
	var attacker := _spawn(board, ENEMY, Vector2i(2, 2))
	var fire := _main(attacker)
	fire.power = 1
	fire.elemental_damage_type = Elemental.Element.FIRE
	fire.targets = EquippableData.TargetMode.MAP
	P.point(fire, 1)
	var clean := WeaponAttackData.new()
	clean.power = 1
	P.point(clean, 2)
	_give_extra(attacker, clean)
	var swimmer := _spawn(board, PLAYER, Vector2i(3, 2), {Stats.Stat.MHP: 40})
	_spawn(board, PLAYER, Vector2i(2, 4), {Stats.Stat.MHP: 40})
	AITactics.queue_main_action(attacker, _ctx(board), board.squad_manager, ATTACK_ONLY)

	var aim := _queued_attack(attacker)
	assert_object(aim).is_not_null()
	if aim == null:
		return
	assert_object(aim.fired_attack).override_failure_message(
			"the AI took a scratch over melting the ice under an enemy").is_same(fire)
	assert_that(aim.target_cell).is_equal(swimmer.movement.cell)
