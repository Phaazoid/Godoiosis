extends Object
class_name TestBoard

# The hardcoded starting board: five units and one chainsword, spawned by game._ready().
#
# Scaffolding from before scenarios existed (Milestone P) that nothing has replaced yet.
# It lives here rather than in game.gd so the coordinator carries no fixed content of its
# own, and so retiring it in favour of a real scenario load is a one-line deletion at the
# call site. Not test-suite code — the name means "the board used while testing by hand".

static func spawn(game) -> void:
	var test_data_baddy := preload("res://Resources/BadGuy1.tres")
	var test_data_goody := preload("res://Resources/GoodGuy1.tres")

	var test_cells := [
		Vector2i(-1, -5)
	]
	for cell in test_cells:
		game.spawn_unit(test_data_goody, cell)

	var test_enemy: Unit = game.spawn_unit(test_data_baddy, Vector2i(4, 4))
	if test_enemy != null:
		var test_item: WeaponData = preload("res://Resources/Weapons/MainVarieties/ChainSword.tres")
		test_enemy.add_item(WeaponInstance.make(test_item))

	var generic_stats := Stats.STAT_DEFAULTS.duplicate()

	var data1 = UnitFactory.create_unit_data(generic_stats, "GoodGuy 2", Team.Faction.PLAYER)
	var data2 = UnitFactory.create_unit_data(generic_stats, "GoodGuyThree", Team.Faction.PLAYER)
	var data3 = UnitFactory.create_unit_data(generic_stats, "BaddyNumeroDos", Team.Faction.ENEMY)

	game.spawn_unit(data1, Vector2i(-6, -5))
	game.spawn_unit(data2, Vector2i(-8, -5))
	game.spawn_unit(data3, Vector2i(4, 6))
