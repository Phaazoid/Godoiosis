# THE THREE CHANNELS BESIDE THE BOLTS (#887 slice 2): sparks on the bodies, a flash on the screen,
# and the current crawling through the water itself.
#
# Each one crosses a system the ribbons do not, which is why they shipped together and are tested
# together: a GPU particle system, a white-out that already had one driver, and the water shader.
# What they SHARE is the arc's own clock -- every one of them is measured against the same elapsed
# seconds the bolts are, so a hitstop freezes the lot rather than three of four.
#
# WHAT NO HEADLESS CASE CAN SEE, stated once so nothing below oversells itself: a GPU particle is
# simulated on the card and never read back, and under the dummy renderer a global shader parameter
# REGISTERS but stores nothing (`global_shader_parameter_get` answers null whatever anyone sets --
# measured by #552 and the reason `SpyMirror` exists). So the assertions here are on the CPU side of
# each wire: what was thrown, what was pushed, and what the arithmetic behind them says.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")
const PLAYER := Team.Faction.PLAYER
const ENEMY := Team.Faction.ENEMY

var _arc: ArcLightning
var _knobs: Dictionary = {}
var _volleys: Array = []


# Records what BoardMirror pushes rather than letting it reach a renderer that is not listening --
# test_water_knobs.gd's own spy, one channel along. The IMAGE is captured as built for the reason
# that file gives at length: headless, an ImageTexture reads back the FIRST image it was ever given
# and never changes again, so a case reading the texture would be green against a mask that had
# stopped updating.
class SpyMirror extends BoardMirror:
	var pushed: Dictionary[String, Variant] = {}
	var shock_image: Image

	func _push_water(uniform: StringName, value: Variant) -> void:
		pushed[String(uniform)] = value
		super(uniform, value)

	func _push_shock_image(image: Image) -> void:
		shock_image = image
		super(image)


func before_test() -> void:
	_arc = ArcLightning.new()
	add_child(_arc)
	auto_free(_arc)
	_arc.set_process(false)     # every schedule below is driven by hand
	_knobs = {
		"sky_strike": ArcLightning.sky_strike,
		"arcs": ArcLightning.arcs,
		"strike_delay": ArcLightning.strike_delay,
		"arc_step_delay": ArcLightning.arc_step_delay,
		"bolt_life": ArcLightning.bolt_life,
		"flash": ArcLightning.flash,
		"flash_life": ArcLightning.flash_life,
		"crawl": ArcLightning.crawl,
		"crawl_life": ArcLightning.crawl_life,
		"sparks": ShockSparks.sparks,
		"sparks_per_victim": ShockSparks.sparks_per_victim,
	}


func after_test() -> void:
	ArcLightning.sky_strike = _knobs["sky_strike"]
	ArcLightning.arcs = _knobs["arcs"]
	ArcLightning.strike_delay = _knobs["strike_delay"]
	ArcLightning.arc_step_delay = _knobs["arc_step_delay"]
	ArcLightning.bolt_life = _knobs["bolt_life"]
	ArcLightning.flash = _knobs["flash"]
	ArcLightning.flash_life = _knobs["flash_life"]
	ArcLightning.crawl = _knobs["crawl"]
	ArcLightning.crawl_life = _knobs["crawl_life"]
	ShockSparks.sparks = _knobs["sparks"]
	ShockSparks.sparks_per_victim = _knobs["sparks_per_victim"]
	# create_volley shares one self-referential array across every sibling, so a volley is a
	# RefCounted cycle that never frees on its own -- test_volley.gd's own teardown.
	var empty: Array[AttackAction] = []
	for volley in _volleys:
		for attack in volley:
			attack.volley = empty
	_volleys.clear()


func _surface_of(cell: Vector2i) -> Vector3:
	return Vector3(float(cell.x), 0.0, float(cell.y))


