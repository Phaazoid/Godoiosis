extends Panel

# Portrait corner of the inspect panel; falls back to the faceless placeholder
# (parity with the hover card).

const FALLBACK: Texture2D = preload("res://Art/Units/Portraits/faceless_one.png")

@onready var portrait_texture: TextureRect = $PortraitTexture

func set_unit(unit: Unit):
	if unit == null:
		portrait_texture.texture = null
		return
	portrait_texture.texture = unit.unit_data.portrait if unit.unit_data.portrait != null else FALLBACK
