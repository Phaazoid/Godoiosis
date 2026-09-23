# THE "WHAT'S NEW" CARD (#1075): who is shown it, what it lists, and that the real boot reaches it.
#
# The door's cases need no scene -- a bare Control is a host -- and drive _show_if_needed with the
# running version as a parameter, so no case has to move project.godot. The last two are WIRE cases
# and boot Main.tscn, because what is under test there is that _open_mission_select actually reaches
# the card, and that a second trip through the title screen does not bring it back.
#
# WhatsNewCard.enabled and ReleaseNotes.persistence_enabled are both FALSE headless, so every case
# that wants the card turns them on and after_test turns them off again: 89 suites boot Main.tscn
# and a leaked `true` would put this panel over most of the test tree's title screens.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const SCRATCH_CFG := "user://__whats_new_test.cfg"
const SCRATCH_LEDGER := "user://__whats_new_test_ledger.md"

const LEDGER := """# Test ledger

## v0.5.0 (2026-02-02)

- Newest line one.
- Newest line two.

### Internal

- Never shown (#1).

## v0.4.1 (2026-02-01)

- Older line.

## v0.4.0 (2026-01-01)

- Already seen.
"""

# Captured when this script LOADS -- the value a real headless process boots with.
static var _enabled_at_load := WhatsNewCard.enabled

var _main: Node
var game: Node2D


func before_test() -> void:
	ReleaseNotes.reset_for_test()
	_wipe()


func after_test() -> void:
	WhatsNewCard.enabled = false
	if is_instance_valid(_main):
		remove_child(_main)
		_main.free()
	_wipe()
	ReleaseNotes.reset_for_test()
	await await_idle_frame()


func _wipe() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_CFG))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH_LEDGER))


# The card switched on, remembering into a scratch cfg, reading a scratch ledger.
func _arm(ledger: String = LEDGER) -> void:
	var file := FileAccess.open(SCRATCH_LEDGER, FileAccess.WRITE)
	file.store_string(ledger)
	file.close()
	WhatsNewCard.enabled = true
	ReleaseNotes.persistence_enabled = true
	ReleaseNotes.config_path = SCRATCH_CFG
	ReleaseNotes.path = SCRATCH_LEDGER


func _host() -> Control:
	var host: Control = auto_free(Control.new())
	add_child(host)
	return host


# Every Label under the card, in tree order -- which is draw order, top to bottom.
func _texts(card: Node) -> Array[String]:
	var out: Array[String] = []
	for node: Node in _descendants(card):
		if node is Label:
			out.append((node as Label).text)
	return out


func _descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child: Node in root.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


# ==============================================================================
#  Who is shown it
# ==============================================================================

# NO RECORD IS SILENCE (dev ruling, 2026-09-22): a fresh install, and anyone upgrading into the
# first build that carries the card, is recorded and shown nothing.
func test_no_record_records_the_running_build_and_shows_nothing() -> void:
	_arm()
	var host := _host()
	assert_object(WhatsNewCard._show_if_needed(host, "0.5.0")).is_null()
	assert_str(ReleaseNotes.last_seen()).is_equal("0.5.0")
	assert_int(host.get_child_count()).is_equal(0)


func test_a_new_release_is_shown_and_recorded() -> void:
	_arm()
	ReleaseNotes.mark_seen("0.4.0")
	var host := _host()
	var card := WhatsNewCard._show_if_needed(host, "0.5.0")
	assert_object(card).is_not_null()
	assert_object(card.get_parent()).is_same(host)
	assert_str(ReleaseNotes.last_seen()).is_equal("0.5.0")


func test_nothing_new_shows_nothing() -> void:
	_arm()
	ReleaseNotes.mark_seen("0.5.0")
	assert_object(WhatsNewCard._show_if_needed(_host(), "0.5.0")).is_null()


# A card we could not record showing would come back on every trip through the title screen.
func test_a_card_that_could_not_be_remembered_is_never_shown() -> void:
	_arm()
	ReleaseNotes.mark_seen("0.4.0")
	ReleaseNotes.persistence_enabled = false
	assert_object(WhatsNewCard._show_if_needed(_host(), "0.5.0")).is_null()


func test_a_headless_run_boots_with_the_card_suppressed() -> void:
	if DisplayServer.get_name() != "headless":
		return
	assert_bool(_enabled_at_load).is_false()


# ==============================================================================
#  What it lists
# ==============================================================================

# Every release since the last one seen, newest first, and nothing from ### Internal.
func test_the_card_lists_every_missed_release_newest_first() -> void:
	_arm()
	ReleaseNotes.mark_seen("0.4.0")
	var card := WhatsNewCard._show_if_needed(_host(), "0.5.0")
	assert_object(card).is_not_null()
	var texts := _texts(card)
	var newest := texts.find("v0.5.0")
	var older := texts.find("v0.4.1")
	assert_int(newest).override_failure_message("no v0.5.0 heading in %s" % [texts]).is_not_equal(-1)
	assert_int(older).override_failure_message("no v0.4.1 heading in %s" % [texts]).is_greater(newest)
	assert_bool(texts.has("Newest line one.")).is_true()
	assert_bool(texts.has("Older line.")).is_true()
	assert_bool(texts.has("Already seen.")).is_false()
	assert_bool(texts.has("Never shown (#1).")).is_false()


