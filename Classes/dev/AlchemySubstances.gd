extends VBoxContainer
class_name AlchemySubstances

# THE ALCHEMY PAGE'S SUBSTANCES TAB (#1532, AlchemyTool hosts it): one substance at a time -- its name,
# formula, phase, and whether a cast beside it finds its parts as well as it (lends_its_parts).
#
# IT EDITS A COPY, the Attack Editor's idiom: Load duplicates the catalog's object, Update writes the copy
# back through DevWidgets.save_over (which writes THROUGH to the object every reader holds) and asks
# first, Save As writes a new file. So nothing moves in play until a save.
#
# The readout under the form is the seams a cast and CI run, handed a catalog in which this substance IS
# the copy: AlchemyFormula.atoms_of, CellSubstances.present_from and ReactionLint.check_substance.
#
# Update and Save As REFUSE a formula the lint BLOCKS (a name nothing answers to, a substance that
# contains itself): play reads a formula -- it is what a compound lends -- so a broken one is never
# written. A DEGRADES finding still saves, AttackEditorTool._refuse_unfireable's two tiers.
#
# There is NO Delete (dev ruling at the mock, 2026-10-31): equations, carving recipes and Sources rows
# name a substance BY TEXT, so a deleted file would leave them naming nothing with no reference sweep
# to catch it.

const ID_RULE := "^[a-z][a-z0-9_]*$"
const WARN_COLOR := Color(1.0, 0.75, 0.35, 1)
const GOOD_COLOR := Color(0.55, 0.9, 0.55, 1)
const KEY_WIDTH := 70
const FORMULA_WIDTH := 380   # a reflective LineEdit sizes to nothing, and a formula is read whole

# The folder Save As writes into. A test aims it at user://.
var dir := SubstanceCatalog.DIR

var current: Substance = null   # the COPY the form edits
var picker: OptionButton
var load_button: Button
var update_button: Button
var name_input: LineEdit
var save_as_button: Button
var status_label: Label

var _game = null
var _loaded_id := ""
var _dirty := false   # the copy moved since its Load or save
var _ids: Array[String] = []   # picker index -> id
var _form: VBoxContainer
var _readout: GridContainer
var _id_rule := RegEx.create_from_string(ID_RULE)


func _ready() -> void:
	var top := HBoxContainer.new()
	add_child(top)
	picker = OptionButton.new()
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.item_selected.connect(func(_index: int) -> void: _refresh_buttons())
	top.add_child(picker)
	load_button = Button.new()
	load_button.text = "Load"
	load_button.tooltip_text = "Put the picked substance into the form, as a copy: nothing moves in play until you save."
	load_button.pressed.connect(_load_selected)
	top.add_child(load_button)
	update_button = Button.new()
	update_button.text = "Update"
	update_button.pressed.connect(_on_update_pressed)
	top.add_child(update_button)
	var second := HBoxContainer.new()
	add_child(second)
	name_input = LineEdit.new()
	name_input.placeholder_text = "new substance name"
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	second.add_child(name_input)
	save_as_button = Button.new()
	save_as_button.text = "Save As"
	save_as_button.tooltip_text = "Write the form as a new substance. Its id is the name typed beside: lower-case letters, digits and _."
	save_as_button.pressed.connect(_on_save_as_pressed)
	second.add_child(save_as_button)
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status_label)
	var note := Label.new()
	note.text = ("A substance is what equations, carving recipes and Sources rows name by its id, the file "
		+ "name. Edit a loaded copy: Update writes it back and asks first, Save As writes a new file. A "
		+ "change reaches play once it is written.")
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


# The catalog may have gained a file (a Save As here, or nowhere else yet): re-list it, keeping the
# copy in the form.
func refresh_on_show() -> void:
	_refresh_list(_loaded_id)


func is_dirty() -> bool:
	return _dirty


