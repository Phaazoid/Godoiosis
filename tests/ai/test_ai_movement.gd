# Where an AI squad stands (#1220): formation plus pins. A member with nobody to hit steps inside the
# leash to a cell that has someone (ruling 9); a member with nobody to hit from anywhere walks beside
# a body when its archetype rescues (ruling 12); a unit with nothing to fire falls back out of reach
# (ruling 5); Hold never moves (ruling 17); and nobody ends on a hazard while a safe cell offers the
# same -- though a kill from a burning tile still beats a scratch from safe ground (rulings 15, 19).
#
# Every case plans through the AI's real door and asserts on the plan it left. Positions that depend
# on a unit's movement are DERIVED from its MOV rather than assumed.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY
const ZONE := "post"


func before_test() -> void:
	AIProfiles.use_fixtures({"": AIProfile.new()})   # #1230: this suite owns its AI profile


func after_test() -> void:
	AIProfiles.clear_fixtures()


func _build_board(size: Rect2i) -> Dictionary:
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


func _plan(squad: Squad, board: Dictionary) -> void:
	AIController.plan_squad(squad, _ctx(board), board.squad_manager)


func _burn(board: Dictionary, cell: Vector2i) -> void:
	var fire := ResolvedCellEffect.new()
	fire.cell = cell
	fire.states_added.assign([Terrain.TileState.BURNING])
	(board.terrain_states as TerrainStateManager).apply(fire)


func _attack_of(unit: Unit) -> AttackAction:
	for action in unit.squad.action_queue:
		if action is AttackAction and action.actor == unit:
			return action as AttackAction
	return null


func _healer_weapon() -> WeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.CHAINSWORD
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = 8
	template.main_attack.heals = true
	template.main_attack.hits_allies = true
	return WeaponInstance.make(template)


func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return GridUtils.manhattan_distance(a, b) == 1


# --- Ruling 9: damage moves a member, inside the leash ---------------------------------------------

# The leader walks up to the target; the member's formation cell keeps its offset, two cells off it.
# A follow cell beside the target is in reach of the (faster) member.
func test_a_member_steps_inside_the_leash_to_hit_someone() -> void:
	var board := _build_board(Rect2i(0, 0, 24, 6))
	var leader := _spawn(board, ENEMY, Vector2i(1, 2))
	var member := _spawn(board, ENEMY, Vector2i(1, 3), {Stats.Stat.DEX: 30})
	board.squad_manager.join_squad(member, leader.squad)
	var mov := leader.get_mov()
	var target := _spawn(board, PLAYER, Vector2i(2 + mov, 2), {Stats.Stat.MHP: 40})

	_plan(leader.squad, board)

	board.squad_manager.validate_squad_plan(leader.squad)
	assert_bool(board.squad_manager.squad_has_invalid_actions(leader.squad)) \
		.override_failure_message("the member's step broke the squad's leash").is_false()
	assert_bool(_adjacent(member.get_projected_destination(), target.movement.cell)).override_failure_message(
			"the member stayed on a formation cell with nobody to hit (%s)" % [member.get_projected_destination()]) \
		.is_true()
	assert_object(_attack_of(member)).is_not_null()


# --- Ruling 17: Hold never moves -------------------------------------------------------------------

func test_a_hold_squad_never_moves_to_find_a_target() -> void:
	var board := _build_board(Rect2i(0, 0, 12, 4))
	var leader := _spawn(board, ENEMY, Vector2i(1, 1))
	var member := _spawn(board, ENEMY, Vector2i(1, 2))
	board.squad_manager.join_squad(member, leader.squad)
	leader.squad.archetype = AIArchetype.Type.HOLD
	_spawn(board, PLAYER, Vector2i(4, 1))

	_plan(leader.squad, board)

	for unit: Unit in [leader, member]:
		assert_that(unit.get_projected_destination()).override_failure_message(
				"a Hold squad moved").is_equal(unit.movement.cell)


