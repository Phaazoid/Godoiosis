# ThreatField (#710, the hover tier): every cell an enemy could attack NEXT turn, as an upper bound
# per archetype -- Hold from where it stands, Sentry only inside its zone, Rushdown across its whole
# move range -- under the same fireable + vertical filters the AI's own candidate builder applies.
# Each case discriminates one rule; the last is the WIRE: every attack the real AI queues lands
# inside the field it was built against. Real managers + TestTiles via board_builder.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")
const ZONE := "post"


func _build_board() -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, Rect2i(0, 0, 8, 3))
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i, armed := true) -> Unit:
	var unit: Unit = BB.spawn(board, H.make_unit_data({}, faction), cell)
	if armed:
		unit.equipped_weapon = H.make_weapon()
	return unit


# Zone = the 4x3 room x:0..3 / y:0..2 (inside the painted 8x3 board).
func _make_zone_manager() -> ZoneManager:
	var zones: ZoneManager = auto_free(ZoneManager.new())
	for x in range(0, 4):
		for y in range(0, 3):
			zones.paint_cell(ZONE, ZoneManager.Kind.PATROL, Vector2i(x, y))
	return zones


func _context(board: Dictionary, zones: ZoneManager = null) -> BoardContext:
	var units: Array[Unit] = []
	for child in board.units_root.get_children():
		units.append(child as Unit)
	return BoardContext.new(board.grid, units, board.squad_manager, null, zones, board.board_heights)


func _bind(unit: Unit, archetype: AIArchetype.Type, zone_name := "") -> Squad:
	var squad: Squad = unit.squad
	squad.archetype = archetype
	squad.zone_name = zone_name
	squad.home_cell = unit.movement.cell
	return squad


func _neighbours(cell: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [cell + Vector2i.LEFT, cell + Vector2i.RIGHT, cell + Vector2i.UP, cell + Vector2i.DOWN]
	out.sort()
	return out


func _sorted(cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = cells.duplicate()
	out.sort()
	return out


func test_a_hold_unit_marks_only_the_reach_from_where_it_stands() -> void:
	var board: Dictionary = _build_board()
	var guard: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1))
	_bind(guard, AIArchetype.Type.HOLD)
	var field := ThreatField.build(_context(board), Team.Faction.PLAYER)
	# A pattern-less weapon reaches the four neighbours and nothing else -- Hold never walks.
	assert_that(_sorted(field.reach_of(guard))).is_equal(_neighbours(Vector2i(3, 1)))
	assert_array(field.attackers_of(Vector2i(2, 1))).contains_exactly([guard])
	assert_array(field.attackers_of(Vector2i(5, 1))).is_empty()


func test_a_rushdown_marks_a_cell_it_must_walk_to_first() -> void:
	var board: Dictionary = _build_board()
	var rusher: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 1))
	_bind(rusher, AIArchetype.Type.RUSHDOWN)
	var mov: int = rusher.get_mov()
	var field := ThreatField.build(_context(board), Team.Faction.PLAYER)
	# One step past its move range is a swing from the far edge of it; two steps past is not.
	assert_bool(field.cells.has(Vector2i(mov + 1, 1))).override_failure_message(
			"a cell one past the move range is reachable by walking then swinging").is_true()
	assert_bool(field.cells.has(Vector2i(mov + 2, 1))).override_failure_message(
			"a cell two past the move range is out of reach next turn").is_false()


func test_a_sentry_ignores_a_cell_in_weapon_reach_but_outside_its_zone() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var sentry: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1))   # zone edge, at its post
	_bind(sentry, AIArchetype.Type.SENTRY, ZONE)
	var field := ThreatField.build(_context(board, zones), Team.Faction.PLAYER)
	# (4, 1) is adjacent -- in weapon reach -- and NOT in the zone: the lure-proofing contract.
	assert_bool(field.cells.has(Vector2i(4, 1))).override_failure_message(
			"a sentry's field leaked past its leash").is_false()
	assert_bool(field.cells.has(Vector2i(2, 1))).is_true()


