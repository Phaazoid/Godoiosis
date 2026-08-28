# Join Squad marks its candidates with the squads' own PULSING rings (#442), instead of the generic
# target-pick ground marker every other pick flow draws. Two markings of one fact was #346's own
# complaint about the TARGET icon Squad Up already lost; join-squad is the half that was left.
#
# Driven through the real game.join_squad_mode -- the documented direct-call idiom -- because the
# claim spans three seams that could each be right alone: which squads are joinable, what gets
# drawn, and what stays CLICKABLE once the marker is gone.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")
const H := preload("res://tests/support/squad_fixtures.gd")

const PLAYER := Team.Faction.PLAYER

var _scene: Node3D
var game: Node2D
var _overlays: BoardOverlays


func before_test() -> void:
	get_tree().root.size = Vector2i(1280, 720)
	PlayerSettings.reset_for_test()   # is_on falls through to DISK otherwise
	var packed := SCENE
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	game = _scene.game
	_overlays = _scene.get_node("BoardOverlays") as BoardOverlays
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	PlayerSettings.reset_for_test()
	get_tree().root.remove_child(_scene)
	_scene.free()


func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()


func _om() -> OverlayManager:
	return game.overlay_manager


func _spawn(cell: Vector2i, overrides: Dictionary = {}) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data(overrides, PLAYER), cell)
	assert_object(unit).is_not_null()   # fixture setup, not the claim
	return unit


func _rings_on() -> void:
	PlayerSettings.set_on(PlayerSettings.Setting.ALWAYS_SHOW_SQUAD_RINGS, true)


# The leader needs ROOM for a third member: Squad.max_size is 1 + eLDR/MEMBER_LDR_COST, and the
# fixture's baseline LDR makes a two-member squad already full -- which reads in the test as
# "nothing is joinable" rather than as a capacity refusal. Overridden here, asserted below.
func _squad_at(leader_cell: Vector2i, member_cell: Vector2i, leader_overrides: Dictionary = {}) -> Array[Unit]:
	var leader := _spawn(leader_cell, leader_overrides)
	var member := _spawn(member_cell)
	game.squad_manager.join_squad(member, leader.squad)
	return [leader, member]


func _icon(unit: Unit, type: OverlayIcon.IconType) -> OverlayIcon:
	if not _om().icons_by_unit.has(unit):
		return null
	return _om().icons_by_unit[unit].get(type) as OverlayIcon


func _ringed_units() -> Array[Unit]:
	var ringed: Array[Unit] = []
	for key in _om().icons_by_unit:
		var unit := key as Unit
		if unit != null and _icon(unit, OverlayIcon.IconType.SQUADMEMBER) != null:
			ringed.append(unit)
	return ringed


func _pulsing_units() -> Array[Unit]:
	var pulsing: Array[Unit] = []
	for unit in _ringed_units():
		if _icon(unit, OverlayIcon.IconType.SQUADMEMBER).is_pulsing():
			pulsing.append(unit)
	return pulsing


# NEAR is inside the joiner's cohesion reach of the leader, FAR is not -- so one squad is joinable
# and the other is not, without either case needing to know what COH is.
func _board_with_two_squads() -> Dictionary:
	var near := _squad_at(Vector2i(2, 2), Vector2i(3, 2), {Stats.Stat.LDR: 8})
	var far := _squad_at(Vector2i(9, 6), Vector2i(8, 6))
	var joiner := _spawn(Vector2i(4, 2))
	# Asserted rather than assumed: every case below is vacuous if nothing is joinable, and the
	# refusal that would cause it (a FULL squad) looks identical to "the feature drew nothing".
	assert_bool(game.squad_manager.can_join_squad(joiner, near[0].squad)).override_failure_message(
			"the fixture's near squad is not joinable -- capacity or cohesion moved, and every case here is now vacuous"
			).is_true()
	assert_bool(game.squad_manager.can_join_squad(joiner, far[0].squad)).override_failure_message(
			"the fixture's far squad became joinable -- it is meant to be the control"
			).is_false()
	return {"near": near, "far": far, "joiner": joiner}


# --- What gets drawn ---------------------------------------------------------------

