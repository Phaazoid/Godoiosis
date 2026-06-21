extends SceneTree
# Headless proof for the Play API (docs/play-api.md, #46 M2): builds a small board,
# plays a scripted sequence through PlaySession, and prints the rendered text trace.
# Run:  <godot console exe> --headless --path . -s res://play/play_host.gd

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")
const BoardView := preload("res://play/board_view.gd")

func _initialize() -> void:
	_run()   # coroutine: it awaits a frame so freshly-added units get their _ready()

func _run() -> void:
	var board := BoardBuilder.build(root)
	BoardBuilder.paint_rect(board.grid, Rect2i(-1, -1, 10, 8))

	var p1 := BoardBuilder.spawn(board, _data("Vanguard", Team.Faction.PLAYER), Vector2i(0, 0))
	var e1 := BoardBuilder.spawn(board, _data("Raider", Team.Faction.ENEMY), Vector2i(5, 0))

	# Nodes added during _initialize don't get _ready until the tree iterates; wait one frame
	# so unit_instance is built, movement is wired to the grid, and inventory is sized.
	await process_frame

	_arm(p1, 6)
	_arm(e1, 4)

	var session := PlaySession.new(board)

	_section("OVERVIEW")
	print(BoardView.render_overview(session))

	_section("FOCUS A (move + attack reach)")
	print(BoardView.render_focus(session, "A"))

	_section("TURN 1 - A moves adjacent to a, then attacks")
	_echo(session.queue_move("A", Vector2i(4, 0)))
	_echo(session.queue_attack("A", Vector2i(5, 0)))
	print(BoardView.render_preview(session))
	var res: Dictionary = session.execute()
	print(BoardView.render_result(res.get("events", [])))

	_section("OVERVIEW (after execute)")
	print(BoardView.render_overview(session))

	_section("LOAD SCENARIO: Castle Assault")
	var board2 := BoardBuilder.build(root, "PlayRoot2")
	var loaded: Array = await BoardBuilder.load_scenario(board2, "res://Scenarios/Castle Assault.tres")
	print("loaded %d units; turn = %s" % [loaded.size(), Team.Faction.keys()[board2.turn_manager.active_faction()]])
	print(BoardView.render_overview(PlaySession.new(board2)))

	quit()

func _data(name: String, faction: Team.Faction) -> UnitData:
	return UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), name, faction)

func _arm(unit: Unit, power: int) -> void:
	var w := WeaponData.new()
	w.power = power
	w.scaling_stat = Stats.Stat.STR
	unit.add_item(w)   # add_item auto-equips the first weapon

func _section(title: String) -> void:
	print("\n========== %s ==========" % title)

func _echo(result: Dictionary) -> void:
	if result.ok:
		print("> " + str(result.get("summary", "ok")))
	else:
		print("> ERROR: " + str(result.error))