func _refresh_list(select_id := "") -> void:
	picker.clear()
	var all := SubstanceCatalog.get_all()
	_ids.assign(all.keys())
	_ids.sort()
	for id: String in _ids:
		picker.add_item("%s   (%s)" % [SubstanceCatalog.name_of(id), id])
	picker.select(-1)   # add_item auto-selects index 0 -- Update must never aim at an entry nobody picked
	if _ids.has(select_id):
		picker.select(_ids.find(select_id))
	_refresh_buttons()


func _selected_id() -> String:
	return _ids[picker.selected] if picker.selected >= 0 and picker.selected < _ids.size() else ""


func _load_selected() -> void:
	var id := _selected_id()
	var live := SubstanceCatalog.by_id(id)
	if live == null:
		return
	_hold(live.duplicate(true) as Substance, id)


func _hold(copy: Substance, id: String) -> void:
	if current != null and current.changed.is_connected(_on_edited):
		current.changed.disconnect(_on_edited)
	current = copy
	_loaded_id = id
	_dirty = false
	current.changed.connect(_on_edited)
	_populate()
	_refresh_buttons()


func _populate() -> void:
	for child in _form.get_children():
		_form.remove_child(child)
		child.queue_free()
	for prop in current.get_property_list():
		if DevWidgets.is_exported(prop):
			var nodes := DevWidgets.add_property_row(_form, current, prop.name, _populate)
			if prop.name == "formula":
				widen_edits(nodes, FORMULA_WIDTH)
	_readout = GridContainer.new()
	_readout.columns = 2
	_readout.add_theme_constant_override("h_separation", 12)
	_form.add_child(_readout)
	_refresh_readout()


# Give the text field among a row's nodes room for a whole formula or equation.
static func widen_edits(nodes: Array[Node], width: int) -> void:
	for node: Node in nodes:
		var found: Array[Node] = node.find_children("*", "LineEdit", true, false)
		if node is LineEdit:
			found.append(node)
		for edit: Node in found:
			(edit as LineEdit).custom_minimum_size.x = width


# Every reflective row writes through DevWidgets.write, which emits `changed`: the one signal.
func _on_edited() -> void:
	_dirty = true
	_refresh_readout()
	_refresh_buttons()


# What this substance would be with the form's values, keyed as `id` -- the catalog every readout reads.
func _catalog_with_copy(id: String) -> Dictionary:
	var catalog := SubstanceCatalog.get_all()   # a copy: adding to it changes no one else's
	catalog[id] = current
	return catalog


func _refresh_readout() -> void:
	if _readout == null:
		return
	for child in _readout.get_children():
		_readout.remove_child(child)
		child.queue_free()
	var catalog := _catalog_with_copy(_loaded_id)
	var atoms := AlchemyFormula.atoms_of(current, catalog)
	_line("Atoms", AlchemyFormula.format_atoms(atoms.counts) if atoms.error == "" else "-")
	if atoms.error == "":
		var lends := lends_text(current, _loaded_id, catalog)
		_line("Lends", lends["text"], null, AlchemySources.EMPTY_COLOR if lends["none"] else null)
	var findings := ReactionLint.check_substance(current, catalog)
	if findings.is_empty():
		_line("Lint", "clean", GOOD_COLOR, GOOD_COLOR)
	for finding: Dictionary in findings:
		_finding_line(finding)


# What a cast beside `substance` finds as well as it, as the readout says it. `none` = it lends nothing.
static func lends_text(substance: Substance, id: String, catalog: Dictionary) -> Dictionary:
	var own := substance.display_name if substance.display_name != "" else id
	if not substance.is_compound():
		return {"text": "nothing: a molecule is one thing, with no parts", "none": true}
	if not substance.lends_its_parts:
		return {"text": "nothing: a cast beside it finds %s alone" % own, "none": true}
	var ids: Array[String] = [id]
	var parts := PackedStringArray()
	for found: String in CellSubstances.present_from(ids, catalog):
		if found != id:
			parts.append(SubstanceCatalog.name_of(found))
	if parts.is_empty():
		return {"text": "nothing", "none": true}
	return {"text": "%s   (what a cast beside it finds as well as %s)" % [", ".join(parts), own], "none": false}


