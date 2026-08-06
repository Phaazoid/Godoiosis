extends ModalCard
class_name CrisisPrompt

# Code-built card for the Crisis Mode offer (#33, will-and-death.md). Built on ModalCard, the base
# shared with every other full-screen surface.
# Usage:  var accept: bool = await CrisisPrompt.show_prompt(game_node, unit_name)

signal chosen(accept: bool)

const BUTTON_ROW_SEPARATION := 24
const TITLE_COLOR := Color(1, 0.3, 0.3)
const PULSE_COLOR := Color(1, 0.75, 0.2)

func _init() -> void:
	title_color = TITLE_COLOR    # red: this is an alarm, not an announcement
	button_size = Vector2(150, 48)

# Takes the Game node rather than a parent, for the reason PauseMenu.show_menu does.
static func show_prompt(game_node: Node, unit_name: String) -> bool:
	var prompt := CrisisPrompt.new()
	game_node.ui_layer.add_child(prompt)
	prompt._build(unit_name, game_node)
	var accept: bool = await prompt.chosen
	prompt.queue_free()
	return accept

func _build(unit_name: String, game_node: Node) -> void:
	var content := _build_chrome(game_node)

	var title := _build_title(content, "ENTER CRISIS MODE?")
	_build_body(content, "%s is going down.\nRise at 5 HP with a surge — but Will locks at 0,\nand the next fall is DEATH." % unit_name)

	var row := _build_button_row(content, false, BUTTON_ROW_SEPARATION)
	_add_button(row, "YES — Crisis", func(): chosen.emit(true))
	_add_button(row, "NO — Stay Down", func(): chosen.emit(false))

	# A pulse so it reads as a big moment. Bound to this node, so it stops when we free.
	var tween := create_tween().set_loops()
	tween.tween_property(title, "modulate", PULSE_COLOR, 0.4)
	tween.tween_property(title, "modulate", TITLE_COLOR, 0.4)
