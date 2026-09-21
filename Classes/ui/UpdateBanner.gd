extends ModalCard
class_name UpdateBanner

# "YOU ARE NOT ON THE NEWEST BUILD" (#1060), across the title screen on every launch until the
# player is current.
#
# BIG AND IN FRONT IS THE SPEC, not a styling accident (dev, 2026-09-20): "The banner can hide
# anything it wants - we're including an OK button to close it. The point of it is to be big and in
# front on every launch." Drawn and ruled on as a mockup first -- full width, vertically centred,
# over everything. It covers Load Game entirely and half of the last mission row, and that was the
# ruling rather than an oversight.
#
# THE COPY IS HIS, verbatim. The URL is not a const here: it arrives from the server beside the
# version, so moving off itch never strands a build already in somebody's hands.
#
# DISMISSAL LASTS THE LAUNCH, which is why _dismissed is STATIC. MissionController reopens the
# title screen after every mission, so a per-instance flag would bring this back mid-session --
# where what was asked for is once per launch, every launch, until they update.

const COPY := "Hey!  This isn't the newest version of the game.  Please grab the newest one at "
const ACKNOWLEDGE := "OK"

# The alert plate. Its own decision rather than a reference to info_panel's AT_RISK_COLOR: that
# value answers "a stat is at risk", this answers "this build is stale", and one colour serving two
# meanings is how a palette stops meaning anything. They are deliberately the SAME amber, so the
# game has one attention colour.
const PLATE := Color(0.95, 0.8, 0.25)
const INK := Color(0.102, 0.078, 0.031)

const BAND_PADDING_H := 24
const BAND_PADDING_V := 20
const TEXT_SIZE := 18
const GAP := 24

# Cleared headless by _static_init, as TelemetryNotice clears its own: 89 suites boot Main.tscn and
# reach the same door. VersionCheck refuses headless too -- two guards, because a card that appears
# in a suite is silent until it breaks an unrelated test.
static var enabled := true

# Survives the screen being rebuilt; dies with the process.
static var _dismissed := false


static func _static_init() -> void:
	if DisplayServer.get_name() == "headless":
		enabled = false


static func should_show() -> bool:
	return enabled and not _dismissed


# The one door. Returns null when there is nothing to show, so the caller states no policy of its
# own -- MissionController asks for the banner and does not know what makes one due.
static func show_if_needed(game_node: Node, url: String) -> UpdateBanner:
	if not should_show() or url == "":
		return null
	var banner := UpdateBanner.new()
	game_node.ui_layer.add_child(banner)
	banner._build(game_node, url)
	return banner


func _init() -> void:
	# Invisible but STOPPING: the drawing he approved has no dim over the screen, and the band is
	# still the only thing that can be answered while it is up.
	backdrop_color = Color(0, 0, 0, 0)
	content_separation = 0


# A band, not a card -- so the frame step is replaced outright rather than the base growing a knob
# for the one surface that is full width.
func _build_frame() -> Container:
	var host := Control.new()
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(host)

	var plate := StyleBoxFlat.new()
	plate.bg_color = PLATE

	var band := PanelContainer.new()
	band.add_theme_stylebox_override("panel", plate)
	# End to end, centred on the vertical midpoint, growing both ways from it.
	band.anchor_left = 0.0
	band.anchor_right = 1.0
	band.anchor_top = 0.5
	band.anchor_bottom = 0.5
	band.grow_vertical = Control.GROW_DIRECTION_BOTH
	host.add_child(band)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", BAND_PADDING_H)
	margin.add_theme_constant_override("margin_right", BAND_PADDING_H)
	margin.add_theme_constant_override("margin_top", BAND_PADDING_V)
	margin.add_theme_constant_override("margin_bottom", BAND_PADDING_V)
	band.add_child(margin)
	return margin


func _build(game_node: Node, url: String) -> void:
	var content := _build_chrome(game_node)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", GAP)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(row)

	# RichTextLabel rather than a Label, because the URL has to be clickable (dev, 2026-09-20).
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.add_theme_font_size_override("normal_font_size", TEXT_SIZE)
	text.add_theme_color_override("default_color", INK)
	# The link TEXT is the url itself, so the sentence stays true after a host move -- there is no
	# "on itch" baked into prose describing a page that has moved.
	text.text = "%s[url=%s]%s[/url]" % [COPY, url, url]
	text.meta_clicked.connect(_open_link)
	row.add_child(text)

	var ok := Button.new()
	ok.text = ACKNOWLEDGE
	ok.custom_minimum_size = Vector2(80, 36)
	ok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(_acknowledge)
	row.add_child(ok)


# The payload is checked for https:// before it ever reaches here (VersionCheck.read_payload), so
# this cannot be handed something that is not a web address.
func _open_link(meta: Variant) -> void:
	OS.shell_open(str(meta))


func _acknowledge() -> void:
	_dismissed = true
	queue_free()


# Esc dismisses, unlike TelemetryNotice which swallows it. That notice must be READ -- this one is
# a nag with a door, and refusing the key would only trap somebody who has already understood it.
func _on_cancel() -> bool:
	_acknowledge()
	return true
