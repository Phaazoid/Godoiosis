# The slam dust (#656): the puff a tile throws when it lands, and the project's first GPU particle.
#
# WHAT THIS SUITE CAN AND CANNOT SEE, said out loud rather than implied by a green run (#506). A
# GPUParticles3D is simulated on the card and never read back, so nothing below asserts that a grain
# was drawn, moved, or looked like dust -- that is the dev's eye, exactly as fire's scatter is
# (#324: "verdict is the dev's eye on a burning board; the geometry is what the tests can pin").
#
# What IS pinnable, and why it is worth the split: StagingDust.grains is pure and static, so every
# CPU-side decision -- where a burst sits, how wide it spreads, whether two Executes differ -- is
# ordinary arithmetic a case can state. That is the whole reason the scatter is derived rather than
# rolled on the GPU. The one thing between the decision and the card is the WIRE, and that IS
# reachable headless: this suite drives a real flight and lets battle3d._process run.
extends GdUnitTestSuite

const SCENE_PATH := "res://Scenes/Battle3D/Battle3D.tscn"
const PROLOG := "res://Scenarios/missions/Prolog.tres"

var _shared := SharedBoard.new(SCENE_PATH, PROLOG)
var _scene: Node3D
var _game: Node2D
var _mirror: BoardMirror


func before() -> void:
	await _shared.open(self)


func before_test() -> void:
	await _shared.reset(self)
	_scene = _shared.scene
	_game = _shared.scene.game
	_mirror = _scene.get_node("BoardMirror") as BoardMirror


func after_test() -> void:
	await _shared.check(self)


func after() -> void:
	_shared.close()


# --- what LANDED (the seam the puff hangs off) --------------------------------------------------

# advance_flight used to answer yes/no. A puff is drawn AT a cell, so the moment has to name one --
# and nothing else can, which is the reason the signature changed rather than a poller being added.
func test_advance_flight_names_the_cells_that_landed_on_this_step() -> void:
	var cells := _cells(3)
	var lift := BoardSpace.lift_offset()
	BoardSpace.stage(cells, lift)
	var plan := StagingFlight.schedule(cells)
	BoardSpace.begin_flight(plan, -lift, Vector3.ZERO, true)

	# Just past the FIRST tile's landing and nobody else's.
	var landed := BoardSpace.advance_flight(float(plan[0]["land"]) + 0.0001)
	assert_int(landed.size()).override_failure_message(
			"the first landing should name exactly one cell, got %s" % [landed]).is_equal(1)
	assert_vector(landed[0]).is_equal(cells[0])

	# A step in which nothing crosses its land time names nobody.
	assert_int(BoardSpace.advance_flight(0.0).size()).override_failure_message(
			"a step with no landing reported one anyway").is_equal(0)

	# ...and a step long enough to take the rest names the REST, never the one already home.
	var remainder := BoardSpace.advance_flight(StagingFlight.total(plan) + 1.0)
	assert_int(remainder.size()).override_failure_message(
			"the closing step should name the two tiles still in the air, got %s" % [remainder]
			).is_equal(2)
	assert_bool(remainder.has(cells[0])).override_failure_message(
			"a tile that landed on an earlier step was reported landing again").is_false()


# The EXIT is the arm a frame-over-frame diff of flying_cells() could never serve: a landed exit
# cell KEEPS an entry in _flight holding its socket (#602 round 7), so the flying set never shrinks.
func test_an_exit_names_its_landings_even_though_the_flying_set_never_shrinks() -> void:
	var cells := _cells(2)
	var lift := BoardSpace.lift_offset()
	BoardSpace.stage(cells, lift)
	var plan := StagingFlight.schedule(cells)
	BoardSpace.begin_flight(plan, Vector3.ZERO, -lift, false)

	var before := BoardSpace.flying_cells().size()
	var landed := BoardSpace.advance_flight(StagingFlight.total(plan) + 0.01)
	assert_int(landed.size()).override_failure_message(
			"an exit reported no landings at all -- which is exactly what a flying_cells() diff "
			+ "would have said").is_equal(cells.size())
	assert_int(BoardSpace.flying_cells().size()).override_failure_message(
			"the exit's flying set shrank, so this case is no longer testing what it says it is"
			).is_equal(before)