func test_a_sentry_with_no_zone_holds_its_ground() -> void:
	var board: Dictionary = _build_board()
	var sentry: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 1))
	_bind(sentry, AIArchetype.Type.SENTRY)   # zone_name "" -- the archetype falls through to Hold
	var field := ThreatField.build(_context(board), Team.Faction.PLAYER)
	assert_that(_sorted(field.reach_of(sentry))).is_equal(_neighbours(Vector2i(0, 1)))


func test_a_ledge_above_the_melee_rule_is_unmarked() -> void:
	var board: Dictionary = _build_board()
	var brawler: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1), false)   # bare fists = melee
	_bind(brawler, AIArchetype.Type.HOLD)
	board.board_heights.set_cell(Vector2i(4, 1), 2 * Terrain.UNITS_PER_LEVEL)   # a sheer two-level rise
	var field := ThreatField.build(_context(board), Team.Faction.PLAYER)
	assert_bool(field.cells.has(Vector2i(2, 1))).is_true()
	assert_bool(field.cells.has(Vector2i(4, 1))).override_failure_message(
			"a cell above the melee rule's tolerance was marked as threatened").is_false()


func test_a_downed_enemy_threatens_nothing() -> void:
	var board: Dictionary = _build_board()
	var body: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1))
	_bind(body, AIArchetype.Type.HOLD)
	body._go_downed(false)
	var field := ThreatField.build(_context(board), Team.Faction.PLAYER)
	assert_bool(field.cells.is_empty()).is_true()
	assert_bool(field.by_unit.has(body)).is_false()


func test_a_player_unit_is_never_part_of_the_field() -> void:
	var board: Dictionary = _build_board()
	var ally: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(3, 1))
	_bind(ally, AIArchetype.Type.HOLD)
	var field := ThreatField.build(_context(board), Team.Faction.PLAYER)
	assert_bool(field.cells.is_empty()).is_true()


func test_the_leash_is_a_sentry_squads_zone_and_nobody_elses() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var sentry: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(1, 1))
	var rusher: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(6, 1))
	_bind(sentry, AIArchetype.Type.SENTRY, ZONE)
	_bind(rusher, AIArchetype.Type.RUSHDOWN, ZONE)   # names the zone, is not leashed to it
	var ctx := _context(board, zones)
	assert_int(ThreatField.leash_of(sentry.squad, ctx).size()).is_equal(12)
	assert_array(ThreatField.leash_of(rusher.squad, ctx)).is_empty()


# THE WIRE. The field is built against the board BEFORE the AI plans, then the real archetypes plan
# through the real SquadManager: every attack they queue must aim inside the field, or the preview
# promised safety the AI did not honour. Both walking archetypes, so a field blind to movement
# (Hold's envelope for everyone) reds here.
func test_every_attack_the_ai_queues_lands_inside_the_field() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var sentry: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 0))
	var rusher: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(7, 2))
	_bind(sentry, AIArchetype.Type.SENTRY, ZONE)
	_bind(rusher, AIArchetype.Type.RUSHDOWN)
	var _intruder: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(3, 1))   # in the zone, 4 steps from either
	var ctx := _context(board, zones)
	var field := ThreatField.build(ctx, Team.Faction.PLAYER)
	var aimed := 0
	for squad: Squad in [sentry.squad, rusher.squad]:
		AIController.plan_squad(squad, ctx, board.squad_manager)
		for action in squad.action_queue:
			if not (action is AttackAction):
				continue
			var aim := action as AttackAction
			aimed += 1
			assert_bool(field.by_unit.get(aim.actor, {}).has(aim.target_cell)).override_failure_message(
					"%s aimed at %s, which the field never marked" % [aim.actor.get_unit_name(), aim.target_cell]).is_true()
	assert_int(aimed).override_failure_message("no attack was queued -- the wire was never exercised").is_greater(0)
