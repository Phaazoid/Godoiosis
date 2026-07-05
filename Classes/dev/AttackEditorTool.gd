extends MarginContainer
class_name AttackEditorTool

@onready var editor_container := %AttackEditorVbox
@onready var load_dropdown: OptionButton = %CarvingLoadDropdown
@onready var name_input: LineEdit = %CarvingNameInput

# Authors TransmutationData carvings in-game (previously inspector-only). Sigils are edited
# as per-element weights (base elements only, by construction); flourish carving is gated by
# can_add_flourish — the editor can't author an illegal circle.
var current : TransmutationData = null
var _carvings := {}

func _ready():
	_refresh_carving_list()
	_on_new_pressed()

func _refresh_carving_list():
	load_dropdown.clear()
	_carvings = TransmutationCatalog.get_all()
	for k in _carvings:
		load_dropdown.add_item(k)

func _load_selected(index: int):
	if index < 0:
		return
	current = _carvings[_carvings.keys()[index]].duplicate(true)
	name_input.text = current.display_name
	populate()

func _on_new_pressed():
	current = TransmutationData.new()
	name_input.text = ""
	populate()

func _on_save_pressed():
	if current == null:
		return
	var carving_name := name_input.text.strip_edges()
	if carving_name == "":
		push_warning("Carving needs a name to save")
		return
	current.display_name = carving_name
	DirAccess.make_dir_recursive_absolute(TransmutationCatalog.CARVING_DIR)
	var err := ResourceSaver.save(current, TransmutationCatalog.CARVING_DIR + carving_name + ".tres")
	if err != OK:
		push_error("Failed to save carving (error %s)" % err)
		return
	_refresh_carving_list()

func populate():
	for child in editor_container.get_children():
		editor_container.remove_child(child)
		child.queue_free()
	if current == null:
		return
	_populate_sigils(current)
	_populate_flourishes(current)
	DevWidgets.build_resource_editor(editor_container, current, populate, ["display_name", "sigils", "flourishes"])

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
