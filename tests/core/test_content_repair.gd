# ContentRepair (#608): content that has lost a reference still LOADS, because the dev tools live
# inside the running game and content that refuses to load takes the only surfaces that could fix it
# down with it.
#
# Measured first, and it decides the whole shape: a dangling ext_resource is a hard PARSE error in
# Godot's text loader, so `load()` returns null for the entire file and for everything referencing
# it. There is no partial resource to be had -- the text has to be repaired before Godot sees it.
#
# These write real .tres to user:// and load them back, because the fault being pinned lives in the
# LOADER, not in anything we could construct in memory.
extends GdUnitTestSuite

const BROKEN_PATH := "user://__test_repair_broken.tres"
const SCRIPT_PATH := "res://Classes/weapons/WeaponModData.gd"
const ATTACK_SCRIPT := "res://Classes/weapons/WeaponAttackData.gd"
const GONE := "res://Resources/WeaponAttacks/__test_no_such_attack.tres"
const HOLDER_PATH := "user://__test_repair_holder.tres"


func after_test() -> void:
	ContentRepair.forget(BROKEN_PATH)
	ContentRepair.forget(HOLDER_PATH)
	if FileAccess.file_exists(HOLDER_PATH):
		DirAccess.remove_absolute(HOLDER_PATH)
	if FileAccess.file_exists(BROKEN_PATH):
		DirAccess.remove_absolute(BROKEN_PATH)


