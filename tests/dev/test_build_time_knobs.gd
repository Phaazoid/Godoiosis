# The BUILD-TIME half of the knob law (#1373). test_game_knobs' live law writes a row, waits two
# frames and reads the PROPERTY back, which proves nothing reverts it -- and is blind to a row read
# only when something is BUILT: the property holds, and what is already on screen never hears of it.
# Bracket arm, the two camera limits, the brush ghost's alpha and seven more shipped that way.
#
# Two clauses, and they fail differently:
#
# THE CLASSIFICATION LAW is structural. Every node row in the declaration tables either re-applies
# on write (its declaration carries a setter) or is named in READ_LIVE, a row read at USE -- every
# frame, or each time the thing it shapes is drawn. A new row with neither is a question nobody has
# answered yet: read at build, it needs a sweep and a case below; read live, it needs a line here.
#
# THE STANDING LAW is behavioural, one case per part: stand the part up on the real Battle3D board,
# write the row through the panel's own door (LookKnobs.write / GameKnobs.write_static), wait two
# frames, and require the STANDING node to have changed. A setter that exists but reaches nothing
# -- the missing wire, OverlayMirror's caches holding the old lift -- passes the first law and
# fails this one.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

# Why a row with no setter is still honest. Grouped by HOW it is read, so a new row names its kind.
const EVERY_FRAME := "read every frame"
const AT_INPUT := "read when the player moves the camera"
const AT_PLAYBACK := "read when a pass or a moment plays"
const PER_DRAW := "pushed to every shown readout each frame"

const READ_LIVE: Dictionary[String, String] = {
	"BoardOverlays:invalid_bracket_color": EVERY_FRAME,   # battle3d._sync_bracket_tint
	"BoardMirror:brush_vertex_ghost_size": EVERY_FRAME,   # battle3d._sync_brush_ghost
	"BoardMirror:flame_fps": EVERY_FRAME,
	"BoardMirror:flame_flicker": EVERY_FRAME,
	"BoardMirror:flame_camera_offset": EVERY_FRAME,
	"BoardMirror:flame_animated": EVERY_FRAME,
	"BoardMirror:flame_light_energy": EVERY_FRAME,
	"UnitMirror:hud_lift": PER_DRAW,
	"UnitMirror:hp_block_texels": PER_DRAW,
	"UnitMirror:hp_block_border_texels": PER_DRAW,
	"UnitMirror:hp_blocks_per_row": PER_DRAW,
	"UnitMirror:hp_block_recess_texels": PER_DRAW,
	"UnitMirror:hp_block_recess_shrink": PER_DRAW,
	"UnitMirror:hp_block_recess_shade": PER_DRAW,
	"UnitMirror:hp_block_top_shade": PER_DRAW,
	"UnitMirror:hp_grid_faces_camera": PER_DRAW,
	"UnitMirror:bar_fill_color": PER_DRAW,
	"UnitMirror:bar_missing_color": PER_DRAW,
	"UnitMirror:number_height_cells": PER_DRAW,
	"UnitMirror:number_outline_size": PER_DRAW,
	"UnitMirror:number_color": PER_DRAW,
	"UnitMirror:number_gap": PER_DRAW,
	"UnitMirror:number_shows_max": PER_DRAW,
	"UnitMirror:bar_doomed_color": PER_DRAW,
	"UnitMirror:bar_heal_color": PER_DRAW,
	"UnitMirror:bar_lost_color": PER_DRAW,
	"UnitMirror:alarm_peak_color": PER_DRAW,
	"UnitMirror:state_icon_texels": PER_DRAW,
	"UnitMirror:state_icon_gap_texels": PER_DRAW,
	"UnitMirror:state_icon_spacing_texels": PER_DRAW,
	"UnitMirror:downed_count_gap_texels": PER_DRAW,
	"UnitMirror:block_burst_speed": AT_PLAYBACK,
	"UnitMirror:block_burst_spread": AT_PLAYBACK,
	"UnitMirror:block_spin_speed": AT_PLAYBACK,
	"UnitMirror:block_gravity": AT_PLAYBACK,
	"UnitMirror:block_bounce": AT_PLAYBACK,
	"UnitMirror:block_lifetime": AT_PLAYBACK,
	"UnitMirror:block_burst_stagger": AT_PLAYBACK,
	"UnitMirror:block_death_power": AT_PLAYBACK,
	"UnitMirror:block_pop_time": PER_DRAW,
	"UnitMirror:hp_pop_lift_texels": PER_DRAW,
	"UnitMirror:hp_pop_stagger": PER_DRAW,
	"CameraRig:zoom_step_share": AT_INPUT,
	"CameraRig:smoothing": EVERY_FRAME,
	"CameraRig:glide_smoothing": EVERY_FRAME,
	"CameraRig:pan_speed_screens": AT_INPUT,
	"CameraRig:orbit_sensitivity": AT_INPUT,
	"CameraRig:max_pitch_degrees": AT_INPUT,
	"CameraRig:min_pitch_degrees": AT_INPUT,
	"CameraRig:playback_distance": AT_PLAYBACK,
	# The march and its light: GasMirror._params() packs every one of these per submit.
	"GasMirror:resolution": EVERY_FRAME,
	"GasMirror:steps": EVERY_FRAME,
	"GasMirror:light_steps": EVERY_FRAME,
	"GasMirror:light_step": EVERY_FRAME,
	"GasMirror:min_step": EVERY_FRAME,
	"GasMirror:contain_softness": EVERY_FRAME,
	"GasMirror:pool_softness": EVERY_FRAME,
	"GasMirror:detail_scale": EVERY_FRAME,
	"GasMirror:upsample_tolerance": EVERY_FRAME,
	"GasMirror:forward_scatter": EVERY_FRAME,
	"GasMirror:back_scatter": EVERY_FRAME,
	"GasMirror:back_mix": EVERY_FRAME,
	"GasMirror:powder": EVERY_FRAME,
	"GasMirror:ambient_strength": EVERY_FRAME,
	"GasMirror:flash_color": EVERY_FRAME,
	"GasMirror:flash_energy": EVERY_FRAME,
	"GasMirror:flash_radius": EVERY_FRAME,
	"GasMirror:held_cloud_strength": EVERY_FRAME,
	"GasMirror:floor_corner_radius": EVERY_FRAME,
	"GasMirror:forecast_width": EVERY_FRAME,
}

