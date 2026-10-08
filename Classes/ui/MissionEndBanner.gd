extends ModalCard
class_name MissionEndBanner

# The end-of-mission card (#96 slice 1) -- the moment the game finally has an ENDING to show.
# Built on ModalCard, the base shared with every other full-screen surface.
#
# Usage:  var choice: Choice = await MissionEndBanner.show_banner(game_node, victory, can_retry, reason, frame)
#
# `reason` is what LOST it (#101), worded by MissionRules.defeat_reason -- the vocabulary belongs to
# the rule, not to the card. Empty falls back to the squad-wipe line every pre-#101 defeat showed.
#
# It ASKS FOR FEEDBACK BY DEFAULT (#1052, dev 2026-09-28): the report form sits under the verdict,
# starting on Just feedback, because this is the moment a player has just been handed a verdict and
# the one screen F3 cannot reach. It is part of the card rather than a card over it, so ignoring it
# costs nothing. `frame` is the board as the mission ended, grabbed before this card drew, so a
# report filed from here carries the board rather than a picture of the form.

# STAY leaves the finished board standing so it can be inspected with the dev tools; the mission
# is still over either way (MissionController's latch never unwinds).
enum Choice { RETRY, MISSION_SELECT, STAY }

signal chosen(choice: Choice)

const BUTTON_ROW_SEPARATION := 24

var form: ReportForm

func _init() -> void:
	title_font_size = 48         # deliberately the biggest title in the game: this is the ending
	button_size = Vector2(160, 48)

# Takes the Game node rather than a parent, for the reason PauseMenu.show_menu does.
static func show_banner(game_node: Node, victory: bool, can_retry: bool, reason := "",
		frame: Image = null) -> Choice:
	var banner := MissionEndBanner.new()
	game_node.card_layer.add_child(banner)
	banner._build(victory, can_retry, game_node, reason)
	game_node.serve_report_form(banner.form, frame)
	var choice: Choice = await banner.chosen
	banner.queue_free()
	return choice

func _build(victory: bool, can_retry: bool, game_node: Node, reason := "") -> void:
	title_color = Color(1, 0.85, 0.3) if victory else Color(0.85, 0.2, 0.2)

	var content := _build_chrome(game_node)
	_build_title(content, "VICTORY" if victory else "DEFEAT")
	var body := "The field is yours."
	if not victory:
		body = reason if reason != "" else MissionRules.defeat_reason(MissionRules.LoseCondition.SQUAD_LOST)
	_build_body(content, body)

	var row := _build_button_row(content, false, BUTTON_ROW_SEPARATION)

	# Hidden on a board that wasn't loaded from disk (the Sandbox board): there is nothing to
	# reload, and a dead button is worse than no button.
	if can_retry:
		_add_button(row, "Retry Mission", func(): chosen.emit(Choice.RETRY))

	_add_button(row, "Mission Select", func(): chosen.emit(Choice.MISSION_SELECT))
	_add_button(row, "Stay (inspect)", func(): chosen.emit(Choice.STAY), Color(0.75, 0.75, 0.8))

	# Below the verdict, and it cannot back out: the three buttons above are the only ways off this
	# card, and a note left unsubmitted when one is pressed is simply dropped. No focus grab either --
	# the form is optional, and a focused note box would swallow the player's first keypress.
	content.add_child(HSeparator.new())
	form = ReportForm.new(self, BugReporter.Kind.FEEDBACK, false)
	content.add_child(form)
