extends Panel

@onready var portrait_texture: TextureRect = $PortraitTexture

func set_unit(unit: Unit):
	if unit == null:
		portrait_texture.texture = null
		return
	portrait_texture.texture = unit.unit_data.portrait