func _line(key: String, value: String, key_color: Variant = null, value_color: Variant = null) -> void:
	var left := Label.new()
	left.text = key
	left.custom_minimum_size = Vector2(KEY_WIDTH, 0)
	if key_color != null:
		left.add_theme_color_override("font_color", key_color)
	_readout.add_child(left)
	var right := Label.new()
	right.text = value
	right.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if value_color != null:
		right.add_theme_color_override("font_color", value_color)
	_readout.add_child(right)


func _finding_line(finding: Dictionary) -> void:
	var blocks: bool = finding["severity"] == ReactionLint.Severity.BLOCKS
	var color := AlchemySources.BAD_COLOR if blocks else WARN_COLOR
	_line("BLOCKS" if blocks else "DEGRADES", finding["text"], color, color)


func _refresh_buttons() -> void:
	DevWidgets.refresh_update_button(update_button, _selected_id(), "substance", _update_block_reason())
	DevWidgets.mark_unsaved(update_button, "Update", _dirty)
	load_button.disabled = _selected_id() == ""


# "" = allowed. Update only overwrites what is actually LOADED (dev call 2026-08-11).
func _update_block_reason() -> String:
	var target := _selected_id()
	if target == "" or target == _loaded_id:
		return ""
	return "Load substance '%s' first -- Update overwrites it with whatever is in the form" % target


# The lint's BLOCKS tier refuses a write, keyed as it would be saved; "" findings beyond that only say so.
func _refuse_broken(id: String) -> bool:
	for finding: Dictionary in ReactionLint.check_substance(current, _catalog_with_copy(id)):
		if finding["severity"] == ReactionLint.Severity.BLOCKS:
			var msg := "Not saved: %s" % finding["text"]
			push_warning(msg)
			status_label.text = msg
			return true
	return false


func _on_update_pressed() -> void:
	if current == null:
		return
	var target := _selected_id()
	if target == "":
		return
	var reason := _update_block_reason()   # the handler is the real gate; the greyed button is its surface
	if reason != "":
		status_label.text = reason
		return
	if _refuse_broken(target):
		return
	var path := SubstanceCatalog.by_id(target).resource_path
	DevWidgets.confirm_overwrite(self, "substance '%s'" % target, "the form's values",
		func() -> void: _update_confirmed(path))


func _update_confirmed(path: String) -> void:
	if DevWidgets.save_over(current, path, status_label):
		_dirty = false
		status_label.text = "Saved %s." % path.get_file()
		AlchemyTool.redraw_plan(_game)
	_refresh_list(_loaded_id)


func _on_save_as_pressed() -> void:
	if current == null:
		return
	var chosen := name_input.text.strip_edges()
	if chosen == "":
		status_label.text = "Needs a name to save"
		return
	if _id_rule.search(chosen) == null:
		status_label.text = ("A substance's name is its id: lower-case letters, digits and _, starting with a "
			+ "letter. A formula or an equation names it that way, so anything else would read as something else.")
		return
	if _refuse_broken(chosen):
		return
	var path := dir + chosen + ".tres"
	if DevWidgets.refuse_existing_file(path, "substance", status_label):
		return
	if not DevWidgets.save_over(current, path, status_label):
		return
	SubstanceCatalog.refresh()   # the folder just gained a file
	name_input.text = ""
	# save_over took the path over with the copy itself, so the form would now edit the live file: hold
	# a fresh copy of it instead.
	_hold(current.duplicate(true) as Substance, chosen)
	_refresh_list(chosen)
	status_label.text = "Saved %s." % path.get_file()
	AlchemyTool.redraw_plan(_game)
