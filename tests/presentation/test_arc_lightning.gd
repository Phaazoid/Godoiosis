# WHAT A SHOCK LOOKS LIKE (#887): the sky strike, and the current arcing over the water.
#
# An effect is normally a transparent surface a headless suite cannot see -- the reason #656's dust
# had to settle for asserting the CPU side of a burst it could never read back. This one is built
# from an ImmediateMesh, which lives on the CPU and can be read: a case can ask how many bolts were
# really put on it and where they went. So the geometry is pinned here and only the pixels are left
# to the dev.
#
# EVERY FEEL VALUE IS A KNOB, so nothing below pins one. The cases measure PROPERTIES the knobs
# cannot move -- a bolt is pinned to the cells it joins, the strike reads top-down, the tail is
# exactly as long as it was asked for, a hop is dark until the current reaches it -- and where a fork
# matters (the photosensitivity freeze) they pin the fork rather than either side of it.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const PLAYER := Team.Faction.PLAYER

var _arc: ArcLightning
var _knobs: Dictionary = {}


func before_test() -> void:
	_arc = ArcLightning.new()
	add_child(_arc)          # _ready fires here, which is what builds the two meshes
	auto_free(_arc)
	# DRIVEN BY HAND, not by frames. The schedule is what several of these cases are about, and a
	# real delta makes "is this hop lit yet" a race with the machine the suite happens to run on.
	_arc.set_process(false)
	_knobs = {
		"sky_strike": ArcLightning.sky_strike,
		"arcs": ArcLightning.arcs,
		"strike_delay": ArcLightning.strike_delay,
		"arc_step_delay": ArcLightning.arc_step_delay,
		"bolt_life": ArcLightning.bolt_life,
		"bolt_jag": ArcLightning.bolt_jag,
	}


# The knobs are STATICS, so a case that moves one moves it for the whole process. Restored here
# rather than at the end of each case: an assertion that fails takes the rest of its case with it.
func after_test() -> void:
	ArcLightning.sky_strike = _knobs["sky_strike"]
	ArcLightning.arcs = _knobs["arcs"]
	ArcLightning.strike_delay = _knobs["strike_delay"]
	ArcLightning.arc_step_delay = _knobs["arc_step_delay"]
	ArcLightning.bolt_life = _knobs["bolt_life"]
	ArcLightning.bolt_jag = _knobs["bolt_jag"]


# The stub the host would otherwise supply: one cell, one world point, on a flat surface at y = 0.
func _surface_of(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x), 0.0, float(cell.y))


func _shocker() -> Unit:
	var unit: Unit = H.spawn_unit(self, PLAYER, Vector2i(0, 0))
	(unit.get_equipped_weapon() as WeaponInstance).template.main_attack.elemental_damage_type = \
		Elemental.Element.SHOCK
	return unit


func _hop(from: Vector2i, to: Vector2i, step: int) -> Conduction.Link:
	var link := Conduction.Link.new()
	link.from = from
	link.to = to
	link.step = step
	return link


# A shock aimed at the origin whose current runs east, one hop per cell.
func _shot(hops: int) -> AttackAction:
	var shooter := _shocker()
	var attack := AttackAction.create(shooter, Vector2i(0, 4), null, Vector2i(0, 0))
	attack.fired_attack = shooter.get_fired_attack()
	var links: Array[Conduction.Link] = []
	for i in hops:
		links.append(_hop(Vector2i(i, 0), Vector2i(i + 1, 0), i + 1))
	attack.arc_links = links
	return attack


func _straight(from: Vector3, to: Vector3, samples: int) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in samples:
		points.append(from.lerp(to, float(i) / float(samples - 1)))
	return points


# --- The sky strike ------------------------------------------------------------------

# The effect never invents a height for the strike: it takes the last stretch of the shot's OWN
# trajectory, which is why an attack authored to clear anything comes down almost vertically.
func test_the_strike_is_the_last_stretch_of_the_shot() -> void:
	var shot := _straight(Vector3(0.0, 40.0, 0.0), Vector3(0.0, 0.0, 0.0), 41)

	var tail := ArcLightning.strike_tail(shot, 8.0)

	assert_float(tail[tail.size() - 1].y).is_equal_approx(0.0, 0.001)
	assert_float(tail[0].y).override_failure_message(
		"the strike is %f cells tall, not the 8 it was asked for" % tail[0].y).is_equal_approx(
		8.0, 0.001)


# ...and it reads TOP-DOWN, because a bolt out of the sky that is built from the ground up would
# stagger and taper the wrong way round.
func test_the_strike_reads_from_the_sky_downward() -> void:
	var shot := _straight(Vector3(0.0, 40.0, 0.0), Vector3(0.0, 0.0, 0.0), 41)

	var tail := ArcLightning.strike_tail(shot, 8.0)

	assert_bool(tail[0].y > tail[tail.size() - 1].y).is_true()