func _shocker() -> Unit:
	var unit: Unit = H.spawn_unit(self, PLAYER, Vector2i(0, 4))
	(unit.get_equipped_weapon() as WeaponInstance).template.main_attack.elemental_damage_type = \
		Elemental.Element.SHOCK
	return unit


func _hop(from: Vector2i, to: Vector2i, step: int) -> Conduction.Link:
	var link := Conduction.Link.new()
	link.from = from
	link.to = to
	link.step = step
	return link


# A current running east from the origin, one hop a cell.
func _river(hops: int) -> Array[Conduction.Link]:
	var links: Array[Conduction.Link] = []
	for i in hops:
		links.append(_hop(Vector2i(i, 0), Vector2i(i + 1, 0), i + 1))
	return links


# A shock whose current runs east and which caught every body in `victims`.
func _shot(victims: Array[Unit], hops: int) -> AttackAction:
	var shooter := _shocker()
	var links := _river(hops)
	var footprint: Array[Vector2i] = [Vector2i(0, 0)]
	if victims.is_empty():
		# #47's cell attack: the water conducts whether or not anyone is standing in it, and every
		# shock rune touches the MAP, so this is a legal order rather than a fixture convenience.
		var cell_shot := AttackAction.create(shooter, Vector2i(0, 4), null, Vector2i(0, 0))
		cell_shot.fired_attack = shooter.get_fired_attack()
		cell_shot.footprint = footprint
		cell_shot.arc_links = links
		return cell_shot
	var volley := AttackAction.create_volley(shooter, Vector2i(0, 4), Vector2i(0, 0), victims,
			shooter.get_fired_attack(), footprint, links)
	_volleys.append(volley)
	return volley[0]


# --- The tree, as a per-cell answer ---------------------------------------------------

# The water shader draws one texel per cell and cannot walk a list of hops, so the tree has a second
# SHAPE. A projection, never a second store -- which is what this pins: the same tree, read the
# other way round.
func test_the_tree_reads_as_a_hop_count_per_cell() -> void:
	var steps := Conduction.steps_of(_river(3))

	assert_int(steps[Vector2i(0, 0)]).override_failure_message(
		"the struck cell is not at hop 0, so the current starts somewhere else").is_equal(0)
	for distance in range(1, 4):
		assert_int(steps[Vector2i(distance, 0)]).is_equal(distance)
	assert_bool(steps.has(Vector2i(9, 9))).is_false()


func test_a_current_that_never_ran_has_no_hops_to_read() -> void:
	var none: Array[Conduction.Link] = []
	assert_int(Conduction.steps_of(none).size()).is_equal(0)


# --- The sparks -----------------------------------------------------------------------

# A burst waits for the hop that reaches the body it belongs to, and the delay is READ BACK off the
# stamped tree rather than tracked beside it -- so the sparks travel with the bolts by construction
# and there is no second schedule to keep in step.
func test_a_body_sparks_when_the_current_reaches_it() -> void:
	ArcLightning.strike_delay = 0.1
	ArcLightning.arc_step_delay = 0.25
	var links := _river(3)

	assert_float(ArcLightning.spark_delay_for(Vector2i(2, 0), links)).is_equal_approx(0.6, 0.001)
	assert_float(ArcLightning.spark_delay_for(Vector2i(0, 0), links)).override_failure_message(
		"a body standing in the blast itself waited for a hop").is_equal(0.0)


func test_a_caught_body_throws_a_burst() -> void:
	_arc.point_of = _surface_of
	ArcLightning.strike_delay = 0.0
	ArcLightning.arc_step_delay = 0.0
	var near: Unit = H.spawn_unit(self, ENEMY, Vector2i(1, 0))
	var far: Unit = H.spawn_unit(self, ENEMY, Vector2i(2, 0))
	var caught: Array[Unit] = [near, far]

	_arc.strike(_shot(caught, 3), PackedVector3Array())
	_arc._process(0.01)

	assert_int(_arc.sparks_thrown()).override_failure_message(
		"the blow caught two bodies and threw %d bursts" % _arc.sparks_thrown()).is_equal(2)


