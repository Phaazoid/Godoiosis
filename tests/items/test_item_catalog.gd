# ItemCatalog (#812): the one answer to "what items exist at all?". #1414 found it had drifted from
# the editors' own walk: RuneCatalog refused an illegal rune and this did not, so a roster set to
# offer every item (Roster.offered_stash) would have offered one.
#
# Every case stands up its own folder under user:// through the projections' `sources` parameter,
# so nothing is written into Resources/ and nothing authored is read or pinned.
extends GdUnitTestSuite

const SCRATCH_DIR := "user://__item_catalog_1414/"
const LEGAL_NAME := "Legal probe"
const ILLEGAL_NAME := "Illegal probe"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var legal := RuneData.new()
	legal.display_name = LEGAL_NAME
	var illegal := RuneData.new()
	illegal.display_name = ILLEGAL_NAME
	var carving := TransmutationData.new()
	carving.recipe = "Push(F2)"
	illegal.inscriptions.append(carving)   # carved with no temper, which RuneData.is_legal refuses
	assert_bool(legal.is_legal()).override_failure_message("fixture: the blank rune is not legal").is_true()
	assert_bool(illegal.is_legal()).override_failure_message("fixture: the carved rune is legal").is_false()
	ResourceSaver.save(legal, SCRATCH_DIR + "legal.tres")
	ResourceSaver.save(illegal, SCRATCH_DIR + "illegal.tres")


func after_test() -> void:
	for file in DirAccess.get_files_at(SCRATCH_DIR):
		DirAccess.remove_absolute(SCRATCH_DIR + file)


func _names(items: Array) -> Array[String]:
	var names: Array[String] = []
	for item: Item in items:
		names.append(item.display_name)
	return names


func _assert_refused(names: Array[String], projection: String) -> void:
	assert_bool(names.has(LEGAL_NAME)).override_failure_message(
			"%s lost the LEGAL rune too -- the folder was not read" % projection).is_true()
	assert_bool(names.has(ILLEGAL_NAME)).override_failure_message(
			"%s offered an illegal rune, which RuneCatalog refuses" % projection).is_false()


# The roster's offer under offers_every_item, which is this call and nothing else.
func test_everything_refuses_an_illegal_rune() -> void:
	_assert_refused(_names(ItemCatalog.everything([SCRATCH_DIR])), "everything()")


# The roster tool's stash column.
func test_by_file_refuses_an_illegal_rune() -> void:
	_assert_refused(_names(ItemCatalog.by_file([SCRATCH_DIR]).values()), "by_file()")


# The Unit and Character Editors' pickers.
func test_by_name_refuses_an_illegal_rune() -> void:
	_assert_refused(_names(ItemCatalog.by_name([SCRATCH_DIR]).values()), "by_name()")
