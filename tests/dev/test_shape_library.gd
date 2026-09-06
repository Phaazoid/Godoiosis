# The shared shape library and the Attack Editor's shape row (#808).
#
# What is worth pinning here is the SHARING, because every one of its failures is silent: a pick
# that copies instead of referencing, a Save As that drags the file every other attack is holding,
# a grid that reaches the board before Update, a delete that leaves a dangling ext_resource. None
# of those looks wrong on the panel, and the last one is a hard parse error in a file two hops away.
#
# NOTHING HERE TOUCHES SHIPPED CONTENT (test_attack_editor_extras.gd's rule): shapes are built, and
# the one case that needs a file on disk writes it under user://. The catalog it READS is real,
# since reading mutates nothing.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")
# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")

const SHAPE_PATH := "user://__test_library_shape.tres"

var _scene: Node3D
var _editor: AttackEditorTool


func before_test() -> void:
	_scene = SCENE.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	var dev_overlay := _scene.get_node("Main/DevOverlay") as DevOverlay
	_editor = dev_overlay.get_node("%Attack Editor") as AttackEditorTool


func after_test() -> void:
	await await_idle_frame()   # #93/#101 false orphans, see test_attack_editor_extras.gd
	get_tree().root.remove_child(_scene)
	_scene.free()
	if FileAccess.file_exists(SHAPE_PATH):
		DirAccess.remove_absolute(SHAPE_PATH)


# An attack holding a shape that owns a real file, which is what "named" means everywhere below.
func _with_named_shape() -> AttackShape:
	var shape := P.shape([Vector2i(0, -1)] as Array[Vector2i], "Probe Shape")
	assert_int(ResourceSaver.save(shape, SHAPE_PATH)).is_equal(OK)
	var library := ResourceLoader.load(SHAPE_PATH) as AttackShape
	_editor._mode = AttackEditorTool.Mode.WEAPON_ATTACK
	_editor.current = WeaponAttackData.new()
	_editor.current.attack_shape = library
	_editor._stage_shape()
	_editor.populate()
	return library


func _picker() -> OptionButton:
	for node in _all_class(_editor, "OptionButton", []):
		var option := node as OptionButton
		for i in option.item_count:
			if option.get_item_text(i) == AttackEditorTool.NEW_SHAPE_KEY:
				return option
	return null


func _all_class(node: Node, klass: String, found: Array[Node]) -> Array[Node]:
	for child in node.get_children():
		if child.is_class(klass):
			found.append(child)
		_all_class(child, klass, found)
	return found


func _row(text: String) -> int:
	var picker := _picker()
	for i in picker.item_count:
		if picker.get_item_text(i) == text:
			return i
	return -1


# --- the grid edits a COPY, never the library object ------------------------------------------

# THE rule the whole row is built around. Editing the shared object directly would break the
# commit-point ruling (2026-08-27) AND make Save As impossible: take_over_path moves the object
# every other attack is still holding, so the fork would drag them all with it.
func test_the_grid_edits_a_copy_and_leaves_the_library_object_alone() -> void:
	var library := _with_named_shape()
	assert_object(_editor._shape_copy).override_failure_message(
		"the editor is editing the library object itself -- a click would reach every attack using it"
	).is_not_same(library)
	assert_object(_editor.current.attack_shape).override_failure_message(
		"the attack stopped referencing the library file, so its save would embed a copy"
	).is_same(library)

	_editor._shape_copy.stamp = [Vector2i(0, -1), Vector2i(0, -2)]
	assert_int(library.stamp.size()).override_failure_message(
		"a grid edit reached the shared shape before Update").is_equal(1)


# An UNNAMED shape has no other holder, so there is nothing to protect and the attack points
# straight at what the grid edits -- otherwise a new shape could never be drawn at all.
func test_an_unnamed_shape_is_edited_in_place() -> void:
	_editor._mode = AttackEditorTool.Mode.WEAPON_ATTACK
	_editor.current = WeaponAttackData.new()
	_editor.current.attack_shape = P.shape([Vector2i.ZERO] as Array[Vector2i])
	_editor._stage_shape()
	assert_object(_editor._shape_copy).is_same(_editor.current.attack_shape)


# --- the picker assigns BY REFERENCE ------------------------------------------------------------

func test_picking_a_library_shape_references_it_rather_than_copying_it() -> void:
	_with_named_shape()
	var library := AttackShapeCatalog.get_library()
	if library.is_empty():
		return   # no shipped shapes to pick: the reference rule is pinned by the case above too
	var name: String = library.keys()[0]
	var row := _row(name)
	assert_int(row).override_failure_message("the library shape '%s' is not in the picker" % name).is_greater(0)
	_picker().item_selected.emit(row)

	assert_object(_editor.current.attack_shape).override_failure_message(
		"picking a library shape COPIED it -- editing it later would reach nothing else, and the "
		+ "folder would stop being a census of what is actually in use").is_same(library[name])


