extends VBoxContainer
class_name WeatherTool

# The Weather page (#1260): how each weather looks and what it does, tuned LIVE. Pick a weather and
# its WeatherLook and WeatherRules are the very objects WeatherMirror draws from and the soak reads
# (each is cached per kind), so a slider shows on the board the next frame. Save writes the touched
# files through DevWidgets.save_over, asking first, since a save overwrites.
#
# Which weather a BOARD wears is the Scenario page's (its Weather picker beside Look). This page opens
# on that one, so tuning the rain you are looking at is one click. A look draws only the rows of what
# it drops (WeatherLook.row_shows), so a snow page lists no splashes.
#
# The wind's strengths are on this page too (#1286), below the weathers in the one picker: a wind is
# a weather the board wears beside the other, and each strength's WindLook is tuned the same way.
#
# The unsaved marker is per FILE (#1370), WeightsTool's _touched: an edit lives on the cached resource,
# so it outlives picking another weather, and Save writes every file touched since the last save.

const CONFIRM_LIST_MAX := 12   # WeightsTool's: a confirm listing every file is one nobody reads
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
# Touched since the last save: each edited look or rules resource -> the file it saves to.
var _touched: Dictionary[Resource, String] = {}


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
		"Write every weather and wind file changed on this page since the last save, whichever is on show. "
		+ "Asks first: the saved versions are lost."))
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
	_refresh_dirty()


func _show_wind(kind: Wind.Kind) -> void:
	_wind = kind
	_picker.select(_picker.get_item_index(WIND_ID + kind))
	_status.text = ""
	_fill()
	_refresh_dirty()


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
		for id: String in Atmosphere.SUBSTANCES:
			DevWidgets.add_knob_row(_rows,
				{"label": "Air: " + SubstanceCatalog.name_of(id), "min": -100, "max": 100, "step": 1},
				int(rules.air.get(id, 0)),
				func(points: Variant) -> void: _write_air(rules, id, int(points)),
				DevWidgets.wrap_tooltip("Percentage points this weather adds to the board's %s while "
					% SubstanceCatalog.name_of(id).to_lower()
					+ "it falls, on top of what the board authors (negative lowers it). The board names "
					+ "this weather beside the substance. One step is %d points." % int(Atmosphere.STEP[id])))
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
	_touch(resource)
	if prop == "fall":
		_fill.call_deferred()   # deferred: the picker that fired this is one of the rows freed
	if resource is WeatherRules:
		_redraw_plan()


# Into the live rules' air (#1324), erasing a substance at 0 so the file names only what the weather
# moves. game._board() composes from the cached rules, so the open plan and the corner HUD are redrawn
# to show the new reading at once.
func _write_air(rules: WeatherRules, id: String, points: int) -> void:
	if points == 0:
		rules.air.erase(id)
	else:
		rules.air[id] = points
	rules.emit_changed()
	_touch(rules)
	_redraw_plan()


# The open plan's END OF TURN rows and the corner HUD's air read the cached rules: re-resolve them now,
# as the Scenario page's weather picker does, rather than show what the rules said before the edit.
func _redraw_plan() -> void:
	if _game != null:
		_game.refresh_action_queue(_game.squad_manager.active_squad)
		_game.refresh_mission_status()


func _touch(resource: Resource) -> void:
	if not _touched.has(resource):
		_touched[resource] = resource.resource_path
	_refresh_dirty()


func _refresh_dirty() -> void:
	DevWidgets.mark_unsaved(_save, "Save", has_unsaved_changes())


func has_unsaved_changes() -> bool:
	return not _touched.is_empty()


func touched_files() -> PackedStringArray:
	var files := PackedStringArray(_touched.values())
	files.sort()
	return files


func _on_save_pressed() -> void:
	var files := touched_files()
	if files.is_empty():
		_status.text = "Nothing has moved off what is saved."
		return
	var shown := PackedStringArray()
	for path: String in files:
		shown.append(path.trim_prefix("res://"))
	if shown.size() > CONFIRM_LIST_MAX:
		var more := shown.size() - CONFIRM_LIST_MAX
		shown = shown.slice(0, CONFIRM_LIST_MAX)
		shown.append("...and %d more" % more)
	DevWidgets.confirm(self,
		"Write %d changed file(s)? The saved versions are lost.\n\n%s" % [files.size(), "\n".join(shown)],
		_save_now)


# A file whose write FAILED stays touched, so the marker keeps saying so and the next Save retries it.
func _save_now() -> void:
	var saved := PackedStringArray()
	var failed := PackedStringArray()
	for resource: Resource in _touched.keys():
		var path: String = _touched[resource]
		if DevWidgets.save_over(resource, path, _status):
			saved.append(path.get_file())
			_touched.erase(resource)
		else:
			failed.append(path.get_file())
	var parts := PackedStringArray()
	if not saved.is_empty():
		parts.append("Saved: %s" % ", ".join(saved))
	if not failed.is_empty():
		parts.append("FAILED: %s" % ", ".join(failed))
	_status.text = " | ".join(parts)
	_refresh_dirty()
