extends MarginContainer
class_name ItemEditorTool

@onready var editor_container := %ItemEditorVbox
@onready var type_dropdown: OptionButton = %ItemTypeDropdown
@onready var load_dropdown: OptionButton = %ItemLoadDropdown
@onready var name_input: LineEdit = %ItemNameInput
@onready var update_button: Button = %UpdateItemButton
@onready var delete_button: Button = %DeleteItemButton
@onready var status_label: Label = %ItemStatusLabel

# Authors a WeaponInstance, a RuneData, a WeaponModData, or a prototype WeaponData. The first two
# fill the equip slot; the third is a COMPONENT fitted into one of a weapon's spaces, and it lives
# here (#74) because this is already where a mod gets fitted -- authoring one anywhere else would
# mean two tabs to make one weapon. The type dropdown lists weapon bases + prototypes + rune sizes
# + the blank mod + the blank prototype; the field area renders a bespoke editor per kind.
# Carvings are authored in the Attack Editor tab.
#
# The PROTOTYPE mode (#486) is the one that edits a TEMPLATE rather than a carried item, which is
# why the read-only rule below does not cover it: that rule forbids editing a shared family
# THROUGH ONE ITEM'S FORM, and a prototype here is edited as itself. Its scope is deliberately
# split against the Attack Editor's Weapon Families mode, which already writes WeaponData files:
# this mode owns what a template IS (family, physique, mod spaces) and only PICKS its main attack;
# that mode owns what it SWINGS (tuning the main, and extra_attacks). Both edit the catalog object
# LIVE, so the two panels cannot hold divergent copies of one file.
#
# current_item is a Resource rather than an EquippableData because a mod is deliberately NOT one --
# WeaponModData is its own content root off Resource, beside Item/AttackData/JobData (CLAUDE.md),
# and making it an Item to satisfy this field would be the model bending to fit its editor. The
# cost is that display_name is reached through _edited_name/_set_edited_name instead of directly.
var current_item: Resource = null
var _variants := {}
# Which catalog entry current_item was loaded from ("" = a New item). Load hands out a COPY with
# no resource_path, so nothing else records this -- and Update's load-gate needs it (2026-08-11).
var _loaded_name := ""

func _ready():
	for key in _base_catalog():
		type_dropdown.add_item(key)
	_refresh_variant_list()
	type_dropdown.select(0)
	_rebase_on_type(0)

# Weapon TYPES + a blank rune per size + a blank mod + a blank prototype — the things "New"/the
# type dropdown can start from. A mod has no varieties to enumerate (no family field yet, #74
# keeps that half), so it contributes exactly one entry; a prototype picks its family in the form.
const NEW_MOD_KEY := "Weapon Mod (blank)"
const NEW_PROTOTYPE_KEY := "Weapon Prototype (new)"

func _base_catalog() -> Dictionary:
	var bases := {}
	var weapons := WeaponCatalog.get_templates()
	for k in weapons:
		bases[k] = weapons[k]
	var runes := RuneCatalog.base_runes()
	for k in runes:
		bases[k] = runes[k]
	bases[NEW_MOD_KEY] = WeaponModData.new()
	bases[NEW_PROTOTYPE_KEY] = _blank_prototype()
	return bases

func _blank_prototype() -> WeaponData:
	var template := WeaponData.new()
	template.is_prototype = true
	return template

func _refresh_variant_list(select_name := ""):
	load_dropdown.clear()
	_variants = {}
	var weapons := WeaponCatalog.get_saved()
	for v in weapons:
		_variants[v] = weapons[v]
	# Prototypes are loadable here since #486 -- they are the one TEMPLATE this tool authors, so
	# the file has to be re-openable. They also appear in the TYPE dropdown, meaning something
	# else there: pick one there to BUILD a weapon on it, pick one here to EDIT the template.
	var prototypes := WeaponCatalog.get_prototypes()
	for v in prototypes:
		_variants[v] = prototypes[v]
	var runes := RuneCatalog.get_variants()
	for v in runes:
		_variants[v] = runes[v]
	var mods := WeaponModCatalog.get_mods()
	for v in mods:
		_variants[v] = mods[v]
	for v in _variants:
		load_dropdown.add_item(v)

	# add_item auto-selects index 0 -- Update must never aim at an entry nobody picked.
	load_dropdown.select(-1)
	for i in load_dropdown.item_count:
		if load_dropdown.get_item_text(i) == select_name:
			load_dropdown.select(i)
			break
	_refresh_update_button()

