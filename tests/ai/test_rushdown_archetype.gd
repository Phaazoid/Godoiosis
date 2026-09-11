# RushdownArchetype (#29): nearest enemy -> path -> attack, and the finding #3 fallback --
# no enemy on the board at all must not mean "do nothing for the whole turn". Real managers +
# TestTiles via board_builder, mirroring test_sentry_archetype.gd's shape (Rushdown had no
# dedicated archetype-level test file before this).
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const BB := preload("res://play/board_builder.gd")


func _build_board() -> Dictionary:
	var board: Dictionary = BB.build(self)
	auto_free(board.root)
	BB.paint_rect(board.grid, Rect2i(0, 0, 8, 3))
	return board


func _spawn(board: Dictionary, faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = BB.spawn(board, H.make_unit_data({}, faction), cell)
	unit.equipped_weapon = H.make_weapon()   # Chainsword pass-through (#82): always rev-capable
	return unit


func _context(board: Dictionary) -> BoardContext:
	var units: Array[Unit] = []
	for child in board.units_root.get_children():
		units.append(child as Unit)
	return BoardContext.new(board.grid, units, board.squad_manager)


func _bind_rushdown(unit: Unit) -> Squad:
	var squad: Squad = unit.squad
	squad.archetype = AIArchetype.Type.RUSHDOWN
	return squad


func _unready_springspear() -> SpringspearWeaponInstance:
	var template := WeaponData.new()
	template.weapon_type = WeaponData.WeaponType.SPRINGSPEAR
	template.main_attack = WeaponAttackData.new()
	template.main_attack.power = 5
	template.main_attack.requires_readiness = true
	var spear := WeaponInstance.make(template) as SpringspearWeaponInstance
	spear.ready = false
	return spear


func _move_destinations(squad: Squad) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for action in squad.action_queue:
		if action is MoveAction:
			result.append((action as MoveAction).destination)
	return result


func test_no_enemy_revs_a_rev_capable_weapon() -> void:
	var board: Dictionary = _build_board()
	var leader: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 1))   # no PLAYER unit exists
	var squad: Squad = _bind_rushdown(leader)

	RushdownArchetype.take_squad_turn(squad, _context(board), board.squad_manager)

	assert_int(squad.action_queue.size()).is_equal(1)
	assert_int(squad.action_queue[0].action_type).is_equal(BaseAction.ActionType.REV)


func test_no_enemy_reloads_an_unready_weapon() -> void:
	var board: Dictionary = _build_board()
	var leader: Unit = BB.spawn(board, H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(0, 1))
	leader.equipped_weapon = _unready_springspear()
	var squad: Squad = _bind_rushdown(leader)

	RushdownArchetype.take_squad_turn(squad, _context(board), board.squad_manager)

	assert_int(squad.action_queue.size()).is_equal(1)
	assert_int(squad.action_queue[0].action_type).is_equal(BaseAction.ActionType.RELOAD)


func test_no_enemy_and_nothing_valid_queues_nothing() -> void:
	var board: Dictionary = _build_board()
	var leader: Unit = BB.spawn(board, H.make_unit_data({}, Team.Faction.ENEMY), Vector2i(0, 1))
	var spear := _unready_springspear()
	spear.ready = true   # loaded, and a Springspear can't rev -- nothing left to try
	leader.equipped_weapon = spear
	var squad: Squad = _bind_rushdown(leader)

	RushdownArchetype.take_squad_turn(squad, _context(board), board.squad_manager)

	assert_array(squad.action_queue).is_empty()


func test_enemy_present_still_prefers_attack_over_fallbacks() -> void:
	var board: Dictionary = _build_board()
	var leader: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 1))
	var squad: Squad = _bind_rushdown(leader)
	var _victim: Unit = _spawn(board, Team.Faction.PLAYER, Vector2i(1, 1))   # adjacent, in reach

	RushdownArchetype.take_squad_turn(squad, _context(board), board.squad_manager)

	var types: Array = []
	for action in squad.action_queue:
		types.append(action.action_type)
	assert_bool(types.has(BaseAction.ActionType.ATTACK)).is_true()
	assert_bool(types.has(BaseAction.ActionType.REV)).is_false()


# ==============================================================================
#  The defended point (#571) -- Rushdown walks at the cargo
# ==============================================================================
#
# board_builder hands its BoardContext a NULL ZoneManager, which is why every case above is
# untouched by this branch and why no shipped board (none paints a DEFEND zone) changes behaviour.
# These cases supply one.