# The break is INTERPOLATED, not snapped to whichever sample happened to cross the ceiling -- so a
# coarsely sampled trace still draws a strike of exactly the height asked for. Six samples over forty
# cells puts them eight apart, and 12 lands squarely between two of them.
func test_the_strike_is_its_full_height_however_coarsely_the_shot_was_sampled() -> void:
	var coarse := _straight(Vector3(0.0, 40.0, 0.0), Vector3(0.0, 0.0, 0.0), 6)

	var tail := ArcLightning.strike_tail(coarse, 12.0)

	assert_float(tail[0].y).override_failure_message(
		"the strike snapped to a sample at %f instead of cutting at 12" % tail[0].y
		).is_equal_approx(12.0, 0.001)


# A FLAT shot never breaks the ceiling, so the whole line comes back and it draws as a horizontal rod
# from the shooter. Not a special case in the code and not one here: the same call, different
# content. It is what makes the strike describe the attack instead of overriding it.
func test_a_flat_shot_draws_its_whole_line() -> void:
	var flat := _straight(Vector3(-5.0, 0.5, 0.0), Vector3(0.0, 0.5, 0.0), 11)

	var tail := ArcLightning.strike_tail(flat, 8.0)

	assert_int(tail.size()).is_equal(flat.size())
	assert_vector(tail[0]).is_equal_approx(Vector3(-5.0, 0.5, 0.0), Vector3.ONE * 0.001)


func test_a_shot_with_no_trajectory_draws_no_strike() -> void:
	assert_int(ArcLightning.strike_tail(PackedVector3Array(), 8.0).size()).is_equal(0)


# --- One bolt's shape ----------------------------------------------------------------

# A bolt joins two things and must still be touching both of them after it kinks -- a jag applied at
# the endpoint leaves the tile the current is supposed to be crossing.
func test_a_bolt_stays_pinned_to_both_ends() -> void:
	var path := PackedVector3Array([Vector3.ZERO, Vector3(1.0, 0.0, 0.0)])

	var bolt := ArcLightning.jagged(path, 12345, 8, 0.4)

	assert_vector(bolt[0]).is_equal_approx(Vector3.ZERO, Vector3.ONE * 0.0001)
	assert_vector(bolt[bolt.size() - 1]).is_equal_approx(
		Vector3(1.0, 0.0, 0.0), Vector3.ONE * 0.0001)


func test_a_bolt_actually_leaves_its_straight_line() -> void:
	var path := PackedVector3Array([Vector3.ZERO, Vector3(1.0, 0.0, 0.0)])

	var straight := ArcLightning.jagged(path, 12345, 8, 0.0)
	var kinked := ArcLightning.jagged(path, 12345, 8, 0.4)

	assert_int(kinked.size()).is_equal(straight.size())
	var moved := false
	for i in kinked.size():
		if kinked[i].distance_to(straight[i]) > 0.001:
			moved = true
	assert_bool(moved).override_failure_message(
		"the jag knob moved nothing -- every bolt is a rod").is_true()


# Derived from the key, never randf(): the same bolt at the same instant of a replay is the same
# bolt. Two keys, two shapes, is the other half -- without it a "deterministic" bolt could be one
# fixed shape for every hop on the board.
func test_a_bolt_is_the_same_shape_for_the_same_key_and_a_different_one_otherwise() -> void:
	var path := PackedVector3Array([Vector3.ZERO, Vector3(1.0, 0.0, 0.0)])

	var once := ArcLightning.jagged(path, 7, 8, 0.4)
	var again := ArcLightning.jagged(path, 7, 8, 0.4)
	var other := ArcLightning.jagged(path, 8, 8, 0.4)

	for i in once.size():
		assert_vector(again[i]).is_equal_approx(once[i], Vector3.ONE * 0.0001)
	var differs := false
	for i in once.size():
		if other[i].distance_to(once[i]) > 0.001:
			differs = true
	assert_bool(differs).is_true()


func test_a_polyline_resamples_to_even_spacing() -> void:
	var path := PackedVector3Array([Vector3.ZERO, Vector3(1.0, 0.0, 0.0), Vector3(4.0, 0.0, 0.0)])

	var even := ArcLightning.resample(path, 5)

	assert_int(even.size()).is_equal(5)
	for i in range(1, even.size()):
		assert_float(even[i - 1].distance_to(even[i])).is_equal_approx(1.0, 0.001)


# --- The fade ------------------------------------------------------------------------

func test_a_bolt_opens_at_full_strength_and_is_gone_at_the_end() -> void:
	assert_float(ArcLightning.envelope(0.0, 0.35)).is_equal_approx(1.0, 0.001)
	assert_float(ArcLightning.envelope(1.0, 0.35)).is_equal(0.0)
	assert_float(ArcLightning.envelope(-0.5, 0.35)).is_equal(0.0)


# The afterimage is the TAIL of one curve rather than a second effect. The fork is what is pinned:
# at 0 the bolt is nearly gone halfway through, at 1 it is exactly half as bright.
func test_the_afterimage_dial_decides_what_the_tail_holds() -> void:
	var popped := ArcLightning.envelope(0.5, 0.0)
	var held := ArcLightning.envelope(0.5, 1.0)

	assert_float(held).is_equal_approx(0.5, 0.001)
	assert_bool(popped < held * 0.2).override_failure_message(
		"with no afterimage the bolt still holds %f of itself halfway through" % popped).is_true()