func _refresh_update_button():
	DevWidgets.refresh_update_button(update_button, DevWidgets.selected_name(load_dropdown), "item", _update_block_reason())
	DevWidgets.refresh_delete_button(delete_button, DevWidgets.selected_name(load_dropdown), "item")

# "" = allowed. Update only overwrites the entry that is actually LOADED (dev call 2026-08-11).
func _update_block_reason() -> String:
	var target := DevWidgets.selected_name(load_dropdown)
	if target == "" or target == _loaded_name:
		return ""
	return "Load '%s' first -- Update overwrites it with whatever is in the editor" % target

func _rebase_on_type(index: int):
	var bases := _base_catalog()
	var key = bases.keys()[index]
	var base = bases[key]
	# The blank prototype IS a WeaponData, so the "build an instance on it" arm below would eat
	# it -- the KEY is what says which of the two this entry means, exactly as it does for a mod.
	if key == NEW_PROTOTYPE_KEY:
		current_item = base.duplicate(true)
	else:
		current_item = WeaponInstance.make(base) if base is WeaponData else base.duplicate(true)
	_loaded_name = ""
	load_dropdown.select(-1)
	_refresh_update_button()
	populate()

func _on_type_selected(index: int):
	_rebase_on_type(index)

func _on_new_pressed():
	_rebase_on_type(type_dropdown.selected)
	name_input.text = ""

func _on_load_dropdown_item_selected(_index: int):
	_refresh_update_button()

func _on_load_pressed():
	var target := DevWidgets.selected_name(load_dropdown)
	if target == "":
		return
	current_item = _editable_copy(_variants[target])
	_loaded_name = target
	_refresh_update_button()
	populate()

# Load hands out a COPY so editing is not editing the catalog's live object. An equippable says how
# to copy itself (WeaponInstance's keeps its template shared); a mod is plain data with no such
# rule, so it deep-copies.
#
# A TEMPLATE is the exception and is handed out LIVE (#486). Copying one would fork it off every
# weapon built on it -- the whole point of the template model -- and it would also let this panel
# and the Attack Editor's Weapon Families mode hold divergent copies of one file, so whichever
# saved last would silently discard the other's edits. Live on both sides, no divergence.
func _editable_copy(entry: Resource) -> Resource:
	if entry is WeaponData:
		return entry
	var equippable := entry as EquippableData
	return equippable.copy_equippable() if equippable != null else entry.duplicate(true)

# display_name is declared separately on Item and on WeaponModData -- two content roots that agree
# on the name but share no base (CLAUDE.md), so a Resource-typed field cannot reach it statically.
func _edited_name() -> String:
	var mod := current_item as WeaponModData
	if mod != null:
		return mod.display_name
	var item := current_item as Item
	return item.display_name if item != null else ""

func _set_edited_name(value: String) -> void:
	var mod := current_item as WeaponModData
	if mod != null:
		mod.display_name = value
		return
	var item := current_item as Item
	if item != null:
		item.display_name = value

func _on_update_pressed():
	var target := DevWidgets.selected_name(load_dropdown)
	if current_item == null or target == "":
		return
	# The handler is the real gate -- the disabled button is only its surface (#166 shape).
	var reason := _update_block_reason()
	if reason != "":
		status_label.text = reason
		return
	if _refuse_unusable(current_item):
		return
	# Overwrite the file the entry actually came from. The dropdown key is the item's NAME, and a
	# path rebuilt from it would miss any file whose basename differs.
	var path: String = _variants[target].resource_path
	if path == "":
		var msg := "%s has no file on disk to update" % target
		push_warning(msg)
		status_label.text = msg
		return
	# Confirmed as well as load-gated (#380's convention): the gate cannot catch a mis-click at
	# the item you DID load.
	DevWidgets.confirm_overwrite(self, "item '%s'" % target, "the editor's values",
		func() -> void: _update_confirmed(path))


func _update_confirmed(path: String) -> void:
	if DevWidgets.save_over(current_item, path, status_label):
		_loaded_name = _edited_name()   # a rename moves the loaded identity with it
		_refresh_variant_list(_edited_name())

