extends VBoxContainer
class_name AlchemyReactions

# THE ALCHEMY PAGE'S REACTIONS TAB (#1532, AlchemyTool hosts it): one WHOLE reaction at a time, a unit's
# (ElementalReaction) or the ground's (TerrainReaction) -- what sets it off, what it does, what it
# releases, its equation and how it shows (dev ruling E: whole reactions, so a Save As copy can mean
# something different from the reaction it copied).
#
# IT EDITS A COPY, AlchemySubstances' idiom: Load duplicates, Update writes back through
# DevWidgets.save_over and asks first, Save As writes a new reaction of the same kind, which fires in
# play at once -- its catalog is refreshed, and a ground reaction re-composes the board's fuel through
# TerrainReactionCatalog.rescan, the door the Tiles page's burnable tick uses.
#
# The form is drawn in the sections the RESOURCE declares (property_sections). A field is routed by its
# type: an Array[enum] to DevWidgets.add_enum_ticks, an enum -> int map to add_enum_number_map, the
# icon to a read-only line (no picker can choose a texture), everything else to add_property_row. Members
# a resource retires (TerrainReaction.property_retired) are never offered.
#
# The equation's readout is what CI checks (tests/dev/test_reaction_lint.gd): ReactionLint.check, plus
# unreleased_gases and unapplied_states. Nothing in play reads an equation, so Update NEVER refuses one
# (dev ruling at the mock, 2026-10-31); the readout says before a save what CI will say after it.
#
# There is NO Delete, for the reason the Substances tab has none.

const WARN_COLOR := AlchemySubstances.WARN_COLOR
const GOOD_COLOR := AlchemySubstances.GOOD_COLOR
const UNIT := "Unit"
const GROUND := "Ground"
const EQUATION_WIDTH := 380
const NO_EQUATION := ("No equation. Saved like this, CI goes red until it has one, or a line in the lint's "
	+ "PENDING ledger saying what it waits on (tests/dev/test_reaction_lint.gd).")

# The folders Save As writes into, one per kind. A test aims them at user://.
var unit_dir := ReactionCatalog.REACTION_DIR
var ground_dir := TerrainReactionCatalog.REACTION_DIR

var current: Resource = null   # the COPY the form edits: an ElementalReaction or a TerrainReaction
var picker: OptionButton
var load_button: Button
var update_button: Button
var name_input: LineEdit
var save_as_button: Button
var status_label: Label

var _game = null
var _loaded := ""   # the loaded entry's key, "<kind>/<id>"
var _dirty := false
var _entries: Array[Dictionary] = []   # picker index -> {kind, id, reaction}
var _form: VBoxContainer
var _equation_readout: VBoxContainer


func _ready() -> void:
	var top := HBoxContainer.new()
	add_child(top)
	picker = OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.item_selected.connect(func(_index: int) -> void: _refresh_buttons())
	top.add_child(picker)
	load_button = Button.new()
	load_button.text = "Load"
	load_button.tooltip_text = "Put the picked reaction into the form, as a copy: nothing moves in play until you save."
	load_button.pressed.connect(_load_selected)
	top.add_child(load_button)
	update_button = Button.new()
	update_button.text = "Update"
	update_button.pressed.connect(_on_update_pressed)
	top.add_child(update_button)
	var second := HBoxContainer.new()
	add_child(second)
	name_input = LineEdit.new()
	name_input.placeholder_text = "new reaction name"
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	second.add_child(name_input)
	save_as_button = Button.new()
	save_as_button.text = "Save As"
	save_as_button.tooltip_text = "Write the form as a new reaction of the same kind, named by the file name typed beside. It fires in play at once."
	save_as_button.pressed.connect(_on_save_as_pressed)
	second.add_child(save_as_button)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)
	var note := Label.new()
	note.text = ("A whole reaction, on a unit or on the ground. Edit a loaded copy: Update writes it back and "
		+ "asks first, Save As writes a new reaction of the same kind, which fires in play at once.")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_color_override("font_color", AlchemySources.NOTE_COLOR)
	add_child(note)
	_form = DevWidgets.add_knob_scroll(self)
	_refresh_list()
	if picker.item_count > 0:
		picker.select(0)
		_load_selected()
	_refresh_buttons()


func init(game) -> void:
	_game = game


# A reaction file may have come or gone (a Save As here, the Tiles page's burnable tick): re-list,
# keeping the copy in the form.
func refresh_on_show() -> void:
	_refresh_list(_loaded)


func is_dirty() -> bool:
	return _dirty


