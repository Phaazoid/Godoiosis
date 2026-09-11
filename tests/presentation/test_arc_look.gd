# A SHOCK ATTACK MAY AUTHOR ITS OWN LOOK (#900): a named EffectLook the attack points at, holding
# only the rows it disagrees with, over the Game tab's values for everything else.
#
# What is worth pinning here is the LAYERING, because every one of its failures is silent. A read
# that forgot its override plays the default and looks exactly like an attack with no look. A look
# that is MERGED rather than replaced between strikes plays the previous attack's numbers, which is
# only visible when two differently-authored shocks land in one battle. And a row whose fallback is
# spelled twice drifts the first time the default is retuned.
#
# EVERYTHING VISUAL IS STILL THE DEV'S, as test_arc_slice2.gd says at length: a GPU particle is
# never read back and a global shader parameter stores nothing headless. These assert the CPU side
# -- what was scheduled, what the arithmetic says, and which value reached the node.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const PLAYER := Team.Faction.PLAYER

# Far enough into a strike that every hop of a three-cell current has lit and none has faded: the
# last one is born a fifth of a second in and the shortest default life is near half a second. A
# case driving the clock to zero instead reads "not yet" as "never" and passes against anything.
const _MID_FLIGHT := 0.3

# A long life, and a moment ~83% through it. There the hard pop has decayed under the draw
# threshold while a linear fade is still a sixth of the way up -- which is the only place the two
# ends of `afterimage` can be told apart at all.
const _LONG_LIFE := 10.0
const _LATE := 8.5

var _arc: ArcLightning
var _knobs: Dictionary = {}
var _volleys: Array = []


func before_test() -> void:
	_arc = ArcLightning.new()
	add_child(_arc)
	auto_free(_arc)
	_arc.set_process(false)     # every schedule below is driven by hand
	_arc.point_of = _surface_of
	_knobs = {
		"arcs": ArcLightning.arcs,
		"bolt_life": ArcLightning.bolt_life,
		"arc_step_delay": ArcLightning.arc_step_delay,
		"strike_delay": ArcLightning.strike_delay,
		"crawl": ArcLightning.crawl,
		"crawl_life": ArcLightning.crawl_life,
		"flash_peak": ArcLightning.flash_peak,
		"sparks_per_victim": ShockSparks.sparks_per_victim,
	}


func after_test() -> void:
	ArcLightning.arcs = _knobs["arcs"]
	ArcLightning.bolt_life = _knobs["bolt_life"]
	ArcLightning.arc_step_delay = _knobs["arc_step_delay"]
	ArcLightning.strike_delay = _knobs["strike_delay"]
	ArcLightning.crawl = _knobs["crawl"]
	ArcLightning.crawl_life = _knobs["crawl_life"]
	ArcLightning.flash_peak = _knobs["flash_peak"]
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


# A look with exactly the rows a case is about. Empty means "inherit everything", which is what
# every attack that names no look is read through.
func _look(overrides: Dictionary = {}) -> EffectLook:
	var look := EffectLook.new()
	look.element = Elemental.Element.SHOCK
	look.overrides = overrides
	return look


# A shock attack of our OWN rather than a shipped one: the element and the look both ride the
# stamped `fired_attack`, so nothing here edits content the dev authored (the content razor).
func _shock_attack(look: EffectLook) -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.display_name = "Probe Shock"
	attack.elemental_damage_type = Elemental.Element.SHOCK
	if look != null:
		attack.effect_looks[Elemental.Element.SHOCK] = look
	return attack


func _hop(from: Vector2i, to: Vector2i, step: int) -> Conduction.Link:
	var link := Conduction.Link.new()
	link.from = from
	link.to = to
	link.step = step
	return link


func _river(hops: int) -> Array[Conduction.Link]:
	var links: Array[Conduction.Link] = []
	for i in hops:
		links.append(_hop(Vector2i(i, 0), Vector2i(i + 1, 0), i + 1))
	return links


