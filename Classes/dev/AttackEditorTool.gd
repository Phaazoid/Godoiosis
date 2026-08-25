extends MarginContainer
class_name AttackEditorTool

@onready var editor_container := %AttackEditorVbox
@onready var load_dropdown: OptionButton = %CarvingLoadDropdown
@onready var name_input: LineEdit = %CarvingNameInput
@onready var new_button: Button = %NewButton
@onready var update_button: Button = %UpdateAttackButton
@onready var delete_button: Button = %DeleteAttackButton
@onready var save_as_button: Button = %SaveAsAttackButton
@onready var status_label: Label = %AttackStatusLabel

# Authors TransmutationData carvings, WeaponAttackData weapon attacks, AND edits an established
# family's/prototype's attacks in place — three modes, one form (#30 / #72; folded from a
# separate Family Mains tab into a third toggle, dev call 2026-07-19). The first two modes author
# POOL content (new/load-a-copy/name/save); FAMILY is fundamentally different — its dropdown
# lists FAMILIES (not saved attacks), selecting one loads that family's main_attack LIVE (never
# duplicated, since edits must stay shared/in-place), there's no "new" (a main is always tied to
# an existing family, never created from scratch), and Save overwrites the attack's OWN
# resource_path instead of a chosen pool filename. attack_pattern gets a class-picker + its own
# params for free in every mode via DevWidgets.build_resource_editor's existing recursion into
# nested Resource fields — no bespoke pattern UI needed anywhere.
#
# FAMILY also carries the family's EXTRA_ATTACKS (#473), which is what closed the loop the Weapon
# Attack mode had been authoring into: WeaponAttackCatalog's library had exactly ONE reader in the
# project and it was this file's own load dropdown, so a saved attack was write-only content that
# no unit could ever swing. Extras belong to the FAMILY, not to a carried WeaponInstance — the Item
# Editor deliberately shows a template read-only (its own header records why), so attaching one
# there would be the shared-template mutation that ruling forbids.
#
# Consequence: this mode's Update writes TWO files, the loaded main's own .tres and the family's,
# under one confirm that names both. They are genuinely two files — a family references its main by
# ext_resource, so saving the family does not save the attack.
enum Mode { TRANSMUTATION, WEAPON_ATTACK, FAMILY }

# What the reflective editor must NOT draw, per mode. Declared here because the form and the
# coverage law in tests/dev/test_property_tips.gd have to agree about which fields are skipped --
# a field skipped in one and not the other is a field that either loses its tooltip or fails a law
# it was never drawn by.
const POOL_SKIP := ["display_name", "scaling_blend"]                # name and blend have bespoke UI above
const CARVING_SKIP := ["display_name", "sigils", "flourishes"]     # the latter two get bespoke UI

var _mode := Mode.TRANSMUTATION
var current: AttackData = null
var current_template: WeaponData = null   # FAMILY only: which family "current" belongs to
var _items := {}
# Which dropdown entry "current" was loaded from ("" = a New attack). Pool modes load a COPY with
# no resource_path, so nothing else records this -- and Update's load-gate needs it (2026-08-11).
var _loaded_name := ""

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

func _on_family_mode_selected():
	_mode = Mode.FAMILY
	new_button.disabled = true
	_refresh_list()
	if _items.is_empty():
		current_template = null
		current = null
		_loaded_name = ""
		name_input.text = ""
		populate()
		_refresh_buttons()
		return
	load_dropdown.select(0)
	_load_selected()
	_refresh_buttons()

func _refresh_list(select_name := ""):
	load_dropdown.clear()
	match _mode:
		Mode.TRANSMUTATION:
			_items = TransmutationCatalog.get_all()
		Mode.WEAPON_ATTACK:
			_items = WeaponAttackCatalog.get_library()
		Mode.FAMILY:
			_items = WeaponCatalog.get_templates()
	for k in _items:
		load_dropdown.add_item(k)

	# add_item auto-selects index 0 -- Update must never aim at an entry nobody picked.
	load_dropdown.select(-1)
	for i in load_dropdown.item_count:
		if load_dropdown.get_item_text(i) == select_name:
			load_dropdown.select(i)
			break
	_refresh_buttons()

# FAMILY has no Save As and no Delete: a main is always tied to an existing family, never
# created from scratch or removed as its own file -- its Update overwrites the attack's own file
# rather than a chosen name.
func _refresh_buttons():
	var noun := "family" if _mode == Mode.FAMILY else "attack"
	DevWidgets.refresh_update_button(update_button, DevWidgets.selected_name(load_dropdown), noun, _update_block_reason())
	DevWidgets.refresh_delete_button(delete_button, DevWidgets.selected_name(load_dropdown), noun)
	save_as_button.disabled = _mode == Mode.FAMILY
	if _mode == Mode.FAMILY:
		delete_button.disabled = true

