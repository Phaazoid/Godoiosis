extends VBoxContainer
class_name ExperimentsTool

# The Experiments page (#382) -- the surface Experiments.gd was built expecting (its own docstring
# says "toggle it from the Experiments dev tab") and never got. One row per flag off the registry's
# own introspection -- a checkbox for a toggle, a dropdown for a choice (#508) -- plus Reset all.
# Session scope: these are dev toggles persisted to user://experiments.cfg, not settings a player
# keeps and not values a mission carries.
#
# No confirm dialog on purpose: a flag flip is a session toggle, not a file overwrite -- the #380
# convention guards saves that destroy an authored version, and there is none here.


func _ready() -> void:
	var reset := Button.new()
	reset.text = "Reset all to defaults"
	reset.tooltip_text = "Put every experiment back to its declared default and forget the saved states."
	reset.pressed.connect(_on_reset_pressed)
	add_child(reset)
	_build_rows()


func _build_rows() -> void:
	for flag: Experiments.Flag in Experiments.all_flags():
		var tip := DevWidgets.wrap_tooltip(Experiments.desc_of(flag))
		if Experiments.is_choice(flag):
			# A choice is a dropdown: the dev window is a real OS window, so the PopupMenu that rules
			# OptionButton out of the game's own SubViewport is fine here (every dev tab uses one).
			var options := Experiments.options_of(flag)
			var row := DevWidgets.add_option(self, Experiments.title_of(flag), options,
				str(options[Experiments.choice_of(flag)]),
				func(label: String) -> void: Experiments.set_choice(flag, options.find(label)))
			DevWidgets.apply_tooltip(row, tip)
		else:
			DevWidgets.add_checkbox(self, Experiments.title_of(flag), Experiments.is_on(flag),
				func(on: bool) -> void: Experiments.set_on(flag, on), tip)


func _on_reset_pressed() -> void:
	Experiments.reset_all()
	_rebuild()


func _rebuild() -> void:
	# The reset button is child 0; everything after it is flag rows.
	while get_child_count() > 1:
		var child := get_child(get_child_count() - 1)
		remove_child(child)
		child.queue_free()
	_build_rows()
