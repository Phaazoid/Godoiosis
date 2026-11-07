extends VBoxContainer
class_name AirGasTool

# The Air & gas page (#1534): the air's and the gases' balance numbers, tuned LIVE. Three kinds of rules
# file, each the object every reader already holds (cached per path), so a slider moves the rule at once:
#   The air  -- AtmosphereRules: each ambient substance's Normal and its step.
#   A gas    -- its GasRules: how long it lingers, the level its state starts at, its scald, its air.
#   Its state -- when a gas gives a PAIRED state (smoke's Smoked), that state's StateRules stat change.
# WeatherTool's shape: Save writes every touched file through DevWidgets.save_over, asking first; Reset
# re-reads each from DISK. Every edit re-resolves the open plan, so the forecast shows the new rule.
#
# Not tuned here: a gas's state, while_standing and insulation (what it IS, one read-only line), a
# paired state's clock (read only when something ADDS the state, and nothing does: #1421 lays a cloud),
# and a gas with no rules file.

const AIR_ID := 100   # the picker's entry for the air, past every Gas.Kind
const CONFIRM_LIST_MAX := 12   # WeatherTool's
const LEVELS: Array[Gas.Level] = [Gas.Level.THIN, Gas.Level.MEDIUM, Gas.Level.THICK]
const LEVEL_NAMES: Array[String] = ["Thin", "Medium", "Thick"]

var _game   # untyped back-ref: game.gd has no class_name
var _picker: OptionButton
var _save: Button
var _reset: Button
var _status: Label
var _rows: VBoxContainer
var _shown := AIR_ID   # AIR_ID, or the Gas.Kind on show
# Touched since the last save: each edited rules resource -> the file it saves to.
var _touched: Dictionary[Resource, String] = {}


func init(game) -> void:
	_game = game
	var head := HBoxContainer.new()
	add_child(head)
	var label := Label.new()
	label.text = "Show"
	head.add_child(label)
	_picker = OptionButton.new()
	_picker.add_item("The air", AIR_ID)
	_picker.add_separator()
	for kind: Gas.Kind in Gas.Kind.values():
		if GasRules.for_kind(kind) != null:
			_picker.add_item("Gas: " + Gas.display_name(kind), kind)
	_picker.item_selected.connect(func(index: int) -> void: show_entry(_picker.get_item_id(index)))
	head.add_child(_picker)
	DevWidgets.apply_tooltip(_picker, DevWidgets.wrap_tooltip(
		"The air every board starts from, or one gas's rules. A gas with no rules file lies where it "
		+ "is put and never moves, so it is not listed."))
	_save = Button.new()
	_save.text = "Save"
	_save.pressed.connect(_on_save_pressed)
	head.add_child(_save)
	DevWidgets.apply_tooltip(_save, DevWidgets.wrap_tooltip(
		"Write every rules file changed on this page since the last save, whichever is on show. "
		+ "Asks first: the saved versions are lost."))
	_reset = Button.new()
	_reset.text = "Reset"
	_reset.pressed.connect(_on_reset_pressed)
	head.add_child(_reset)
	DevWidgets.apply_tooltip(_reset, DevWidgets.wrap_tooltip(
		"Put every rules file changed on this page back to what is saved on disk, whichever is on "
		+ "show. Greyed while nothing has moved."))
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	_rows = DevWidgets.add_knob_scroll(self)
	show_entry(AIR_ID)


# On every show: re-read the files, in case the inspector moved one.
func refresh_on_show() -> void:
	if _rows != null:
		_fill()


# AIR_ID or a Gas.Kind with a rules file.
func show_entry(id: int) -> void:
	_shown = id
	_picker.select(_picker.get_item_index(id))
	_status.text = ""
	_fill()
	_refresh_dirty()


func _fill() -> void:
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	if _shown == AIR_ID:
		_fill_air()
	else:
		_fill_gas(_shown as Gas.Kind)


func _note(text: String) -> void:
	var note := Label.new()
	note.text = text
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(note)