func _zoned_context(board: Dictionary, zones: ZoneManager) -> BoardContext:
	var units: Array[Unit] = []
	for child in board.units_root.get_children():
		units.append(child as Unit)
	return BoardContext.new(board.grid, units, board.squad_manager, null, zones)


func _zone(kind: ZoneManager.Kind, cells: Array, zone_name := "The Cargo") -> ZoneManager:
	var zones := ZoneManager.new()
	auto_free(zones)   # a ZoneManager is a Node: un-freed it is a gdUnit4 ORPHAN, verdict 101
	for cell: Vector2i in cells:
		zones.paint_cell(zone_name, kind, cell)
	return zones


# THE DISCRIMINATING CASE, and the fixture is built so candidate order fights the rule: the player
# unit sits one step from the rusher and the cargo is the whole board away in the OPPOSITE
# direction. Pursuit alone walks left; only a rusher that wants the point walks right. A fixture
# with the two on the same side would pass under either rule.
func test_the_cargo_outranks_the_nearest_enemy() -> void:
	var board: Dictionary = _build_board()
	var leader: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(4, 1))
	var squad: Squad = _bind_rushdown(leader)
	_spawn(board, Team.Faction.PLAYER, Vector2i(3, 1))    # one step LEFT -- what pursuit would take
	var zones := _zone(ZoneManager.Kind.DEFEND, [Vector2i(7, 1)])   # the cargo, six steps RIGHT

	RushdownArchetype.take_squad_turn(squad, _zoned_context(board, zones), board.squad_manager)

	var moves: Array[Vector2i] = _move_destinations(squad)
	assert_array(moves) \
		.override_failure_message("a rusher with a defended point in reach queued no move at all") \
		.is_not_empty()
	assert_int(moves[0].x) \
		.override_failure_message("walked toward the nearest body (x=%d), not the cargo at x=7" % moves[0].x) \
		.is_greater(4)


# It is a change of DESTINATION, not of personality: the ordinary main-action pass still runs, so a
# rusher that cannot reach the cargo this turn is not suddenly idle on the way there.
func test_walking_at_the_cargo_still_takes_a_main_action() -> void:
	var board: Dictionary = _build_board()
	var leader: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(0, 1))
	var squad: Squad = _bind_rushdown(leader)
	var zones := _zone(ZoneManager.Kind.DEFEND, [Vector2i(7, 1)])

	RushdownArchetype.take_squad_turn(squad, _zoned_context(board, zones), board.squad_manager)

	var verbs: Array[int] = []
	for action in squad.action_queue:
		verbs.append(action.action_type)
	assert_array(verbs) \
		.override_failure_message("the cargo branch queued a move and then nothing else") \
		.contains([BaseAction.ActionType.REV])


# The gate is the KIND, not "any painted zone". A capture point is the player's to take and means
# nothing to the enemy -- CAPTURE is still NEVER for every archetype (missions.md, #96).
func test_a_capture_zone_is_not_cargo() -> void:
	var board: Dictionary = _build_board()
	var leader: Unit = _spawn(board, Team.Faction.ENEMY, Vector2i(4, 1))
	var squad: Squad = _bind_rushdown(leader)
	_spawn(board, Team.Faction.PLAYER, Vector2i(3, 1))
	var zones := _zone(ZoneManager.Kind.CAPTURE, [Vector2i(7, 1)])

	RushdownArchetype.take_squad_turn(squad, _zoned_context(board, zones), board.squad_manager)

	var moves: Array[Vector2i] = _move_destinations(squad)
	if not moves.is_empty():
		assert_int(moves[0].x) \
			.override_failure_message("a CAPTURE zone pulled the rusher off its pursuit") \
			.is_less_equal(4)


# A DEFEND zone is implicitly the PLAYER's, so only a faction hostile to them wants it. An ALLY
# squad marching its own side's cargo down would be absurd, and Team.is_enemy is what says so.
func test_an_allied_rusher_ignores_the_cargo() -> void:
	var board: Dictionary = _build_board()
	var leader: Unit = _spawn(board, Team.Faction.ALLY, Vector2i(4, 1))
	var squad: Squad = _bind_rushdown(leader)
	_spawn(board, Team.Faction.ENEMY, Vector2i(3, 1))   # the ALLY's own quarry, to the LEFT
	var zones := _zone(ZoneManager.Kind.DEFEND, [Vector2i(7, 1)])

	RushdownArchetype.take_squad_turn(squad, _zoned_context(board, zones), board.squad_manager)

	var moves: Array[Vector2i] = _move_destinations(squad)
	if not moves.is_empty():
		assert_int(moves[0].x) \
			.override_failure_message("an ALLY squad marched on the player's own cargo") \
			.is_less_equal(4)