# "" = allowed. Update only overwrites what is actually LOADED (dev call 2026-08-11). In
# FAMILY this also keeps the tooltip's named family and the written file in agreement --
# its Update always wrote the loaded main's own file whatever the dropdown said.
func _update_block_reason() -> String:
	var target := DevWidgets.selected_name(load_dropdown)
	if target == "" or target == _loaded_name:
		return ""
	var noun := "family" if _mode == Mode.FAMILY else "attack"
	return "Load %s '%s' first -- Update overwrites it with whatever is in the editor" % [noun, target]

func _load_selected():
	var target := DevWidgets.selected_name(load_dropdown)
	if target == "" or not _items.has(target):
		return
	var picked = _items[target]
	if _mode == Mode.FAMILY:
		current_template = picked
		current = current_template.main_attack if current_template != null else null
	else:
		current_template = null
		current = picked.duplicate(true)
	_loaded_name = target
	_refresh_buttons()
	populate()

func _on_load_dropdown_item_selected(_index: int):
	_refresh_buttons()

func _on_load_pressed():
	_load_selected()

func _on_new_pressed():
	if _mode == Mode.FAMILY:
		return
	current_template = null
	current = TransmutationData.new() if _mode == Mode.TRANSMUTATION else WeaponAttackData.new()
	_loaded_name = ""
	name_input.text = ""
	load_dropdown.select(-1)
	_refresh_buttons()
	populate()

func _on_update_pressed():
	# FAMILY is the exception: with no main there is still a family file, and its extras are worth
	# saving. Every other mode has nothing to write without an attack in hand.
	if current == null and _mode != Mode.FAMILY:
		return
	var target := DevWidgets.selected_name(load_dropdown)
	if target == "":
		return
	# The handler is the real gate -- the disabled button is only its surface (#166 shape).
	var reason := _update_block_reason()
	if reason != "":
		status_label.text = reason
		return
	if _refuse_unfireable(current):
		return
	if _mode == Mode.FAMILY:
		# TWO files, because a family references its main by ext_resource: saving one saves nothing
		# of the other. The family always has a path; the main is edited LIVE so it already knows
		# its own, and an empty one means extras-only -- which is a legitimate save, not a refusal.
		var family_path: String = current_template.resource_path if current_template != null else ""
		if family_path == "":
			var msg := "%s has no file on disk to update" % target
			push_warning(msg)
			status_label.text = msg
			return
		var main_path: String = current.resource_path if current != null else ""
		var victim := "family '%s'" % target
		victim += " and its main attack" if main_path != "" else " (extras only -- its main has no file yet)"
		# Confirmed as well as load-gated (#380's convention), both branches: the gate cannot
		# catch a mis-click at the attack you DID load.
		DevWidgets.confirm_overwrite(self, victim, "the editor's values",
			func() -> void: _update_family_confirmed(family_path, main_path))
		return
	var path: String = _items[target].resource_path
	if path == "":
		var msg := "%s has no file on disk to update" % target
		push_warning(msg)
		status_label.text = msg
		return
	DevWidgets.confirm_overwrite(self, "attack '%s'" % target, "the editor's values",
		func() -> void: _update_confirmed(path))


func _update_confirmed(path: String) -> void:
	if DevWidgets.save_over(current, path, status_label):
		_loaded_name = current.display_name   # a rename moves the loaded identity with it
		_refresh_list(current.display_name)


# The main first, then the family. A partial write is possible and is REPORTED rather than rolled
# back -- save_over already puts its own failure in the status label, and the half that landed is
# on disk either way.
func _update_family_confirmed(family_path: String, main_path: String) -> void:
	if main_path != "" and not DevWidgets.save_over(current, main_path, status_label):
		return
	if not DevWidgets.save_over(current_template, family_path, status_label):
		return
	status_label.text = "Saved %s" % _loaded_name
	populate()   # the extras list re-reads its carriers and lint marks off what is now on disk


