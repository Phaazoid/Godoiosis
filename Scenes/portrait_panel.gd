extends Panel

@onready var portrait_texture: TextureRect = $PortraitTexture

func set_unit(unit: Unit):
	if unit == null:
		portrait_texture.texture = null
		return
		
	portrait_texture.texture = unit.unit_data.portrait


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
