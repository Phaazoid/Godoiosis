extends HBoxContainer
class_name ActionQueueRow

@onready var actor_texture: TextureRect = $ActorTexture
@onready var action_icon: TextureRect = $ActionIcon
@onready var target_texture: TextureRect = $TargetTexture
@onready var description_label: Label = $DescriptionLabel

func setup(action: BaseAction):
	actor_texture.texture = action.get_actor_texture()
	actor_texture.modulate = action.get_actor_modulate()
	action_icon.texture = action.get_action_icon()
	target_texture.texture = action.get_target_texture()
	description_label.text = action.get_description()
