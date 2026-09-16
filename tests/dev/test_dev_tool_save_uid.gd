# #481: DevWidgets.save_over -- the single writer every dev-tool save routes through -- used to
# silently drop a resource's uid. ResourceSaver.save() at runtime writes no uid= attribute (or mints
# a new one for a fresh resource), and take_over_path preserves none -- neither the file's OWN header
# uid nor the uid= on its ext_resource reference lines (the script/texture/other-resource refs). The
# symptom was the Carbine main attack losing uid://dbboy21d8bwwo on an ordinary Update while
# MainVarieties/Carbine.tres still named it by uid, plus the same Update stripping uid= from the
# family template's script references: Godot degrades to the path= fallback and warns, but the
# reference breaks outright the moment the target is moved or renamed.
#
# This drives the REAL save path (stage a uid-bearing file, save_over it, read it back) and asserts
# BOTH halves of the fix: the header uid AND the ext_resource uids survive, and the header uid is
# registered in ResourceUID -- the engine registry tests/law/test_resource_uid_references.gd asks
# rather than the file text. It writes to a user:// temp file and cleans up, matching the real-disk
# convention in tests/flow/test_cast_references.gd.
extends GdUnitTestSuite

const TEMP_PATH := "user://__test_save_uid.tres"

# WeaponAttackData.gd's own script uid (Classes/weapons/WeaponAttackData.gd.uid) -- a real committed
# reference the staged file can point at, so load() resolves it the way a real attack does.
const SCRIPT_UID := "uid://ddqeee7njjjq2"
const SCRIPT_PATH := "res://Classes/weapons/WeaponAttackData.gd"
# A second committed script a slot can be repointed AT (#996). Its uid is asked of the engine in the
# case, never hardcoded, so a regenerated sidecar cannot red it.
const OTHER_SCRIPT_PATH := "res://Classes/flow/ScenarioData.gd"

var _staged_id: int = -1


func after_test() -> void:
	if _staged_id != -1 and ResourceUID.has_id(_staged_id):
		ResourceUID.remove_id(_staged_id)
	_staged_id = -1
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(TEMP_PATH)


func _write(text: String) -> void:
	var f := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _stage_bare(uid: String) -> void:
	_write('[gd_resource type="Resource" format=3 uid="%s"]\n\n[resource]\n' % uid)


func _stage_weapon_attack(header_uid: String, script_uid: String) -> void:
	_write(
		'[gd_resource type="Resource" script_class="WeaponAttackData" format=3 uid="%s"]\n\n'
		% header_uid
		+ '[ext_resource type="Script" uid="%s" path="res://Classes/weapons/WeaponAttackData.gd" id="2_wad"]\n\n'
		% script_uid
		+ '[resource]\nscript = ExtResource("2_wad")\n')


func test_save_over_preserves_the_uids_it_overwrites() -> void:
	_staged_id = ResourceUID.create_id()
	var header := ResourceUID.id_to_text(_staged_id)
	_stage_weapon_attack(header, SCRIPT_UID)

	var res := load(TEMP_PATH)
	assert_object(res).is_not_null()

	assert_bool(DevWidgets.save_over(res, TEMP_PATH, null)).is_true()

	var text := FileAccess.get_file_as_string(TEMP_PATH)
	assert_str(text).contains('uid="%s"' % header)       # the file's OWN uid survived
	assert_str(text).contains('uid="%s"' % SCRIPT_UID)   # the ext_resource reference uid survived
	assert_bool(ResourceUID.has_id(_staged_id)).is_true()
	assert_str(ResourceUID.get_id_path(_staged_id)).is_equal(TEMP_PATH)


func test_restore_uids_corrects_a_minted_uid() -> void:
	# A fresh resource saved over an existing path gets a NEW header uid minted, not merely dropped.
	# The restore must compare the VALUE and put the original back, not trust "a uid= is present".
	_staged_id = ResourceUID.create_id()
	var original := ResourceUID.id_to_text(_staged_id)
	var minted := ResourceUID.id_to_text(ResourceUID.create_id())
	_stage_bare(minted)

	assert_bool(DevWidgets.restore_uids(TEMP_PATH, {"_header": original})).is_true()

	var text := FileAccess.get_file_as_string(TEMP_PATH)
	assert_str(text).contains('uid="%s"' % original)
	assert_str(text).not_contains('uid="%s"' % minted)


func _stage_without_uid() -> void:
	_write('[gd_resource type="Resource" format=3]\n\n[resource]\n')


# The gap #598 closes. restore_uids puts back only what the PRIOR file held, and the header has no
# other source -- so a .tres born through a dev tool started uid-less and stayed that way forever,
# while the editor stamps one on everything IT writes. Nine of ten authored weapon .tres were in
# that state when this landed, which is what makes a rename break every holder (#596, one layer up).
#
# The uid is read back through uid_map_in_file rather than a second parser here: one answer to
# "what uid does this file carry".
func test_save_over_mints_a_uid_for_a_file_that_never_had_one() -> void:
	_stage_without_uid()
	assert_str(FileAccess.get_file_as_string(TEMP_PATH)).not_contains("uid=")   # precondition
	var res := load(TEMP_PATH)
	assert_object(res).is_not_null()

	assert_bool(DevWidgets.save_over(res, TEMP_PATH, null)).is_true()

	var minted: String = DevWidgets.uid_map_in_file(TEMP_PATH).get("_header", "")
	assert_str(minted).is_not_empty()

	# ...and REGISTERED, not merely written. A uid nothing claims is exactly what
	# tests/law/test_resource_uid_references.gd exists to catch, so minting one would be a new way
	# to redden that law rather than a fix.
	_staged_id = ResourceUID.text_to_id(minted)   # so after_test releases it
	assert_bool(ResourceUID.has_id(_staged_id)).is_true()
	assert_str(ResourceUID.get_id_path(_staged_id)).is_equal(TEMP_PATH)


