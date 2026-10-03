# The pre-mission phase, headlessly (#46): the loadout screen's placement decisions and its Begin,
# driven through PlaySession with the session as PreMissionPhase's host.
#
# The roster is a REAL shipped one (RosterCatalog), because a roster resolves by name off disk; its
# contents are never asserted (the content razor, tests/README #9) -- every expectation is derived
# from the roster's own offered entries or from the phase's own answers. The mission around it is
# authored here, in memory: a strip of grass, a five-cell DEPLOYMENT zone, one enemy.
#
# The game-vs-headless agreement is tests/flow/test_pre_mission_two_hosts.gd; this file is the
# headless host on its own.
extends GdUnitTestSuite

const BoardBuilder := preload("res://play/board_builder.gd")
const PlaySession := preload("res://play/play_session.gd")

const CAP := 2
const ZONE: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0)]
const OUTSIDE := Vector2i(6, 2)   # grass, but not in the zone

var _board: Dictionary
var _sess
var _drawn := 0


func before_test() -> void:
	_board = BoardBuilder.build(self, "PreMissionRoot")
	auto_free(_board.root)
	BoardBuilder.paint_rect(_board.grid, Rect2i(0, 0, 10, 4))
	BoardBuilder.spawn(_board, UnitFactory.create_unit_data(Stats.STAT_DEFAULTS.duplicate(), "Foe",
			Team.Faction.ENEMY), Vector2i(9, 3))
	var scenario := ScenarioData.new()
	scenario.roster = _largest_roster()
	scenario.deployment_cap = CAP
	scenario.zones = {"landing": {"kind": ZoneManager.Kind.DEPLOYMENT, "cells": ZONE.duplicate()}}
	_board.zone_manager.load_dict(scenario.zones)
	_board["scenario"] = scenario
	_sess = PlaySession.new(_board)
	_drawn = _sess.start_pre_mission()


# The shipped roster offering the most characters, so the cap leaves someone in reserve.
static func _largest_roster() -> String:
	var best := ""
	var most := -1
	for name: String in RosterCatalog.saved_rosters():
		var count := _offered_count(name)
		if count > most:
			best = name
			most = count
	return best


static func _offered_count(roster_name: String) -> int:
	var roster: Roster = RosterCatalog.resolve(roster_name)
	if roster == null:
		return 0
	var count := 0
	for entry: ScenarioUnitEntry in roster.offered_entries():
		if entry != null and entry.unit_data != null:
			count += 1
	return count


func _deployed() -> Array[Unit]:
	var out: Array[Unit] = []
	for unit: Unit in _sess.roster_units():
		if _sess.is_deployed(unit):
			out.append(unit)
	return out


func _reserve() -> Array[Unit]:
	return _sess.reserve_units()


func _precondition_reserve() -> bool:
	if _reserve().is_empty():
		fail("fixture: the largest shipped roster is not larger than the cap (%d), so nobody waits in reserve" % CAP)
		return false
	return true


func _free_zone_cell() -> Vector2i:
	for cell: Vector2i in ZONE:
		if _sess.get_unit_at_cell(cell) == null:
			return cell
	return Vector2i(-99, -99)


# ==============================================================================

func test_the_draw_puts_the_roster_in_reserve_and_stands_the_authored_plan() -> void:
	assert_bool(_drawn > 0).override_failure_message("nobody stood up -- is a roster shipped?").is_true()
	assert_bool(_sess.is_deploying()).is_true()
	assert_int(_sess.deployed_count()).is_equal(_drawn)
	assert_int(_drawn).is_less_equal(CAP)
	for unit: Unit in _deployed():
		assert_bool(ZONE.has(unit.movement.cell)).override_failure_message(
			"%s stood outside the deployment zone" % unit.get_unit_name()).is_true()
	# Everybody the roster offers exists, standing or waiting.
	assert_int(_deployed().size() + _reserve().size()).is_equal(_offered_count(_largest_roster()))


func test_every_battle_verb_waits_for_begin() -> void:
	var h: String = _sess.handle_for(_deployed()[0])
	var answers: Array[Dictionary] = [
		_sess.legal_moves(h), _sess.queue_move(h, Vector2i(1, 1)), _sess.execute(), _sess.end_turn()]
	for answer: Dictionary in answers:
		assert_bool(answer.ok).is_false()
		assert_str(str(answer.error)).contains("has not begun")