# The declaration a setter rides, whatever comes after the default: `@export var x := 1.0: set = _f`.
const SETTER := "(?m)^@export var %s\\b[^\\n]*:\\s*set\\s*="

var _board := SharedBoard.new(SCENE_PATH)
var _scene: Node3D
var game: Node2D
var _overlays: BoardOverlays


func before() -> void:
	await _board.open(self, _clear_the_board)


# board_loaded is what builds the 3D hover wire and fits the camera; test_overlay_mirror's reason.
func _clear_the_board() -> void:
	_board.game.scenario_manager.clear_board()
	_board.game.game_state = _board.game.GameState.IDLE


func before_test() -> void:
	await _board.reset(self)
	_scene = _board.scene
	game = _board.game
	_overlays = _scene.get_node("BoardOverlays") as BoardOverlays


func after_test() -> void:
	await _board.check(self)


func after() -> void:
	_board.close()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _om() -> OverlayManager:
	return game.overlay_manager


# --- the classification law ------------------------------------------------------------------------

func test_every_row_without_a_setter_is_declared_read_live() -> void:
	var unanswered: Array[String] = []
	var stale: Array[String] = []
	var named: Dictionary[String, bool] = {}
	for knob: Dictionary in _declaration_tables():
		var key := "%s:%s" % [knob["node"], knob["prop"]]
		var node := _scene.get_node_or_null(NodePath(knob["node"]))
		assert_object(node).override_failure_message("%s names no node" % key).is_not_null()
		if node == null:
			continue
		var prop: String = String(knob["prop"]).get_slice(":", 0)
		key = "%s:%s" % [knob["node"], prop]
		named[key] = true
		var source: String = (node.get_script() as Script).source_code
		var has_setter := RegEx.create_from_string(SETTER % prop).search(source) != null
		if has_setter and READ_LIVE.has(key):
			stale.append(key)
		elif not has_setter and not READ_LIVE.has(key):
			unanswered.append(key)
	for key: String in READ_LIVE:
		if not named.has(key):
			stale.append(key)
	assert_array(unanswered).override_failure_message(
			("Rows with no setter that nobody has said are read live: %s. Read when something is BUILT, " +
			"the row needs a setter that reaches what stands and a case below; read at use, a READ_LIVE " +
			"line.") % ", ".join(unanswered)).is_empty()
	assert_array(stale).override_failure_message(
			"READ_LIVE names rows that now have a setter or no longer exist: %s" % ", ".join(stale)).is_empty()


# --- the standing law ------------------------------------------------------------------------------

func test_the_bracket_knobs_reshape_a_bracket_already_standing() -> void:
	_overlays.set_cells(BoardOverlays.Layer.HOVER, [Vector3i(2, 0, 2)])   # battle3d's own door
	await _settle()
	assert_array(_bracket_vertices()).override_failure_message(
			"no bracket stood up -- this case cannot see the knobs").is_not_empty()
	await _assert_all_reach("BoardOverlays", ["bracket_arm", "bracket_thickness", "bracket_scale"], _bracket_vertices)