func _on_delete_pressed():
	var target := DevWidgets.selected_name(load_dropdown)
	if target == "":
		return
	DevWidgets.confirm_delete(self, "item '%s'" % target, func(): _delete_confirmed(target))

func _delete_confirmed(target: String) -> void:
	if not _variants.has(target):
		return   # catalog moved between the press and the Yes
	if DevWidgets.delete_saved_file(_variants[target].resource_path, "item", status_label):
		if target == _loaded_name:
			_loaded_name = ""
		_refresh_variant_list()

func _on_save_as_pressed():
	if current_item == null:
		return
	var entered_name := name_input.text.strip_edges()
	if entered_name == "":
		var msg := "Item needs a name to save"
		push_warning(msg)
		status_label.text = msg
		return
	if DevWidgets.refuse_illegal_name(entered_name, "item", status_label):
		return
	if _refuse_unusable(current_item):
		return
	var dir := _save_dir_for(current_item)
	var path := dir + entered_name + ".tres"
	if DevWidgets.refuse_existing_file(path, "item", status_label):
		return
	_set_edited_name(entered_name)
	if DevWidgets.save_over(current_item, path, status_label):
		_loaded_name = entered_name   # save_over take_over_path'd it: the editor now holds this file
		name_input.text = ""
		_refresh_variant_list(entered_name)

func populate():
	for child in editor_container.get_children():
		editor_container.remove_child(child)
		child.queue_free()
	if current_item == null:
		return
	DevWidgets.add_lineedit(editor_container, "Item name", _edited_name(), func(s: String): _set_edited_name(s))
	if current_item is RuneData:
		_populate_rune_editor(current_item)
	elif current_item is WeaponInstance:
		_populate_weapon_editor(current_item)
	elif current_item is WeaponModData:
		_populate_mod_editor(current_item)
	elif current_item is WeaponData:
		_populate_prototype_editor(current_item)
	else:
		DevWidgets.build_resource_editor(editor_container, current_item, populate, ["weapon_type", "display_name"])

# A rune is a size + a capacity-bounded list of inscribed carvings. We only choose WHICH carvings
# to inscribe (authored in the Attack Editor tab); inscribe() enforces the capacity budget.
func _populate_rune_editor(rune: RuneData):
	var on_size := func(v):
		rune.size = v
		populate()

	var temper_label := "(blank — the first carving sets it, permanently)"
	if rune.temper != Elemental.Element.NONE:
		temper_label = Elemental.Element.keys()[rune.temper]
	DevWidgets.add_label(editor_container, "Temper: %s" % temper_label)
	if not rune.is_legal():
		DevWidgets.add_label(editor_container, "ILLEGAL: over a knob or breaks the temper rule — won't load from disk")

	DevWidgets.add_enum_option(editor_container, "Size", ",".join(RuneData.Size.keys()), rune.size, on_size)
	DevWidgets.add_label(editor_container, "Capacity: %d / %d used" % [rune.used_capacity(), rune.capacity()])
	DevWidgets.add_label(editor_container, "Inscriptions:")

	for i in range(rune.inscriptions.size()):
		var carving: TransmutationData = rune.inscriptions[i]
		var idx := i
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s (cost %d)" % [_carving_label(carving), carving.cost()]
		label.custom_minimum_size = Vector2(160, 0)
		row.add_child(label)
		var remove := Button.new()
		remove.text = "Remove"
		remove.pressed.connect(func():
			rune.inscriptions.remove_at(idx)
			populate()
		)
		row.add_child(remove)
		editor_container.add_child(row)

	var carvings := TransmutationCatalog.get_all()
	if carvings.is_empty():
		DevWidgets.add_label(editor_container, "(no carvings in Resources/TransmutationData/)")
		return
	var add_row := HBoxContainer.new()
	var picker := OptionButton.new()
	for k in carvings:
		picker.add_item(k)
	add_row.add_child(picker)
	var add_btn := Button.new()
	add_btn.text = "Inscribe"
	add_btn.pressed.connect(func():
		var key = carvings.keys()[picker.selected]
		if rune.inscribe(carvings[key].duplicate(true)):
			populate()
		else:
			push_warning("Won't fit %s: capacity, circle cap, or temper rule" % key)
		)
	add_row.add_child(add_btn)
	editor_container.add_child(add_row)

func _carving_label(carving: TransmutationData) -> String:
	return carving.display_name if carving.display_name != "" else "carving"

