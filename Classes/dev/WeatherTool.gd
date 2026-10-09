extends VBoxContainer
class_name WeatherTool

# The Weather page (#1260): how each weather looks and what it does, tuned LIVE. Pick a weather and
# its WeatherLook and WeatherRules are the very objects WeatherMirror draws from and the soak reads
# (each is cached per kind), so a slider shows on the board the next frame. Save writes both files
# through DevWidgets.save_over, asking first, since a save overwrites.
#
# Which weather a BOARD wears is the Scenario page's (its Weather picker beside Look). This page opens
# on that one, so tuning the rain you are looking at is one click. A look draws only the rows of what
# it drops (WeatherLook.row_shows), so a snow page lists no splashes.

const NO_LOOK := "No look file for this weather -- add one under Resources/WeatherLooks/."

var _game   # untyped back-ref: game.gd has no class_name
var _picker: OptionButton
var _save: Button
var _status: Label
var _rows: VBoxContainer
var _kind := Weather.Kind.RAIN
var _dirty := false


func init(game) -> void:
	_game = game
	var head := HBoxContainer.new()
	add_child(head)
	var label := Label.new()
	label.text = "Weather"
	head.add_child(label)
	_picker = OptionButton.new()
	for kind: Weather.Kind in Weather.Kind.values():
		if kind != Weather.Kind.CLEAR:
			_picker.add_item(Weather.display_name(kind), kind)
	_picker.item_selected.connect(func(index: int) -> void:
		_show(_picker.get_item_id(index) as Weather.Kind))
	head.add_child(_picker)
	_save = Button.new()
	_save.text = "Save"
	_save.pressed.connect(_on_save_pressed)
	head.add_child(_save)
	DevWidgets.apply_tooltip(_save, DevWidgets.wrap_tooltip(
		"Write this weather's look and rules to their files. Asks first: the saved version is lost."))
	_status = Label.new()
	add_child(_status)
	_rows = DevWidgets.add_knob_scroll(self)
	_show(_kind)


# On every show: open on the weather the loaded board wears, if it wears one.
func refresh_on_show() -> void:
	var board: Weather.Kind = _game.scenario_manager.current_weather if _game != null else Weather.Kind.CLEAR
	if board != Weather.Kind.CLEAR and board != _kind:
		_show(board)


func _show(kind: Weather.Kind) -> void:
	_kind = kind
	_picker.select(_picker.get_item_index(kind))
	_status.text = ""
	_fill()
	_set_dirty(false)


func _fill() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var kind := _kind
	var rules := WeatherRules.for_kind(kind)
	if rules != null:
		var states: Array = []
		for key: String in Elemental.State.keys():
			states.append(key.capitalize())
		DevWidgets.add_knob_row(_rows, {"label": "Soaks with", "options": states}, int(rules.state),
			func(picked: Variant) -> void: _write(rules, "state", int(picked)),
			DevWidgets.wrap_tooltip("The state a unit gains at the end of its own turn while this "
				+ "weather falls. None soaks nobody."))
	var look := WeatherLook.for_kind(kind)
	if look == null:
		DevWidgets.add_label(_rows, NO_LOOK)
	else:
		for row: Dictionary in WeatherLook.ROWS:
			if not WeatherLook.row_shows(row, look.fall):
				continue
			var prop: String = row["prop"]
			DevWidgets.add_knob_row(_rows, row, look.get(prop),
				func(value: Variant) -> void: _write(look, prop, value),
				DevWidgets.wrap_tooltip(row["tip"]))


# Into the live resource: the mirror and the soak read the cached object, so this IS the preview.
func _write(resource: Resource, prop: String, value: Variant) -> void:
	if typeof(resource.get(prop)) == TYPE_INT:
		value = int(value)
	resource.set(prop, value)
	resource.emit_changed()
	_set_dirty(true)
	if prop == "fall":
		_fill.call_deferred()   # deferred: the picker that fired this is one of the rows freed


func _set_dirty(dirty: bool) -> void:
	_dirty = dirty
	DevWidgets.mark_unsaved(_save, "Save", dirty)


func has_unsaved_changes() -> bool:
	return _dirty


func _on_save_pressed() -> void:
	var name := Weather.display_name(_kind)
	DevWidgets.confirm_overwrite(self, "the saved %s" % name, "what is on this page", _save_now)


func _save_now() -> void:
	var ok := true
	var look := WeatherLook.for_kind(_kind)
	if look != null:
		ok = DevWidgets.save_over(look, WeatherLook.path_of(_kind), _status) and ok
	var rules := WeatherRules.for_kind(_kind)
	if rules != null:
		ok = DevWidgets.save_over(rules, WeatherRules.FOLDER + Weather.name_of(_kind) + ".tres", _status) and ok
	if ok:
		_status.text = "Saved %s." % Weather.display_name(_kind)
		_set_dirty(false)
