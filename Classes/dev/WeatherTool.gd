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
#
# The wind's strengths are on this page too (#1286), below the weathers in the one picker: a wind is
# a weather the board wears beside the other, and each strength's WindLook is tuned the same way.

const NO_LOOK := "No look file for this weather -- add one under Resources/WeatherLooks/."
const NO_WIND_LOOK := "No look file for this wind -- add one under Resources/WindLooks/."
# A wind strength's id in the picker, past every weather's.
const WIND_ID := 100

var _game   # untyped back-ref: game.gd has no class_name
var _picker: OptionButton
var _save: Button
var _status: Label
var _rows: VBoxContainer
var _kind := Weather.Kind.RAIN
var _wind := -1   # the Wind.Kind on show, or -1 while a weather is
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
	_picker.add_separator()
	for kind: Wind.Kind in Wind.Kind.values():
		if kind != Wind.Kind.CALM:
			_picker.add_item("Wind: " + Wind.display_name(kind), WIND_ID + kind)
	_picker.item_selected.connect(func(index: int) -> void:
		var id := _picker.get_item_id(index)
		if id >= WIND_ID:
			_show_wind((id - WIND_ID) as Wind.Kind)
		else:
			_show(id as Weather.Kind))
	head.add_child(_picker)
	_save = Button.new()
	_save.text = "Save"
	_save.pressed.connect(_on_save_pressed)
	head.add_child(_save)
	DevWidgets.apply_tooltip(_save, DevWidgets.wrap_tooltip(
		"Write this weather's look and rules, or this wind's look, to their files. Asks first: the saved version is lost."))
	_status = Label.new()
	add_child(_status)
	_rows = DevWidgets.add_knob_scroll(self)
	_show(_kind)


# On every show: open on the weather the loaded board wears, if it wears one, or else on its wind.
func refresh_on_show() -> void:
	if _game == null:
		return
	var board: Weather.Kind = _game.scenario_manager.current_weather
	var wind: Wind.Kind = _game.scenario_manager.current_wind
	if board != Weather.Kind.CLEAR:
		if board != _kind or _wind >= 0:
			_show(board)
	elif wind != Wind.Kind.CALM and wind != _wind:
		_show_wind(wind)


func _show(kind: Weather.Kind) -> void:
	_kind = kind
	_wind = -1
	_picker.select(_picker.get_item_index(kind))
	_status.text = ""
	_fill()
	_set_dirty(false)


func _show_wind(kind: Wind.Kind) -> void:
	_wind = kind
	_picker.select(_picker.get_item_index(WIND_ID + kind))
	_status.text = ""
	_fill()
	_set_dirty(false)


func _fill() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if _wind >= 0:
		_fill_wind(_wind as Wind.Kind)
		return
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


func _fill_wind(kind: Wind.Kind) -> void:
	var look := WindLook.for_kind(kind)
	if look == null:
		DevWidgets.add_label(_rows, NO_WIND_LOOK)
		return
	for row: Dictionary in WindLook.ROWS:
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
	var name := Weather.display_name(_kind) if _wind < 0 else Wind.display_name(_wind as Wind.Kind) + " wind"
	DevWidgets.confirm_overwrite(self, "the saved %s" % name, "what is on this page", _save_now)


func _save_now() -> void:
	if _wind >= 0:
		var wind := _wind as Wind.Kind
		var wind_look := WindLook.for_kind(wind)
		if wind_look != null and DevWidgets.save_over(wind_look, WindLook.path_of(wind), _status):
			_status.text = "Saved %s wind." % Wind.display_name(wind)
			_set_dirty(false)
		return
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