# A weapon's per-item state is just its fitted mods (item 6/7, weapons.md). The template
# is shown read-only, never as a nested editable form — that's what the old reflection
# path got wrong: it silently let you mutate the shared family .tres through any one
# item's editor. Mirrors _populate_rune_editor's capacity-bounded fit/remove shape.
func _populate_weapon_editor(weapon: WeaponInstance) -> void:
	var template := weapon.template
	if template == null:
		DevWidgets.add_label(editor_container, "(no template)")
		return
	DevWidgets.add_label(editor_container, "Family: %s" % (template.display_name if template.display_name != "" else WeaponData.WeaponType.keys()[template.weapon_type]))
	DevWidgets.add_label(editor_container, "Weight: %d" % weapon.get_effective_weight())

	if template.weapon_type == WeaponData.WeaponType.PROSTHETIC:
		DevWidgets.add_option(editor_container, "Limb Kind", WeaponData.LimbKind.keys(), WeaponData.LimbKind.keys()[weapon.limb_kind],
			func(s): _on_limb_kind_picked(weapon, s))

	var mods := WeaponModCatalog.get_mods()
	for i in range(weapon.space_count()):
		_populate_mod_space(weapon, i, mods)

func _on_limb_kind_picked(weapon: WeaponInstance, kind_name: String) -> void:
	weapon.limb_kind = WeaponData.LimbKind[kind_name]
	populate()

func _populate_mod_space(weapon: WeaponInstance, index: int, mods: Dictionary) -> void:
	var capacity: int = weapon.template.mod_spaces[index]
	DevWidgets.add_label(editor_container, "Space %d: %d / %d used" % [index + 1, weapon.used_capacity(index), capacity])

	# space() hands back the LIVE array, which is what Remove below mutates through. It is untyped
	# (Godot has no nested typed arrays), so the element needs its type named.
	var fitted := weapon.space(index)
	for i in range(fitted.size()):
		var mod: WeaponModData = fitted[i]
		var idx := i
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "%s (size %d)" % [mod.display_name if mod.display_name != "" else mod.id, mod.size]
		label.custom_minimum_size = Vector2(160, 0)
		row.add_child(label)
		var remove := Button.new()
		remove.text = "Remove"
		remove.pressed.connect(func():
			fitted.remove_at(idx)
			populate()
		)
		row.add_child(remove)
		editor_container.add_child(row)

	if mods.is_empty():
		DevWidgets.add_label(editor_container, "(no mods in Resources/WeaponMods/)")
		return

	# The picker lists what this WEAPON could ever take, not what fits right now (#74). A family
	# refusal is permanent, so showing those entries is offering a door that never opens; a full
	# space is live state you fix by removing something, so those stay listed and are refused WITH
	# THE REASON. That split is #166's policy call — grey (or here, refuse) only what you can
	# explain, hide what would never be true.
	var offerable := {}
	for k in mods:
		var mod: WeaponModData = mods[k]
		if mod.fits_family(weapon.template.weapon_type):
			offerable[k] = mod
	if offerable.is_empty():
		# The FAMILY, not the template's own name — a prototype called The Jaw takes Chainsword
		# mods, so naming the template here would say the wrong thing. Deliberately not the
		# "Family:" line above, which answers what this weapon IS rather than what gates its mods.
		var family_name: String = WeaponData.WeaponType.keys()[weapon.template.weapon_type].capitalize()
		DevWidgets.add_label(editor_container, "(no mods fit %s)" % family_name)
		return

	var add_row := HBoxContainer.new()
	var picker := OptionButton.new()
	for k in offerable:
		picker.add_item(k)
	add_row.add_child(picker)
	var add_btn := Button.new()
	add_btn.text = "Fit"
	add_btn.pressed.connect(func():
		var key = offerable.keys()[picker.selected]
		# a direct ref, not a duplicate — WeaponModCatalog's header already documents mods as
		# live-shared, the same model as templates
		var reason := weapon.fit_block_reason(index, offerable[key])
		if reason != "":
			push_warning(reason)
			status_label.text = reason
			return
		weapon.fit(index, offerable[key])
		populate()
	)
	add_row.add_child(add_btn)
	editor_container.add_child(add_row)

