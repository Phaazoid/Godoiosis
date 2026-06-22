extends HBoxContainer
class_name UnitStatesBar

func set_unit(unit: Unit) -> void:
	if unit == null:
		StateIcons.populate(self, [])
		return
	StateIcons.populate(self, unit.element_states)
