extends HBoxContainer
class_name ActionQueueRow

@onready var actor_texture: TextureRect = $ActorTexture
@onready var action_icon: TextureRect = $ActionIcon
@onready var target_texture: TextureRect = $TargetTexture
@onready var description_label: Label = $DescriptionLabel
@onready var cancel_button: Button = $CancelButton

const STATE_ICONS := {
	Elemental.State.WET: preload("res://Art/Icons/WetIcon.png"),
}

var action: BaseAction

signal cancel_requested(action: BaseAction)
signal hover_changed(action: BaseAction, hovering: bool)

func setup(action_ref: BaseAction):
	action = action_ref

	actor_texture.texture = action.get_actor_texture()
	actor_texture.modulate = action.get_actor_modulate()
	action_icon.texture = action.get_action_icon()
	target_texture.texture = action.get_target_texture()
	description_label.text = action.get_description()

	if action is AttackAction:
		var atk := action as AttackAction
		var summary := atk.get_outcome_summary()
		if summary != "":
			description_label.text += "    " + summary
		_show_elemental_overlays(atk)

	action_icon.modulate = action.get_ui_modulate()

	# The X keeps its slot on every row (so content stays aligned) but is inert on rows that
	# can't be cancelled: hold-position moves and derived counters (counters are computed, not
	# player orders — Law #2).
	var hide_cancel: bool = (action is MoveAction and action.is_hold_position) or action is CounterAttackAction
	if hide_cancel:
		cancel_button.modulate.a = 0.0
		cancel_button.disabled = true
		cancel_button.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		cancel_button.modulate.a = 1.0
		cancel_button.disabled = false
		cancel_button.mouse_filter = Control.MOUSE_FILTER_STOP

	cancel_button.pressed.connect(_on_cancel_pressed)
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _on_cancel_pressed():
	cancel_requested.emit(action)

func _on_mouse_entered():
	hover_changed.emit(action, true)

func _on_mouse_exited():
	hover_changed.emit(action, false)

func _show_elemental_overlays(atk: AttackAction) -> void:
	if atk.resolved == null:
		return
	for state in atk.resolved.states_added:
		if STATE_ICONS.has(state):
			_overlay_behind(action_icon, STATE_ICONS[state], Vector2(0, -8))
	for icon in atk.resolved.reaction_icons:
		if icon != null:
			_overlay_behind(target_texture, icon)

func _overlay_behind(host: TextureRect, tex: Texture2D, pixel_offset := Vector2.ZERO) -> void:
	var bg := TextureRect.new()
	bg.texture = tex
	bg.show_behind_parent = true
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.offset_left += pixel_offset.x
	bg.offset_right += pixel_offset.x
	bg.offset_top += pixel_offset.y
	bg.offset_bottom += pixel_offset.y
