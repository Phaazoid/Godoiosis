# Can the player READ the action-queue panel under every palette (#1356)?
#
# test_queue_palette pins each role against its ground, and the section headers passed it while
# drawing slate grey on parchment's tan: the label read the slate CONST rather than the role, and a
# pair test cannot see which door a label took. So this builds the real panel with several sections,
# swaps the palette through restyle() (the door SettingsScreen closes through), and asks every control
# what it will actually draw -- tests/support/palette_contrast.gd's walk, as test_pre_mission_contrast
# and test_info_card_contrast ask it of their surfaces.
#
# IT WALKS THE HEADER STRIPS, NOT THE WHOLE PANEL. Every row carries ActionQueueRow.tscn's
# DescriptionLabel, which is hidden and never drawn, and the walker cannot tell a hidden label from a
# drawn one. The ground is still composited down the full ancestor chain, so the strip is judged
# against the frame, card and strip really painted under it.
#
# One case, every finding: a failing case truncates the rest of its suite file.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const PC := preload("res://tests/support/palette_contrast.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

# The dock is drawn over the board, which varies; its frame is near-opaque, so the other contrast
# suites' dark base is as honest a floor as any.
const SCREEN_BASE := Color(0.06, 0.06, 0.09)

var _main: Node
var game: Node2D
var panel: SquadActionQueueControl


func before_test() -> void:
	PlayerSettings.reset_for_test()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		for y in range(5):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	panel = game.squad_action_queue_control
	await await_idle_frame()


func after_test() -> void:
	panel = null
	get_tree().root.remove_child(_main)
	_main.free()
	PlayerSettings.reset_for_test()
	await await_idle_frame()


func _frames(n: int) -> void:
	for i in range(n):
		await await_idle_frame()


# Three sections: a member's step (MOVE), the leader's swing (ATTACK) and the enemy's answer
# (REACTION). Every header the panel draws has the same builder, so three is plenty.
func _queue_several_sections() -> void:
	var leader: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), Vector2i(1, 1))
	var member: Unit = game.spawn_unit(H.make_unit_data({}, PLAYER), Vector2i(0, 2))
	var enemy: Unit = game.spawn_unit(H.make_unit_data({}, ENEMY), Vector2i(2, 1))
	for unit: Unit in [leader, member, enemy]:
		unit.equipped_weapon = H.make_weapon(4)
	game.squad_manager.join_squad(member, leader.squad)
	game.squad_manager.active_squad = leader.squad

	var step := Vector2i(0, 1)
	var reach := RulesService.compute_move_range(member, game._board())
	var move := MoveAction.new()
	move.init(member, RulesService.reconstruct_path(reach.came_from, member.movement.cell, step),
			GridUtils.get_terrain_icon_at_cell(game.grid, step))
	assert_bool(game.squad_manager.queue_action(leader.squad, move)) \
		.override_failure_message("fixture: the member's step was refused").is_true()
	assert_bool(game.squad_manager.queue_action(leader.squad, H.stamped_attack(leader, enemy))) \
		.override_failure_message("fixture: the leader's attack was refused").is_true()
	game.refresh_action_queue(leader.squad)
	await _frames(2)


# The live header labels: a Label carrying a HEADER entry's title, on a card still in the tree.
func _header_labels() -> Array[Label]:
	var titles: Array[String] = []
	for entry: ActionQueueDisplayEntry in panel._last_entries:
		if entry != null and entry.entry_type == ActionQueueDisplayEntry.EntryType.HEADER:
			titles.append(entry.label)
	var out: Array[Label] = []
	for node in PC.walk(panel.sections_box):
		var label := node as Label
		if label != null and titles.has(label.text) and not label.is_queued_for_deletion():
			out.append(label)
	return out


func test_every_section_header_can_be_read_in_every_palette() -> void:
	await _queue_several_sections()
	var found: Array[String] = []
	for palette: int in PlayerSettings.QueuePalette.values():
		PlayerSettings.set_choice(PlayerSettings.Setting.QUEUE_PALETTE, palette)
		panel.restyle()
		await _frames(2)
		var headers := _header_labels()
		assert_int(headers.size()).override_failure_message(
				"precondition: palette %d built fewer than two section headers, so the walk proves little"
				% palette).is_greater_equal(2)
		for header: Label in headers:
			found.append_array(PC.findings(header.get_parent(), SCREEN_BASE, "palette %d" % palette))

	assert_array(found).override_failure_message(
			"unreadable section headers on the action-queue panel:\n  %s" % "\n  ".join(found)).is_empty()