static func kind_of(reaction: Resource) -> String:
	return UNIT if reaction is ElementalReaction else GROUND


static func _key(kind: String, id: String) -> String:
	return "%s/%s" % [kind, id]


func _refresh_list(select_key := "") -> void:
	picker.clear()
	_entries.clear()
	var all: Array[Resource] = []
	all.append_array(ReactionCatalog.get_all())
	all.append_array(TerrainReactionCatalog.get_all())
	for reaction: Resource in all:
		var id := reaction.resource_path.get_file().get_basename()
		var kind := kind_of(reaction)
		_entries.append({"kind": kind, "id": id, "reaction": reaction})
		picker.add_item("%s  ·  %s   \"%s\"" % [kind, id, reaction.get("popup")])
	picker.select(-1)   # add_item auto-selects index 0 -- Update must never aim at an entry nobody picked
	for i in _entries.size():
		if _key(_entries[i]["kind"], _entries[i]["id"]) == select_key:
			picker.select(i)
			break
	_refresh_buttons()


func _selected() -> Dictionary:
	return _entries[picker.selected] if picker.selected >= 0 and picker.selected < _entries.size() else {}


func _selected_key() -> String:
	var entry := _selected()
	return "" if entry.is_empty() else _key(entry["kind"], entry["id"])


func _load_selected() -> void:
	var entry := _selected()
	if entry.is_empty():
		return
	_hold((entry["reaction"] as Resource).duplicate(true), _selected_key())


func _hold(copy: Resource, key: String) -> void:
	if current != null and current.changed.is_connected(_on_edited):
		current.changed.disconnect(_on_edited)
	current = copy
	_loaded = key
	_dirty = false
	current.changed.connect(_on_edited)
	_populate()
	_refresh_buttons()


func _populate() -> void:
	for child in _form.get_children():
		_form.remove_child(child)
		child.queue_free()
	_equation_readout = null
	for section: Dictionary in current.call("property_sections"):
		DevWidgets.add_heading(_form, section["title"])
		for field: String in section["fields"]:
			_draw_field(field)
	_refresh_readout()


func _draw_field(field: String) -> void:
	var prop := DevWidgets.exported_property(current, field)
	if prop.is_empty():
		return
	var reaction := current
	var label := field.capitalize()
	var skip := DevWidgets.retired_values(reaction, field)
	var read := func() -> Variant: return reaction.get(field)
	var write := func(value: Variant) -> void: DevWidgets.write(reaction, field, value)
	var row: Control = null
	if DevWidgets.is_enum_array(prop):
		row = DevWidgets.add_enum_ticks(_form, label, prop.hint_string, read, write, skip)
	elif DevWidgets.is_enum_number_map(prop):
		row = DevWidgets.add_enum_number_map(_form, label, prop.hint_string, read, write, skip, "turns",
			"+ add a state", unlisted_note(reaction))
	elif field == "icon":
		row = _icon_line(reaction.get(field) as Texture2D)
	else:
		var nodes := DevWidgets.add_property_row(_form, reaction, field, _populate)
		if field == "equation":
			AlchemySubstances.widen_edits(nodes, EQUATION_WIDTH)
			_equation_readout = VBoxContainer.new()
			_form.add_child(_equation_readout)
	if row != null:
		DevWidgets.apply_tooltip(row, DevWidgets.property_tip(reaction, field))


# What an added state with no listed length does, which is the one thing the two kinds disagree on.
static func unlisted_note(reaction: Resource) -> String:
	if reaction is ElementalReaction:
		return "unlisted: the state's own length"
	return "unlisted: lasts until something removes it"


func _icon_line(icon: Texture2D) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Icon"
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	var value := Label.new()
	value.text = "%s   (set in Godot's own inspector: this form cannot pick a texture)" % (
		icon.resource_path.get_file() if icon != null and icon.resource_path != "" else "none")
	value.add_theme_color_override("font_color", AlchemySources.EMPTY_COLOR)
	value.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(value)
	_form.add_child(row)
	return row


# Every row writes through DevWidgets.write, which emits `changed`: the one signal.
func _on_edited() -> void:
	_dirty = true
	_refresh_readout()
	_refresh_buttons()


func _refresh_readout() -> void:
	if _equation_readout == null:
		return
	for child in _equation_readout.get_children():
		_equation_readout.remove_child(child)
		child.queue_free()
	for line: Dictionary in readout_lines(current):
		var label := Label.new()
		label.text = line["text"]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color", line["color"])
		_equation_readout.add_child(label)