func _fill_air() -> void:
	var rules := AtmosphereRules.authored()
	_note("The air every board starts from. A substance a board does not author reads Normal, and each "
		+ "step away from Normal adds (or takes) one damage on a carving that draws it.")
	for group: String in Atmosphere.GROUPS:
		DevWidgets.add_heading(_rows, group)
		for id: String in Atmosphere.GROUPS[group]:
			var said := SubstanceCatalog.name_of(id)
			var readout := Label.new()
			DevWidgets.add_knob_row(_rows, {"label": said + ": Normal %", "min": 0, "max": 100, "step": 1},
				Atmosphere.normal_of(id),
				func(value: Variant) -> void: _write_table(rules, rules.normal, id, int(value), readout),
				DevWidgets.wrap_tooltip("The %s a board reads when it does not author its own. A "
					% said.to_lower() + "board's reading is on Scenario > Properties; a weather or a gas "
					+ "moves it from there."))
			DevWidgets.add_knob_row(_rows, {"label": said + ": points per step", "min": 1, "max": 50, "step": 1},
				Atmosphere.step_of(id),
				func(value: Variant) -> void: _write_table(rules, rules.step, id, int(value), readout),
				DevWidgets.wrap_tooltip("How many points of %s away from Normal make one step. A "
					% said.to_lower() + "carving that draws it hits one harder per step above Normal and "
					+ "one softer per step below. Steps are whole: a part step counts for nothing."))
			readout.text = _steps_text(id)
			_rows.add_child(readout)


# Where a substance first reads one step off Normal, both ways: "+1 at 85%, -1 at 65%".
static func _steps_text(id: String) -> String:
	var normal := Atmosphere.normal_of(id)
	var step := Atmosphere.step_of(id)
	var parts: Array[String] = []
	if normal + step <= 100:
		parts.append("+1 at %d%%" % (normal + step))
	if normal - step >= 0:
		parts.append("-1 at %d%%" % (normal - step))
	return "      " + (", ".join(parts) if not parts.is_empty() else "no step fits between 0% and 100%")


func _fill_gas(kind: Gas.Kind) -> void:
	var rules := GasRules.for_kind(kind)
	if rules == null:
		return
	_note(_what_it_is(kind, rules))
	DevWidgets.add_heading(_rows, "How long it lingers")
	DevWidgets.add_knob_row(_rows, {"label": "Rounds per level", "min": 1, "max": 4, "step": 1},
		rules.hold_rounds, func(value: Variant) -> void: _write(rules, "hold_rounds", int(value)),
		DevWidgets.wrap_tooltip("How many rounds a cell holds a level before it thins one step. Thin "
			+ "gas that thins is gone. Four is the most the cell can count."))
	if rules.state != Elemental.State.NONE:
		var state := Elemental.state_display_name(rules.state)
		DevWidgets.add_heading(_rows, state)
		DevWidgets.add_knob_row(_rows, {"label": "From level", "options": LEVEL_NAMES},
			LEVELS.find(rules.state_from),
			func(index: Variant) -> void: _write(rules, "state_from", int(LEVELS[int(index)])),
			DevWidgets.wrap_tooltip("The thinnest level of this gas that gives %s. Anything thinner "
				% state + "is harmless."))
		var state_rules := StateRules.for_state(rules.state)
		if state_rules != null and not Elemental.paired_stat_mods(rules.state).is_empty():
			for stat: Stats.Stat in state_rules.stat_mods:
				var stat_name: String = Stats.Stat.keys()[stat]
				DevWidgets.add_knob_row(_rows,
					{"label": "%s: %s change" % [state, stat_name], "min": -10, "max": 10, "step": 1},
					state_rules.stat_mods[stat],
					func(value: Variant) -> void: _write_table(state_rules, state_rules.stat_mods, stat, int(value)),
					DevWidgets.wrap_tooltip("What %s does to %s while it is held, however the unit "
						% [state, stat_name] + "came by it. Saved in %s." % state_rules.resource_path.get_file()))
	DevWidgets.add_heading(_rows, "Scald at the end of its side's turn")
	for i in LEVELS.size():
		var level := LEVELS[i]
		DevWidgets.add_knob_row(_rows, {"label": "Damage at " + LEVEL_NAMES[i], "min": 0, "max": 10, "step": 1},
			int(rules.damage.get(level, 0)),
			func(value: Variant) -> void: _write_sparse(rules, rules.damage, level, int(value)),
			DevWidgets.wrap_tooltip("What a unit still standing in %s gas takes when its own side's "
				% LEVEL_NAMES[i].to_lower() + "turn ends. A tile hit like fire's burn: no armour, no "
				+ "reaction, no limb. Zero deals nothing."))
	DevWidgets.add_heading(_rows, "Air, per level")
	for id: String in Atmosphere.SUBSTANCES:
		var said := SubstanceCatalog.name_of(id)
		DevWidgets.add_knob_row(_rows, {"label": said, "min": -50, "max": 50, "step": 1},
			int(rules.air.get(id, 0)),
			func(value: Variant) -> void: _write_sparse(rules, rules.air, id, int(value)),
			DevWidgets.wrap_tooltip("Percentage points of %s this gas adds to the air of the cell it "
				% said.to_lower() + "lies on, for each level (negative lowers it). One step is %d points."
				% Atmosphere.step_of(id)))