func test_the_lift_and_billboard_knobs_reach_a_squad_already_drawn() -> void:
	var pair := _squad_pair()
	_om().redraw_squad_unit_icons(pair[0].squad)
	game.draw_squad_cohesion(pair[0].squad, pair[0].movement.cell)
	await _settle()
	assert_array(_overlays.markers_of(BoardOverlays.Layer.GROUND_ICONS)).override_failure_message(
			"no ring stood under the squad -- this case cannot see the lifts").is_not_empty()
	assert_object(_crown()).override_failure_message(
			"no crown stood over the leader -- this case cannot see the billboard rows").is_not_null()
	assert_array(_overlays.lines_of(BoardOverlays.Layer.COHESION_EDGE)).override_failure_message(
			"no range outline was drawn -- this case cannot see the composed lift").is_not_empty()
	# A ring is lifted inside BoardOverlays; the range outline is lifted UPSTREAM, by OverlayMirror.
	# Both have to move, which is why the probe reads one of each.
	await _assert_all_reach("BoardOverlays", ["fill_lift", "lift_step"], _ring_and_outline_heights)
	await _assert_all_reach("BoardOverlays", ["billboard_lift", "billboard_pixel_size"], _crown_shape)
	await _assert_all_reach("BoardOverlays", ["squad_line_width"], _cone_extent.bind(BoardOverlays.Layer.TETHERS))


func test_the_reach_mark_width_reaches_a_cone_already_drawn() -> void:
	var foe: Unit = game.spawn_unit(H.make_unit_data({}, ENEMY), Vector2i(3, 2))
	assert_object(foe).is_not_null()   # fixture setup, not the claim
	foe.equipped_weapon = H.make_weapon(3)
	foe.squad.archetype = AIArchetype.Type.HOLD
	game.show_reach_lines_at(Vector2i(2, 2))
	await _settle()
	assert_array(_overlays.cone_vertices_of(BoardOverlays.Layer.REACH_LINES)).override_failure_message(
			"no reach cone was drawn -- this case cannot see the width").is_not_empty()
	await _assert_all_reach("BoardOverlays", ["mark_width"], _cone_extent.bind(BoardOverlays.Layer.REACH_LINES))
	_om().clear_reach_lines()


func test_the_ghost_alpha_reaches_a_ghost_already_showing() -> void:
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	mirror.show_brush_ghost(BrushGhost.at_vertex(Vector2i(2, 2), 0))
	assert_that(_ghost_alpha()).override_failure_message(
			"no ghost was built -- this case cannot see the alpha").is_not_null()
	await _assert_all_reach("BoardMirror", ["brush_ghost_alpha"], _ghost_alpha)
	mirror.hide_brush_ghost()


func test_the_ground_gap_reaches_a_fire_already_burning() -> void:
	var mirror := _scene.get_node("BoardMirror") as BoardMirror
	# The gap is a CLAMP that only binds while the flame writes depth (flame_base_lift_for).
	LookKnobs.write(_scene, _knob("BoardMirror", "flame_writes_depth"), true)
	var cell := _a_ground_cell()
	var effect := ResolvedCellEffect.new()
	effect.cell = cell
	effect.states_added.assign([Terrain.TileState.BURNING])
	game.terrain_states.apply(effect)
	await _settle()
	assert_object(mirror.fire_marker_at(cell)).override_failure_message(
			"no flame stood up -- this case cannot see the gap").is_not_null()
	await _assert_all_reach("BoardMirror", ["flame_ground_gap"], _flame_heights.bind(mirror, cell))


func test_the_camera_limit_knobs_refit_the_limits_already_set() -> void:
	var rig := _scene.get_node("CameraRig") as CameraRig3D
	# fit_margin_cells is the Moods tab's row, read by the same rebound().
	await _assert_all_reach("CameraRig", ["pan_stray_screens", "zoom_out_slack", "fit_margin_cells"],
			func() -> Array: return [rig.max_distance, rig.pan_limit])


func test_the_thin_gas_floor_reaches_puffs_already_risen() -> void:
	# Only the cloud mix's puffs rise with their column -- the field's slots all sit at a fixed lift.
	Experiments.set_choice(Experiments.Flag.GAS_STYLE, GasMirror.MIXES.size() - 1)
	var gas := _scene.get_node("GasMirror") as GasMirror
	game.gas_field.set_level(_a_ground_cell(), Gas.Kind.STEAM, Gas.Level.THIN)
	await _settle()
	assert_array(gas.puff_entries()).override_failure_message(
			"no puffs stood up -- this case cannot see the floor").is_not_empty()
	await _assert_all_reach("GasMirror", ["thin_floor"], _puff_heights.bind(gas))


