extends ModalCard
class_name MissionEndBanner

# The end-of-mission card (#96 slice 1) -- the moment the game finally has an ENDING to show.
# Built on ModalCard, the base shared with every other full-screen surface.
#
# Usage:  var choice: Choice = await MissionEndBanner.show_banner(game_node, victory, can_retry)

# STAY leaves the finished board standing so it can be inspected with the dev tools; the mission
# is still over either way (MissionController's latch never unwinds).
enum Choice { RETRY, MISSION_SELECT, STAY }

signal chosen(choice: Choice)

const BUTTON_ROW_SEPARATION := 24

func _init() -> void:
	title_font_size = 48         # deliberately the biggest title in the game: this is the ending
	button_size = Vector2(160, 48)

# Takes the Game node rather than a parent, for the reason PauseMenu.show_menu does.
static func show_banner(game_node: Node, victory: bool, can_retry: bool) -> Choice:
	var banner := MissionEndBanner.new()
	game_node.ui_layer.add_child(banner)
	banner._build(victory, can_retry, game_node)
	var choice: Choice = await banner.chosen
	banner.queue_free()
	return choice

func _build(victory: bool, can_retry: bool, game_node: Node) -> void:
	title_color = Color(1, 0.85, 0.3) if victory else Color(0.85, 0.2, 0.2)

	var content := _build_chrome(game_node)
	_build_title(content, "VICTORY" if victory else "DEFEAT")
	_build_body(content, "The field is yours." if victory else "Your squad has fallen.")

	var row := _build_button_row(content, false, BUTTON_ROW_SEPARATION)

	# Hidden on a board that wasn't loaded from disk (the Sandbox board): there is nothing to
	# reload, and a dead button is worse than no button.
	if can_retry:
		_add_button(row, "Retry Mission", func(): chosen.emit(Choice.RETRY))

	_add_button(row, "Mission Select", func(): chosen.emit(Choice.MISSION_SELECT))
	_add_button(row, "Stay (inspect)", func(): chosen.emit(Choice.STAY), Color(0.75, 0.75, 0.8))
