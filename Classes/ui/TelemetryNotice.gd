extends ModalCard
class_name TelemetryNotice

# THE FIRST-LAUNCH NOTICE (#53 slice 3): what a player is told about playtest data, once, before
# they have played anything. ConfirmCard's shape -- build, show, free -- and every ModalCard style
# default taken verbatim.
#
# IT IS A NOTIFICATION, NOT CONSENT, and that is a deliberate scope rather than an oversight (dev,
# 2026-09-08): "Let's not even give them the option to turn it off. The entire point of this build
# is playtest data... If they don't want to give me data, they can't play the early version of my
# game." So there is no opt-out toggle and no recording gate -- #841 was closed 2026-09-18 as never
# having been open in the sense it claimed, and a data-sharing opt-out is not to be re-raised for
# this demo. The copy is HIS and deliberately brief: it tells the player what is happening, and does
# not argue the case.
#
# IT NOW ALSO ASKS FOR A NAME (#1049), which is the one thing on this card the player may answer
# rather than merely read. Opt-in, freeform, skippable, default empty -- so it is not consent
# wearing a text box: leaving it blank is the same deal as before, and the card says so.
#
# THE CARD IS VERSIONED. What this says is a description of what the game sends, so when that
# CHANGES the description is due again -- to everyone, not only to installs that have never seen a
# card. VERSION below is the whole mechanism: the store keeps the last version acknowledged, this
# file owns what each version says, and the two are in one place so bumping the copy without
# bumping the number is a thing you have to do on purpose.
#
# ESC DOES NOT DISMISS IT. _on_cancel returns false, which per ModalCard's contract makes this card
# SWALLOW the key -- the deliberate choice for a surface where cancelling is meaningless, alongside
# MissionEndBanner and MissionSelectScreen. The button is the only door, which is the point of a
# notice somebody is meant to read.

# WHICH TERMS THIS CARD STATES. Bump it whenever BODY's description of what the game sends changes,
# and every install -- new or long-since-acknowledged -- is shown the card once more. 1 was the
# #53 slice 3 card, which no key records: an install that saw it carries the retired `notice_seen`
# bool and reads 0 here, so it is shown version 2, which is the intent rather than a wart.
const VERSION := 2

const TITLE := "Thanks for trying out this little demo!"
# PLACEHOLDER COPY, FOR THE DEV TO REPLACE. The old wording promised "No name, no account", which
# the box below makes false, so it could not ship unedited -- but player-facing prose is his, and
# this is a stand-in that states the facts rather than finished writing.
const BODY := """This is a very early build of the game.  Please give feedback, or report bugs, through the feedback options in the menu!

There are a couple of short levels to try.

This build sends playtest data.

It is anonymous by default: a random id for this install, and nothing about your machine or your files.

If you want your reports to have a name on them, put one here. Anything you like -- it doesn't have to be your real name. Leave it blank to stay anonymous."""
const ACKNOWLEDGE := "Got it"

# PLACEHOLDER, as BODY is.
const NAME_PLACEHOLDER := "Optional -- a name for your reports"

# How wide the paragraph runs before wrapping, in the 1280x720 design space (#659).
const BODY_WIDTH := 620.0

# Cleared headless by _static_init, exactly as TelemetryStore / PlayerSettings / Experiments clear
# their own: a headless process has no player to notify. This is load-bearing well beyond tidiness
# -- 89 suites boot Main.tscn and every one reaches the deferred open_mission_select, so an
# unsuppressed card here would stack a modal over the front door of most of the test tree.
#
# A suite that wants the real card sets this back to true itself, the way test_telemetry_store does
# with persistence_enabled. Declared residual: a gdUnit4 run driven from the EDITOR panel is not
# headless, so those 89 suites would each meet the card there -- run_tests.ps1 and CI are both
# headless, so both are covered.
static var enabled := true

# The name box, held so _acknowledge can read it. Null until _build runs, which is why the write
# below is guarded -- should_show() can hand back a card nobody ever built in a suite.
var _name_edit: LineEdit


static func _static_init() -> void:
	if DisplayServer.get_name() == "headless":
		enabled = false


# Three questions, all of which must answer yes.
#
# The persistence clause is NOT a test convenience: a notice we cannot record having shown would
# reappear on every single launch, which is worse for the player than never showing it at all.
static func should_show() -> bool:
	return enabled and TelemetryStore.persistence_enabled \
			and TelemetryStore.notice_version_seen() < VERSION


# The one door. Returns null when there was nothing to show, so the caller states no policy of its
# own -- MissionController asks for the notice and does not know what makes one due.
static func show_if_needed(game_node: Node) -> TelemetryNotice:
	if not should_show():
		return null
	var card := TelemetryNotice.new()
	game_node.ui_layer.add_child(card)
	card._build(game_node)
	return card


func _build(game_node: Node) -> void:
	var content := _build_chrome(game_node)
	_build_title(content, TITLE)
	var body := _build_body(content, BODY)
	# The paragraph is long and _build_body's Label does not wrap on its own, so an unbounded one
	# would run off both edges of the card (ModalCard's own bound-your-body law).
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = BODY_WIDTH
	_build_name_box(content)
	var row := _build_button_row(content, false, content_separation)
	_add_button(row, ACKNOWLEDGE, _acknowledge)


# PREFILLED FROM THE STORE, never blank-by-default (#1049). This card is due again whenever VERSION
# moves, so a later showing can reach a player who already set a name -- on this card or on the
# settings page -- and _acknowledge writes whatever the box holds. A box that always started empty
# would quietly clear their name every time the terms changed.
#
# max_length comes off the SETTING, so the box and the store cannot disagree about what fits: the
# store's cap would otherwise silently truncate a name the box let somebody finish typing.
func _build_name_box(parent: Container) -> void:
	_name_edit = LineEdit.new()
	_name_edit.text = PlayerSettings.text_of(PlayerSettings.Setting.PLAYER_NAME)
	_name_edit.placeholder_text = NAME_PLACEHOLDER
	_name_edit.max_length = PlayerSettings.max_length_of(PlayerSettings.Setting.PLAYER_NAME)
	_name_edit.custom_minimum_size.x = BODY_WIDTH
	# Enter finishes the card, the way it finishes any one-field form. The signal hands over the
	# text, which is ignored: _acknowledge reads the box, so there is one path to the store rather
	# than two that can disagree about trimming.
	_name_edit.text_submitted.connect(func(_text: String) -> void: _acknowledge())
	parent.add_child(_name_edit)


# Marking BEFORE freeing, so a player who quits in the same breath as clicking is still recorded as
# told. The write is one-way; nothing ever un-sees the notice.
#
# THE NAME IS WRITTEN FIRST, and the order is the guarantee rather than a preference: mark_notice_seen
# is what stops this card coming back, so a crash between the two writes must not be able to lose the
# name AND the chance to ask for it again. Cleaning is set_text's, not this file's.
func _acknowledge() -> void:
	if _name_edit != null:
		PlayerSettings.set_text(PlayerSettings.Setting.PLAYER_NAME, _name_edit.text)
	TelemetryStore.mark_notice_seen(VERSION)
	queue_free()


# Deliberately takes NOTHING -- see the header. Returning false leaves the key unhandled here, and
# game.gd._input stands down while anything is in the `modal` group, so Esc does nothing at all
# while this is up rather than falling through to the title screen behind it.
func _on_cancel() -> bool:
	return false
