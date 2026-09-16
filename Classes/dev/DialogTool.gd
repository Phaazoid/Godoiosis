extends VBoxContainer
class_name DialogTool

# The Dialog & Tutorial page (#397): authoring for a scenario's #182 arrays -- dialog beats and
# tutorial steps -- which were the last mission content still edited in the Godot inspector.
# Edits write ScenarioManager's live stores DIRECTLY (the same arrays the armed director reads
# and capture_scenario saves), so a change is playable immediately and Update carries it.
# Rows rebuild whole on every structural edit: content is tiny, and rebuild-on-write cannot
# drift from the store. Timeline choices come from Dialogic's own dtl registry -- the one
# directory the editor plugin maintains -- never a second file scan.

var game   # the Game coordinator; set by init()
var _header: ScenarioHeader
var _beat_list: VBoxContainer
var _step_list: VBoxContainer

# --- the #982 timeline editor ---
# A timeline is PROJECT scope, like a roster: Save writes the file at once and registers it, while
# the BEAT that points at one is board content and still rides the header's Update. So this half
# keeps its own dirty flag and its own status line.
var _timeline_picker: OptionButton
var _line_list: VBoxContainer
var _name_field: LineEdit
var _save_button: Button
var _status: Label
var _lines: Array[Dictionary] = []      # [{speaker, text}] -- the working copy
var _loaded_name := ""                  # registry name of the timeline being edited; "" = new
var _loaded: DialogicTimeline = null    # the LOADED object, updated in place on save (see _save)
var _editable := true                   # false = a timeline this page cannot round-trip
var _timeline_dirty := false
var _speaker_panel: VBoxContainer
var _cast_picker: OptionButton
var _speaker_color := Color(0.85, 0.6, 0.25)

# done_when choices: the triggers a step can WAIT on. MISSION_START is the arming moment itself,
# STEP_COMPLETED is derived FROM steps, and PRE_MISSION_START is before the lesson is armed at all
# -- none of the three is a thing a step can watch for.
const STEP_TRIGGERS: Array[DialogBeat.Trigger] = [
	DialogBeat.Trigger.TURN_START,
	DialogBeat.Trigger.SQUAD_FORMED,
	DialogBeat.Trigger.UNIT_SELECTED,
	DialogBeat.Trigger.SQUAD_MEMBER_ADDED,
]


func init(p_game, header: ScenarioHeader) -> void:
	game = p_game
	_header = header
	_build_skeleton()
	refresh()


func refresh_on_show() -> void:
	refresh()


func _mark() -> void:
	if _header != null:
		_header.mark_modified()


func _beats() -> Array[DialogBeat]:
	return game.scenario_manager.current_dialog_beats


func _steps() -> Array[TutorialStep]:
	return game.scenario_manager.current_tutorial_steps


func _build_skeleton() -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	DevWidgets.add_label(vbox, "DIALOG BEATS")
	_beat_list = VBoxContainer.new()
	vbox.add_child(_beat_list)
	var add_beat := Button.new()
	add_beat.text = "Add beat"
	DevWidgets.apply_tooltip(add_beat, "A beat fires ONCE per battle when its trigger happens: "
		+ "a Dialogic timeline plays over the board. Beats are independent of each other. "
		+ "Pre mission start is the BRIEFING slot -- it plays over the bare board before the "
		+ "loadout screen opens, so a line about the map can still be acted on; it needs a "
		+ "roster, since a board with no pre-mission phase never reaches it.")
	add_beat.pressed.connect(_on_add_beat)
	vbox.add_child(add_beat)

	_build_timeline_section(vbox)

	DevWidgets.add_label(vbox, "TUTORIAL STEPS")
	_step_list = VBoxContainer.new()
	vbox.add_child(_step_list)
	var add_step := Button.new()
	add_step.text = "Add step"
	DevWidgets.apply_tooltip(add_step, "Steps are a SEQUENTIAL lesson: the active step's text "
		+ "shows on the mission-status HUD until its done-when fires, then the next activates. "
		+ "Order matters -- use the arrows.")
	add_step.pressed.connect(_on_add_step)
	vbox.add_child(add_step)


