extends Object
class_name DevWidgets

static func add_label(container: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	container.add_child(label)

static func add_spinbox(container: Node, label_text: String, initial_value: float, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	var spinbox := SpinBox.new()
	spinbox.min_value = -999
	spinbox.max_value = 999
	spinbox.value = initial_value
	spinbox.value_changed.connect(on_change)
	row.add_child(label)
	row.add_child(spinbox)
	container.add_child(row)

static func add_checkbox(container: Node, label_text: String, initial_value: bool, on_change: Callable) -> void:
	var checkbox := CheckBox.new()
	checkbox.text = label_text
	checkbox.button_pressed = initial_value
	checkbox.toggled.connect(on_change)
	container.add_child(checkbox)

static func add_option(container: Node, label_text: String, options: Array, current: String, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	var option := OptionButton.new()
	for i in options.size():
		option.add_item(options[i])
		if options[i] == current:
			option.select(i)
	option.item_selected.connect(func(idx): on_change.call(options[idx]))
	row.add_child(label)
	row.add_child(option)
	container.add_child(row)

static func add_lineedit(container: Node, label_text: String, initial_value: String, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	var edit := LineEdit.new()
	edit.text = initial_value
	edit.custom_minimum_size = Vector2(100, 0)
	edit.text_changed.connect(on_change)
	row.add_child(label)
	row.add_child(edit)
	container.add_child(row)

# Parse an enum @export hint_string into ordered {name, value} entries. Godot emits
# "Name0,Name1,..." for contiguous 0-based enums, or "Name:Val,..." when the values are
# explicit / non-sequential. Handle both so the dropdown maps labels -> real enum ints.
static func parse_enum_hint(hint_string: String) -> Array:
	var entries := []
	var parts := hint_string.split(",", false)
	for i in parts.size():
		var part: String = parts[i]
		var colon := part.find(":")
		if colon != -1:
			entries.append({"name": part.substr(0, colon), "value": int(part.substr(colon + 1))})
		else:
			entries.append({"name": part, "value": i})
	return entries

# Dropdown for an int-backed enum property: shows the names, reports back the enum int.
static func add_enum_option(container: Node, label_text: String, hint_string: String, current: int, on_change: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	var option := OptionButton.new()
	var entries := parse_enum_hint(hint_string)
	for i in entries.size():
		option.add_item(entries[i]["name"])
		if entries[i]["value"] == current:
			option.select(i)
	option.item_selected.connect(func(idx): on_change.call(entries[idx]["value"]))
	row.add_child(label)
	row.add_child(option)
	container.add_child(row)

static func build_resource_editor(container: Node, resource: Resource, rebuild: Callable, skip: Array = []) -> void:
	for prop in resource.get_property_list():
		if prop.name in skip:
			continue
		var is_exported_var = (prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) != 0 and (prop.usage & PROPERTY_USAGE_EDITOR) != 0
		if not is_exported_var:
			continue
		_add_property_control(container, resource, prop, rebuild)
		
static func _add_property_control(container: Node, resource: Resource, prop: Dictionary, rebuild: Callable) -> void:
	var value = resource.get(prop.name)
	var label: String = prop.name.capitalize()

	match prop.type:
		TYPE_INT:
			if prop.hint == PROPERTY_HINT_ENUM:
				add_enum_option(container, label, prop.hint_string, value, func(v): resource.set(prop.name, v))
			else:
				add_spinbox(container, label, value, func(v): resource.set(prop.name, int(v)))
		TYPE_FLOAT:
			add_spinbox(container, label, value, func(v): resource.set(prop.name, v))
		TYPE_BOOL:
			add_checkbox(container, label, value, func(v): resource.set(prop.name, v))
		TYPE_STRING:
			if prop.hint == PROPERTY_HINT_ENUM:
				add_option(container, label, prop.hint_string.split(","), value, func(s): resource.set(prop.name, s))
			else:
				add_lineedit(container, label, value, func(s): resource.set(prop.name, s))
		TYPE_OBJECT:
			if prop.hint == PROPERTY_HINT_RESOURCE_TYPE:
				_add_resource_swapper(container, resource, prop, value, rebuild)
			if value is Resource and value.get_script() != null:
				var indent := MarginContainer.new()
				indent.add_theme_constant_override("margin_left", 16)
				container.add_child(indent)
				var inner := VBoxContainer.new()
				indent.add_child(inner)
				build_resource_editor(inner, value, rebuild)

static func _add_resource_swapper(container: Node, resource: Resource, prop: Dictionary, value: Resource, rebuild: Callable) -> void:
	var base_type: String = prop.hint_string
	var candidates := []
	for entry in ProjectSettings.get_global_class_list():
		if entry["base"] == base_type:
			candidates.append(entry)
	if candidates.is_empty():
		return
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = prop.name.capitalize()
	var option := OptionButton.new()
	var current_class := ""
	if value != null and value.get_script() != null:
		current_class = value.get_script().get_global_name()
	for i in candidates.size():
		option.add_item(candidates[i]["class"])
		if candidates[i]["class"] == current_class:
			option.select(i)
	option.item_selected.connect(func(idx):
		resource.set(prop.name, load(candidates[idx]["path"]).new())
		rebuild.call()
	)
	row.add_child(label)
	row.add_child(option)
	container.add_child(row)
