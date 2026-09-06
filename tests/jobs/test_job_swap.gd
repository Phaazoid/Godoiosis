# Changing a job at the roster (#742): the write door, and the preview that has to agree with it.
#
# WHY THE PREVIEW IS PINNED AGAINST THE REAL CHANGE RATHER THAN AGAINST ARITHMETIC. A job moves body
# stats, and WEAR GATES READ BODY STATS -- so a pick can take armour off, and picking the old job back
# does not put it on. That makes the preview the only warning the player gets before an act they
# cannot undo, and a preview computed by a second walk is one that can quietly stop matching. Every
# case below reads the prediction, commits, and asserts reality equals what was predicted; a preview
# that forgets to strip fails at the DEF and ability lines specifically.
#
# CONTENT-FREE: the nudges, the gate and the granted abilities are all built here and restored after
# (job_fixtures' snapshot/restore), so retuning Water Walker or Ballast Harness cannot red this file.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")
const F := preload("res://tests/support/job_fixtures.gd")

var _tank: JobData
var _tank_snap: Dictionary
var _scout: JobData
var _scout_snap: Dictionary


func before_test() -> void:
	_tank = JobCatalog.get_job("tank")
	_tank_snap = F.snapshot(_tank)
	_scout = JobCatalog.get_job("scout")
	_scout_snap = F.snapshot(_scout)


func after_test() -> void:
	F.restore(_tank, _tank_snap)
	F.restore(_scout, _scout_snap)


func _ability(id: Abilities.Id) -> AbilityData:
	var ability := AbilityData.new()
	ability.id = id
	ability.display_name = String(Abilities.Id.keys()[id])
	return ability


# A piece with a ceiling exactly at what this unit has now: legal today, illegal the moment anything
# nudges that stat up. The number comes off the UNIT rather than off authored content.
func _ceiling_plate(unit: Unit, stat: Stats.Stat, grants: Abilities.Id) -> ArmorData:
	var plate := ArmorData.new()
	plate.display_name = "Test Plate"
	plate.def_power = 2
	plate.stat_maximums = {stat: unit.get_body_stat(stat)}
	plate.granted_abilities = [_ability(grants)]
	return plate


func _wear(unit: Unit, plate: ArmorData) -> void:
	assert_bool(unit.add_item(plate)).is_true()
	assert_bool(unit.wear_armor(unit.inventory.find(plate))).is_true()


func _ability_ids(live: Array[AbilityData]) -> Array:
	var ids: Array = []
	for ability: AbilityData in live:
		ids.append(ability.id)
	ids.sort()
	return ids


# --- the write door ------------------------------------------------------------------------------

# One at a time binds at the ROSTER (#731 ruling 10), so the door REPLACES. The model stays uncapped
# for enemies, which is why the rule has to live in a door rather than in UnitInstance.jobs.
func test_choosing_a_job_replaces_rather_than_adds() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0))
	assert_str(unit.set_sole_job("tank")).is_empty()
	assert_array(unit.unit_instance.jobs).contains_exactly(["tank"])
	assert_str(unit.set_sole_job("scout")).is_empty()
	assert_array(unit.unit_instance.jobs).contains_exactly(["scout"])
	# ...and back to none, which is where every roster character starts: nothing under Resources/Units
	# authors a starting job at all.
	assert_str(unit.set_sole_job("")).is_empty()
	assert_array(unit.unit_instance.jobs).is_empty()


func test_a_job_the_catalogue_does_not_have_is_refused_and_says_so() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0))
	assert_str(unit.set_sole_job("no_such_job")).contains("no_such_job")
	assert_array(unit.unit_instance.jobs).is_empty()