# A mod is scalars + two grant LISTS + two stat dictionaries. The reflective editor draws the
# scalars; the other four get bespoke UI here, because build_resource_editor has no arm for an
# Array or a Dictionary and silently draws nothing for either.
#
# scaling_change is in that second group and PREDATES #74 -- it has been undrawn since the field was
# written, so this is the first build in which every field of a mod is actually editable. `family`
# joins it as bespoke UI: the two are one control surface, since a scaling change is meaningless
# until a family says what it is measured against.
const MOD_SKIP := ["display_name", "family", "replaces_main", "scaling_change", "stat_modifiers", "granted_attacks", "granted_abilities"]

func _populate_mod_editor(mod: WeaponModData) -> void:
	DevWidgets.build_resource_editor(editor_container, mod, populate, MOD_SKIP)
	_populate_mod_family(mod)
	_populate_mod_replacement(mod)
	_populate_scaling_change(mod)
	_populate_mod_grants(mod)

# The family picker. Changing it re-measures the scaling against the NEW family's main, which is
# why it rebuilds -- the sliders' whole meaning is relative to that reference.
func _populate_mod_family(mod: WeaponModData) -> void:
	var first := editor_container.get_child_count()
	DevWidgets.add_option(editor_container, "Fits family", WeaponData.WeaponType.keys(),
		WeaponData.WeaponType.keys()[mod.family],
		func(s: String):
			mod.family = WeaponData.WeaponType[s]
			populate()
	)
	_tip_from(first, DevWidgets.property_tip(mod, "family"))

# The main-replacement picker (#529). A lone object @export WOULD auto-render, through
# build_resource_editor's resource swapper -- which then nests a LIVE editor for the attack it
# points at, making the mod panel a back door into content the Attack Editor owns. Same reason
# a prototype's own main gets a picker rather than the auto arm.
func _populate_mod_replacement(mod: WeaponModData) -> void:
	var first := editor_container.get_child_count()
	var choices := _main_choices(NO_REPLACEMENT_KEY)
	var current_key := _key_for(choices, mod.replaces_main, NO_REPLACEMENT_KEY)
	DevWidgets.add_option(editor_container, "Replaces main", choices.keys(), current_key,
		func(s: String):
			mod.replaces_main = choices[s]
			populate()
	)
	_tip_from(first, DevWidgets.property_tip(mod, "replaces_main"))

# ABSOLUTE in, DELTA at rest (#74, dev ruling). You author the percentages you want the weapon to
# scale off; what is stored is the difference from the family main attack's own blend, so every
# attack that weapon fires moves by the same amount and keeps its own character.
#
# NO FAMILY, NO SLIDERS. A change is measured against one family's main and means nothing without
# it, so the door simply is not there yet -- which makes the derived rule visible rather than
# letting you author a number with nothing behind it.

func _populate_scaling_change(mod: WeaponModData) -> void:
	if mod.family == WeaponData.WeaponType.NONE:
		DevWidgets.add_label(editor_container,
			"Damage scaling: pick a family first — a change is measured against that family's main attack.")
		return
	var family_name: String = WeaponData.WeaponType.keys()[mod.family].capitalize()
	var reference := _reference_blend(mod.family)
	if reference.is_empty():
		DevWidgets.add_label(editor_container,
			"Damage scaling: %s has no main attack blend to measure against." % family_name)
		return

	var absolute := _absolute_blend(reference, mod.scaling_change)
	# Names the MAIN, deliberately. "what this weapon scales off" would say a weapon has one blend,
	# which is the assumption #485 abolished -- the main is the REFERENCE the number is measured
	# against, not the only thing the shift reaches (see the stored line below).
	DevWidgets.add_label(editor_container, "%s main scales %s — drag to where its MAIN should land:"
		% [family_name, Stats.blend_text(reference)])

	# Built now, parented AFTER the sliders so it reads below them, and refreshed from the callback
	# rather than by rebuilding: populate() on every drag tick would tear the slider out from under
	# the mouse. It carries the STORED shift, which is the half the sliders cannot show.
	var stored := Label.new()
	var refresh := func() -> void:
		stored.text = "   stored shift: %s%s" % [_shift_text(mod.scaling_change),
			"" if mod.scaling_change.is_empty() else " — applied to EVERY attack this weapon fires"]
	DevWidgets.add_blend_sliders(editor_container, absolute,
		func():
			_store_scaling_change(mod, reference, absolute)
			refresh.call(),
		DevWidgets.property_tip(mod, "scaling_change"))
	refresh.call()
	editor_container.add_child(stored)