# --- where a puff SITS --------------------------------------------------------------------------

# One expression serves both arms because BoardMirror.surface_point already carries the staged
# offset -- the seam every per-cell node in that file is placed by. The two arms are 40 cells apart,
# so a placement that ignored the offset would be right on one and catastrophic on the other.
func test_a_puff_sits_on_the_surface_the_tile_landed_on_in_both_directions() -> void:
	var cells := _cells(1)
	var cell := cells[0]
	var lift := BoardSpace.lift_offset()
	var heights: BoardHeights = _game.board_heights

	BoardSpace.stage(cells, lift)
	BoardSpace.begin_flight(StagingFlight.schedule(cells), -lift, Vector3.ZERO, true)
	BoardSpace.advance_flight(999.0)
	var arrived := _mirror.surface_point(cell, heights)

	BoardSpace.begin_flight(StagingFlight.schedule(cells), Vector3.ZERO, -lift, false)
	BoardSpace.advance_flight(999.0)
	var home := _mirror.surface_point(cell, heights)

	assert_float(arrived.y - home.y).override_failure_message(
			"the two arms landed at the same height -- one of them is not reading the staged "
			+ "offset").is_equal_approx(lift.y, 0.001)
	# ...and the entry's is the DIORAMA's surface, which is the one in front of the camera.
	assert_float(arrived.y).is_greater(home.y)


# Grains start ON the ground, never inside it, and within the tile they were thrown from. Asserted
# per axis rather than as a distance from the centre, because a scatter's mean is not its centre
# and a tolerance the size of the spread is a budget that grows to fit whatever it measures.
func test_every_grain_starts_on_the_surface_and_inside_its_own_spread() -> void:
	var origin := Vector3(4.5, 2.0, 7.5)
	var grains := StagingDust.grains(origin, 12345)
	assert_int(grains.size()).is_greater(0)
	for grain: Dictionary in grains:
		var at: Vector3 = grain["position"]
		assert_float(at.y).override_failure_message(
				"a grain started at or below the surface, so half its quad is buried in the "
				+ "ground it was thrown off").is_greater(origin.y)
		var reach := Vector2(at.x - origin.x, at.z - origin.z).length()
		assert_float(reach).override_failure_message(
				"a grain started %.3f cells out, past its own spread knob" % reach
				).is_less_equal(StagingDust.burst_spread * 2.0)


# --- the randomisation (the dev's own ask) ------------------------------------------------------

# Two Executes of the same tile must not look identical, and a replay of one must. staging_version
# is what carries both -- it already bumps per landing step and per begin_flight, so no counter of
# this effect's own had to exist.
func test_the_same_tile_puffs_differently_on_a_later_execute_and_identically_on_a_replay() -> void:
	var cell := Vector2i(3, 4)
	var origin := Vector3(3.5, 1.0, 4.5)
	var first := StagingDust.grains(origin, StagingDust.burst_key(cell, 7))
	var again := StagingDust.grains(origin, StagingDust.burst_key(cell, 7))
	var later := StagingDust.grains(origin, StagingDust.burst_key(cell, 8))

	assert_vector(first[0]["position"] as Vector3).override_failure_message(
			"the same tile at the same version puffed differently -- a replay cannot reproduce it "
			+ "and neither can a case").is_equal(again[0]["position"])
	assert_bool(_same_scatter(first, later)).override_failure_message(
			"the same tile puffed identically on a later Execute -- the version is not reaching "
			+ "the seed").is_false()


# Two tiles landing on the SAME step share a version, so the cell has to separate them or a whole
# stage puffs in lockstep.
func test_two_tiles_landing_together_do_not_puff_in_lockstep() -> void:
	var origin := Vector3(0.5, 0.0, 0.5)
	var left := StagingDust.grains(origin, StagingDust.burst_key(Vector2i(1, 1), 4))
	var right := StagingDust.grains(origin, StagingDust.burst_key(Vector2i(2, 1), 4))
	assert_bool(_same_scatter(left, right)).override_failure_message(
			"two cells landing on one step threw the identical puff").is_false()


