# The unsaved marker (#389): every knob panel says when it holds changes you have not kept.
#
# ONE suite for all three panels, because "one mechanism, three panels" is the thing worth pinning.
# They answer "has anything moved?" differently -- Moods and Game have baselines, Objects has none
# and its edits go straight into the live TileSet -- so what is shared is the AFFORDANCE, and this
# is where a panel that grows its own spelling of it gets caught.
#
# The marker is a FLAG (touched since the last save/reset), not a live compare: reading every knob
# resolves its node, so a derived answer would be dozens of get_node calls per drag tick. The exact
# answer is never lost -- pressing a save still runs the real comparison. Both halves are asserted
# per case, since the flag without the label is invisible and the label without the flag is a lie.
#
# NOTHING HERE WRITES TO DISK, matching test_dev_tool_overwrite_guards.gd's discipline. That shapes
# the Objects cases twice over: its only clear is a disk write, so "still marked while the
# confirmation is up" is what pins cleared-on-landed; and its edit is driven through _write_field
# with a SYNTHETIC TileData rather than by pressing the real checkbox, because
# Resources/TestTiles.tres is served from the resource cache to every suite in the run and a case
# that wrote into it would leak into whatever ran next (test_object_fields.gd documents the same
# rule). The funnel is still the one every widget calls; what is skipped is the widget.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")

var _scene: Node3D
var _moods: MoodsTool
var _game: GameTool
var _objects: ObjectTool


func before_test() -> void:
	var packed := SCENE
	_scene = packed.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	var dev_overlay := _scene.get_node("Main/DevOverlay") as DevOverlay
	_moods = dev_overlay.moods_tool
	_game = dev_overlay.game_tool
	_objects = dev_overlay.object_tool


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()


# --- Helpers -------------------------------------------------------------------------------

# Drives a REAL widget in the built panel, which is the whole point: the marker hangs off the
# on_change closure every row is built with, and setting a value through the panel API instead
# would pass against a panel that never wired one.
func _drag_a_slider(panel: Node) -> void:
	var slider := _find_slider(panel)
	assert_object(slider).override_failure_message("no slider row in this panel to drag").is_not_null()
	slider.value = slider.value + slider.step


func _find_slider(node: Node) -> HSlider:
	for child in node.get_children():
		if child is HSlider:
			return child as HSlider
		var found := _find_slider(child)
		if found != null:
			return found
	return null


# A tile the panel never reads: the real board tileset is shared through the resource cache.
func _synthetic_tile() -> TileData:
	var tiles := TileSet.new()
	for field: Dictionary in ObjectKnobs.FIELDS:
		var at := tiles.get_custom_data_layers_count()
		tiles.add_custom_data_layer()
		tiles.set_custom_data_layer_name(at, field["layer"])
		tiles.set_custom_data_layer_type(at, field["type"])
	var source := TileSetAtlasSource.new()
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	source.texture = ImageTexture.create_from_image(image)
	source.texture_region_size = Vector2i(16, 16)
	source.create_tile(Vector2i.ZERO)
	tiles.add_source(source, 0)
	auto_free(tiles)
	return source.get_tile_data(Vector2i.ZERO, 0)


func _dialog_under(host: Node) -> ConfirmationDialog:
	for child in host.get_children():
		if child is ConfirmationDialog:
			return child as ConfirmationDialog
	return null


# --- Set on edit, once per panel -----------------------------------------------------------

func test_a_tuned_mood_knob_marks_both_of_its_save_buttons() -> void:
	assert_bool(_moods.has_unsaved_changes()).is_false()
	assert_str(_moods._update_button.text).is_equal("Update")

	_drag_a_slider(_moods)

	assert_bool(_moods.has_unsaved_changes()).override_failure_message(
		"moving a knob left the Moods panel reading clean").is_true()
	assert_str(_moods._update_button.text).is_equal("Update *")
	assert_str(_moods._save_as_button.text).override_failure_message(
		"Save As is the only way to keep a tuned look when nothing is loaded, so it wears the mark too"
	).is_equal("Save As *")
	await await_idle_frame()


func test_a_tuned_game_knob_marks_its_save_button() -> void:
	assert_bool(_game.has_unsaved_changes()).is_false()

	_drag_a_slider(_game)

	assert_bool(_game.has_unsaved_changes()).is_true()
	assert_str(_game._save_button.text).is_equal("Save to source *")
	await await_idle_frame()


func test_an_edited_object_field_marks_its_save_button() -> void:
	assert_bool(_objects.has_unsaved_changes()).is_false()
	assert_str(_objects._save_button.text).is_equal("Save object fields")

	var field: Dictionary = ObjectKnobs.FIELDS[0]
	_objects._write_field(_synthetic_tile(), field["layer"], GridUtils.INHERIT)

	assert_bool(_objects.has_unsaved_changes()).is_true()
	assert_str(_objects._save_button.text).is_equal("Save object fields *")
	await await_idle_frame()


# --- Cleared where the panel and its store agree again ---------------------------------------

func test_reset_clears_the_mood_marker() -> void:
	_moods._touch()
	assert_bool(_moods.has_unsaved_changes()).is_true()

	_moods._on_reset_pressed()

	assert_bool(_moods.has_unsaved_changes()).is_false()
	assert_str(_moods._update_button.text).is_equal("Update")
	assert_str(_moods._save_as_button.text).is_equal("Save As")
	await await_idle_frame()


# Re-DERIVED rather than blindly cleared, which is why this asserts through a Reset that really did
# put every knob back: a partial save must leave the panel still marked.
func test_reset_clears_the_game_marker() -> void:
	_game._touch()
	assert_bool(_game.has_unsaved_changes()).is_true()

	_game._on_reset_pressed()

	assert_bool(_game.has_unsaved_changes()).override_failure_message(
		"Reset put every knob back on disk's value, so nothing is unsaved any more").is_false()
	assert_str(_game._save_button.text).is_equal("Save to source")
	await await_idle_frame()


# The press only opens the confirmation. Objects is the panel where this matters most -- its ONLY
# clear is the disk write, so a marker cleared at press time would go clean on a save the dev then
# cancelled, and nothing else would ever tell him.
func test_the_object_marker_survives_until_the_write_actually_lands() -> void:
	_objects._touch()

	_objects._on_save_fields_pressed()

	assert_object(_dialog_under(_objects)).override_failure_message(
		"the tileset save stopped asking first").is_not_null()
	assert_bool(_objects.has_unsaved_changes()).override_failure_message(
		"the marker cleared on the PRESS -- a cancelled save would read as saved").is_true()
	assert_str(_objects._save_button.text).is_equal("Save object fields *")
	await await_idle_frame()