func _reference_blend(family: WeaponData.WeaponType) -> Dictionary:
	var blend: Dictionary[Stats.Stat, int] = {}
	var main := WeaponCatalog.family_main(family)
	if main == null:
		return blend
	for stat: Stats.Stat in main.scaling_blend:
		blend[stat] = main.scaling_blend[stat]
	return blend

# What the sliders start on. Clamped at zero exactly as WeaponInstance.effective_blend clamps it,
# so the panel shows what the weapon would really scale off -- including the DRIFT case, where a
# family main retuned since this mod was authored makes the absolutes move (dev ruling: keep the
# drift, make it visible). A drifted total will not be 100; the first drag re-pins it.
func _absolute_blend(reference: Dictionary, change: Dictionary) -> Dictionary:
	var absolute: Dictionary[Stats.Stat, int] = {}
	for stat: Stats.Stat in Stats.SCALING_STATS:
		var value: int = maxi(0, int(reference.get(stat, 0)) + int(change.get(stat, 0)))
		if value != 0:
			absolute[stat] = value   # zero means absent, the same rule the sliders themselves keep
	return absolute

# The inverse, run on every slider change. Zero means absent here too: a stat the mod does not move
# is not an entry worth storing, and writing it would grow every saved mod four keys wide.
func _store_scaling_change(mod: WeaponModData, reference: Dictionary, absolute: Dictionary) -> void:
	for stat: Stats.Stat in Stats.SCALING_STATS:
		var shift: int = int(absolute.get(stat, 0)) - int(reference.get(stat, 0))
		if shift == 0:
			mod.scaling_change.erase(stat)
		else:
			mod.scaling_change[stat] = shift

func _shift_text(change: Dictionary) -> String:
	if change.is_empty():
		return "none — this mod leaves the family's scaling alone"
	var parts: Array[String] = []
	for stat: Stats.Stat in Stats.SCALING_STATS:
		if change.has(stat):
			parts.append("%s %+d" % [Stats.Stat.keys()[stat], change[stat]])
	return ", ".join(parts)

func _populate_mod_grants(mod: WeaponModData) -> void:
	DevWidgets.add_stat_dict(editor_container, "Wielder stat modifiers", mod.stat_modifiers,
		DevWidgets.property_tip(mod, "stat_modifiers"))
	_populate_grant_list("Granted attacks:", mod.granted_attacks, WeaponAttackCatalog.get_library(),
		"(no attacks in %s)" % WeaponAttackCatalog.LIBRARY_DIR, DevWidgets.property_tip(mod, "granted_attacks"))
	_populate_grant_list("Granted abilities:", mod.granted_abilities, AbilityCatalog.get_abilities(),
		"(no abilities in %s)" % AbilityCatalog.ABILITY_DIR, DevWidgets.property_tip(mod, "granted_abilities"))

# One "list + remove + pick-and-add" block, used for both grant lists. Same shape as the rune
# inscribe list and the mod fitting list above, minus their capacity budget: a grant costs nothing
# on its own, since what a mod costs is its own `size` in the space it is fitted to.
func _populate_grant_list(title: String, entries: Array, catalog: Dictionary, empty_text: String, tooltip: String) -> void:
	var first := editor_container.get_child_count()
	DevWidgets.add_label(editor_container, title)
	for i in range(entries.size()):
		var idx := i
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = _grant_label(entries[idx])
		label.custom_minimum_size = Vector2(160, 0)
		row.add_child(label)
		var remove := Button.new()
		remove.text = "Remove"
		remove.pressed.connect(func():
			entries.remove_at(idx)
			populate()
		)
		row.add_child(remove)
		editor_container.add_child(row)

	if catalog.is_empty():
		DevWidgets.add_label(editor_container, empty_text)
		_tip_from(first, tooltip)
		return
	var add_row := HBoxContainer.new()
	var picker := OptionButton.new()
	for k in catalog:
		picker.add_item(k)
	add_row.add_child(picker)
	var add_btn := Button.new()
	add_btn.text = "Add"
	add_btn.pressed.connect(func():
		var key = catalog.keys()[picker.selected]
		var picked: Resource = catalog[key]
		# A direct ref, not a duplicate -- same live-sync model as a fitted mod, so editing the
		# authored attack or ability updates every mod granting it.
		if picked != null and not entries.has(picked):
			entries.append(picked)
			populate()
	)
	add_row.add_child(add_btn)
	editor_container.add_child(add_row)
	_tip_from(first, tooltip)