# The stagger again, one channel over: a body the current has not reached yet is not sparking. Same
# property the bolts have, asserted separately because a second schedule is exactly what this
# design avoids and a case is what says so.
func test_a_far_body_waits_for_the_current() -> void:
	_arc.point_of = _surface_of
	ArcLightning.strike_delay = 0.0
	ArcLightning.arc_step_delay = 1.0
	var near: Unit = H.spawn_unit(self, ENEMY, Vector2i(1, 0))
	var far: Unit = H.spawn_unit(self, ENEMY, Vector2i(3, 0))
	var caught: Array[Unit] = [near, far]

	_arc.strike(_shot(caught, 3), PackedVector3Array())
	_arc._process(1.5)                     # past the first hop, short of the third
	var early := _arc.sparks_thrown()
	_arc._process(2.0)

	assert_int(early).override_failure_message(
		"%d bodies sparked at once -- the sparks do not travel with the current" % early
		).is_equal(1)
	assert_int(_arc.sparks_thrown()).is_equal(2)


func test_the_sparks_toggle_throws_nothing() -> void:
	_arc.point_of = _surface_of
	ArcLightning.strike_delay = 0.0
	ArcLightning.arc_step_delay = 0.0
	ShockSparks.sparks = false
	var body: Unit = H.spawn_unit(self, ENEMY, Vector2i(1, 0))
	var caught: Array[Unit] = [body]

	_arc.strike(_shot(caught, 3), PackedVector3Array())
	_arc._process(0.01)

	assert_int(_arc.sparks_thrown()).is_equal(0)


# The scatter is SHARED with the slam dust and parameterised rather than copied, so the two
# genuinely differ by their own knobs -- which is the whole reason it could be shared at all. A fan
# that ignored what it was handed would be one effect wearing two names.
func test_the_two_effects_fan_their_own_way() -> void:
	var dust := ParticleFan.scatter(Vector3.ZERO, 7, 12, 0.4, 2.0, 0.5, 0.05)
	var sparks := ParticleFan.scatter(Vector3.ZERO, 7, 12, 0.1, 6.0, 1.5, 0.05)

	assert_int(dust.size()).is_equal(sparks.size())
	var differs := false
	for i in dust.size():
		if (dust[i]["velocity"] as Vector3).distance_to(sparks[i]["velocity"]) > 0.001:
			differs = true
	assert_bool(differs).override_failure_message(
		"two fans with different knobs came out identical -- the parameters reach nothing"
		).is_true()


# --- The flash ------------------------------------------------------------------------

func test_the_flash_pops_and_is_gone() -> void:
	_arc.point_of = _surface_of
	ArcLightning.flash_life = 0.2
	var body: Unit = H.spawn_unit(self, ENEMY, Vector2i(1, 0))
	var caught: Array[Unit] = [body]

	_arc.strike(_shot(caught, 1), PackedVector3Array())
	_arc._process(0.001)
	var struck := _arc.flash_level()
	_arc._process(0.5)

	assert_float(struck).override_failure_message(
		"the blow landed and the screen did not brighten").is_greater(0.0)
	assert_float(_arc.flash_level()).override_failure_message(
		"the flash is still up half a second after a 0.2s life").is_equal(0.0)


# THE CLOCK ONLY ADVANCES WHILE SOMETHING IS LIVE, which is what makes a strike's own timestamps
# self-consistent -- and is therefore also what would strand a flash forever if the flash were not
# one of the things counted as live. With both ribbon toggles off there are no bolts at all.
func test_a_flash_with_no_bolts_still_ends() -> void:
	_arc.point_of = _surface_of
	ArcLightning.sky_strike = false
	ArcLightning.arcs = false
	# ...and the crawl too, or IT would be what keeps the clock running and this case would pass
	# against a flash the liveness test had never heard of.
	ArcLightning.crawl = false
	ArcLightning.flash_life = 0.2
	var none: Array[Unit] = []

	_arc.strike(_shot(none, 1), PackedVector3Array())
	_arc._process(0.001)
	assert_float(_arc.flash_level()).is_greater(0.0)
	_arc._process(0.5)

	assert_float(_arc.flash_level()).override_failure_message(
		"with nothing else in the air the clock froze and the screen stayed white").is_equal(0.0)


