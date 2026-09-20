# The update nag (#1060) at the RENDERED band rather than the flags behind it (the #166 doctrine:
# assert on what the player sees). What is pinned here is the three things the dev ruled on -- the
# copy is his and unaltered, the link is the url itself, and OK makes it stay gone for the launch.
#
# Fixture is test_mission_status_panel's: a real game scene, root named "Main" under /root, because
# the banner parents to game.ui_layer.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const URL := "https://example.com/game"

var _main: Node
var game: Node2D
# Both are statics cleared headless by _static_init and outliving a case, so every one of them is
# saved and put back -- a case that left `enabled` true would leak a modal into the next suite.
var _enabled: bool
var _dismissed: bool


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	_enabled = UpdateBanner.enabled
	_dismissed = UpdateBanner._dismissed
	# The suite wants the real card, so it asks for it -- exactly as test_telemetry_store sets
	# persistence_enabled back.
	UpdateBanner.enabled = true
	UpdateBanner._dismissed = false
	await await_idle_frame()


func after_test() -> void:
	UpdateBanner.enabled = _enabled
	UpdateBanner._dismissed = _dismissed
	get_tree().root.remove_child(_main)
	_main.free()
	await await_idle_frame()


func _text_of(banner: UpdateBanner) -> String:
	var found := _find_rich_text(banner)
	assert_object(found).is_not_null()
	return found.text


func _find_rich_text(node: Node) -> RichTextLabel:
	for child in node.get_children():
		if child is RichTextLabel:
			return child
		var deeper := _find_rich_text(child)
		if deeper != null:
			return deeper
	return null


func _find_button(node: Node) -> Button:
	for child in node.get_children():
		if child is Button:
			return child
		var deeper := _find_button(child)
		if deeper != null:
			return deeper
	return null


# HIS WORDS, UNALTERED. A test's name pins a rule, and the rule here is that player-facing prose is
# the dev's: anything that reworded this line would go red rather than ship quietly.
func test_the_band_carries_his_copy_verbatim() -> void:
	var banner := UpdateBanner.show_if_needed(game, URL)
	assert_object(banner).is_not_null()
	await await_idle_frame()
	assert_str(_text_of(banner)).contains(
		"Hey!  This isn't the newest version of the game.  Please grab the newest one at ")


# The link TEXT is the url, not a phrase -- which is what keeps the sentence true after a move off
# itch, since there is no host named in prose anywhere.
func test_the_url_is_the_link_and_its_own_label() -> void:
	var banner := UpdateBanner.show_if_needed(game, URL)
	await await_idle_frame()
	assert_str(_text_of(banner)).contains("[url=%s]%s[/url]" % [URL, URL])


func test_no_banner_without_a_url() -> void:
	assert_object(UpdateBanner.show_if_needed(game, "")).is_null()


# THE WHOLE POINT OF THE STATIC. MissionController reopens the title screen after every mission, so
# a per-instance flag would bring the band back mid-session where what was asked for is once per
# launch. Pressing OK and then asking for the banner again is exactly that sequence.
func test_ok_keeps_it_gone_for_the_rest_of_the_launch() -> void:
	var banner := UpdateBanner.show_if_needed(game, URL)
	await await_idle_frame()
	var ok := _find_button(banner)
	assert_object(ok).is_not_null()
	ok.pressed.emit()
	await await_idle_frame()

	assert_bool(UpdateBanner.should_show()).is_false()
	assert_object(UpdateBanner.show_if_needed(game, URL)).is_null()


# Esc is a door here, unlike TelemetryNotice which swallows it -- and a card with no door is the
# failure ModalCard's cancel contract exists to prevent.
func test_escape_dismisses_it_too() -> void:
	var banner := UpdateBanner.show_if_needed(game, URL)
	await await_idle_frame()
	assert_bool(banner._on_cancel()).is_true()
	await await_idle_frame()
	assert_bool(UpdateBanner.should_show()).is_false()


# The band spans the viewport rather than sitting in the content column (dev, 2026-09-20: end to
# end, over everything). Measured as a PROPORTION of the design space, never a pinned pixel width,
# so the ruling survives anyone retuning the padding.
func test_the_band_runs_end_to_end() -> void:
	var banner := UpdateBanner.show_if_needed(game, URL)
	await await_idle_frame()
	await await_idle_frame()
	var band := _find_panel(banner)
	assert_object(band).is_not_null()
	assert_float(band.size.x).is_equal_approx(banner.size.x, 1.0)


func _banner_under(node: Node) -> UpdateBanner:
	for child in node.get_children():
		if child is UpdateBanner:
			return child
	return null


# THE GUARD AGAINST A NAG LANDING ON A BATTLE. The answer arrives off the network, so it can come
# back after the player has already picked a mission -- and this band claims ModalLock, so dropping
# one onto a running board would freeze it behind something the player never asked for.
#
# Both halves, because the negative alone would pass on a _nag_if_outdated that does nothing at all.
# VersionCheck's cache is SEEDED rather than fetched, which is what lets the real async path run
# here with no network: latest() hands back _latest once _asked is set.
func test_the_nag_waits_for_the_title_screen_and_gives_up_without_it() -> void:
	var was_enabled := VersionCheck.enabled
	var was_asked := VersionCheck._asked
	var was_latest := VersionCheck._latest
	VersionCheck.enabled = true
	VersionCheck._asked = true
	VersionCheck._latest = {"version": "9.9.9", "url": URL}
	var mc: MissionController = game.mission_controller

	# Still on the title screen -- the band is due.
	mc._select_screen = MissionSelectScreen.open(game, [], [], false)
	await mc._nag_if_outdated()
	await await_idle_frame()
	assert_object(_banner_under(game.ui_layer)).is_not_null()

	_banner_under(game.ui_layer).free()
	mc._select_screen.free()
	mc._select_screen = null
	UpdateBanner._dismissed = false
	await await_idle_frame()

	# Gone from it -- the reply is the same, and nothing may appear.
	await mc._nag_if_outdated()
	await await_idle_frame()
	assert_object(_banner_under(game.ui_layer)).is_null()

	VersionCheck.enabled = was_enabled
	VersionCheck._asked = was_asked
	VersionCheck._latest = was_latest


func _find_panel(node: Node) -> PanelContainer:
	for child in node.get_children():
		if child is PanelContainer:
			return child
		var deeper := _find_panel(child)
		if deeper != null:
			return deeper
	return null
