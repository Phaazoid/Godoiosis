extends MarginContainer
class_name AttackEditorTool

@onready var editor_container := %AttackEditorVbox
@onready var load_dropdown: OptionButton = %CarvingLoadDropdown
@onready var name_input: LineEdit = %CarvingNameInput
@onready var new_button: Button = %NewButton

# Authors TransmutationData carvings, WeaponAttackData weapon attacks, AND edits an established
# family's/prototype's MAIN attack in place — three modes, one form (#30 / #72; folded from a
# separate Family Mains tab into a third toggle, dev call 2026-07-19). The first two modes author
# POOL content (new/load-a-copy/name/save); FAMILY_MAINS is fundamentally different — its dropdown
# lists FAMILIES (not saved attacks), selecting one loads that family's main_attack LIVE (never
# duplicated, since edits must stay shared/in-place), there's no "new" (a main is always tied to
# an existing family, never created from scratch), and Save overwrites the attack's OWN
# resource_path instead of a chosen pool filename. attack_pattern gets a class-picker + its own
# params for free in every mode via DevWidgets.build_resource_editor's existing recursion into
# nested Resource fields — no bespoke pattern UI needed anywhere.
enum Mode { TRANSMUTATION, WEAPON_ATTACK, FAMILY_MAINS }

var _mode := Mode.TRANSMUTATION
var current: AttackData = null
var current_template: WeaponData = null   # FAMILY_MAINS only: which family "current" belongs to
var _items := {}

func _ready():
	_refresh_list()
	_on_new_pressed()

func _on_transmutation_mode_selected():
	_mode = Mode.TRANSMUTATION
	new_button.disabled = false
	_refresh_list()
	_on_new_pressed()

func _on_weapon_attack_mode_selected():
	_mode = Mode.WEAPON_ATTACK
	new_button.disabled = false
	_refresh_list()
	_on_new_pressed()

func _on_family_mains_mode_selected():
	_mode = Mode.FAMILY_MAINS
	new_button.disabled = true   # no "new" concept — a main is always tied to an existing family
	_refresh_list()
	if _items.is_empty():
		current_template = null
		current = null
		name_input.text = ""
		populate()
	else:
		_load_selected(0)

func _refresh_list():
	load_dropdown.clear()
	match _mode:
		Mode.TRANSMUTATION:
			_items = TransmutationCatalog.get_all()
		Mode.WEAPON_ATTACK:
			_items = WeaponAttackCatalog.get_library()
		Mode.FAMILY_MAINS:
			_items = WeaponCatalog.get_templates()
	for k in _items:
		load_dropdown.add_item(k)

func _load_selected(index: int):
	if index < 0:
		return
	var picked = _items[_items.keys()[index]]
	if _mode == Mode.FAMILY_MAINS:
		current_template = picked
		current = current_template.main_attack if current_template != null else null
	else:
		current_template = null
		current = picked.duplicate(true)
	name_input.text = current.display_name if current != null else ""
	populate()

func _on_new_pressed():
	if _mode == Mode.FAMILY_MAINS:
		return
	current_template = null
	current = TransmutationData.new() if _mode == Mode.TRANSMUTATION else WeaponAttackData.new()
	name_input.text = ""
	populate()

func _on_save_pressed():
	if current == null:
		return
	if _mode == Mode.FAMILY_MAINS:
		var live_name := name_input.text.strip_edges()
		if live_name != "":
			current.display_name = live_name
		if current.resource_path == "":
			push_warning("This family's main attack has no saved path yet — author it in Weapon Attack mode first")
			return
		var save_err := ResourceSaver.save(current, current.resource_path)
		if save_err != OK:
			push_error("Failed to save (error %s)" % save_err)
		return
	var chosen_name := name_input.text.strip_edges()
	if chosen_name == "":
		push_warning("Needs a name to save")
		return
	current.display_name = chosen_name
	var dir := TransmutationCatalog.CARVING_DIR if _mode == Mode.TRANSMUTATION else WeaponAttackCatalog.LIBRARY_DIR
	DirAccess.make_dir_recursive_absolute(dir)
	var err := ResourceSaver.save(current, dir + chosen_name + ".tres")
	if err != OK:
		push_error("Failed to save (error %s)" % err)
		return
	_refresh_list()