# The class half: the Glossary quotes the limb-loss thresholds and caches what it built.
func test_the_limb_loss_knobs_reach_the_maim_text() -> void:
	for name: String in ["LIMB_LOSS_DAMAGE", "LIMB_LOSS_DAMAGE_WOUNDED"]:
		var before := Glossary.short(Glossary.Term.MAIM)   # built, and so cached, first
		var was: Variant = GameKnobs.read_static(name)
		GameKnobs.write_static(_scene, name, int(was) + 1)
		var after := Glossary.short(Glossary.Term.MAIM)
		GameKnobs.write_static(_scene, name, was)
		assert_str(after).override_failure_message(
				"%s moved and the Maim entry still quotes the old number" % name).is_not_equal(before)


# --- helpers ---------------------------------------------------------------------------------------

# Writes each row the way its slider does, and fails naming every row the standing part ignored.
# Each is put back before the next, so one row's move cannot stand in for another's.
func _assert_all_reach(node: String, props: Array, probe: Callable) -> void:
	var dead: Array[String] = []
	for prop: String in props:
		var knob := _knob(node, prop)
		var was: Variant = LookKnobs.read(_scene, knob)
		var before: Variant = probe.call()
		LookKnobs.write(_scene, knob, _nudged(knob, was))
		await _settle()
		var after: Variant = probe.call()
		LookKnobs.write(_scene, knob, was)
		await _settle()
		if _same(before, after):
			dead.append("%s:%s" % [node, prop])
	assert_array(dead).override_failure_message(
			"Moved, and what was already standing never changed: %s" % ", ".join(dead)).is_empty()


func _declaration_tables() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append_array(GameKnobs.KNOBS)
	out.append_array(ObjectKnobs.GLOBALS)
	return out


func _knob(node: String, prop: String) -> Dictionary:
	for knob: Dictionary in _declaration_tables() + LookKnobs.KNOBS:
		if knob["node"] == node and knob["prop"] == prop:
			return knob
	assert_bool(false).override_failure_message("no row names %s:%s" % [node, prop]).is_true()
	return {}


# A quarter of the row's range toward whichever end is further, so the move is never too small to see.
func _nudged(knob: Dictionary, value: Variant) -> Variant:
	if typeof(value) == TYPE_BOOL:
		return not value
	var low: float = knob["min"]
	var high: float = knob["max"]
	var step := (high - low) * 0.25
	return float(value) - step if float(value) + step > high else float(value) + step


func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_FLOAT and typeof(b) == TYPE_FLOAT:
		return is_equal_approx(a, b)
	return a == b


func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


func _squad_pair() -> Array[Unit]:
	var leader := _spawn(PLAYER, Vector2i(2, 2))
	var member := _spawn(PLAYER, Vector2i(5, 2))
	game.squad_manager.join_squad(member, leader.squad)
	return [leader, member]


func _a_ground_cell() -> Vector2i:
	var ground: Array[Vector2i] = game.grid.get_used_cells()
	assert_bool(ground.is_empty()).override_failure_message("the fixture board has no ground").is_false()
	ground.sort()
	return ground[ground.size() / 2]


func _bracket_vertices() -> PackedVector3Array:
	var pool: Array = _overlays._pool_for(BoardOverlays.Layer.HOVER)
	if pool.is_empty():
		return PackedVector3Array()
	var mesh := (pool[0] as MeshInstance3D).mesh
	return PackedVector3Array() if mesh == null else mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _ring_and_outline_heights() -> Array:
	var ring := (_overlays._pool_for(BoardOverlays.Layer.GROUND_ICONS)[0] as Node3D).position.y
	var outline: Array[PackedVector3Array] = _overlays.lines_of(BoardOverlays.Layer.COHESION_EDGE)
	return [ring, outline[0][0].y]


func _crown() -> Sprite3D:
	for node in _overlays._pool_for(BoardOverlays.Layer.ICONS):
		if (node as Sprite3D).visible:
			return node as Sprite3D
	return null


func _crown_shape() -> Array:
	var crown := _crown()
	return [crown.position, crown.pixel_size]


func _cone_extent(layer: BoardOverlays.Layer) -> AABB:
	var box := AABB()
	var first := true
	for vertex: Dictionary in _overlays.cone_vertices_of(layer):
		var point: Vector3 = vertex["point"]
		box = AABB(point, Vector3.ZERO) if first else box.expand(point)
		first = false
	return box


func _ghost_alpha() -> Variant:
	var ghost: MeshInstance3D = (_scene.get_node("BoardMirror") as BoardMirror)._brush_ghost
	if ghost == null:
		return null
	return (ghost.material_override as StandardMaterial3D).albedo_color.a


func _flame_heights(mirror: BoardMirror, cell: Vector2i) -> Array:
	var heights: Array = []
	for child in mirror.fire_marker_at(cell).get_children():
		if child is MeshInstance3D:
			heights.append((child as MeshInstance3D).position.y)
	return heights


func _puff_heights(gas: GasMirror) -> Array:
	var heights: Array = []
	for entry: Array in gas.puff_entries():
		heights.append((entry[0] as Vector3).y)
	return heights