# A blow that lights three hops of river, wearing `look`. A #47 cell attack, so it catches nobody
# and every assertion below is about the current rather than about a victim.
func _shot(look: EffectLook) -> AttackAction:
	var shooter: Unit = H.spawn_unit(self, PLAYER, Vector2i(0, 4))
	var shot := AttackAction.create(shooter, Vector2i(0, 4), null, Vector2i(0, 0))
	shot.fired_attack = _shock_attack(look)
	shot.footprint = [Vector2i(0, 0)] as Array[Vector2i]
	shot.arc_links = _river(3)
	return shot


# --- an override REACHES the effect ---------------------------------------------------

# The baseline the rest reads against: an attack with no look at all plays the statics, so a case
# that fails below is about the override rather than about the fixture.
func test_an_attack_with_no_look_plays_the_game_tabs_own_values() -> void:
	ArcLightning.arcs = true
	_arc.strike(_shot(null), PackedVector3Array())
	_arc._process(_MID_FLIGHT)

	assert_int(_arc.bolts_drawn).override_failure_message(
		"an attack authoring no look did not draw the default's arcs").is_greater(0)


func test_a_looks_override_turns_the_arcs_off_for_that_attack_alone() -> void:
	ArcLightning.arcs = true
	_arc.strike(_shot(_look({"arcs": false})), PackedVector3Array())
	_arc._process(_MID_FLIGHT)

	assert_int(_arc.bolts_drawn).override_failure_message(
		"the look's `arcs` override never reached the strike").is_equal(0)


# The per-frame half. `afterimage` is read on every REBUILD rather than at birth, so an override of
# it proves the look survives past the call that adopted it -- which a birth-time row cannot say.
#
# Both ends in one case, deliberately: "nothing was drawn" is what an unreached hop and a broken
# fixture look like too, so the linear half is what makes the hard-pop half mean something.
func test_a_per_frame_row_follows_the_look_too() -> void:
	ArcLightning.arcs = true
	_arc.strike(_shot(_look({"afterimage": 0.0, "bolt_life": _LONG_LIFE})), PackedVector3Array())
	_arc._process(_LATE)
	assert_int(_arc.bolts_drawn).override_failure_message(
		"a hard-popping bolt was still drawn most of the way through its life"
	).is_equal(0)

	_arc.strike(_shot(_look({"afterimage": 1.0, "bolt_life": _LONG_LIFE})), PackedVector3Array())
	_arc._process(_LATE)
	assert_int(_arc.bolts_drawn).override_failure_message(
		"a linear fade decayed like a hard pop, so the per-frame read ignores the look"
	).is_greater(0)


# --- a look does NOT leak into the next strike ----------------------------------------

# The sharpest failure this shape has, and the one nothing on screen would explain: a look MERGED
# rather than replaced plays the previous attack's numbers on an attack that authored none.
func test_the_next_strike_does_not_inherit_the_last_ones_look() -> void:
	ArcLightning.arcs = true
	_arc.strike(_shot(_look({"arcs": false})), PackedVector3Array())
	_arc._process(_MID_FLIGHT)
	assert_int(_arc.bolts_drawn).is_equal(0)

	_arc.strike(_shot(null), PackedVector3Array())
	_arc._process(_MID_FLIGHT)

	assert_int(_arc.bolts_drawn).override_failure_message(
		"the previous attack's look survived into an attack that authors none"
	).is_greater(0)


# --- the channels beside the bolts ----------------------------------------------------

# The sparks' schedule is composed from the two delays a look may move, so it has to read the SAME
# look the bolts did -- or the sparks stop travelling with the current they are marking.
func test_the_spark_schedule_is_composed_from_the_looks_own_delays() -> void:
	var look := _look({"strike_delay": 1.0, "arc_step_delay": 0.5})
	var reached := ArcLightning.spark_delay_for(Vector2i(2, 0), _river(3), look)

	assert_float(reached).override_failure_message(
		"the spark delay ignored the look and used the Game tab's own numbers").is_equal_approx(2.0, 0.001)


