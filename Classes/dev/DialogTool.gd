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

# done_when choices: the triggers a step can WAIT on. MISSION_START is the arming moment itself
# and STEP_COMPLETED is derived FROM steps -- neither is a thing a step can watch for.
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
		+ "a Dialogic timeline plays over the board. Beats are independent of each other.")
	add_beat.pressed.connect(_on_add_beat)
	vbox.add_child(add_beat)

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


func refresh() -> void:
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
	var directory := _timeline_directory()
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


func _timeline_directory() -> Dictionary:
	return ProjectSettings.get_setting("dialogic/directories/dtl_directory", {})