# --- timelines (#982) ---

func _build_timeline_section(vbox: VBoxContainer) -> void:
	DevWidgets.add_label(vbox, "TIMELINES")

	var top := HBoxContainer.new()
	_timeline_picker = OptionButton.new()
	_timeline_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	DevWidgets.apply_tooltip(_timeline_picker, "Pick a timeline to edit. One holding anything this "
		+ "page cannot write back -- a choice, a portrait, a conditional -- opens read-only and "
		+ "says so; edit that one in Dialogic's tab.")
	_timeline_picker.item_selected.connect(_on_timeline_picked)
	top.add_child(_timeline_picker)

	var new_button := Button.new()
	new_button.text = "New"
	DevWidgets.apply_tooltip(new_button, "Start an empty timeline. Nothing is written until Save.")
	new_button.pressed.connect(_on_new_timeline)
	top.add_child(new_button)

	var play := Button.new()
	play.text = "Play"
	DevWidgets.apply_tooltip(play, "Play the SAVED timeline over the board now, so you can hear it "
		+ "without walking a board to its trigger. It spends no beat. Refused while anything else "
		+ "is talking, and it plays in the GAME window -- click there to advance it.")
	play.pressed.connect(_on_play_timeline)
	top.add_child(play)

	var delete := Button.new()
	delete.text = "Delete"
	DevWidgets.apply_tooltip(delete, "Remove this timeline, its .uid and its registry entry. "
		+ "Refused while any mission still names it -- deleting one that is referenced turns that "
		+ "mission into a parse error, not a missing line.")
	delete.pressed.connect(_on_delete_timeline)
	top.add_child(delete)
	vbox.add_child(top)

	var name_row := HBoxContainer.new()
	var name_label := Label.new()
	name_label.text = "name"
	name_row.add_child(name_label)
	_name_field = LineEdit.new()
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	DevWidgets.apply_tooltip(_name_field, "The filename under Scenarios/dialog/, and the name the "
		+ "beat row's dropdown lists. Renaming here SAVES A SECOND FILE rather than moving one -- "
		+ "a rename has to repoint whatever references it, which only the editor can do.")
	name_row.add_child(_name_field)
	_save_button = Button.new()
	_save_button.text = "Save"
	DevWidgets.apply_tooltip(_save_button, "Write the timeline and register it. Immediate -- a "
		+ "timeline is project-scope like a roster. The BEAT that points at it is board content "
		+ "and still saves with the header's Update.")
	_save_button.pressed.connect(_on_save_timeline)
	name_row.add_child(_save_button)
	vbox.add_child(name_row)

	_line_list = VBoxContainer.new()
	vbox.add_child(_line_list)

	var add_line := Button.new()
	add_line.text = "Add line"
	DevWidgets.apply_tooltip(add_line, "One spoken line. The speaker list is the project's Dialogic "
		+ "characters -- (narration) is a line nobody is credited with.")
	add_line.pressed.connect(_on_add_line)
	vbox.add_child(add_line)

	var mint := Button.new()
	mint.text = "New speaker from cast..."
	DevWidgets.apply_tooltip(mint, "Make a Dialogic character out of a cast member, so they can "
		+ "speak. Name and portrait come FROM the unit -- colour is the one thing a speaker "
		+ "authors that the unit has no opinion on.")
	mint.pressed.connect(func() -> void:
		_speaker_panel.visible = not _speaker_panel.visible)
	vbox.add_child(mint)

	# INLINE rather than a dialog: a colour row belongs beside the cast pick, and the dev-tools
	# window is a real OS window that embeds its subwindows -- the ColorPicker family froze it
	# solid once already, so this stays plain sliders on the page.
	_speaker_panel = VBoxContainer.new()
	_speaker_panel.visible = false
	_build_speaker_panel(_speaker_panel)
	vbox.add_child(_speaker_panel)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_status)