# --- The whole effect ----------------------------------------------------------------

# Everything lit at once, so the count is the whole storm: three hops and the strike.
func test_a_shock_puts_every_bolt_it_was_handed_on_the_mesh() -> void:
	_arc.point_of = _surface_of
	ArcLightning.strike_delay = 0.0
	ArcLightning.arc_step_delay = 0.0
	var shot := _shot(3)

	_arc.strike(shot, _straight(Vector3(0.0, 40.0, 0.0), Vector3.ZERO, 41))
	_arc._process(0.01)

	assert_int(_arc.bolts_drawn).override_failure_message(
		"the blow reached the node and %d bolts were built" % _arc.bolts_drawn).is_equal(4)


# THE CURRENT TRAVELS, and this is the one thing in the effect that is not a knob: a hop waits for
# the flood's own step count before it lights. Driven on an explicit schedule so the case measures
# the ORDER rather than any of the durations, which are all tunable.
func test_a_far_hop_is_dark_until_the_current_reaches_it() -> void:
	_arc.point_of = _surface_of
	ArcLightning.sky_strike = false        # the strike would otherwise be in the count
	ArcLightning.strike_delay = 0.0
	ArcLightning.arc_step_delay = 1.0
	ArcLightning.bolt_life = 10.0          # nothing expires inside the window under test
	var shot := _shot(3)

	_arc.strike(shot, PackedVector3Array())
	_arc._process(1.5)                     # past the first hop's turn, short of the second's
	var near := _arc.bolts_drawn
	_arc._process(2.0)                     # past all three
	var all := _arc.bolts_drawn

	assert_int(near).override_failure_message(
		"%d hops lit at once -- the current does not travel, it appears" % near).is_equal(1)
	assert_int(all).is_equal(3)


# The ruling this effect exists to satisfy: the current is drawn ABOVE the water. Asserted against
# the surface the host reported rather than against the lift knob's own number, so retuning it
# cannot red this. The jag is off, so what is measured is the lift and not a kink that happened to
# throw a segment upward.
func test_the_current_is_drawn_above_the_surface_it_crosses() -> void:
	_arc.point_of = _surface_of
	ArcLightning.sky_strike = false        # so the bounds are the CURRENT's and nothing else
	ArcLightning.strike_delay = 0.0
	ArcLightning.arc_step_delay = 0.0
	ArcLightning.bolt_jag = 0.0
	var shot := _shot(2)

	_arc.strike(shot, PackedVector3Array())
	_arc._process(0.01)

	var bounds := _arc.drawn_bounds()
	assert_int(_arc.bolts_drawn).override_failure_message(
		"fixture: nothing was drawn, so these bounds are empty rather than high").is_equal(2)
	assert_bool(bounds.position.y > 0.0).override_failure_message(
		"the bolts sit at y=%f, on the water rather than over it" % bounds.position.y).is_true()


func test_an_attack_carrying_no_shock_draws_nothing() -> void:
	_arc.point_of = _surface_of
	ArcLightning.strike_delay = 0.0
	ArcLightning.arc_step_delay = 0.0
	var shot := _shot(3)
	(shot.actor.get_equipped_weapon() as WeaponInstance).template.main_attack \
		.elemental_damage_type = Elemental.Element.FIRE
	shot.fired_attack = shot.actor.get_fired_attack()

	assert_bool(ArcLightning.draws(shot)).is_false()
	_arc.strike(shot, _straight(Vector3(0.0, 40.0, 0.0), Vector3.ZERO, 41))
	_arc._process(0.01)

	assert_int(_arc.bolts_drawn).is_equal(0)


# #217'S FORK, both sides. What strobes is the RE-ROLL, so the safe mode freezes the shape and leaves
# the strike, the spread and the fade exactly as they were -- the setting's promise is a steady state
# rather than a missing effect. Pinning either side alone would pin authored content (#449).
func test_the_photosensitivity_setting_freezes_the_flicker_and_nothing_else() -> void:
	var bolt := ArcLightning.Bolt.new()
	bolt.path = PackedVector3Array([Vector3.ZERO, Vector3(1.0, 0.0, 0.0)])
	bolt.key = 99
	bolt.life = 1.0

	_arc._elapsed = 0.0
	var safe_first := _arc._shape_key(bolt, true)
	var loud_first := _arc._shape_key(bolt, false)
	_arc._elapsed = 0.5
	var safe_later := _arc._shape_key(bolt, true)
	var loud_later := _arc._shape_key(bolt, false)

	assert_int(safe_later).override_failure_message(
		"the bolt re-rolled its shape with the photosensitivity setting on").is_equal(safe_first)
	assert_bool(loud_later != loud_first).override_failure_message(
		"the bolt never re-rolls at all, so the setting above is switching nothing off").is_true()
