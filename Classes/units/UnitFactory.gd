extends Object
class_name UnitFactory

# Static construction of Unit nodes and ad-hoc UnitData: create_unit instantiates the Unit
# scene off a UnitData (deep-copied — see below — with the source file remembered for #177's
# reference saves); create_unit_data builds a throwaway UnitData for the dev spawner's form.

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
	# already spawned from it. Nothing relied on that -- and since #589 there is a door,
	# Unit.reseed_kit(), which reads unit_data_source below precisely because THIS is a copy.
	#
	# IF FACTION EVER NEEDS TO VARY per battle (mind control, defections, a unit that switches
	# sides mid-mission), this copy is the wrong fix and you want the other one: move `faction`
	# off UnitData onto Unit as battle-scoped state, per the persistence seam -- faction is a
	# board fact, not identity. That change also needs a `faction` field on ScenarioUnitEntry,
	# because today saves persist it implicitly by copying the whole UnitData.
	unit.unit_data = data.duplicate(true)
	# Provenance (#177): remember the standalone character FILE this unit came from — the duplicate
	# above has no resource_path, and a scenario-embedded sub-resource's path carries "::" and is
	# not a character file. Authored saves read this to serialize a reference instead of a copy.
	if data.resource_path != "" and not data.resource_path.contains("::"):
		unit.unit_data_source = data

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