# What CI will say about this reaction once it is saved, as {text, color} lines, from the lint's own calls.
static func readout_lines(reaction: Resource) -> Array[Dictionary]:
	var lines: Array[Dictionary] = []
	var equation := String(reaction.get("equation")).strip_edges()
	if equation == "":
		lines.append({"text": NO_EQUATION, "color": WARN_COLOR})
		return lines
	var findings := ReactionLint.check(reaction)
	var blocked := false
	for finding: Dictionary in findings:
		blocked = blocked or finding["severity"] == ReactionLint.Severity.BLOCKS
	if not blocked:
		var inputs := AlchemyFormula.side(equation.split(AlchemyFormula.ARROW)[0], SubstanceCatalog.get_all())
		lines.append({"text": "Balanced: each side holds %s" % AlchemyFormula.format_atoms(inputs.counts),
			"color": GOOD_COLOR})
	for finding: Dictionary in findings:
		var blocks: bool = finding["severity"] == ReactionLint.Severity.BLOCKS
		lines.append({"text": "%s   %s" % ["BLOCKS" if blocks else "DEGRADES", finding["text"]],
			"color": AlchemySources.BAD_COLOR if blocks else WARN_COLOR})
	for kind: Gas.Kind in ReactionLint.unreleased_gases(reaction):
		lines.append({"text": ("Makes %s, which this reaction never releases: CI goes red unless the lint's "
			+ "NOT_YET_FOLLOWED ledger lists it.") % Gas.display_name(kind).to_lower(), "color": WARN_COLOR})
	for state: Elemental.State in ReactionLint.unapplied_states(reaction):
		lines.append({"text": "Leaves %s on the body, which this reaction never applies: CI goes red until it does."
			% Elemental.state_display_name(state), "color": WARN_COLOR})
	if not findings.is_empty():
		lines.append({"text": "CI goes red on any BLOCKS or DEGRADES line once this is saved.",
			"color": AlchemySources.EMPTY_COLOR})
	return lines


func _refresh_buttons() -> void:
	DevWidgets.refresh_update_button(update_button, _selected_key(), "reaction", _update_block_reason())
	DevWidgets.mark_unsaved(update_button, "Update", _dirty)
	load_button.disabled = _selected_key() == ""


# "" = allowed. Update only overwrites what is actually LOADED (dev call 2026-08-11).
func _update_block_reason() -> String:
	var target := _selected_key()
	if target == "" or target == _loaded:
		return ""
	return "Load reaction '%s' first -- Update overwrites it with whatever is in the form" % _selected()["id"]


func _on_update_pressed() -> void:
	if current == null:
		return
	var entry := _selected()
	if entry.is_empty():
		return
	var reason := _update_block_reason()   # the handler is the real gate; the greyed button is its surface
	if reason != "":
		status_label.text = reason
		return
	var path := (entry["reaction"] as Resource).resource_path
	DevWidgets.confirm_overwrite(self, "%s reaction '%s'" % [String(entry["kind"]).to_lower(), entry["id"]],
		"the form's values", func() -> void: _update_confirmed(path))


func _update_confirmed(path: String) -> void:
	if DevWidgets.save_over(current, path, status_label):
		_dirty = false
		status_label.text = "Saved %s." % path.get_file()
		AlchemyTool.redraw_plan(_game)
	_refresh_list(_loaded)


func _on_save_as_pressed() -> void:
	if current == null:
		return
	var chosen := name_input.text.strip_edges()
	if chosen == "":
		status_label.text = "Needs a name to save"
		return
	if DevWidgets.refuse_illegal_name(chosen, "reaction", status_label):
		return
	var unit := current is ElementalReaction
	var path := (unit_dir if unit else ground_dir) + chosen + ".tres"
	if DevWidgets.refuse_existing_file(path, "reaction", status_label):
		return
	if not DevWidgets.save_over(current, path, status_label):
		return
	if unit:
		ReactionCatalog.refresh()   # the folder just gained a file
	else:
		_rescan_ground()
	name_input.text = ""
	var kind := kind_of(current)
	# save_over took the path over with the copy itself, so the form would now edit the live file: hold
	# a fresh copy of it instead.
	_hold(current.duplicate(true), _key(kind, chosen))
	_refresh_list(_loaded)
	status_label.text = "Saved %s." % path.get_file()
	AlchemyTool.redraw_plan(_game)


func _rescan_ground() -> void:
	var states: TerrainStateManager = null
	var grid: TileMapLayer = null
	if _game != null:
		states = _game.terrain_states
		grid = _game.grid
	TerrainReactionCatalog.rescan(states, grid)