# --- speakers (#982): a .dch MINTED from the cast ---

func _build_speaker_panel(panel: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "cast"
	row.add_child(label)
	_cast_picker = OptionButton.new()
	_cast_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	DevWidgets.apply_tooltip(_cast_picker, "The character file this speaker is made from. Their "
		+ "display name and portrait come from it, so who a character IS keeps one source.")
	row.add_child(_cast_picker)
	panel.add_child(row)

	DevWidgets.add_color(panel, "colour", Color(0.85, 0.6, 0.25), func(value: Color) -> void:
		_speaker_color = value)

	var create := Button.new()
	create.text = "Create speaker"
	create.pressed.connect(_on_mint_speaker)
	panel.add_child(create)


func _refresh_cast_picker() -> void:
	var names: Array = UnitCatalog.get_characters().keys()
	names.sort()
	_cast_picker.clear()
	_cast_picker.select(-1)
	for i in names.size():
		_cast_picker.add_item(String(names[i]), i)
	if not names.is_empty():
		_cast_picker.select(0)


func _on_mint_speaker() -> void:
	if _cast_picker.selected < 0:
		_status.text = "Pick a cast member first."
		return
	var chosen := _cast_picker.get_item_text(_cast_picker.selected)
	var unit_data := UnitCatalog.get_characters().get(chosen) as UnitData
	if unit_data == null:
		_status.text = "Could not read '%s'." % chosen
		return
	var identifier := DialogicSource.identifier_for(unit_data.display_name)
	if identifier == "":
		_status.text = "'%s' has no display name to make an identifier from." % chosen
		return
	if DialogicSource.directory("dch").has(identifier):
		_status.text = "'%s' already speaks -- they are in the speaker list." % identifier
		return
	var path := DialogicSource.character_path(identifier)
	if DevWidgets.refuse_existing_file(path, "speaker", _status):
		return
	var character := DialogicSource.character_from_cast(unit_data, _speaker_color)
	if not DialogicSource.write_character(character, path):
		_status.text = "Could not write %s." % path
		return
	if not DialogicSource.register("dch", identifier, path):
		_status.text = "Wrote %s but could not register it." % path
		return
	_speaker_panel.visible = false
	_status.text = "'%s' can speak now." % identifier
	_refresh_lines()   # every speaker dropdown rebuilds off the registry


func _refresh_timeline_picker() -> void:
	var names: Array = DialogicSource.directory("dtl").keys()
	names.sort()
	_timeline_picker.clear()
	_timeline_picker.select(-1)   # add_item auto-selects the first entry; a stale name must not stick
	for i in names.size():
		_timeline_picker.add_item(String(names[i]), i)
		if String(names[i]) == _loaded_name:
			_timeline_picker.select(i)


func _refresh_lines() -> void:
	for child in _line_list.get_children():
		child.queue_free()
	if not _editable:
		return
	for i in _lines.size():
		_line_list.add_child(_line_row(i))
	if _lines.is_empty():
		DevWidgets.add_label(_line_list, "  (no lines -- Add line, or pick a timeline above)")
	DevWidgets.mark_unsaved(_save_button, "Save", _timeline_dirty)


func _line_row(index: int) -> HBoxContainer:
	var row := HBoxContainer.new()

	var speaker := OptionButton.new()
	var ids: Array = DialogicSource.directory("dch").keys()
	ids.sort()
	speaker.add_item("(narration)", 0)
	var chosen := 0
	for i in ids.size():
		speaker.add_item(String(ids[i]), i + 1)
		if String(ids[i]) == String(_lines[index]["speaker"]):
			chosen = i + 1
	speaker.select(chosen)
	DevWidgets.apply_tooltip(speaker, "Who says this. A dropdown rather than a field because a "
		+ "speaker no character answers to invents a nameless one at runtime, and CI refuses it.")
	speaker.item_selected.connect(func(item: int) -> void:
		_lines[index]["speaker"] = "" if item == 0 else speaker.get_item_text(item)
		_mark_timeline())
	row.add_child(speaker)

	var text := LineEdit.new()
	text.text = String(_lines[index]["text"])
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text_changed.connect(func(value: String) -> void:
		_lines[index]["text"] = value
		_mark_timeline())
	row.add_child(text)

	var up := Button.new()
	up.text = "^"
	up.disabled = index == 0
	up.pressed.connect(func() -> void: _move_line(index, -1))
	row.add_child(up)
	var down := Button.new()
	down.text = "v"
	down.disabled = index == _lines.size() - 1
	down.pressed.connect(func() -> void: _move_line(index, 1))
	row.add_child(down)

	row.add_child(_remove_button(func() -> void:
		_lines.remove_at(index)
		_mark_timeline()
		_refresh_lines()))
	return row


func _move_line(index: int, delta: int) -> void:
	var line: Dictionary = _lines[index]
	_lines.remove_at(index)
	_lines.insert(index + delta, line)
	_mark_timeline()
	_refresh_lines()


func _mark_timeline() -> void:
	_timeline_dirty = true
	DevWidgets.mark_unsaved(_save_button, "Save", true)


func _on_add_line() -> void:
	_lines.append({"speaker": DialogicSource.NARRATION, "text": ""})
	_editable = true
	_mark_timeline()
	_refresh_lines()


func _on_new_timeline() -> void:
	_loaded_name = ""
	_loaded = null
	_lines.clear()
	_editable = true
	_timeline_dirty = false
	_name_field.text = _suggested_name()
	_timeline_picker.select(-1)
	_status.text = ""
	_refresh_lines()


# The board's own name plus the briefing suffix the five shipped timelines use, so the common case
# is one keystroke. Only a suggestion -- the field is editable.
func _suggested_name() -> String:
	var path := String(game.scenario_manager.last_loaded_path)
	if path == "":
		return ""
	return ScenarioManager.display_name(path).to_snake_case() + "_intro"


func _on_timeline_picked(item: int) -> void:
	var name := _timeline_picker.get_item_text(item)
	var path := String(DialogicSource.directory("dtl").get(name, ""))
	var timeline := load(path) as DialogicTimeline
	var read := DialogicSource.read_timeline(timeline)
	_loaded_name = name
	_loaded = timeline
	_name_field.text = name
	_timeline_dirty = false
	_editable = bool(read["editable"])
	_lines.clear()
	for line: Dictionary in read["lines"]:
		_lines.append(line.duplicate())
	_status.text = String(read["reason"])
	_refresh_lines()


func _on_save_timeline() -> void:
	var name := _name_field.text.strip_edges()
	if name == "":
		_status.text = "Give the timeline a name first."
		return
	if not _editable:
		_status.text = "This timeline is not editable here, so saving would drop what it holds."
		return
	var path := DialogicSource.timeline_path(name)
	var known := DialogicSource.directory("dtl").has(name)
	if not known and DevWidgets.refuse_existing_file(path, "timeline", _status):
		return
	if known and name != _loaded_name:
		_status.text = "'%s' already exists -- load it and save over it, or pick another name." % name
		return
	if known:
		DevWidgets.confirm_overwrite(self, name, "what is on screen",
			func() -> void: _write_timeline(name, path, true))
		return
	_write_timeline(name, path, false)


# The LOADED object is updated in place rather than reloaded, because DialogBeat.timeline holds a
# REFERENCE: load() would serve the same cached object anyway, and building a fresh one would
# leave every beat pointing at the pre-edit copy. A new file has no such holder, so it loads.
func _write_timeline(name: String, path: String, known: bool) -> void:
	var text := DialogicSource.timeline_text(_lines)
	if not DialogicSource.write(path, text):
		_status.text = "Could not write %s." % path
		return
	if not known and not DialogicSource.register("dtl", name, path):
		_status.text = "Wrote %s but could not register it -- the beat list will not see it." % path
		return
	if known and _loaded != null:
		_loaded.from_text(text)
		_loaded.process()
	else:
		_loaded = load(path) as DialogicTimeline
	_loaded_name = name
	_timeline_dirty = false
	_status.text = "Saved '%s'." % name
	refresh()   # the beat rows' dropdown reads the registry, so it has to rebuild too


func _on_play_timeline() -> void:
	if _loaded == null:
		_status.text = "Save the timeline first -- Play plays what is on disk."
		return
	if _timeline_dirty:
		_status.text = "Unsaved changes -- Play plays the saved version."
	if not game.scenario_director.preview(_loaded):
		_status.text = "Something is already talking. Let it finish, then press Play."
		return
	if not PlayerSettings.is_on(PlayerSettings.Setting.SHOW_DIALOG):
		_status.text = "Playing '%s'. (Dialog is switched off for the player, but Play ignores that.)" % _loaded_name


func _on_delete_timeline() -> void:
	if _loaded_name == "":
		_status.text = "Pick a saved timeline to delete."
		return
	var victim := _loaded_name
	DevWidgets.confirm_delete(self, victim, func() -> void:
		var verdict := DialogicSource.delete("dtl", victim)
		if not bool(verdict["ok"]):
			_status.text = String(verdict["reason"])
			return
		_on_new_timeline()
		_status.text = "Deleted '%s'." % victim
		refresh())


func refresh() -> void:
	_refresh_timeline_picker()
	_refresh_cast_picker()
	_refresh_lines()
	for child in _beat_list.get_children():
		child.queue_free()
	for child in _step_list.get_children():
		child.queue_free()
	var beats := _beats()
	for i in beats.size():
		_beat_list.add_child(_beat_row(beats[i], i))
	if beats.is_empty():
		DevWidgets.add_label(_beat_list, "  (no beats -- this mission plays silent)")
	var steps := _steps()
	for i in steps.size():
		_step_list.add_child(_step_row(steps[i], i))
	if steps.is_empty():
		DevWidgets.add_label(_step_list, "  (no steps -- no lesson on this mission)")


func _on_add_beat() -> void:
	_beats().append(DialogBeat.new())
	_mark()
	refresh()


func _on_add_step() -> void:
	_steps().append(TutorialStep.new())
	_mark()
	refresh()


# --- beat rows ---

func _beat_row(beat: DialogBeat, index: int) -> HBoxContainer:
	var row := HBoxContainer.new()

	var trigger := OptionButton.new()
	for value: int in DialogBeat.Trigger.values():
		trigger.add_item(String(DialogBeat.Trigger.keys()[value]).capitalize(), value)
	trigger.select(trigger.get_item_index(beat.trigger))
	DevWidgets.apply_tooltip(trigger, "When this beat fires. Step completed = when the lesson "
		+ "advances past step N (the payoff voice).")
	trigger.item_selected.connect(func(item_index: int) -> void:
		beat.trigger = trigger.get_item_id(item_index) as DialogBeat.Trigger
		_mark()
		refresh())   # the conditional param below follows the trigger
	row.add_child(trigger)

	if beat.trigger == DialogBeat.Trigger.TURN_START:
		row.add_child(_int_field("turn", beat.turn, 1, func(value: int) -> void:
			beat.turn = value
			_mark()))
	if beat.trigger == DialogBeat.Trigger.STEP_COMPLETED:
		row.add_child(_int_field("step", beat.step, 1, func(value: int) -> void:
			beat.step = value
			_mark()))

	var timeline := OptionButton.new()
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.add_item("(no timeline)", 0)
	var directory := DialogicSource.directory("dtl")
	var names: Array = directory.keys()
	names.sort()
	var selected := 0
	for i in names.size():
		timeline.add_item(names[i], i + 1)
		if beat.timeline != null and beat.timeline.resource_path == String(directory[names[i]]):
			selected = i + 1
	timeline.select(selected)
	DevWidgets.apply_tooltip(timeline, "The Dialogic timeline this beat plays -- Dialogic's own "
		+ "registry (every .dtl the project knows). A beat with no timeline fires into nothing; "
		+ "Check board flags it.")
	timeline.item_selected.connect(func(item_index: int) -> void:
		if item_index == 0:
			beat.timeline = null
		else:
			beat.timeline = load(String(directory[timeline.get_item_text(item_index)])) as DialogicTimeline
		_mark())
	row.add_child(timeline)

	row.add_child(_remove_button(func() -> void:
		_beats().remove_at(index)
		_mark()
		refresh()))
	return row


# --- step rows ---

func _step_row(step: TutorialStep, index: int) -> HBoxContainer:
	var row := HBoxContainer.new()

	var text := LineEdit.new()
	text.text = step.text
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	DevWidgets.apply_tooltip(text, "The instruction shown on the mission-status HUD while this "
		+ "step is active.")
	text.text_changed.connect(func(value: String) -> void:
		step.text = value
		_mark())
	row.add_child(text)

	var done := OptionButton.new()
	for trigger in STEP_TRIGGERS:
		done.add_item(String(DialogBeat.Trigger.keys()[trigger]).capitalize(), trigger)
	done.select(done.get_item_index(step.done_when))
	DevWidgets.apply_tooltip(done, "What completes this step and activates the next.")
	done.item_selected.connect(func(item_index: int) -> void:
		step.done_when = done.get_item_id(item_index) as DialogBeat.Trigger
		_mark()
		refresh())   # which params show follows the choice
	row.add_child(done)

	if step.done_when != DialogBeat.Trigger.TURN_START:
		var unit_name := LineEdit.new()
		unit_name.text = step.unit_name
		unit_name.placeholder_text = "any unit"
		unit_name.custom_minimum_size.x = 90
		DevWidgets.apply_tooltip(unit_name, "Match against a unit's display name (the squad "
			+ "LEADER for squad triggers). Empty = any. A name no board unit carries stalls the "
			+ "lesson -- Check board flags it.")
		unit_name.text_changed.connect(func(value: String) -> void:
			step.unit_name = value
			_mark())
		row.add_child(unit_name)
	if step.done_when == DialogBeat.Trigger.SQUAD_MEMBER_ADDED:
		row.add_child(_int_field("size", step.squad_size, 0, func(value: int) -> void:
			step.squad_size = value
			_mark()))
	if step.done_when == DialogBeat.Trigger.TURN_START:
		row.add_child(_int_field("turn", step.turn, 1, func(value: int) -> void:
			step.turn = value
			_mark()))

	var up := Button.new()
	up.text = "^"
	up.disabled = index == 0
	up.pressed.connect(func() -> void: _move_step(index, -1))
	row.add_child(up)
	var down := Button.new()
	down.text = "v"
	down.disabled = index == _steps().size() - 1
	down.pressed.connect(func() -> void: _move_step(index, 1))
	row.add_child(down)

	row.add_child(_remove_button(func() -> void:
		_steps().remove_at(index)
		_mark()
		refresh()))
	return row


func _move_step(index: int, delta: int) -> void:
	var steps := _steps()
	var step: TutorialStep = steps[index]
	steps.remove_at(index)
	steps.insert(index + delta, step)
	_mark()
	refresh()


# --- small shared pieces ---

func _int_field(label_text: String, initial: int, minimum: int, on_change: Callable) -> HBoxContainer:
	var box := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	box.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = 99
	spin.value = initial
	spin.value_changed.connect(func(value: float) -> void: on_change.call(int(value)))
	box.add_child(spin)
	return box


func _remove_button(on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = "x"
	DevWidgets.apply_tooltip(button, "Remove this row. No confirm -- Update is where the file is "
		+ "at stake, and it asks.")
	button.pressed.connect(on_pressed)
	return button


# ONE reader, DialogicSource's -- the registry is also what the timeline editor above writes,
# and a second spelling here would disagree with it the moment one of them learns something.
