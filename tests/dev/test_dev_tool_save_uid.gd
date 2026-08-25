# #481: DevWidgets.save_over -- the single writer every dev-tool save routes through -- used to
# silently drop a resource's uid. ResourceSaver.save() at runtime writes no uid= header line (or
# mints a new one for a fresh resource), and take_over_path does not preserve it either. The symptom
# was the Carbine main attack losing uid://dbboy21d8bwwo on an ordinary Update while
# MainVarieties/Carbine.tres still named it by uid: Godot degrades to the path= fallback and warns,
# but the reference breaks outright the moment the target is moved or renamed.
#
# This drives the REAL save path (stage a uid-bearing file, save_over it, read it back) and asserts
# BOTH halves of the fix: the uid survives in the header, and it is registered in ResourceUID -- the
# engine registry tests/law/test_resource_uid_references.gd asks rather than the file text. It writes
# to a user:// temp file and cleans up, matching the real-disk convention in
# tests/flow/test_cast_references.gd.
extends GdUnitTestSuite

const TEMP_PATH := "user://__test_save_uid.tres"

var _staged_id: int = -1


func after_test() -> void:
	if _staged_id != -1 and ResourceUID.has_id(_staged_id):
		ResourceUID.remove_id(_staged_id)
	_staged_id = -1
	if FileAccess.file_exists(TEMP_PATH):
		DirAccess.remove_absolute(TEMP_PATH)


func _stage_file(uid: String) -> void:
	var f := FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	f.store_string('[gd_resource type="Resource" format=3 uid="%s"]\n\n[resource]\n' % uid)
	f.close()


func test_save_over_preserves_the_uid_it_overwrites() -> void:
	_staged_id = ResourceUID.create_id()
	var uid := ResourceUID.id_to_text(_staged_id)
	_stage_file(uid)

	var res := load(TEMP_PATH)
	assert_object(res).is_not_null()

	assert_bool(DevWidgets.save_over(res, TEMP_PATH, null)).is_true()

	var text := FileAccess.get_file_as_string(TEMP_PATH)
	assert_str(text).contains('uid="%s"' % uid)
	assert_bool(ResourceUID.has_id(_staged_id)).is_true()
	assert_str(ResourceUID.get_id_path(_staged_id)).is_equal(TEMP_PATH)


func test_restore_uid_corrects_a_minted_uid() -> void:
	# A fresh resource saved over an existing path gets a NEW uid minted, not merely dropped. The
	# restore must compare the VALUE and put the original back, not trust "a uid= is present".
	_staged_id = ResourceUID.create_id()
	var original := ResourceUID.id_to_text(_staged_id)
	var minted := ResourceUID.id_to_text(ResourceUID.create_id())
	_stage_file(minted)

	assert_bool(DevWidgets.restore_uid(TEMP_PATH, original)).is_true()

	var text := FileAccess.get_file_as_string(TEMP_PATH)
	assert_str(text).contains('uid="%s"' % original)
	assert_str(text).not_contains('uid="%s"' % minted)