func test_the_close_button_takes_it_down() -> void:
	_arm()
	ReleaseNotes.mark_seen("0.4.0")
	var card := WhatsNewCard._show_if_needed(_host(), "0.5.0")
	var close: Button = null
	for node: Node in _descendants(card):
		if node is Button:
			close = node as Button
	assert_object(close).is_not_null()
	close.pressed.emit()
	await _frames(2)
	assert_bool(is_instance_valid(card)).is_false()


# A long absence must not run the panel off the screen: past the cap, the list scrolls.
func test_a_long_list_scrolls_rather_than_growing_past_the_cap() -> void:
	var ledger := "# Long\n"
	for i in range(20, 0, -1):
		ledger += "\n## v0.%d.0\n\n- A line long enough to wrap onto a second row inside the panel, for release %d.\n- Another.\n" % [i, i]
	_arm(ledger)
	ReleaseNotes.mark_seen("0.0.1")
	var card := WhatsNewCard._show_if_needed(_host(), "0.20.0")
	await _frames(3)
	var scroll: ScrollContainer = null
	for node: Node in _descendants(card):
		if node is ScrollContainer:
			scroll = node as ScrollContainer
	assert_object(scroll).is_not_null()
	assert_int(scroll.vertical_scroll_mode).is_equal(ScrollContainer.SCROLL_MODE_AUTO)
	assert_float(scroll.size.y).is_less_equal(WhatsNewCard.MAX_BODY_HEIGHT + 1.0)


# ==============================================================================
#  How it reads (#1102: "the items all kind of run together")
# ==============================================================================

const WRAPPING_LEDGER := """# Wrapping

## v0.5.0

- A line long enough that it cannot fit the card on one row, so it wraps onto a second and likely a third.
- A second item.
"""


# Every item row, in draw order: the HBox holding a bullet and its line.
func _item_rows(card: Node) -> Array[HBoxContainer]:
	var out: Array[HBoxContainer] = []
	for node: Node in _descendants(card):
		if node is HBoxContainer and node.get_child_count() == 2 and node.get_child(0) is Label:
			if (node.get_child(0) as Label).text == WhatsNewCard.BULLET:
				out.append(node as HBoxContainer)
	return out


func _wrapped_card() -> Array[HBoxContainer]:
	_arm(WRAPPING_LEDGER)
	ReleaseNotes.mark_seen("0.4.0")
	var card := WhatsNewCard._show_if_needed(_host(), "0.5.0")
	await _frames(3)
	var rows := _item_rows(card)
	assert_int(rows.size()).is_equal(2)
	# Without a wrap, a centred bullet and a top one are the same place, and both cases pass vacuously.
	var line := rows[0].get_child(1) as Label
	assert_int(line.get_line_count()) \
		.override_failure_message("the first item never wrapped, so this case cannot tell top from centre") \
		.is_greater(1)
	return rows


# The bullet marks where an item STARTS, so it sits beside the first line of a wrapped one.
func test_a_bullet_sits_on_its_items_first_line() -> void:
	var rows: Array[HBoxContainer] = await _wrapped_card()
	var dot := rows[0].get_child(0) as Label
	var line := rows[0].get_child(1) as Label
	assert_float(dot.position.y).is_equal_approx(line.position.y, 0.5)


# The report as a rule: the break between two items is wider than a line break inside one.
func test_items_stand_further_apart_than_the_lines_inside_one() -> void:
	var rows: Array[HBoxContainer] = await _wrapped_card()
	var line := rows[0].get_child(1) as Label
	var gap := rows[1].position.y - (rows[0].position.y + rows[0].size.y)
	assert_float(gap).is_greater(float(line.get_theme_constant("line_spacing")))


# ==============================================================================
#  The wire -- booting the real scene
# ==============================================================================

func _boot() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	add_child(_main)
	await _frames(3)
	game = _main.get_node("GameContainer/GameView/Game")


func _select_screen() -> MissionSelectScreen:
	var layer: CanvasLayer = game.ui_layer
	for node: Node in layer.get_children():
		if node is MissionSelectScreen and not node.is_queued_for_deletion():
			return node as MissionSelectScreen
	return null


func _card_on(screen: Node) -> WhatsNewCard:
	if screen == null:
		return null
	for node: Node in screen.get_children():
		if node is WhatsNewCard:
			return node as WhatsNewCard
	return null


# The ledger is versioned BELOW the running build, whatever project.godot says today, so the case
# does not pin the version it runs at.
func test_booting_puts_the_card_on_the_title_screen() -> void:
	_arm()
	ReleaseNotes.mark_seen("0.4.0")
	await _boot()
	var screen := _select_screen()
	assert_object(screen).is_not_null()
	assert_object(_card_on(screen)) \
		.override_failure_message("the title screen came up without the what's-new card").is_not_null()
	assert_str(ReleaseNotes.last_seen()).is_equal(Build.version())


# Marked on SHOW: the title screen is rebuilt after every mission, and the card must not ride along.
func test_a_second_trip_through_the_title_screen_does_not_bring_it_back() -> void:
	_arm()
	ReleaseNotes.mark_seen("0.4.0")
	await _boot()
	var first := _select_screen()
	assert_object(_card_on(first)).is_not_null()
	first.queue_free()
	await _frames(2)
	var mc: MissionController = game.mission_controller
	mc.open_mission_select()
	await _frames(2)
	var second := _select_screen()
	assert_object(second).is_not_null()
	assert_object(second).is_not_same(first)
	assert_object(_card_on(second)).is_null()
