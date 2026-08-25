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