func test_the_grain_count_follows_its_knob() -> void:
	var was := StagingDust.grains_per_tile
	StagingDust.grains_per_tile = 5
	var five := StagingDust.grains(Vector3.ZERO, 1).size()
	StagingDust.grains_per_tile = 21
	var twenty_one := StagingDust.grains(Vector3.ZERO, 1).size()
	StagingDust.grains_per_tile = was
	assert_int(five).is_equal(5)
	assert_int(twenty_one).is_equal(21)


# --- the WIRE -----------------------------------------------------------------------------------

# A landing has to REACH the emitter, and both ends being correct while nothing connects them is
# #103's shape -- the one this project keeps paying for. It is reachable headless because
# _drive_transition runs off battle3d._process: the executor's await returns instantly with no
# frames, but a flight driven by hand and then given two idle frames is advanced by the real driver.
func test_a_landing_reaches_the_emitter_at_that_cell_s_surface() -> void:
	var dust := _dust()
	var cells := _cells(1)
	var cell := cells[0]
	var lift := BoardSpace.lift_offset()
	BoardSpace.stage(cells, lift)
	BoardSpace.begin_flight(StagingFlight.schedule(cells), -lift, Vector3.ZERO, true)

	var land := float(StagingFlight.schedule(cells)[0]["land"])
	var before := dust.puff_count

	# Half way, then let the driver run: it advances a flight that has not arrived, and must not
	# puff for a tile still in the air.
	BoardSpace.advance_flight(land * 0.5)
	await _settle()
	assert_int(dust.puff_count).override_failure_message(
			"the emitter fired for a tile still in the air").is_equal(before)

	# ...and now park the flight a hair short of its landing and hand the rest to the DRIVER. The
	# advance that crosses the landing time has to be _drive_transition's own, or this case proves
	# only that advance_flight works -- which the cases above already say.
	BoardSpace.advance_flight(maxf(land - BoardSpace.flight_elapsed() - 0.0001, 0.0))
	assert_int(dust.puff_count).override_failure_message(
			"the hand-driven setup crossed the landing itself, so the driver is not what is being "
			+ "tested here").is_equal(before)
	for _frame in range(120):
		if dust.puff_count > before:
			break
		await await_idle_frame()
	assert_int(dust.puff_count).override_failure_message(
			"a tile landed and the emitter never heard about it -- the wire from advance_flight "
			+ "to StagingDust.puff is cut").is_greater(before)
	assert_vector(dust.last_origin).override_failure_message(
			"the puff was thrown somewhere other than the cell that landed").is_equal(
			_mirror.surface_point(cell, _game.board_heights))


# The emitter must never be told to emit on its own: measured on 4.7.1, the first emit_particle on
# an emitting system CLEARS every live particle, so a puff already in the air would be wiped by the
# next tile to land.
func test_the_emitter_never_emits_on_its_own() -> void:
	assert_bool(_dust().emitting).override_failure_message(
			"emitting is true, so the first landing will wipe whatever is already in the air"
			).is_false()


# The other measured cap: emit_particle past `amount` is dropped with no error, so a busy board
# silently stops throwing dust. Sized from the knob rather than authored, so moving the knob cannot
# leave the buffer behind.
func test_the_emission_buffer_holds_every_burst_that_can_overlap() -> void:
	var dust := _dust()
	assert_int(dust.amount).override_failure_message(
			"the buffer holds fewer grains than the overlapping bursts a staggered stage throws, "
			+ "and the overflow is dropped silently").is_greater_equal(
			StagingDust.grains_per_tile * StagingDust.CONCURRENT_BURSTS)


# --- helpers ------------------------------------------------------------------------------------

func _dust() -> StagingDust:
	for child in _scene.get_children():
		var dust := child as StagingDust
		if dust != null:
			return dust
	fail("the battle scene built no StagingDust")
	return null


func _cells(count: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	cells.assign(_game.grid.get_used_cells())
	assert_int(cells.size()).override_failure_message(
			"the board is empty, so this case is asserting nothing").is_greater_equal(count)
	return cells.slice(0, count)


func _same_scatter(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if not (a[i]["position"] as Vector3).is_equal_approx(b[i]["position"]):
			return false
	return true


# process_frame resumes coroutines BEFORE node _process, so one frame is stale -- test_staging's own
# settle, and the same reason.
func _settle() -> void:
	await await_idle_frame()
	await await_idle_frame()