func test_the_cap_refuses_one_more_in_the_phases_own_words() -> void:
	if not _precondition_reserve():
		return
	assert_int(_sess.deployed_count()).is_equal(CAP)
	var reason: String = _sess.deploy_block_reason()
	assert_str(reason).override_failure_message("fixture: the force is not full").is_not_empty()
	var r: Dictionary = _sess.deploy(_sess.handle_for(_reserve()[0]), _free_zone_cell())
	assert_bool(r.ok).is_false()
	assert_str(str(r.error)).is_equal(reason)


func test_undeploy_frees_a_place_and_deploy_takes_only_a_zone_cell() -> void:
	if not _precondition_reserve():
		return
	var standing := _deployed()[0]
	assert_bool((_sess.undeploy(_sess.handle_for(standing)) as Dictionary).ok).is_true()
	assert_bool(_sess.is_deployed(standing)).is_false()

	var waiting := _reserve()[0]
	var outside: Dictionary = _sess.deploy(_sess.handle_for(waiting), OUTSIDE)
	assert_bool(outside.ok).is_false()
	assert_bool(_sess.is_deployed(waiting)).is_false()

	var cell := _free_zone_cell()
	assert_bool((_sess.deploy(_sess.handle_for(waiting), cell) as Dictionary).ok).is_true()
	assert_bool(_sess.is_deployed(waiting)).is_true()
	assert_object(waiting.squad).override_failure_message("a deployed unit has no squad").is_not_null()
	assert_that(waiting.movement.cell).is_equal(cell)


func test_reposition_swaps_two_drawn_units_and_stays_in_the_zone() -> void:
	var standing := _deployed()
	if standing.size() < 2:
		fail("fixture: fewer than two units stood up")
		return
	var a := standing[0]
	var b := standing[1]
	var a_cell := a.movement.cell
	var b_cell := b.movement.cell
	assert_bool((_sess.reposition(_sess.handle_for(a), b_cell) as Dictionary).ok).is_true()
	assert_that(a.movement.cell).is_equal(b_cell)
	assert_that(b.movement.cell).is_equal(a_cell)
	assert_bool((_sess.reposition(_sess.handle_for(a), OUTSIDE) as Dictionary).ok).is_false()


func test_a_reserve_unit_takes_no_squad_verb() -> void:
	if not _precondition_reserve():
		return
	var r: String = _sess.handle_for(_reserve()[0])
	var d: String = _sess.handle_for(_deployed()[0])
	for answer: Dictionary in [_sess.join(r, d) as Dictionary, _sess.join(d, r) as Dictionary,
			_sess.leave(r) as Dictionary]:
		assert_bool(answer.ok).is_false()
		assert_str(str(answer.error)).contains("in reserve")


func test_begin_is_refused_with_nobody_standing_and_then_opens_the_battle() -> void:
	for unit: Unit in _deployed():
		_sess.undeploy(_sess.handle_for(unit))
	var refused: Dictionary = _sess.begin()
	assert_bool(refused.ok).is_false()
	assert_bool(_sess.is_deploying()).is_true()

	var first: Unit = _sess.roster_units()[0]
	assert_bool((_sess.deploy(_sess.handle_for(first), _free_zone_cell()) as Dictionary).ok).is_true()
	assert_bool((_sess.begin() as Dictionary).ok).is_true()
	assert_bool(_sess.is_deploying()).is_false()
	var moves: Dictionary = _sess.legal_moves(_sess.handle_for(first))
	assert_str(str(moves.get("error", ""))).not_contains("has not begun")


# ==============================================================================
# The loadout screen's writes (#46 slice 2a): gear, jobs and mods, each through the door the screen
# calls. Every piece moved is authored HERE (a bare Item), and the jobs and mods are whatever the
# catalogues hold -- nothing below asserts which.

const BoardView := preload("res://play/board_view.gd")
const NOT_OPEN := "the pre-mission phase is not open"


func _loadout() -> Loadout:
	return _sess._phase.loadout


func _stash_piece(piece_name := "Loadout Test Piece") -> Item:
	var piece := Item.new()
	piece.display_name = piece_name
	_loadout().stash.append(piece)
	return piece


# The first of these with an empty slot, or null.
static func _with_room(units: Array[Unit]) -> Unit:
	for unit: Unit in units:
		if unit.inventory.has(null):
			return unit
	return null


func _enemy_handle() -> String:
	for unit: Unit in _sess.live_units():
		if unit.get_faction() == Team.Faction.ENEMY:
			return _sess.handle_for(unit)
	return ""