# Tooltip every control this block just added -- Godot does not walk up to a parent, so the row is
# identified by the children that appeared (DevWidgets._tip_rows_from's shape, which is private).
func _tip_from(first: int, tooltip: String) -> void:
	if tooltip == "":
		return
	for i in range(first, editor_container.get_child_count()):
		DevWidgets.apply_tooltip(editor_container.get_child(i), tooltip)

# Both grant kinds carry a display_name, but off different roots (AttackData / AbilityData), so
# there is no shared base to read it from.
func _grant_label(entry: Resource) -> String:
	var attack := entry as AttackData
	if attack != null:
		return attack.display_name if attack.display_name != "" else "attack"
	var ability := entry as AbilityData
	if ability != null:
		return ability.display_name if ability.display_name != "" else "ability"
	return "(unknown)"

# Which catalog folder a new file belongs in. Each kind is scanned from its own directory, so the
# fork is the catalogs' own rather than this tool's invention.
func _save_dir_for(item: Resource) -> String:
	if item is RuneData:
		return RuneCatalog.VARIANT_DIR
	if item is WeaponModData:
		return WeaponModCatalog.MOD_DIR
	if item is WeaponData:
		return WeaponCatalog.PROTOTYPE_DIR
	return WeaponCatalog.SAVED_DIR

# --- Prototype mode (#486) ---

# Refuse to WRITE content nothing could use. ONE door for every kind this tab authors, because
# "may this be saved" is one question -- a second gate beside it is exactly the duplicate seam this
# tool would grow first. Both Update and Save As call it; each kind answers in its own terms and
# everything else passes straight through.
func _refuse_unusable(item: Resource) -> bool:
	var template := item as WeaponData
	if template != null:
		return _refuse_template(template)
	var mod := item as WeaponModData
	if mod != null:
		return _refuse_with(mod.save_block_reason())
	return false

# A template nobody could carry. Only BLOCKS stops the save, on AttackEditorTool's reasoning: a
# DEGRADES finding describes a file that may already be on disk in that state, so refusing would
# leave the only tool that can repair it unable to write.
func _refuse_template(template: WeaponData) -> bool:
	var findings := WeaponTemplateLint.check(template)
	for finding in findings:
		if finding["severity"] == WeaponTemplateLint.Severity.BLOCKS:
			return _refuse_with(finding["text"])
	if not findings.is_empty():
		status_label.text = findings[0]["text"]   # said, not refused
	return false

func _refuse_with(reason: String) -> bool:
	if reason == "":
		return false
	push_warning(reason)
	status_label.text = reason
	return true

# What the reflective editor must NOT draw here, for two different reasons. THREE are not drawn at
# all: display_name has its own LineEdit above the form, is_prototype is forced true (a Prototype
# mode offering to untick it is a door to nowhere), and extra_attacks belongs to the Attack Editor's
# Weapon Families mode. The other THREE are drawn BESPOKE below and skipped here only so they are
# not drawn twice.
#
# So this list is deliberately LONGER than the coverage law's in tests/dev/test_property_tips.gd,
# which skips only the first three -- the mod editor's split exactly. A field with bespoke UI still
# reaches a control, so it still owes text; being undrawable reflectively is not an excuse.
const PROTOTYPE_SKIP := ["display_name", "is_prototype", "extra_attacks", "weapon_type", "main_attack", "mod_spaces"]

# The SpinBox bound on a space's capacity. A widget affordance, not a rule: mods are size 1-3, so
# anything past a few is off-doctrine rather than illegal, and nothing in the model refuses it.
const MAX_SPACE_CAPACITY := 9

# The main-attack picker's "no main" row. A template with none is a legitimate intermediate state
# (the lint DEGRADES it rather than refusing), so the picker has to be able to express it.
const NO_MAIN_KEY := "(none)"
const NO_REPLACEMENT_KEY := "(the weapon's own)"

# Every attack that can stand as a main, catalog mains first. TWO pickers ask it -- a prototype's
# own main and a mod's replacement (#529) -- so it is one answer rather than two loops that could
# drift about which catalogs count.
func _main_choices(none_key: String) -> Dictionary:
	var choices := {none_key: null}
	for source: Dictionary in [WeaponAttackCatalog.get_mains(), WeaponAttackCatalog.get_library()]:
		for k in source:
			if not choices.has(k):    # a library attack sharing a main's name loses; one name, one entry
				choices[k] = source[k]
	return choices