# THE consequence the picker exists to warn about. The gate strips on the way in, and NOTHING puts the
# piece back on the way out -- so this is a one-way act reached by an ordinary click.
func test_a_job_that_breaks_a_wear_gate_takes_the_armour_off_and_going_back_does_not_restore_it() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)
	var plate := _ceiling_plate(unit, Stats.Stat.DEX, Abilities.Id.INTIMIDATION)
	_wear(unit, plate)
	assert_int(unit.get_effective_def()).is_greater(0)
	_tank.stat_nudges = {Stats.Stat.DEX: 1}

	assert_str(unit.set_sole_job("tank")).is_empty()
	assert_object(unit.worn_armor).is_null()
	assert_int(unit.get_effective_def()).is_equal(0)
	# Carried, just not worn -- #112's rule, and what makes the loss quiet rather than obvious.
	assert_bool(unit.inventory.has(plate)).is_true()

	assert_str(unit.set_sole_job("")).is_empty()
	assert_object(unit.worn_armor).override_failure_message(
		"dropping the job put the armour back on -- then the warning would be a lie").is_null()


# --- the preview -----------------------------------------------------------------------------------

# Read the prediction, commit, assert reality matches. The three guards above the commit are what stop
# this passing vacuously: a preview and a live read that BOTH miss the strip agree perfectly.
func test_the_preview_is_exactly_what_the_change_turns_out_to_do() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)
	var plate := _ceiling_plate(unit, Stats.Stat.DEX, Abilities.Id.INTIMIDATION)
	_wear(unit, plate)
	_tank.stat_nudges = {Stats.Stat.DEX: 1}
	_tank.ability_pool = [_ability(Abilities.Id.TAUNT)]

	var ids: Array[String] = ["tank"]
	var lost := unit.gear_lost_under_jobs(ids)
	var previewed_dex := unit.previewed_stat_for_jobs(Stats.Stat.DEX, ids)
	var previewed_def := unit.previewed_def_for_jobs(ids)
	var previewed_abilities := _ability_ids(unit.previewed_abilities_for_jobs(ids))

	assert_array(lost).override_failure_message(
		"nothing was predicted to come off, so the rest of this case proves nothing").contains([plate])
	assert_int(previewed_def).override_failure_message(
		"DEF was predicted unchanged -- the preview is reading the plate that is about to come off"
		).is_not_equal(unit.get_effective_def())
	assert_array(previewed_abilities).override_failure_message(
		"the ability list was predicted unchanged").is_not_equal(_ability_ids(unit.get_live_abilities()))

	assert_str(unit.set_sole_job("tank")).is_empty()
	assert_int(unit.get_effective_stat(Stats.Stat.DEX)).is_equal(previewed_dex)
	assert_int(unit.get_effective_def()).is_equal(previewed_def)
	assert_array(_ability_ids(unit.get_live_abilities())).is_equal(previewed_abilities)


# with_jobs lends the unit a body and takes it back. Everything it touches -- the jobs, the worn piece
# and the equipped one -- has to be exactly where it was, or the "preview" is a change.
func test_asking_what_a_job_would_do_leaves_the_unit_untouched() -> void:
	var unit: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0))
	var plate := _ceiling_plate(unit, Stats.Stat.DEX, Abilities.Id.INTIMIDATION)
	_wear(unit, plate)
	assert_str(unit.set_sole_job("scout")).is_empty()
	_tank.stat_nudges = {Stats.Stat.DEX: 1}

	var before_jobs: Array[String] = unit.unit_instance.jobs.duplicate()
	var before_armor := unit.worn_armor
	var before_weapon := unit.equipped_weapon
	var before_def := unit.get_effective_def()

	var ids: Array[String] = ["tank"]
	assert_array(unit.gear_lost_under_jobs(ids)).is_not_empty()   # it really did strip something
	unit.previewed_stat_for_jobs(Stats.Stat.DEX, ids)
	unit.previewed_def_for_jobs(ids)
	unit.previewed_abilities_for_jobs(ids)

	assert_array(unit.unit_instance.jobs).contains_exactly(before_jobs)
	assert_object(unit.worn_armor).is_same(before_armor)
	assert_object(unit.equipped_weapon).is_same(before_weapon)
	assert_int(unit.get_effective_def()).is_equal(before_def)