func test_give_moves_gear_between_the_stash_and_roster_units() -> void:
	if not _precondition_reserve():
		return
	var taker := _with_room(_reserve())
	var other := _with_room(_deployed())
	if taker == null or other == null:
		fail("fixture: no roster unit on one side has an empty slot")
		return
	var piece := _stash_piece()
	var taker_h: String = _sess.handle_for(taker)
	var other_h: String = _sess.handle_for(other)

	var given: Dictionary = _sess.give("stash", _loadout().stash.find(piece), taker_h)
	assert_bool(given.ok).override_failure_message(str(given.get("error", ""))).is_true()
	assert_bool(_loadout().stash.has(piece)).override_failure_message(
		"the piece reached a reserve unit and is still in the stash").is_false()
	assert_bool(taker.inventory.has(piece)).is_true()

	var passed: Dictionary = _sess.give(taker_h, taker.inventory.find(piece), other_h)
	assert_bool(passed.ok).override_failure_message(str(passed.get("error", ""))).is_true()
	assert_bool(taker.inventory.has(piece)).is_false()
	assert_bool(other.inventory.has(piece)).is_true()

	var back: Dictionary = _sess.give(other_h, other.inventory.find(piece), "stash")
	assert_bool(back.ok).override_failure_message(str(back.get("error", ""))).is_true()
	assert_bool(other.inventory.has(piece)).is_false()
	assert_bool(_loadout().stash.has(piece)).is_true()


func test_give_refuses_in_the_loadouts_own_words() -> void:
	var unit := _with_room(_sess.roster_units())
	if unit == null:
		fail("fixture: no roster unit has an empty slot")
		return
	var h: String = _sess.handle_for(unit)

	# An empty slot: Loadout's sentence for moving nothing.
	var empty: Dictionary = _sess.give(h, unit.inventory.find(null), "stash")
	assert_bool(empty.ok).is_false()
	assert_str(str(empty.error)).is_equal(_loadout().move_block_reason(null, unit, null))

	# A full unit: the unit's own sentence, through Loadout.
	while unit.inventory.has(null):
		unit.add_item(Item.new())
	var piece := _stash_piece()
	var full: Dictionary = _sess.give("stash", _loadout().stash.find(piece), h)
	assert_bool(full.ok).is_false()
	assert_str(str(full.error)).override_failure_message("fixture: the unit is not full").is_not_empty()
	assert_str(str(full.error)).is_equal(unit.add_block_reason(piece))
	assert_bool(_loadout().stash.has(piece)).is_true()

	# An enemy holds no roster gear.
	var foe := _enemy_handle()
	assert_str(foe).override_failure_message("fixture: no enemy on the board").is_not_empty()
	var to_foe: Dictionary = _sess.give("stash", _loadout().stash.find(piece), foe)
	assert_bool(to_foe.ok).is_false()
	assert_str(str(to_foe.error)).contains("not part of the roster")


func test_a_job_is_picked_from_what_the_mission_offers_and_nothing_else() -> void:
	var unit: Unit = _sess.roster_units()[0]
	var held: Array[String] = unit.unit_instance.jobs
	if held.size() > 1:
		fail("fixture: the first roster unit holds several jobs, which the picker refuses outright")
		return
	# One job to offer, and one neither offered nor held.
	var offered := ""
	var withheld := ""
	for id: String in JobCatalog.get_jobs():
		if held.has(id):
			continue
		if offered == "":
			offered = id
		elif withheld == "":
			withheld = id
	if withheld == "":
		fail("fixture: the job catalogue holds fewer than two jobs this unit does not hold")
		return
	var only: Array[String] = [offered]
	_loadout().available_jobs = only
	var h: String = _sess.handle_for(unit)

	assert_bool((_sess.set_job(h, offered) as Dictionary).ok).is_true()
	assert_array(unit.unit_instance.jobs).contains_exactly([offered])
	assert_bool((_sess.set_job(h, "") as Dictionary).ok).is_true()
	assert_array(unit.unit_instance.jobs).is_empty()

	var refused: Dictionary = _sess.set_job(h, withheld)
	assert_bool(refused.ok).override_failure_message(
		"a job the mission does not offer was taken").is_false()
	assert_str(str(refused.get("error", ""))).contains("does not offer")
	assert_array(unit.unit_instance.jobs).is_empty()


# A weapon with mod spaces anywhere in the phase, as [holder name, slot, weapon], or [].
func _weapon_with_spaces() -> Array:
	var stash := _loadout().stash
	for i in stash.size():
		var weapon := stash[i] as WeaponInstance
		if weapon != null and weapon.space_count() > 0:
			return ["stash", i, weapon]
	for unit: Unit in _sess.roster_units():
		for i in unit.inventory.size():
			var weapon := unit.inventory[i] as WeaponInstance
			if weapon != null and weapon.space_count() > 0:
				return [_sess.handle_for(unit), i, weapon]
	return []