# The crawl's own clock, which the HOST reads on a frame path where it has no attack in hand. That
# is why these are accessors on the node rather than reads of the statics at battle3d.
func test_the_crawl_clock_the_host_reads_follows_the_look() -> void:
	ArcLightning.crawl = true
	ArcLightning.crawl_life = 0.9
	_arc.strike(_shot(_look({"crawl_life": 4.0})), PackedVector3Array())

	assert_bool(_arc.draws_crawl()).is_true()
	assert_float(_arc.crawl_life_now()).override_failure_message(
		"battle3d would push the Game tab's crawl life over an attack that authored its own"
	).is_equal_approx(4.0, 0.001)


func test_a_look_can_switch_the_crawl_off_for_one_attack() -> void:
	ArcLightning.crawl = true
	_arc.strike(_shot(_look({"crawl": false})), PackedVector3Array())

	assert_bool(_arc.draws_crawl()).is_false()
	assert_float(_arc.crawl_age()).override_failure_message(
		"the crawl ran on an attack whose look turned it off").is_less(0.0)


func test_the_screen_flash_takes_its_peak_from_the_look() -> void:
	ArcLightning.flash_peak = 0.28
	_arc.strike(_shot(_look({"flash_peak": 0.9})), PackedVector3Array())

	assert_float(_arc.flash_level()).override_failure_message(
		"the white-out this shock drives is the Game tab's strength, not the attack's"
	).is_greater(0.5)


# The emitter's own numbers. `fan` is the only part of a burst a headless case can read at all --
# what it returns is what would be handed to emit_particle.
func test_the_spark_fan_is_built_from_the_looks_own_count() -> void:
	ShockSparks.sparks_per_victim = 18
	var many := ShockSparks.fan(Vector3.ZERO, 1, _look({"sparks_per_victim": 40}))

	assert_int(many.size()).override_failure_message(
		"the burst ignored the look's own count").is_equal(40)
	assert_int(ShockSparks.fan(Vector3.ZERO, 1, _look()).size()).override_failure_message(
		"an empty look stopped falling through to the Game tab's count").is_equal(18)


# --- SHARED by reference --------------------------------------------------------------

# The dev's own ruling on the store (2026-09-10): a named look several attacks point at. So an edit
# through one of them is meant to reach the others, which is the property a per-attack dictionary
# would NOT have had -- and the reason the library has a used-by caption at all.
func test_one_look_edited_reaches_every_attack_wearing_it() -> void:
	ArcLightning.arcs = true
	var shared := _look()
	var first := _shot(shared)
	var second := _shot(shared)

	shared.overrides["arcs"] = false
	_arc.strike(first, PackedVector3Array())
	_arc._process(_MID_FLIGHT)
	assert_int(_arc.bolts_drawn).is_equal(0)

	_arc.strike(second, PackedVector3Array())
	_arc._process(_MID_FLIGHT)
	assert_int(_arc.bolts_drawn).override_failure_message(
		"the second attack wearing the same look did not see the edit, so they are not sharing one"
	).is_equal(0)


# --- what an EMPTY look means ---------------------------------------------------------

# Absence is the override's own sentinel-free spelling, so every accessor has to fall through on a
# missing key rather than on a magic value. Asked of all four kinds, because each has its own read.
func test_an_empty_look_falls_through_on_every_kind_of_value() -> void:
	var empty := EffectLook.new()

	assert_float(empty.num("anything", 4.5)).is_equal_approx(4.5, 0.001)
	assert_int(empty.whole("anything", 7)).is_equal(7)
	assert_bool(empty.flag("anything", true)).is_true()
	assert_object(empty.tint("anything", Color.RED)).is_equal(Color.RED)
	assert_bool(empty.is_silent()).is_true()


# A row authored to the SAME value the default happens to hold is still an override, and that is the
# whole reason this storage has no sentinel: #660's trap is that a value equal to the sentinel
# cannot be authored at all, and here there is nothing for it to collide with.
func test_a_row_authored_to_its_own_default_is_still_authored() -> void:
	var look := _look({"bolt_life": ArcLightning.bolt_life})

	assert_bool(look.is_silent()).override_failure_message(
		"a row authored to the default's own value read as no opinion at all").is_false()
	assert_float(look.num("bolt_life", 99.0)).is_equal_approx(ArcLightning.bolt_life, 0.001)
