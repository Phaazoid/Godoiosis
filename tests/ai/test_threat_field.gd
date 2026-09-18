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


func _keys(store: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(store.keys())
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


# SLICE 4 REVERSED THIS CASE'S VERDICT, and the rule it used to pin is still true one layer up:
# a sentry will not OPEN outside its leash (SentryArchetype's own lure-proofing, pinned there and by
# the wire case at the bottom of this file), but it ANSWERS a blow from anywhere it can stand. The
# field is what a player must not walk into, so it carries both.
func test_a_sentry_answers_one_counter_range_outside_its_leash() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	var sentry: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1))   # zone edge, at its post
	_bind(sentry, AIArchetype.Type.SENTRY, ZONE)
	var field := ThreatField.build(_context(board, zones), Team.Faction.PLAYER)
	# (4, 1) is adjacent and OUTSIDE the zone: poke it from there and it swings back.
	assert_bool(field.cells.has(Vector2i(4, 1))).override_failure_message(
			"a patrol's counter rim never reached past its leash").is_true()
	assert_bool(field.cells.has(Vector2i(2, 1))).is_true()
	# ...and the rim is the COUNTER's reach, not the whole board: two cells out is still clear.
	assert_bool(field.cells.has(Vector2i(5, 1))).override_failure_message(
			"the rim ran past the counter's own range").is_false()


func test_an_unarmed_patrol_gets_no_counter_rim() -> void:
	var board: Dictionary = _build_board()
	var zones: ZoneManager = _make_zone_manager()
	# No weapon: attack_source_can_counter() is false, which is the gate the rim borrows rather than
	# restating -- so a dry or unarmed enemy adds nothing, exactly as it counters with nothing.
	var sentry: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(3, 1), false)
	_bind(sentry, AIArchetype.Type.SENTRY, ZONE)
	var field := ThreatField.build(_context(board, zones), Team.Faction.PLAYER)
	assert_bool(field.cells.has(Vector2i(4, 1))).override_failure_message(
			"a unit that cannot counter still painted a counter rim").is_false()


func test_the_counter_rim_adds_nothing_to_a_rushdown() -> void:
	var board: Dictionary = _build_board()
	var rusher: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(4, 1))
	_bind(rusher, AIArchetype.Type.RUSHDOWN)
	var field := ThreatField.build(_context(board), Team.Faction.PLAYER)
	# The rim is a PATROL fix and must not widen anybody else's red -- the reason being structural
	# rather than incidental: a leashless archetype clips nothing, and its counter attack is already
	# one of the attacks the first pass walks. Assert the reason, then the consequence.
	assert_array(rusher.get_selectable_attacks()).contains([rusher.get_counter_attack()])
	var opens := {}
	for origin: Vector2i in field.move_of(rusher):
		for attack: AttackData in rusher.get_selectable_attacks():
			for cell: Vector2i in Reach.get_all_attack_cells_from(rusher, origin, attack):
				opens[cell] = true
	assert_array(_sorted(field.reach_of(rusher))).override_failure_message(
			"the counter rim widened an archetype that has no leash to widen past"
			).is_equal(_sorted(_keys(opens)))


# A FOLLOWER IS NOT LEASHED TO WHERE ITS LEADER STANDS NOW (slice 4). compute_move_range files every
# cell outside the cohesion bubble under `squad_unreachable`, measured against the leader's CURRENT
# cell -- but the enemy's own turn moves the leader FIRST and GroupMoveSolver then measures members
# against its DESTINATION, so those cells are exactly the ground a follower walks. This field is an
# upper bound; applying the clamp made it a lower one.
func test_a_followers_envelope_holds_the_cells_its_leash_files_as_unreachable() -> void:
	var board: Dictionary = _build_board()
	var leader: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 1))
	var member: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(4, 1))   # out at the leash's edge
	board.squad_manager.join_squad(member, leader.squad)
	_bind(leader, AIArchetype.Type.RUSHDOWN)

	var context := _context(board)
	var walk: Dictionary = RulesService.compute_move_range(member, context)
	var clamped: Dictionary = walk["squad_unreachable"]
	assert_int(clamped.size()).override_failure_message(
			"fixture is vacuous: this member's range never spills past its leader's bubble"
			).is_greater(0)

	var field := ThreatField.build(context, Team.Faction.PLAYER)
	var envelope := {}
	for cell: Vector2i in field.move_of(member):
		envelope[cell] = true
	for cell: Vector2i in clamped:
		assert_bool(envelope.has(cell)).override_failure_message(
				"%s is walkable next turn once the leader moves, and the envelope omitted it" % cell
				).is_true()


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