func populate():
	for child in editor_container.get_children():
		editor_container.remove_child(child)
		child.queue_free()
	if current == null:
		if _mode == Mode.FAMILY_MAINS:
			DevWidgets.add_label(editor_container, "(no main attack)")
		return
	match _mode:
		Mode.TRANSMUTATION:
			var carving := current as TransmutationData
			_populate_sigils(carving)
			_populate_flourishes(carving)
			DevWidgets.build_resource_editor(editor_container, current, populate, ["display_name", "sigils", "flourishes"])
		Mode.WEAPON_ATTACK:
			DevWidgets.build_resource_editor(editor_container, current, populate, ["display_name"])
		Mode.FAMILY_MAINS:
			var family_label := current_template.item_name if current_template != null and current_template.item_name != "" else "?"
			DevWidgets.add_label(editor_container, "Editing the MAIN attack for %s — changes every weapon of this family." % family_label)
			DevWidgets.build_resource_editor(editor_container, current, populate, ["display_name"])

# Sigils as per-element weights ("2 Fire, 1 Earth"). Weight changes append/remove
# occurrences instead of rebuilding, so first-inscribed tie-break order survives edits.
func _populate_sigils(carving: TransmutationData):
	DevWidgets.add_label(editor_container, "Sigils (weight per element):")
	for e in Elemental.SIGIL_ELEMENTS:
		var element: Elemental.Element = e
		var on_weight := func(v):
			_set_sigil_weight(carving, element, int(v))
		DevWidgets.add_spinbox(editor_container, Elemental.Element.keys()[element].capitalize(), carving.sigils.count(element), on_weight)
	DevWidgets.add_label(editor_container, "Cost %d | Tier %d | Flourish slots %d" % [carving.cost(), carving.tier(), carving.flourish_slots()])
	DevWidgets.add_label(editor_container, "Resolves to: %s" % _tags_label(carving))

func _set_sigil_weight(carving: TransmutationData, element: Elemental.Element, weight: int):
	var target := maxi(0, weight)
	var delta = target - carving.sigils.count(element)
	for i in range(delta):
		carving.sigils.append(element)
	for i in range(-delta):
		carving.sigils.remove_at(carving.sigils.rfind(element))
	# Fewer sigils can mean fewer slots — trim overflow so the circle stays legal.
	while carving.flourishes.size() > carving.flourish_slots():
		push_warning("Slot lost: removed %s" % Flourish.Type.keys()[carving.flourishes.pop_back()])
	populate()

func _populate_flourishes(carving: TransmutationData):
	DevWidgets.add_label(editor_container, "Flourishes (%d / %d slots):" % [carving.flourishes.size(), carving.flourish_slots()])
	for i in range(carving.flourishes.size()):
		var idx := i
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = Flourish.Type.keys()[carving.flourishes[idx]].capitalize()
		label.custom_minimum_size = Vector2(160, 0)
		row.add_child(label)
		var remove := Button.new()
		remove.text = "Remove"
		remove.pressed.connect(func():
			carving.flourishes.remove_at(idx)
			populate()
		)
		row.add_child(remove)
		editor_container.add_child(row)

	var add_row := HBoxContainer.new()
	var picker := OptionButton.new()
	var types: Array = Flourish.Type.values().filter(func(t): return t != Flourish.Type.NONE)
	for t in types:
		picker.add_item(Flourish.Type.keys()[t].capitalize())
	add_row.add_child(picker)
	var add_btn := Button.new()
	add_btn.text = "Carve"
	add_btn.pressed.connect(func():
		var chosen: Flourish.Type = types[picker.selected]
		if carving.can_add_flourish(chosen):
			carving.flourishes.append(chosen)
			populate()
		else:
			push_warning("Can't carve %s (no free slot, or its opposite is already carved)" % Flourish.Type.keys()[chosen])
	)
	add_row.add_child(add_btn)
	editor_container.add_child(add_row)

func _tags_label(carving: TransmutationData) -> String:
	if carving.sigils.is_empty():
		return "(nothing — add a sigil)"
	var names := []
	for e in carving.get_elements():
		names.append(Elemental.Element.keys()[e].capitalize())
	return ", ".join(names)
