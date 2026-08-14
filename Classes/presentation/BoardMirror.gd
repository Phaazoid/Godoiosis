extends Node3D
class_name BoardMirror

# The Battle3D board mirror (#215 / #176 stage 4a): paints the 3D GridMap from the
# LIVE 2D grid — the hidden game is the authority, this only reads. Terrain kinds
# resolve through the existing seam (GridUtils.get_terrain_kind_at_cell); the one
# Kind -> meshlib-item table below is law-tested complete. Boards mirror FLAT
# (column height 1) because the sim has no elevation yet — the diorama's hills
# arrive when the rules do.
#
# Fire-state cells (BURNING / BLAZE) get a flame billboard + a real OmniLight —
# the torch recipe, and the dev's "fire casts light" wish. refresh_states() is
# re-read each turn: a declared v1 approximation (mid-pass ignitions appear at
# the next turn boundary).

# NONE is the one declared skip: an authored tile with no kind still renders
# ground via FALLBACK_ITEM rather than a hole.
const KIND_TO_ITEM: Dictionary[Terrain.Kind, int] = {
	Terrain.Kind.GRASS: 0,
	Terrain.Kind.ROCK: 1,
	Terrain.Kind.DIRT: 3,
	Terrain.Kind.MUD: 4,
	Terrain.Kind.WATER: 5,
	Terrain.Kind.TREE: 6,
}
const FALLBACK_ITEM := 3  # dirt
const FLAME_TEXTURE_PATH := "res://Art/LookDev/torch_flame.png"

var board: GridMap

var _fire_markers: Array[Node3D] = []


func rebuild(grid: TileMapLayer, states: Dictionary) -> void:
	board.clear()
	for cell in grid.get_used_cells():
		var kind := GridUtils.get_terrain_kind_at_cell(grid, cell)
		var item: int = KIND_TO_ITEM.get(kind, FALLBACK_ITEM)
		board.set_cell_item(BoardSpace.of_flat(cell), item)
	refresh_states(states)


func refresh_states(states: Dictionary) -> void:
	for marker in _fire_markers:
		marker.queue_free()
	_fire_markers.clear()
	for cell: Vector2i in states.keys():
		if _has_fire(states[cell]):
			_fire_markers.append(_make_fire(BoardSpace.of_flat(cell)))


func fire_marker_count() -> int:
	return _fire_markers.size()


func _has_fire(cell_states: Array) -> bool:
	for state in cell_states:
		if (state as Terrain.TileState) in Terrain.FIRE_STATES:
			return true
	return false


func _make_fire(cell: Vector3i) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	root.position = BoardSpace.standing_point(cell)

	var flame := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.7)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0, 0, 0, 1)
	material.albedo_texture = load(FLAME_TEXTURE_PATH) as Texture2D
	material.emission_enabled = true
	material.emission = Color(1, 0.55, 0.15)
	material.emission_energy_multiplier = 2.5
	material.emission_texture = material.albedo_texture
	material.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	quad.material = material
	flame.mesh = quad
	flame.position = Vector3(0, 0.35, 0)
	flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(flame)

	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.62, 0.3)
	light.light_energy = 2.0
	light.omni_range = 4.0
	light.position = Vector3(0, 0.6, 0)
	root.add_child(light)
	return root
