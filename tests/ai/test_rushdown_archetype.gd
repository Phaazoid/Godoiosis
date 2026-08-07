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