func test_picking_none_leaves_the_attack_shapeless_rather_than_empty() -> void:
	# A shapeless attack covers the cell it is aimed at; an EMPTY stamp covers nothing and is a
	# lint BLOCKS. The (none) row has to mean the first.
	_with_named_shape()
	_picker().item_selected.emit(_row(AttackEditorTool.NO_SHAPE_KEY))
	assert_object(_editor.current.attack_shape).is_null()
	assert_object(_editor._shape_copy).is_null()
	assert_array(Reach.get_affected_cells_from(null, Vector2i.ZERO, Vector2i(1, 0), _editor.current, null)) \
		.contains_exactly([Vector2i(1, 0)])


func test_the_none_row_is_first_so_a_shapeless_attack_displays_honestly() -> void:
	# add_item auto-selects the row it is handed, so the empty state has to BE row zero -- the
	# ordering IS the mechanism, exactly as in DevWidgets._add_resource_swapper (#807).
	_editor._mode = AttackEditorTool.Mode.WEAPON_ATTACK
	_editor.current = WeaponAttackData.new()
	_editor._stage_shape()
	_editor.populate()
	var picker := _picker()
	assert_str(picker.get_item_text(0)).is_equal(AttackEditorTool.NO_SHAPE_KEY)
	assert_str(picker.get_item_text(picker.selected)).override_failure_message(
		"the picker claims a shape on an attack that has none").is_equal(AttackEditorTool.NO_SHAPE_KEY)


# --- Save As FORKS ------------------------------------------------------------------------------

func test_save_as_re_points_this_attack_and_leaves_every_other_holder_alone() -> void:
	var library := _with_named_shape()
	var other := WeaponAttackData.new()
	other.attack_shape = library          # a second attack sharing the same file
	_editor._shape_copy.stamp = [Vector2i(0, -1), Vector2i(0, -2)]

	_editor._on_shape_save_as("__test_forked_shape")
	var forked_path := AttackShapeCatalog.LIBRARY_DIR + "__test_forked_shape.tres"

	assert_bool(FileAccess.file_exists(forked_path)).is_true()
	assert_str(_editor.current.attack_shape.resource_path).is_equal(forked_path)
	assert_int(other.attack_shape.stamp.size()).override_failure_message(
		"Save As dragged the shape every other attack was holding onto the new file"
	).is_equal(1)
	assert_str(other.attack_shape.resource_path).is_equal(SHAPE_PATH)
	DirAccess.remove_absolute(forked_path)


# --- Update writes BOTH files -------------------------------------------------------------------

# The FAMILY mode precedent, one file further out: a shape reference means the attack's own save
# writes nothing of the shape, so an Update that saved only the attack would leave the file pointing
# at a stamp the dev never drew.
func test_updating_writes_the_shape_file_too_and_the_attack_keeps_referencing_it() -> void:
	var library := _with_named_shape()
	_editor._shape_copy.stamp = [Vector2i(0, -1), Vector2i(0, -2)]

	assert_bool(_editor._save_named_shape()).is_true()

	assert_int(library.stamp.size()).override_failure_message(
		"Update did not reach the object the board is holding").is_equal(2)
	var written := FileAccess.get_file_as_string(SHAPE_PATH)
	assert_str(written).contains("Vector2i(0, -2)")


func test_an_unnamed_shape_needs_no_second_write() -> void:
	# It is embedded in the attack's own file, so there is no second victim -- and the confirm must
	# not name one.
	_editor._mode = AttackEditorTool.Mode.WEAPON_ATTACK
	_editor.current = WeaponAttackData.new()
	_editor.current.attack_shape = P.shape([Vector2i.ZERO] as Array[Vector2i])
	_editor._stage_shape()
	assert_bool(_editor._save_named_shape()).is_true()
	assert_str(_editor._shape_victim()).is_empty()


func test_the_overwrite_confirm_names_the_shared_shape() -> void:
	_with_named_shape()
	assert_str(_editor._shape_victim()).override_failure_message(
		"the confirm does not say a shared file is about to be written").contains("__test_library_shape.tres")


# --- who else holds it --------------------------------------------------------------------------

# Read off the repo rather than a catalog: an attack embedded in a mission or a rune is in no
# catalog, and those are exactly the referrers a caption listing saved attacks alone would hide.
func test_users_of_finds_a_referrer_a_catalog_cannot_see() -> void:
	var shipped := AttackShapeCatalog.get_library()
	assert_bool(shipped.is_empty()).override_failure_message(
		"no shapes scanned -- the scan is broken, not the content").is_false()
	var found_any := false
	for key in shipped:
		var shape: AttackShape = shipped[key]
		if not AttackShapeCatalog.users_of(shape.resource_path).is_empty():
			found_any = true
	assert_bool(found_any).override_failure_message(
		"no shipped shape has a single referrer, so the caption and the delete gate are both blind"
	).is_true()


func test_a_shape_reports_no_user_for_its_own_file() -> void:
	# The header names its own path; counting that would make every shape undeletable.
	var shipped := AttackShapeCatalog.get_library()
	for key in shipped:
		var shape: AttackShape = shipped[key]
		assert_array(AttackShapeCatalog.users_of(shape.resource_path)) \
			.not_contains([shape.resource_path.get_file()])
