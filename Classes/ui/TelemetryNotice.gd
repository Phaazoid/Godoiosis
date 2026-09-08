extends ModalCard
class_name TelemetryNotice

# THE FIRST-LAUNCH NOTICE (#53 slice 3): what a player is told about playtest data, once, before
# they have played anything. ConfirmCard's shape -- build, show, free -- and every ModalCard style
# default taken verbatim.
#
# IT IS A NOTIFICATION, NOT CONSENT, and that is a deliberate scope rather than an oversight (dev,
# 2026-09-08): "Let's not even give them the option to turn it off. The entire point of this build
# is playtest data... If they don't want to give me data, they can't play the early version of my
# game." So there is no PlayerSettings row, no toggle and no recording gate. The copy is HIS and
# deliberately brief -- it tells the player what is happening and that it is anonymous, and does not
# argue the case. That ruling is scoped to the early hand-delivered builds; putting the setting back
# before any wider release is #841.
#
# ESC DOES NOT DISMISS IT. _on_cancel returns false, which per ModalCard's contract makes this card
# SWALLOW the key -- the deliberate choice for a surface where cancelling is meaningless, alongside
# MissionEndBanner and MissionSelectScreen. The button is the only door, which is the point of a
# notice somebody is meant to read.

const TITLE := "This is an early playtest build."
const BODY := """This build sends playtest data.    

It is anonymous: a random id for this install, and nothing else. No name, no account, nothing about your machine or your files. """
const ACKNOWLEDGE := "Got it"

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


static func _static_init() -> void:
	if DisplayServer.get_name() == "headless":
		enabled = false


# Three questions, all of which must answer yes.
#
# The persistence clause is NOT a test convenience: a notice we cannot record having shown would
# reappear on every single launch, which is worse for the player than never showing it at all.
static func should_show() -> bool:
	return enabled and TelemetryStore.persistence_enabled and not TelemetryStore.notice_seen()


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
	var row := _build_button_row(content, false, content_separation)
	_add_button(row, ACKNOWLEDGE, _acknowledge)


# Marking BEFORE freeing, so a player who quits in the same breath as clicking is still recorded as
# told. The write is one-way; nothing ever un-sees the notice.
func _acknowledge() -> void:
	TelemetryStore.mark_notice_seen()
	queue_free()


# Deliberately takes NOTHING -- see the header. Returning false leaves the key unhandled here, and
# game.gd._input stands down while anything is in the `modal` group, so Esc does nothing at all
# while this is up rather than falling through to the title screen behind it.
func _on_cancel() -> bool:
	return false