# --- Ruling 12: the rescue walk --------------------------------------------------------------------

# A Sentry squad meets an intruder in its zone. Its healer has nobody hostile to hit from any cell;
# a squadmate lies downed inside the zone, so the healer walks beside it and picks it up.
func test_a_member_with_nobody_to_hit_walks_beside_a_body_and_rescues_it() -> void:
	var board := _build_board(Rect2i(0, 0, 8, 6))
	for x in range(0, 7):
		for y in range(0, 5):
			(board.zone_manager as ZoneManager).paint_cell(ZONE, ZoneManager.Kind.PATROL, Vector2i(x, y))
	var leader := _spawn(board, ENEMY, Vector2i(1, 1))
	var healer := _spawn(board, ENEMY, Vector2i(1, 2))
	healer.equipped_weapon = _healer_weapon()
	board.squad_manager.join_squad(healer, leader.squad)
	leader.squad.archetype = AIArchetype.Type.SENTRY
	leader.squad.zone_name = ZONE
	leader.squad.home_cell = leader.movement.cell
	var body := _spawn(board, ENEMY, Vector2i(3, 4))
	body.force_down()
	_spawn(board, PLAYER, Vector2i(5, 1), {Stats.Stat.MHP: 40})

	_plan(leader.squad, board)

	assert_bool(_adjacent(healer.get_projected_destination(), body.get_projected_destination())) \
		.override_failure_message("the healer did not walk to the body (%s)" % [healer.get_projected_destination()]) \
		.is_true()
	var rescued := false
	for action in leader.squad.action_queue:
		rescued = rescued or (action is RescueAction and action.actor == healer and (action as RescueAction).target == body)
	assert_bool(rescued).override_failure_message("the healer walked to the body and did not rescue it").is_true()


# --- Ruling 5: nothing to fire ---------------------------------------------------------------------

# A lone unit with nothing to fire used to walk up to an enemy and stand there. It falls back to a
# cell nobody can attack it on.
func test_a_lone_unit_with_nothing_to_fire_falls_back_out_of_reach() -> void:
	var board := _build_board(Rect2i(0, 0, 16, 3))
	var dry := _spawn(board, ENEMY, Vector2i(6, 1))
	dry.equipped_weapon = null
	assert_bool(dry.get_selectable_attacks().is_empty()).override_failure_message(
			"fixture: the unit must have nothing to fire").is_true()
	_spawn(board, PLAYER, Vector2i(2, 1))
	var field := ThreatField.build(_ctx(board), ENEMY)

	_plan(dry.squad, board)

	assert_bool(field.cells.has(dry.get_projected_destination())).override_failure_message(
			"the unarmed unit ended at %s, inside the enemy's reach" % [dry.get_projected_destination()]).is_false()


# A dry member of an armed squad leaves a formation cell an enemy could hit for one it cannot.
# The enemy holds its ground, so its threat is exactly the cells beside it.
func test_a_dry_member_falls_back_to_a_cell_nobody_threatens() -> void:
	var board := _build_board(Rect2i(0, 0, 14, 6))
	var leader := _spawn(board, ENEMY, Vector2i(2, 2), {Stats.Stat.DEX: 30})
	var dry := _spawn(board, ENEMY, Vector2i(3, 3), {Stats.Stat.DEX: 30})
	dry.equipped_weapon = null
	board.squad_manager.join_squad(dry, leader.squad)
	var target := _spawn(board, PLAYER, Vector2i(7, 2), {Stats.Stat.MHP: 40})
	target.squad.archetype = AIArchetype.Type.HOLD
	var field := ThreatField.build(_ctx(board), ENEMY)

	_plan(leader.squad, board)

	assert_bool(field.cells.has(dry.get_projected_destination())).override_failure_message(
			"the dry member ended at %s, beside the enemy" % [dry.get_projected_destination()]).is_false()


# --- Rulings 15 and 19: hazards ---------------------------------------------------------------------