# What the gas IS, which this page does not tune: its state, how it gives it, and what stops its scald.
static func _what_it_is(kind: Gas.Kind, rules: GasRules) -> String:
	var said := Gas.display_name(kind)
	var line: String
	if rules.state == Elemental.State.NONE:
		line = "%s gives no state." % said
	elif rules.while_standing:
		line = "%s: a unit standing in it is %s for as long as it stays." \
			% [said, Elemental.state_display_name(rules.state)]
	else:
		line = "%s: a unit still in it when its side's turn ends is left %s." \
			% [said, Elemental.state_display_name(rules.state)]
	if rules.damage_element != Elemental.Element.NONE:
		line += " %s insulation stops its scald." % Elemental.display_name(rules.damage_element)
	return line


# Into a live rules file's own field.
func _write(resource: Resource, prop: String, value: int) -> void:
	resource.set(prop, value)
	_changed(resource)


# Into one key of a table a row always names (Normal, a step, a stat change), with the air's readout.
func _write_table(resource: Resource, table: Dictionary, key: Variant, value: int, readout: Label = null) -> void:
	table[key] = value
	if readout != null:
		readout.text = _steps_text(String(key))
	_changed(resource)


# Into a table that names only what moves (a scald, a gas's air): zero erases, so the file stays sparse.
func _write_sparse(resource: Resource, table: Dictionary, key: Variant, value: int) -> void:
	if value == 0:
		table.erase(key)
	else:
		table[key] = value
	_changed(resource)


func _changed(resource: Resource) -> void:
	resource.emit_changed()
	if not _touched.has(resource):
		_touched[resource] = resource.resource_path
	_refresh_dirty()
	_redraw()


# Every reader holds the edited object, but the open plan, the corner HUD's air and the Glossary's text
# were derived from the old rule: re-derive them now (AlchemyTool.redraw_plan also drops the enemy
# ranges, which a leash or a carving's damage can move). The hover repaints last, for the pointer
# left on the board: the leash ring and an aim's forecast redraw only on a cell change otherwise.
func _redraw() -> void:
	Glossary.refresh()
	if _game == null:
		return
	AlchemyTool.redraw_plan(_game)
	_game.refresh_mission_status()
	_game.hover_presenter.refresh()


func _refresh_dirty() -> void:
	DevWidgets.mark_unsaved(_save, "Save", has_unsaved_changes())
	DevWidgets.offer_reset(_reset, has_unsaved_changes())


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
	_report(saved, failed, "Saved: %s")
	_refresh_dirty()


# Save's mirror: every touched file re-read from DISK onto the object every reader holds. A file that
# will not read stays touched, as on Save.
func _on_reset_pressed() -> void:
	var reset := PackedStringArray()
	var failed := PackedStringArray()
	for resource: Resource in _touched.keys():
		var path: String = _touched[resource]
		if DevWidgets.revert_to_saved(resource, path, _status):
			reset.append(path.get_file())
			_touched.erase(resource)
		else:
			failed.append(path.get_file())
	_fill()
	_refresh_dirty()
	if not reset.is_empty():
		_redraw()
	_report(reset, failed, "Back to disk: %s")


func _report(done: PackedStringArray, failed: PackedStringArray, done_text: String) -> void:
	var parts := PackedStringArray()
	if not done.is_empty():
		parts.append(done_text % ", ".join(done))
	if not failed.is_empty():
		parts.append("FAILED: %s" % ", ".join(failed))
	_status.text = " | ".join(parts)