# --- The crawl ------------------------------------------------------------------------

func test_the_water_is_dormant_until_a_shock_and_after_one() -> void:
	_arc.point_of = _surface_of
	ArcLightning.crawl_life = 0.2
	ArcLightning.arc_step_delay = 0.0
	var none: Array[Unit] = []

	assert_float(_arc.crawl_age()).override_failure_message(
		"a board nobody has shocked is not dormant").is_less(0.0)
	_arc.strike(_shot(none, 1), PackedVector3Array())
	_arc._process(0.01)
	assert_float(_arc.crawl_age()).is_greater_equal(0.0)
	_arc._process(3.0)
	assert_float(_arc.crawl_age()).override_failure_message(
		"the crawl never went dormant again").is_less(0.0)


# The crawl deliberately outlives the bolts -- the water holding the charge after the air has
# cleared is what makes it read as a current passing THROUGH rather than as a second set of bolts.
# It is also why the clock's own liveness test had to count the crawl.
func test_the_crawl_outlives_the_bolts_that_lit_it() -> void:
	_arc.point_of = _surface_of
	ArcLightning.bolt_life = 0.2
	ArcLightning.crawl_life = 2.0
	ArcLightning.strike_delay = 0.0
	ArcLightning.arc_step_delay = 0.0
	var none: Array[Unit] = []

	_arc.strike(_shot(none, 2), PackedVector3Array())
	_arc._process(0.5)                     # every bolt has expired
	var after_the_bolts := _arc.crawl_age()
	_arc._process(0.5)                     # ...and the water must go on running

	assert_int(_arc.bolts_drawn).is_equal(0)
	assert_float(after_the_bolts).override_failure_message(
		"the water stopped the moment the bolts did").is_greater_equal(0.0)
	# ADVANCING, not merely non-negative: the clock only ticks while something is counted as live,
	# so a crawl left out of that test freezes at whatever age the last bolt died at -- which reads
	# as a frozen age rather than as a dormant one, and no is_greater_equal could see it.
	assert_float(_arc.crawl_age()).override_failure_message(
		"the crawl's age stuck at %f once the bolts were gone" % after_the_bolts
		).is_greater(after_the_bolts)


func test_the_crawl_toggle_leaves_the_water_dormant() -> void:
	_arc.point_of = _surface_of
	ArcLightning.crawl = false
	var none: Array[Unit] = []

	_arc.strike(_shot(none, 2), PackedVector3Array())

	assert_float(_arc.crawl_age()).is_less(0.0)


# The picture the water reads: one texel per cell, holding the hop's own step +1 so that ZERO can
# mean "the current never came here". Asserted through the mirror's own push funnel, because
# headless an ImageTexture reads back the first image it was ever handed and never changes again.
func test_the_mask_holds_a_hop_per_cell_and_zero_everywhere_else() -> void:
	var mirror: SpyMirror = auto_free(SpyMirror.new())
	add_child(mirror)
	var grid: TileMapLayer = auto_free(TileMapLayer.new())
	add_child(grid)
	grid.tile_set = load("res://Resources/TestTiles.tres")
	for x in range(4):
		grid.set_cell(Vector2i(x, 0), 0, Vector2i(5, 0))

	mirror.push_shock(grid, Conduction.steps_of(_river(3)))

	assert_object(mirror.shock_image).override_failure_message(
		"nothing was pushed at the water at all").is_not_null()
	assert_int(mirror.shock_image.get_width()).is_equal(4)
	for distance in range(4):
		var byte := int(round(mirror.shock_image.get_pixel(distance, 0).r * 255.0))
		assert_int(byte).override_failure_message(
			"the cell %d out encodes hop %d" % [distance, byte]).is_equal(distance + 1)