# Refuse to WRITE an attack nothing can aim (#473). At the SAVE rather than as a live row in the
# form, deliberately: a SpinBox change does not rebuild these rows, so a readout drawn here would
# still say the old reach while you were typing the value that broke it -- stale in exactly the
# moment it was needed. "" findings = nothing wrong.
# Refuses on BLOCKS only, since #485 gave the lint a second tier. A DEGRADES finding still SAYS so
# -- a blend that does not total 100 is worth seeing -- but it must not stop the save: it describes
# a file that already exists on disk in that state, so refusing would leave the only tool that can
# repair it unable to write. BoardLint's two tiers, honoured at the consumer rather than only at
# the rule (the "justify it at every surface" law).
func _refuse_unfireable(attack: AttackData) -> bool:
	var findings := AttackLint.check(attack)
	if findings.is_empty():
		return false
	for finding in findings:
		if finding["severity"] == AttackLint.Severity.BLOCKS:
			var msg: String = finding["text"]
			push_warning(msg)
			status_label.text = msg
			return true
	status_label.text = findings[0]["text"]
	return false

# The one-line form of a finding, for a list row that has no space for the full sentence.
func _mark_for(finding: Dictionary) -> String:
	return "reaches no cells" if finding["severity"] == AttackLint.Severity.BLOCKS else "blend does not total %d%%" % Stats.BLEND_TOTAL

func _on_delete_pressed():
	if _mode == Mode.FAMILY:
		return
	var target := DevWidgets.selected_name(load_dropdown)
	if target == "":
		return
	DevWidgets.confirm_delete(self, "attack '%s'" % target, func(): _delete_confirmed(target))

func _delete_confirmed(target: String) -> void:
	if not _items.has(target):
		return   # catalog moved between the press and the Yes
	if DevWidgets.delete_saved_file(_items[target].resource_path, "attack", status_label):
		if target == _loaded_name:
			_loaded_name = ""
		_refresh_list()

func _on_save_as_pressed():
	if current == null or _mode == Mode.FAMILY:
		return
	var chosen_name := name_input.text.strip_edges()
	if chosen_name == "":
		var msg := "Needs a name to save"
		push_warning(msg)
		status_label.text = msg
		return
	if DevWidgets.refuse_illegal_name(chosen_name, "attack", status_label):
		return
	if _refuse_unfireable(current):
		return
	var dir := TransmutationCatalog.CARVING_DIR if _mode == Mode.TRANSMUTATION else WeaponAttackCatalog.LIBRARY_DIR
	var path := dir + chosen_name + ".tres"
	if DevWidgets.refuse_existing_file(path, "attack", status_label):
		return
	current.display_name = chosen_name
	if DevWidgets.save_over(current, path, status_label):
		_loaded_name = chosen_name   # save_over take_over_path'd it: the editor now holds this file
		name_input.text = ""
		_refresh_list(chosen_name)

func populate():
	for child in editor_container.get_children():
		editor_container.remove_child(child)
		child.queue_free()
	if _mode == Mode.FAMILY:
		_populate_family()
		return
	if current == null:
		return
	var edited := current
	DevWidgets.add_lineedit(editor_container, "Display name", edited.display_name, func(s: String): edited.display_name = s)
	match _mode:
		Mode.TRANSMUTATION:
			var carving := current as TransmutationData
			_populate_sigils(carving)
			_populate_flourishes(carving)
			DevWidgets.build_resource_editor(editor_container, current, populate, CARVING_SKIP)
		Mode.WEAPON_ATTACK:
			DevWidgets.build_resource_editor(editor_container, current, populate, POOL_SKIP)
			_populate_blend()
			_populate_carriers()

# The family form: its main (edited live, in place) AND its extras. Extras render whether or not
# there is a main -- the old early return on a null `current` made a main-less family's extras
# unreachable, which is a door that cannot be opened rather than one that refuses.
func _populate_family() -> void:
	if current_template == null:
		DevWidgets.add_label(editor_container, "(no family loaded)")
		return
	var family_label := current_template.display_name if current_template.display_name != "" else "?"
	if current == null:
		DevWidgets.add_label(editor_container, "%s has no main attack yet — author one in Weapon Attack mode." % family_label)
	else:
		var edited := current
		DevWidgets.add_lineedit(editor_container, "Display name", edited.display_name, func(s: String): edited.display_name = s)
		DevWidgets.add_label(editor_container, "Editing the MAIN attack for %s — changes every weapon of this family." % family_label)
		DevWidgets.build_resource_editor(editor_container, current, populate, POOL_SKIP)
		_populate_blend()
	_populate_extras(family_label)

