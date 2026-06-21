extends CanvasLayer

@onready var turn_label = $TurnLabel

func show_label(text: String):
	turn_label.text = text
	visible = true
	
	#turn_label.modulate.a = 0
	var tween = create_tween()
	#TODO - make this effect fancier.  Fade in/out, blue for player team, red for enemy.  
	#tween.tween_property(self, "modulate:a", 1.0, 0.3)
	tween.tween_interval(1.0)
	#tween.tween_property(self, "modulate:a", 0.0, 0.5)
	tween.tween_callback(Callable(self, "hide"))