func test_a_cell_the_current_missed_reads_as_nothing() -> void:
	var mirror: SpyMirror = auto_free(SpyMirror.new())
	add_child(mirror)
	var grid: TileMapLayer = auto_free(TileMapLayer.new())
	add_child(grid)
	grid.tile_set = load("res://Resources/TestTiles.tres")
	for x in range(4):
		grid.set_cell(Vector2i(x, 0), 0, Vector2i(5, 0))

	mirror.push_shock(grid, Conduction.steps_of(_river(1)))

	assert_float(mirror.shock_image.get_pixel(3, 0).r).override_failure_message(
		"a cell the current never reached is lit").is_equal(0.0)


func test_the_crawl_clock_reaches_the_water() -> void:
	var mirror: SpyMirror = auto_free(SpyMirror.new())
	add_child(mirror)

	mirror.push_shock_clock(0.25, 0.9, 0.05, Color(0.7, 0.5, 0.9, 0.5))

	assert_float(float(mirror.pushed["water_shock_age"])).is_equal_approx(0.25, 0.0001)
	assert_float(float(mirror.pushed["water_shock_life"])).is_equal_approx(0.9, 0.0001)
	assert_float(float(mirror.pushed["water_shock_step"])).is_equal_approx(0.05, 0.0001)


# The crawl's HUE is the element's, never a copy: what colour electricity is should be one decision.
# Asserted against the palette rather than against a number, so retuning Shock moves both.
func test_the_crawl_wears_the_elements_own_colour() -> void:
	var hue := ElementPalette.color_for_element(Elemental.Element.SHOCK)
	var tint := _arc.crawl_tint()

	assert_float(tint.r).is_equal_approx(hue.r, 0.0001)
	assert_float(tint.g).is_equal_approx(hue.g, 0.0001)
	assert_float(tint.b).is_equal_approx(hue.b, 0.0001)


# --- The white-out's two drivers ------------------------------------------------------

# THE ONE CASE THAT NEEDS THE REAL SCENE, and it needs it because the failure it guards is a WIRE.
#
# The white-out was built for the tear-out and had exactly ONE writer, reached only from inside the
# transition's own driver -- which returns early the moment no tear-out is flying, i.e. on every
# frame a shock is ever struck on. So the second driver needed a push of its own on the ordinary
# frame path, and that push is invisible from either end: the level is computed correctly, the
# channel applies correctly, and nothing joins them (#103's shape).
#
# Driven through `_process` rather than through the composition itself, and the difference is not
# academic -- a case calling `_push_whiteout()` directly PASSES with the frame-path push deleted,
# which is what a mutant established rather than reasoning.
func test_a_shock_flash_reaches_the_screen_on_an_ordinary_frame() -> void:
	var scene: Node3D = auto_free(SCENE.instantiate() as Node3D)
	get_tree().root.add_child(scene)
	await await_idle_frame()
	var arc: ArcLightning = scene._arc
	assert_object(arc).override_failure_message(
		"the scene built no arc effect, so this case is about nothing").is_not_null()
	ArcLightning.flash = true
	ArcLightning.flash_life = 1.0

	arc._flash_at = 0.0
	arc._elapsed = 0.0
	scene._process(0.0)
	var lit: bool = scene._whiteout != null and scene._whiteout.visible

	arc._flash_at = -1.0
	scene._process(0.0)
	var dark: bool = scene._whiteout != null and scene._whiteout.visible

	get_tree().root.remove_child(scene)
	assert_bool(lit).override_failure_message(
		"a shock's flash never reached the screen -- outside a tear-out nothing writes this " \
		+ "channel at all").is_true()
	assert_bool(dark).override_failure_message(
		"the flash never cleared").is_false()