# Minting must happen ONCE. A fresh id per save would rewrite the header on every Update and put the
# file permanently in `git status` -- the dirty-tree rule's acceptance half, and the failure mode
# #540 and #111 both were.
func test_a_minted_uid_does_not_change_on_the_next_save() -> void:
	_stage_without_uid()
	var res := load(TEMP_PATH)
	assert_bool(DevWidgets.save_over(res, TEMP_PATH, null)).is_true()
	var first: String = DevWidgets.uid_map_in_file(TEMP_PATH).get("_header", "")
	assert_str(first).is_not_empty()
	_staged_id = ResourceUID.text_to_id(first)

	var text_after_first := FileAccess.get_file_as_string(TEMP_PATH)
	assert_bool(DevWidgets.save_over(res, TEMP_PATH, null)).is_true()

	assert_str(DevWidgets.uid_map_in_file(TEMP_PATH).get("_header", "")).is_equal(first)
	assert_str(FileAccess.get_file_as_string(TEMP_PATH)).is_equal(text_after_first)   # byte-stable


# #996. An ext_resource uid belongs to the file at path=, never to the line's id=. Godot's saver hands
# a repointed slot the same id, so a restore keyed by id stamped terraces_intro's uid onto the line
# that now named terraces_start -- and Godot resolves a known uid BEFORE the path: the beat kept
# playing the old timeline, and deleting it turned Terraces.tres into a parse error. The prior map is
# built by uid_map_in_file from the real prior text, the way save_over builds it. Two committed
# scripts stand in for the two timelines: the engine answers a uid for res:// files only (a user://
# target reads back INVALID), and nothing here writes under res://.
func test_a_repointed_reference_takes_the_new_targets_uid_not_the_old_slots() -> void:
	var other_id := ResourceLoader.get_resource_uid(OTHER_SCRIPT_PATH)
	assert_int(other_id).is_not_equal(ResourceUID.INVALID_ID)   # precondition: the target can answer
	var new_uid := ResourceUID.id_to_text(other_id)
	_write(('[gd_resource type="Resource" format=3]\n\n'
		+ '[ext_resource type="Script" uid="%s" path="%s" id="1_slot"]\n\n'
		+ '[resource]\n') % [SCRIPT_UID, SCRIPT_PATH])
	var prior := DevWidgets.uid_map_in_file(TEMP_PATH)
	# What the runtime saver writes after the repoint: the same slot id, the new path, no uid.
	_write(('[gd_resource type="Resource" format=3]\n\n'
		+ '[ext_resource type="Script" path="%s" id="1_slot"]\n\n'
		+ '[resource]\n') % OTHER_SCRIPT_PATH)

	assert_bool(DevWidgets.restore_uids(TEMP_PATH, prior)).is_true()

	var text := FileAccess.get_file_as_string(TEMP_PATH)
	assert_str(text).contains('uid="%s" path="%s"' % [new_uid, OTHER_SCRIPT_PATH])
	assert_str(text).not_contains(SCRIPT_UID)


# The fallback half: when the target cannot answer for itself, the prior uid follows the PATH it was
# written beside -- a same-path reference keeps it, a repointed one inherits nothing.
func test_a_prior_uid_follows_its_path_when_the_target_cannot_answer() -> void:
	var kept := ResourceUID.id_to_text(ResourceUID.create_id())
	var old_uid := ResourceUID.id_to_text(ResourceUID.create_id())
	_write(('[gd_resource type="Resource" format=3]\n\n'
		+ '[ext_resource type="Resource" uid="%s" path="user://__gone_a.tres" id="1_a"]\n'
		+ '[ext_resource type="Resource" uid="%s" path="user://__gone_b.tres" id="2_b"]\n\n'
		+ '[resource]\n') % [kept, old_uid])
	var prior := DevWidgets.uid_map_in_file(TEMP_PATH)
	# Saved again: slot 1 still names gone_a, slot 2 was repointed to gone_c. No target exists.
	_write('[gd_resource type="Resource" format=3]\n\n'
		+ '[ext_resource type="Resource" path="user://__gone_a.tres" id="1_a"]\n'
		+ '[ext_resource type="Resource" path="user://__gone_c.tres" id="2_b"]\n\n'
		+ '[resource]\n')

	assert_bool(DevWidgets.restore_uids(TEMP_PATH, prior)).is_true()

	var text := FileAccess.get_file_as_string(TEMP_PATH)
	assert_str(text).contains('uid="%s" path="user://__gone_a.tres"' % kept)
	assert_str(text).not_contains(old_uid)