# The scaling sliders (#485). Drawn in both attack modes and NOT for a carving, which scales off
# the wielder's aura and has no blend to edit -- the cast is what says so rather than a mode check.
# This is the family-scaling surface the ticket asked for: a family's blend IS its main attack's,
# so editing it in FAMILY mode is editing the family, with no separate template field to keep.
func _populate_blend() -> void:
	var weapon_attack := current as WeaponAttackData
	if weapon_attack == null:
		return
	DevWidgets.add_label(editor_container, "Damage scaling — the four always total %d%%:" % Stats.BLEND_TOTAL)
	DevWidgets.add_blend_sliders(editor_container, weapon_attack.scaling_blend, func(): pass,
		DevWidgets.property_tip(weapon_attack, "scaling_blend"))

# The family's extra_attacks, in the rune editor's inscribe-list idiom. Entries are DIRECT REFS,
# never copies: Springspear.tres and Kinetic_Mace.tres already store theirs as ext_resource, so a
# duplicate here would fork the file the Weapon Attack mode edits.
#
# The lint mark beside an entry is safe to draw where a mark on the main's own fields would not be
# (see _refuse_unfireable): an extra is a library file this form does not edit, so nothing on this
# panel can make the mark stale.
func _populate_extras(family_label: String) -> void:
	var extras := current_template.extra_attacks
	DevWidgets.add_label(editor_container, "Extra attacks for %s (%d) — every weapon of this family gets them:" % [family_label, extras.size()])
	for i in range(extras.size()):
		var extra := extras[i]
		var idx := i
		var row := HBoxContainer.new()
		var label := Label.new()
		var label_text := "(missing file)"
		if extra != null:
			label_text = extra.display_name if extra.display_name != "" else "(unnamed)"
			# The mark names the FINDING, not a fixed phrase: since #485 the lint answers two
			# different faults, and "reaches no cells" beside a blend that does not total 100
			# would be a label describing the wrong problem.
			var findings := AttackLint.check(extra)
			if not findings.is_empty():
				label_text += "  — %s" % _mark_for(findings[0])
		label.text = label_text
		label.custom_minimum_size = Vector2(220, 0)
		row.add_child(label)
		var remove := Button.new()
		remove.text = "Remove"
		remove.pressed.connect(func():
			current_template.extra_attacks.remove_at(idx)
			populate()
		)
		row.add_child(remove)
		editor_container.add_child(row)

	var library := WeaponAttackCatalog.get_library()
	if library.is_empty():
		DevWidgets.add_label(editor_container, "(no saved attacks yet — author one in Weapon Attack mode)")
		return
	var add_row := HBoxContainer.new()
	var picker := OptionButton.new()
	for k in library:
		picker.add_item(k)
	add_row.add_child(picker)
	var add_btn := Button.new()
	add_btn.text = "Add"
	add_btn.pressed.connect(func():
		if picker.selected < 0:
			return
		_add_extra(library[library.keys()[picker.selected]])
	)
	add_row.add_child(add_btn)
	editor_container.add_child(add_row)

func _add_extra(attack: WeaponAttackData) -> void:
	if attack == null or current_template == null:
		return
	# attacks() is main + extras, so this also refuses adding a family's own main back as an extra.
	if current_template.attacks().has(attack):
		var msg := "%s already carries %s" % [_loaded_name, attack.display_name]
		push_warning(msg)
		status_label.text = msg
		return
	current_template.extra_attacks.append(attack)
	populate()

# Which families can actually fire the loaded library attack (#473's part 1 made visible). Read off
# the CATALOG entry rather than `current`, which is a duplicate with no resource_path of its own.
func _populate_carriers() -> void:
	if _loaded_name == "" or not _items.has(_loaded_name):
		return   # a New attack has no file, so it has no carriers to report
	var carriers := AttackLint.carriers_of(_items[_loaded_name])
	if carriers.is_empty():
		DevWidgets.add_label(editor_container, "Nothing carries this attack — no unit can fire it. Add it to a family in Weapon Families mode.")
	else:
		DevWidgets.add_label(editor_container, "Carried by: %s" % ", ".join(carriers))

# Sigils as per-element weights ("2 Fire, 1 Earth"). Weight changes append/remove
# occurrences instead of rebuilding, so first-inscribed tie-break order survives edits.
func _populate_sigils(carving: TransmutationData):
	DevWidgets.add_label(editor_container, "Sigils (weight per element):")
	for e in Elemental.SIGIL_ELEMENTS:
		var element: Elemental.Element = e
		var on_weight := func(v):
			_set_sigil_weight(carving, element, int(v))
		DevWidgets.add_spinbox(editor_container, Elemental.display_name(element), carving.sigils.count(element), on_weight)
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
		names.append(Elemental.display_name(e))
	return ", ".join(names)