func _write(text: String) -> void:
	var f := FileAccess.open(BROKEN_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# A mod whose granted_attacks holds ONE reference, to a file that is not there.
func _stage_missing_array_element() -> void:
	_write('[gd_resource type="Resource" script_class="WeaponModData" format=3]\n\n'
		+ '[ext_resource type="Script" path="%s" id="1_mod"]\n' % SCRIPT_PATH
		+ '[ext_resource type="Script" path="%s" id="2_wad"]\n' % ATTACK_SCRIPT
		+ '[ext_resource type="Resource" path="%s" id="3_gone"]\n\n' % GONE
		+ '[resource]\nscript = ExtResource("1_mod")\ndisplay_name = "Degraded"\npower_delta = 3\n'
		+ 'granted_attacks = Array[ExtResource("2_wad")]([ExtResource("3_gone")])\n')


# ==============================================================================
#  The precondition this whole class exists for
# ==============================================================================

# Not an assumption -- the design rests on it. If Godot ever returns a partial resource instead,
# ContentRepair is the wrong answer and this case is where that shows up.
func test_a_dangling_reference_makes_godot_fail_the_whole_file() -> void:
	_stage_missing_array_element()
	assert_object(ResourceLoader.load(BROKEN_PATH, "", ResourceLoader.CACHE_MODE_IGNORE)) \
		.override_failure_message(
			"Godot loaded a file with a dangling ext_resource. If it now returns a partial "
			+ "resource, ContentRepair's text surgery is no longer the right mechanism."
		).is_null()


# ==============================================================================
#  What the repair does
# ==============================================================================

func test_a_file_with_a_missing_reference_still_loads() -> void:
	_stage_missing_array_element()
	var res := ContentRepair.load_tolerant(BROKEN_PATH) as WeaponModData
	assert_object(res).is_not_null()
	# Everything that did NOT depend on the missing file survives untouched.
	assert_str(res.display_name).is_equal("Degraded")
	assert_int(res.power_delta).is_equal(3)
	# ...and the element that did is gone rather than null, so nothing downstream iterates a hole.
	assert_array(res.granted_attacks).is_empty()


# The repaired object must answer as the REAL file. Without this the dev tools would write their
# edits into user://__repaired/ and the actual content would never get fixed.
func test_the_repaired_resource_still_claims_the_original_path() -> void:
	_stage_missing_array_element()
	var res := ContentRepair.load_tolerant(BROKEN_PATH)
	assert_str(res.resource_path).is_equal(BROKEN_PATH)


func test_the_repair_records_what_it_cost() -> void:
	_stage_missing_array_element()
	ContentRepair.load_tolerant(BROKEN_PATH)
	assert_array(ContentRepair.dropped_properties(BROKEN_PATH)).contains(["granted_attacks"])
	assert_array(ContentRepair.missing_targets(BROKEN_PATH)).contains([GONE])


# ==============================================================================
#  What it refuses to repair
# ==============================================================================

# A missing SCRIPT is a code fault, not content. Stripping it would change what the resource IS, so
# it stays exactly as loud as it was.
func test_a_missing_script_is_not_repaired() -> void:
	_write('[gd_resource type="Resource" format=3]\n\n'
		+ '[ext_resource type="Script" path="res://Classes/__test_no_such_script.gd" id="1_s"]\n\n'
		+ '[resource]\nscript = ExtResource("1_s")\n')
	assert_object(ContentRepair.load_tolerant(BROKEN_PATH)).is_null()
	assert_array(ContentRepair.dropped_properties(BROKEN_PATH)).is_empty()


# Broken for some OTHER reason: we have not diagnosed it, so we do not claim to have fixed it.
func test_a_file_broken_some_other_way_is_not_repaired() -> void:
	_write("this is not a resource file at all\n")
	assert_object(ContentRepair.load_tolerant(BROKEN_PATH)).is_null()


func test_a_file_that_loads_cleanly_is_returned_untouched() -> void:
	_write('[gd_resource type="Resource" script_class="WeaponModData" format=3]\n\n'
		+ '[ext_resource type="Script" path="%s" id="1_mod"]\n\n' % SCRIPT_PATH
		+ '[resource]\nscript = ExtResource("1_mod")\ndisplay_name = "Fine"\n')
	var res := ContentRepair.load_tolerant(BROKEN_PATH) as WeaponModData
	assert_object(res).is_not_null()
	assert_str(res.display_name).is_equal("Fine")
	assert_array(ContentRepair.dropped_properties(BROKEN_PATH)).is_empty()


# ==============================================================================
#  The save refusal -- without it, the repair becomes the loss
# ==============================================================================

# A degraded resource written back over its own file makes the loss permanent. That is #596's silent
# class arriving through a new door, and it is the reason the repair is allowed to exist at all.
func test_save_over_refuses_a_resource_that_loaded_degraded() -> void:
	_stage_missing_array_element()
	var res := ContentRepair.load_tolerant(BROKEN_PATH)
	assert_object(res).is_not_null()

	assert_bool(DevWidgets.save_over(res, BROKEN_PATH, null)).is_false()

	# The claim that matters is not the return value but the FILE: it still names what it lost, so
	# restoring that target repairs everything with no further work.
	assert_str(FileAccess.get_file_as_string(BROKEN_PATH)).contains(GONE)


# ...and the refusal lifts the moment the gap is filled, which is how the repair is meant to end:
# open the degraded thing in an editor, set what it lost, save, and the dangling reference is gone
# because the dev replaced it -- not because anything quietly dropped it.
func test_save_over_allows_it_once_the_gap_is_filled() -> void:
	_stage_missing_array_element()
	var res := ContentRepair.load_tolerant(BROKEN_PATH) as WeaponModData
	var filled: Array[WeaponAttackData] = [WeaponAttackData.new()]
	res.granted_attacks = filled

	assert_bool(DevWidgets.save_over(res, BROKEN_PATH, null)).is_true()
	assert_str(FileAccess.get_file_as_string(BROKEN_PATH)).not_contains(GONE)


# The refusal is about THIS path's record, not a global mood: an untouched resource saves normally.
func test_save_over_is_unaffected_for_content_that_never_degraded() -> void:
	_write('[gd_resource type="Resource" script_class="WeaponModData" format=3]\n\n'
		+ '[ext_resource type="Script" path="%s" id="1_mod"]\n\n' % SCRIPT_PATH
		+ '[resource]\nscript = ExtResource("1_mod")\ndisplay_name = "Fine"\n')
	var res := ContentRepair.load_tolerant(BROKEN_PATH)
	assert_bool(DevWidgets.save_over(res, BROKEN_PATH, null)).is_true()


# ==============================================================================
#  The CASCADE -- the shape #596 actually had
# ==============================================================================

# Level_1 referenced Noemie, which referenced a weapon that was gone. The MIDDLE file exists, so
# scanning the top file's own references finds nothing wrong -- and the top file still will not
# load, because Godot fails everything downstream of the missing one. Repairing only the file named
# in the error is not enough; the repair has to follow the chain.
#
# On its OWN paths on purpose. Written first against the shared fixture, it passed for a rotten
# reason: an earlier case had already repaired the middle file, and take_over_path had left that
# object in Godot's resource cache, so the top file resolved from memory rather than from disk.
func test_a_file_referencing_a_degraded_file_still_loads() -> void:
	var mid := "user://__test_cascade_mid.tres"
	var top := "user://__test_cascade_top.tres"
	var m := FileAccess.open(mid, FileAccess.WRITE)
	m.store_string('[gd_resource type="Resource" script_class="WeaponModData" format=3]\n\n'
		+ '[ext_resource type="Script" path="%s" id="1_mod"]\n' % SCRIPT_PATH
		+ '[ext_resource type="Script" path="%s" id="2_wad"]\n' % ATTACK_SCRIPT
		+ '[ext_resource type="Resource" path="%s" id="3_gone"]\n\n' % GONE
		+ '[resource]\nscript = ExtResource("1_mod")\ndisplay_name = "Middle"\n'
		+ 'granted_attacks = Array[ExtResource("2_wad")]([ExtResource("3_gone")])\n')
	m.close()
	var t := FileAccess.open(top, FileAccess.WRITE)
	t.store_string('[gd_resource type="Resource" script_class="WeaponModData" format=3]\n\n'
		+ '[ext_resource type="Script" path="%s" id="1_mod"]\n' % SCRIPT_PATH
		+ '[ext_resource type="Resource" path="%s" id="2_mid"]\n\n' % mid
		+ '[resource]\nscript = ExtResource("1_mod")\ndisplay_name = "Top"\n'
		+ 'replaces_main = ExtResource("2_mid")\n')
	t.close()

	var res := ContentRepair.load_tolerant(top) as WeaponModData
	ContentRepair.forget(mid)
	ContentRepair.forget(top)
	DirAccess.remove_absolute(mid)
	DirAccess.remove_absolute(top)

	assert_object(res).override_failure_message(
		"the top file did not load, so a chain of length two defeats the repair -- which is exactly "
		+ "the shape #596 had: Level_1 -> Noemie -> a weapon that was gone"
	).is_not_null()
	assert_str(res.display_name).is_equal("Top")
