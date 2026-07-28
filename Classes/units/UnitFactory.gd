extends Object
class_name UnitFactory

static func create_unit(data: UnitData, grid: TileMapLayer, pos : Vector2i) -> Unit:
	var unit_scene = preload("res://Scenes/Unit.tscn")
	var unit = unit_scene.instantiate()
	
	
	unit.setup(grid, pos)
	# Its OWN copy, never the caller's. `faction` is the one field on UnitData that mutates at
	# runtime -- Unit.change_faction writes straight through to it, and Unit.get_faction reads it
	# back -- so two units sharing one UnitData would flip factions together. Reachable today via
	# TestBoard, which preloads (and therefore cache-SHARES) its .tres files: spawning a second
	# unit from one of them is a one-line change. Deep copy is cheap here -- Godot skips
	# resources that have a resource_path, so the sprite textures stay shared; what it actually
	# protects is the base_stats dictionary, which a shallow copy would share.
	#
	# Accepted trade-off (2026-07-27): editing a UnitData .tres no longer live-updates units
	# already spawned from it. Nothing relied on that.
	#
	# IF FACTION EVER NEEDS TO VARY per battle (mind control, defections, a unit that switches
	# sides mid-mission), this copy is the wrong fix and you want the other one: move `faction`
	# off UnitData onto Unit as battle-scoped state, per the persistence seam -- faction is a
	# board fact, not identity. That change also needs a `faction` field on ScenarioUnitEntry,
	# because today saves persist it implicitly by copying the whole UnitData.
	unit.unit_data = data.duplicate(true)

	return unit
	
static func create_unit_data(
		stats: Dictionary[Stats.Stat, int],
		name: String,
		faction: Team.Faction,
		map_sprite: Texture2D = null,
		move_sprite: Texture2D = null,
		downed_sprite: Texture2D = null) -> UnitData:
	var data := UnitData.new()
	data.base_stats = stats
	data.display_name = name
	data.faction = faction
	if map_sprite != null:
		data.map_sprite = map_sprite
	if move_sprite != null:
		data.move_sprite = move_sprite
	if downed_sprite != null:
		data.downed_sprite = downed_sprite
	return data
