extends HBoxContainer
class_name ActionQueueRow

@onready var actor_texture: TextureRect = $ActorTexture
@onready var action_icon: TextureRect = $ActionIcon
@onready var target_texture: TextureRect = $TargetTexture
@onready var description_label: Label = $DescriptionLabel

# Applied-state symbols that sit BEHIND the middle action icon (e.g. WET behind the sword/arrow).
const STATE_ICONS := {
	Elemental.State.WET: preload("res://Art/Icons/WetIcon.png"),
}

func setup(action: BaseAction):
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

func _show_elemental_overlays(action: AttackAction) -> void:
	if action.resolved == null:
		return
	# States this hit APPLIES -> behind the middle action icon, nudged up so it peeks out.
	for state in action.resolved.states_added:
		if STATE_ICONS.has(state):
			_overlay_behind(action_icon, STATE_ICONS[state], Vector2(0, -8))
	# Reactions this hit TRIGGERS -> behind the far-right target sprite (the spark).
	for icon in action.resolved.reaction_icons:
		if icon != null:
			_overlay_behind(target_texture, icon)

# Drop `tex` in as a background layer filling `host`, drawn under the host's own texture.
# `pixel_offset` shifts it within the slot (negative y = up).
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
