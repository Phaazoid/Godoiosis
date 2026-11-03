# EVERY STORE A BOARD CARRIES SAYS HOW A PASS'S SEAL TREATS IT (#1529). The tile seal (#1498 stage 4)
# counts a live read of the two stores a pass changes; a store added to BoardContext later is read live
# by a pass with nothing to say so. The table (tests/support/board_context_fields.gd) classifies every
# script variable as SEALED or UNSEALED with its reason, and this law refuses one it does not name, an
# entry naming no variable, and a SEALED read that does not count inside a pass.
extends GdUnitTestSuite

const Fields := preload("res://tests/support/board_context_fields.gd")


static func _script_vars(obj: Object) -> Array[String]:
	var names: Array[String] = []
	for prop in obj.get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			names.append(prop["name"])
	return names


func _board() -> BoardContext:
	var none: Array[Unit] = []
	var board := BoardContext.new(null, none, null, auto_free(TerrainStateManager.new()), null, null, GasField.new())
	return board


func test_every_board_variable_is_classified() -> void:
	var names := _script_vars(_board())
	var unknown: Array[String] = []
	for name in names:
		if not Fields.SEALED.has(name) and not Fields.UNSEALED.has(name):
			unknown.append(name)
	assert_array(unknown).override_failure_message(
			"BoardContext has stores no table says how a pass's seal treats: %s" % [unknown]).is_empty()
	var stale: Array[String] = []
	for name: String in Fields.SEALED.keys() + Fields.UNSEALED.keys():
		if not names.has(name):
			stale.append(name)
	assert_array(stale).override_failure_message(
			"the table classifies stores BoardContext no longer has: %s" % [stale]).is_empty()
	for name: String in Fields.SEALED:
		assert_bool(Fields.UNSEALED.has(name)).override_failure_message(
				"%s is classified both SEALED and UNSEALED" % name).is_false()


func test_every_sealed_read_counts_inside_a_pass() -> void:
	var board := _board()
	for name: String in Fields.SEALED:
		var store: Object = board.get(name)
		assert_object(store).override_failure_message("fixture: the board carries no %s" % name).is_not_null()
		if store == null:
			continue
		var reads: Dictionary = Fields.SEALED[name]
		for method: String in reads:
			assert_bool(store.has_method(method)).override_failure_message(
					"%s has no read named %s" % [name, method]).is_true()
			if not store.has_method(method):
				continue
			var before := PlannedTiles.seal_breaks
			PlannedTiles.open_seal()
			store.callv(method, reads[method])
			PlannedTiles.close_seal()
			assert_int(PlannedTiles.seal_breaks - before).override_failure_message(
					"%s.%s read live inside a pass without counting" % [name, method]).is_equal(1)
			before = PlannedTiles.seal_breaks
			store.callv(method, reads[method])
			assert_int(PlannedTiles.seal_breaks - before).override_failure_message(
					"%s.%s counted with no pass open" % [name, method]).is_equal(0)
