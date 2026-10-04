# #1196: a unit that leaves its squad keeps the old squad's archetype and zone in its solo squad
# (dev ruling, 2026-10-03), and never its name or its post. One case per door into a solo squad:
# eject's three causes share one body, so a down and a loss of contact stand in for it, and disband
# is the other door.
#
# Driven through the real SquadManager (make_manager), the test_squad_member_left fixture.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const ENEMY := Team.Faction.ENEMY
const SENTRY := AIArchetype.Type.SENTRY
const ZONE := "Gate"

var _sm: SquadManager
# What each new squad held at the moment squad_created fired, keyed by the squad.
var _at_emit: Dictionary = {}


func before_test() -> void:
	_sm = H.make_manager(self)
	_at_emit = {}
	_sm.squad_created.connect(_on_created)


func _on_created(squad: Squad) -> void:
	_at_emit[squad] = {"archetype": squad.archetype, "zone": squad.zone_name}


# A named Sentry squad bound to ZONE, its post set, a leader at the origin and one member beside it.
func _sentry_pair() -> Array[Unit]:
	var leader: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(0, 0))
	var member: Unit = H.spawn_solo(self, _sm, ENEMY, Vector2i(1, 0))
	_sm.join_squad(member, leader.squad)
	var squad := leader.squad
	squad.squad_name = "Gate Watch"
	squad.archetype = SENTRY
	squad.zone_name = ZONE
	squad.home_cell = Vector2i(0, 0)
	_at_emit = {}
	return [leader, member]


func _assert_kept(unit: Unit, old: Squad, door: String) -> void:
	var squad := unit.squad
	assert_object(squad).override_failure_message("%s: the unit is not in a new squad" % door) \
			.is_not_null().is_not_same(old)
	assert_int(int(squad.archetype)).override_failure_message(
			"%s: the solo squad lost its archetype" % door).is_equal(SENTRY)
	assert_str(squad.zone_name).override_failure_message("%s: the solo squad lost its zone" % door) \
			.is_equal(ZONE)
	assert_str(squad.squad_name).override_failure_message(
			"%s: the solo squad carried the formation's name" % door).is_empty()
	assert_that(squad.home_cell).override_failure_message(
			"%s: the solo squad carried the old leader's post" % door).is_equal(Squad.NO_HOME)


# The reported path: a Hold or Sentry squad rescues its own downed member, and the solo squad the
# down made is what the revived unit plays as.
func test_a_downed_member_keeps_the_squads_archetype_and_zone() -> void:
	var units := _sentry_pair()
	var old := units[0].squad
	_sm.handle_unit_downed(units[1])
	_assert_kept(units[1], old, "down")


# A listener reading the squad off squad_created sees settled state (the join_squad rule).
func test_the_archetype_is_set_before_squad_created_fires() -> void:
	var units := _sentry_pair()
	_sm.handle_unit_downed(units[1])
	var heard: Dictionary = _at_emit.get(units[1].squad, {})
	assert_bool(heard.is_empty()).override_failure_message("fixture: squad_created never named the new squad") \
			.is_false()
	assert_int(int(heard["archetype"])).override_failure_message(
			"squad_created fired before the archetype was set").is_equal(SENTRY)
	assert_str(str(heard["zone"])).override_failure_message(
			"squad_created fired before the zone was set").is_equal(ZONE)


func test_a_member_out_of_contact_keeps_the_squads_archetype_and_zone() -> void:
	var units := _sentry_pair()
	var old := units[0].squad
	units[1].movement.cell = Vector2i(12, 0)   # far past any cohesion range on open ground
	_sm.enforce_contact()
	_assert_kept(units[1], old, "loss of contact")


func test_disbanding_keeps_the_squads_archetype_and_zone_for_everyone() -> void:
	var units := _sentry_pair()
	var old := units[0].squad
	_sm.disband_squad(old)
	for unit in units:
		_assert_kept(unit, old, "disband")