func test_a_leader_fights_from_safe_ground_over_a_burning_tile() -> void:
	var board := _build_board(Rect2i(0, 0, 12, 5))
	var leader := _spawn(board, ENEMY, Vector2i(2, 2), {Stats.Stat.DEX: 30})
	var target := _spawn(board, PLAYER, Vector2i(6, 2), {Stats.Stat.MHP: 40})
	_burn(board, Vector2i(5, 2))

	_plan(leader.squad, board)

	var at := leader.get_projected_destination()
	assert_that(at).override_failure_message("the leader ended its turn on the burning tile").is_not_equal(Vector2i(5, 2))
	assert_bool(_adjacent(at, target.movement.cell)).override_failure_message(
			"fixture: the leader must still fight, from %s" % [at]).is_true()


func test_a_leader_avoids_ending_in_a_hostile_watch() -> void:
	var board := _build_board(Rect2i(0, 0, 12, 5))
	var leader := _spawn(board, ENEMY, Vector2i(2, 2), {Stats.Stat.DEX: 30})
	var watcher := _spawn(board, PLAYER, Vector2i(6, 2), {Stats.Stat.MHP: 40})
	var lane: Array[Vector2i] = [Vector2i(5, 2)]
	var attack: AttackData = (watcher.get_equipped_weapon() as WeaponInstance).template.main_attack
	watcher.watch = Watch.arm(watcher, watcher.movement.cell, Vector2i(5, 2), lane, attack)

	_plan(leader.squad, board)

	var at := leader.get_projected_destination()
	assert_that(at).override_failure_message("the leader ended its turn in the watch's lane").is_not_equal(Vector2i(5, 2))
	assert_bool(_adjacent(at, watcher.movement.cell)).is_true()


# The only removal is from a burning tile -- a frail enemy in a pocket whose one way in burns -- and a
# sturdy enemy beside safe ground offers only a scratch. The kill wins.
func test_a_kill_from_a_burning_tile_beats_a_scratch_from_safe_ground() -> void:
	var board := _build_board(Rect2i(0, 0, 10, 5))
	for hole: Vector2i in [Vector2i(5, 0), Vector2i(7, 0)]:
		board.grid.erase_cell(hole)
	var leader := _spawn(board, ENEMY, Vector2i(2, 2), {Stats.Stat.DEX: 30})
	_spawn(board, PLAYER, Vector2i(6, 0), {Stats.Stat.MHP: 2})
	_spawn(board, PLAYER, Vector2i(2, 4), {Stats.Stat.MHP: 40})
	_burn(board, Vector2i(6, 1))

	_plan(leader.squad, board)

	assert_that(leader.get_projected_destination()).override_failure_message(
			"the leader passed up a kill because the cell it is taken from burns").is_equal(Vector2i(6, 1))


# A member whose formation cell burns is placed beside it instead. The member is a healer with nobody
# to mend, so nothing but the formation decides where it ends.
func test_a_member_is_never_placed_on_a_burning_formation_cell() -> void:
	var board := _build_board(Rect2i(0, 0, 14, 5))
	var leader := _spawn(board, ENEMY, Vector2i(2, 2), {Stats.Stat.DEX: 30})
	var healer := _spawn(board, ENEMY, Vector2i(1, 2), {Stats.Stat.DEX: 30})
	healer.equipped_weapon = _healer_weapon()
	board.squad_manager.join_squad(healer, leader.squad)
	var target := _spawn(board, PLAYER, Vector2i(7, 2), {Stats.Stat.MHP: 40})
	_burn(board, Vector2i(5, 2))
	assert_that(AITactics.best_attack_destination(leader, target, _ctx(board))) \
		.override_failure_message("fixture: the leader must stand at (6, 2), so the healer's offset cell is the fire") \
		.is_equal(Vector2i(6, 2))

	_plan(leader.squad, board)

	assert_that(healer.get_projected_destination()).override_failure_message(
			"the healer was placed on the burning tile").is_not_equal(Vector2i(5, 2))