func test_a_mod_goes_on_and_comes_off_by_the_name_the_kit_prints() -> void:
	var found := _weapon_with_spaces()
	if found.is_empty():
		fail("fixture: no weapon in the phase carries a mod space")
		return
	var holder: String = found[0]
	var slot: int = found[1]
	var weapon: WeaponInstance = found[2]
	# A mod some empty space would take, and a second mod to offer in its place.
	var everything := WeaponModCatalog.offerable_for(weapon.template.weapon_type)
	var key := ""
	var mod: WeaponModData = null
	var space := -1
	for k in everything:
		var candidate: WeaponModData = everything[k]
		for i in range(weapon.space_count()):
			if weapon.can_fit(i, candidate):
				key = str(k)
				mod = candidate
				space = i + 1
				break
		if mod != null:
			break
	if mod == null:
		fail("fixture: no authored mod fits %s" % weapon.shown_name())
		return
	var all_mods := WeaponModCatalog.get_mods()
	var other: WeaponModData = null
	for k in all_mods:
		var candidate: WeaponModData = all_mods[k]
		if candidate.resource_path != mod.resource_path:
			other = candidate
			break
	if other == null:
		fail("fixture: the mod catalogue holds a single mod")
		return

	# Outside the mission's pool: the card's library would not list it, so `fit` refuses it.
	var not_this: Array[WeaponModData] = [other]
	_loadout().available_mods = not_this
	var unoffered: Dictionary = _sess.fit(holder, slot, key, space)
	assert_bool(unoffered.ok).override_failure_message(
		"a mod the mission does not offer was fitted").is_false()
	assert_int(weapon.space_holding(mod)).is_equal(-1)

	var just_this: Array[WeaponModData] = [mod]
	_loadout().available_mods = just_this
	var fitted: Dictionary = _sess.fit(holder, slot, key, space)
	assert_bool(fitted.ok).override_failure_message(str(fitted.get("error", ""))).is_true()
	assert_int(weapon.space_holding(mod)).is_equal(space - 1)

	# A second fit is refused in the weapon's own words.
	var again: Dictionary = _sess.fit(holder, slot, key, space)
	assert_bool(again.ok).is_false()
	assert_str(str(again.get("error", ""))).is_equal(weapon.fit_block_reason(space - 1, mod))

	# The name the kit prints for a fitted mod is the name `unfit` takes: the round trip.
	assert_str(str(_sess.mod_key(mod, all_mods))).is_equal(key)
	var off: Dictionary = _sess.unfit(holder, slot, key)
	assert_bool(off.ok).override_failure_message(str(off.get("error", ""))).is_true()
	assert_int(weapon.space_holding(mod)).is_equal(-1)


func test_the_loadout_writes_close_with_the_phase() -> void:
	var piece := _stash_piece()
	var unit := _with_room(_deployed())
	if unit == null:
		fail("fixture: no deployed unit has an empty slot")
		return
	assert_bool((_sess.begin() as Dictionary).ok).is_true()
	var h: String = _sess.handle_for(unit)
	var answers: Array[Dictionary] = [
		_sess.give("stash", _loadout().stash.find(piece), h),
		_sess.set_job(h, ""),
		_sess.fit(h, 0, "anything", 1),
		_sess.unfit(h, 0, "anything"),
	]
	for answer: Dictionary in answers:
		assert_bool(answer.ok).is_false()
		assert_str(str(answer.get("error", ""))).is_equal(NOT_OPEN)
	assert_bool(_loadout().stash.has(piece)).is_true()


func test_the_kit_shows_a_given_piece_under_the_unit_that_took_it() -> void:
	var unit := _with_room(_sess.roster_units())
	if unit == null:
		fail("fixture: no roster unit has an empty slot")
		return
	var piece := _stash_piece("Kit Readout Probe")
	var h: String = _sess.handle_for(unit)
	assert_str(BoardView.render_kit(_sess, "stash")).contains("Kit Readout Probe")
	assert_bool((_sess.give("stash", _loadout().stash.find(piece), h) as Dictionary).ok).is_true()
	assert_str(BoardView.render_kit(_sess, h)).contains(
		"slot %d  Kit Readout Probe" % unit.inventory.find(piece))
	assert_str(BoardView.render_kit(_sess, "stash")).not_contains("Kit Readout Probe")