# The dev's second case: with the setting OFF, entering the mode is what puts the viable squads'
# rings on screen at all.
func test_with_rings_off_only_the_joinable_squad_is_ringed() -> void:
	var b := _board_with_two_squads()
	var near: Array[Unit] = b["near"]
	var far: Array[Unit] = b["far"]
	var joiner: Unit = b["joiner"]
	assert_array(_ringed_units()).is_empty()   # precondition: nothing standing
	game.join_squad_mode(joiner)
	await _settle()
	var ringed := _ringed_units()
	assert_bool(ringed.has(near[0]) and ringed.has(near[1])).override_failure_message(
			"the joinable squad's members are not all ringed -- the marking still follows LEADERS only"
			).is_true()
	assert_bool(ringed.has(far[0]) or ringed.has(far[1])).override_failure_message(
			"an unjoinable squad was ringed").is_false()
	assert_bool(ringed.has(joiner)).is_false()


# The dev's first case: with the setting ON everyone already wears a ring, so the only thing the
# mode changes is WHICH ONES PULSE.
func test_with_rings_on_every_squad_keeps_its_ring_and_only_the_joinable_pulses() -> void:
	_rings_on()
	var b := _board_with_two_squads()
	var near: Array[Unit] = b["near"]
	var far: Array[Unit] = b["far"]
	await _settle()
	assert_int(_ringed_units().size()).is_equal(4)   # precondition, not the claim
	game.join_squad_mode(b["joiner"])
	await _settle()
	assert_int(_ringed_units().size()).override_failure_message(
			"entering join mode dropped a standing ring").is_equal(4)
	var pulsing := _pulsing_units()
	assert_bool(pulsing.has(near[0]) and pulsing.has(near[1])).override_failure_message(
			"the joinable squad's rings are not pulsing").is_true()
	assert_bool(pulsing.has(far[0]) or pulsing.has(far[1])).override_failure_message(
			"an unjoinable squad's ring pulsed -- every ring is pulsing rather than the viable ones"
			).is_false()


# #346's channel split, and visual-clarity principle 2: the ring is what the INTERACTION is about,
# the crown is what the unit IS. Pulsing both would be two motifs for one signal.
func test_the_crown_does_not_pulse() -> void:
	var b := _board_with_two_squads()
	var near: Array[Unit] = b["near"]
	game.join_squad_mode(b["joiner"])
	await _settle()
	var crown := _icon(near[0], OverlayIcon.IconType.CROWN)
	assert_object(crown).override_failure_message(
			"the joinable squad's leader lost its crown").is_not_null()
	assert_bool(crown.is_pulsing()).override_failure_message(
			"the crown pulsed -- the head channel is carrying the interaction signal too"
			).is_false()


# --- The marker, and the click it must not take with it ------------------------------

# THE pair that could silently come apart: the ground marker and target_pick_cells are set two lines
# apart, so suppressing the draw is one edit away from suppressing the click as well -- which reads
# as "Join Squad does nothing" rather than as a missing marker.
func test_the_target_pick_marker_is_gone_but_the_candidates_are_still_clickable() -> void:
	var b := _board_with_two_squads()
	var near: Array[Unit] = b["near"]
	game.join_squad_mode(b["joiner"])
	await _settle()
	assert_array(_om().attack_overlay.get_used_cells()).override_failure_message(
			"the generic target-pick marker is still drawn -- two markings of one fact"
			).is_empty()
	var cells: Array = game.target_pick_cells
	assert_bool(cells.has(near[0].movement.cell) and cells.has(near[1].movement.cell)
			).override_failure_message(
			"a joinable squad's members are no longer clickable -- the draw and the cell list came apart"
			).is_true()


# --- Leaving the mode ----------------------------------------------------------------

func test_leaving_the_mode_stops_every_pulse_and_leaves_the_standing_set() -> void:
	_rings_on()
	var b := _board_with_two_squads()
	var near: Array[Unit] = b["near"]
	game.join_squad_mode(b["joiner"])
	await _settle()
	assert_int(_pulsing_units().size()).is_equal(2)   # precondition, not the claim
	game.exit_current_mode()
	await _settle()
	assert_array(_pulsing_units()).override_failure_message(
			"a ring kept pulsing after the mode ended -- a tween left running writes modulate forever"
			).is_empty()
	var ringed := _ringed_units()
	assert_bool(ringed.has(near[0]) and ringed.has(near[1])).override_failure_message(
			"the standing rings did not come back after the mode ended").is_true()


# Parity (#292): the mirror copies the 2D sprite's modulate, so the pulse reaches 3D for free -- but
# only if the rings reach the ground channel at all.
func test_the_joinable_rings_reach_the_3d_ground_channel() -> void:
	var b := _board_with_two_squads()
	game.join_squad_mode(b["joiner"])
	await _settle()
	assert_int(_overlays.markers_of(BoardOverlays.Layer.GROUND_ICONS).size()).override_failure_message(
			"the joinable squad's rings never reached 3D").is_equal(_ringed_units().size())