func _key_for(choices: Dictionary, value: Variant, fallback: String) -> String:
	for k in choices:
		if choices[k] == value:
			return k
	return fallback

func _populate_prototype_editor(template: WeaponData) -> void:
	DevWidgets.add_label(editor_container, "Editing a TEMPLATE, not a carried weapon -- every weapon built on it reads this live.")
	_populate_prototype_family(template)
	_populate_prototype_main(template)
	_populate_mod_spaces(template)
	DevWidgets.build_resource_editor(editor_container, template, populate, PROTOTYPE_SKIP)
	for finding in WeaponTemplateLint.check(template):
		DevWidgets.add_label(editor_container, "%s: %s" % [WeaponTemplateLint.severity_word(finding), finding["text"]])

func _populate_prototype_family(template: WeaponData) -> void:
	var first := editor_container.get_child_count()
	DevWidgets.add_option(editor_container, "Family", WeaponData.WeaponType.keys(),
		WeaponData.WeaponType.keys()[template.weapon_type],
		func(s: String): _on_prototype_family_picked(template, s))
	_tip_from(first, DevWidgets.property_tip(template, "weapon_type"))

# Picking the family AUTO-FILLS its main attack, as the ask asked -- but only over a main that was
# itself auto-filled. A deliberate library pick survives a family change, because refilling over it
# would silently discard an authoring decision; re-picking the same family is then how you get the
# stock main back.
func _on_prototype_family_picked(template: WeaponData, family_name: String) -> void:
	var picked: WeaponData.WeaponType = WeaponData.WeaponType[family_name]
	if picked == template.weapon_type:
		return
	template.weapon_type = picked
	if template.main_attack == null or _is_a_family_main(template.main_attack):
		template.main_attack = WeaponCatalog.family_main(picked)
	populate()

func _is_a_family_main(attack: WeaponAttackData) -> bool:
	return WeaponAttackCatalog.get_mains().values().has(attack)

# A PICKER, never an authoring surface. Everything it lists is a file the Attack Editor wrote, and
# the pick is a direct ref -- so a prototype that never swaps follows its family's retunes, and one
# that does is pointed at content that already exists. This mode writes no attack file at all.
func _populate_prototype_main(template: WeaponData) -> void:
	var first := editor_container.get_child_count()
	var choices := _main_choices(NO_MAIN_KEY)
	var current_key := _key_for(choices, template.main_attack, NO_MAIN_KEY)
	DevWidgets.add_option(editor_container, "Main attack", choices.keys(), current_key,
		func(s: String):
			template.main_attack = choices[s]
			populate()
	)
	_tip_from(first, DevWidgets.property_tip(template, "main_attack"))

# #486's authorable half: both the COUNT and each capacity are the author's. Nothing here caps the
# count -- proficiency decides what a wielder reaches, and a template is free to author more spaces
# than any unit can currently use.
func _populate_mod_spaces(template: WeaponData) -> void:
	var first := editor_container.get_child_count()
	DevWidgets.add_label(editor_container, "Mod spaces (%d):" % template.mod_spaces.size())
	for i in range(template.mod_spaces.size()):
		var idx := i
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = "Space %d capacity" % (idx + 1)
		label.custom_minimum_size = Vector2(160, 0)
		row.add_child(label)
		var spin := SpinBox.new()
		spin.min_value = 1     # a zero-capacity space is one nothing can ever fit; the lint owns the .tres door
		spin.max_value = MAX_SPACE_CAPACITY
		spin.value = template.mod_spaces[idx]
		spin.value_changed.connect(func(v: float): template.mod_spaces[idx] = int(v))
		row.add_child(spin)
		var remove := Button.new()
		remove.text = "Remove"
		remove.pressed.connect(func():
			template.mod_spaces.remove_at(idx)
			populate()
		)
		row.add_child(remove)
		editor_container.add_child(row)

	var add := Button.new()
	add.text = "Add space"
	add.pressed.connect(func():
		template.mod_spaces.append(1)
		populate()
	)
	editor_container.add_child(add)
	_tip_from(first, DevWidgets.property_tip(template, "mod_spaces"))
