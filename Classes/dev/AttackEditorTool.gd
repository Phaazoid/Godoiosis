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
# resource_path instead of a chosen pool filename.
#
# THE FORM IS DRAWN IN SECTIONS THE RESOURCE DECLARES (#825) -- AttackData.property_sections walks
# the fields, this file draws each one, and a field with no bespoke drawer falls through to
# DevWidgets' reflective row. So a new @export lands in its declared section with no code here at
# all, and there is no skip list to forget to update: a field is drawn because it is DECLARED, not
# because nobody excluded it. Which rows are HIDDEN right now is the resource's answer too
# (hidden_fields), applied live off `changed` rather than by rebuilding -- see DevWidgets.
#
# Six fields get a bespoke drawer instead, each because a reflective control cannot express what
# is being authored: the RANGE trio (one toggle over max_range 0, which is a different kind of
# attack rather than a shorter one), the SHAPE (a shared library file needs picking, naming and
# deleting -- #808), the EFFECT LOOKS (the same, once per element, with a page of override rows
# under each -- #900), the EFFECT pair (two bools over one three-way question), the damage KIND
# (NONE is answered by rule and must never be offered) and the empowered form (a picker, never a
# nested editor). The blend, sigils and flourishes were already bespoke for their own reasons.
#
# A SECTION HIDES WITH ITS ROWS since #900 -- the look section is the first that can be empty, and a
# heading drawn over nothing is worse than an absent section. Derived in _draw_sections rather than
# declared, so the resource states relevance once (hidden_fields) and not twice.
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

# The three-way EFFECT choice, which is what `heals` and `deals_no_damage` are between them: two
# bools over one question, kept as two fields because `heals` has eight production readers, but
# authored as one control so the both-true state is unrepresentable rather than merely refused.
const EFFECT_DAMAGE := "Damage"
const EFFECT_HEAL := "Heal"
const EFFECT_NONE := "No damage"

# The shape picker's two non-file rows, in the order they are added -- (none) FIRST, for the reason
# DevWidgets._add_resource_swapper spells out: add_item silently selects the row it is handed, so
# the empty state has to be row zero or the control claims a shape on an attack that has none.
const NO_SHAPE_KEY := "(none - the aimed cell alone)"
const NEW_SHAPE_KEY := "(new shape)"
const UNNAMED_SHAPE_KEY := "(unnamed - Save as... to name it)"
const NO_EMPOWERED_KEY := "(none — fires the same however full the tank is)"
const NO_PAYLOAD_KEY := "(none - drops nothing)"
# The worst case a payload chain may fan out to before the readout warns (#1058, ruling 41: a warning,
# never a refusal). A feel number, so a const rather than a rule anything else reads.
const FANOUT_WARN := 16
const FANOUT_WARN_COLOR := Color(1.0, 0.6, 0.3)

# ...and the look picker's three, worded for what THEY explain (#900). Same order and same reason.
const NO_LOOK_KEY := "(none - the Game tab's own values)"
const NEW_LOOK_KEY := "(new look)"
const UNNAMED_LOOK_KEY := "(unnamed - Save as... to name it)"

var _mode := Mode.TRANSMUTATION
var current: AttackData = null
var current_template: WeaponData = null   # FAMILY only: which family "current" belongs to
# The two SHARED-LIBRARY fields this form edits, both on `LibraryField` since #900: what the grid
# stamps, and one look per element the loaded attack can author for. Each holds a COPY of the
# library resource it points at, never the library resource itself -- editing the shared object
# would break the commit-point ruling (Update, not every keystroke) and make Save As impossible,
# take_over_path moving the object every other attack is still holding.
var _shape: LibraryField = null
var _looks: Dictionary[Elemental.Element, LibraryField] = {}
var _items := {}
# Which dropdown entry "current" was loaded from ("" = a New attack). Pool modes load a COPY with
# no resource_path, so nothing else records this -- and Update's load-gate needs it (2026-08-11).
var _loaded_name := ""
# The Payload section's live readouts (#1058), refreshed off the attack's `changed` rather than by a
# rebuild, so the plate and the sentences follow the tick, the targets and the shape as they move.
var _payload_plate: ShapePlate = null
var _payload_where: Label = null
var _payload_fanout: Label = null

func _ready():
	_shape = LibraryField.new(self, status_label)
	_shape.noun = "shape"
	_shape.library_dir = AttackShapeCatalog.LIBRARY_DIR
	_shape.none_key = NO_SHAPE_KEY
	_shape.new_key = NEW_SHAPE_KEY
	_shape.unnamed_key = UNNAMED_SHAPE_KEY
	_shape.list = func() -> Dictionary: return AttackShapeCatalog.get_library()
	_shape.held = func() -> Resource: return null if current == null else current.attack_shape
	_shape.assign = func(picked: Resource) -> void:
		if current != null:
			current.attack_shape = picked as AttackShape
	_shape.make = func() -> Resource: return AttackShape.new()
	_shape.refresh = populate
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
		_stage_fields()
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
	_stage_fields()
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
	# A new attack arrives FIREABLE with no shape at all: the range defaults to 1 and a null shape
	# covers the aimed cell, which is an ordinary single-target attack rather than the useless state
	# a pattern-less attack used to be (#808). The shape row is where it gains a footprint -- either
	# by adopting a library shape or by starting a new one.
	_stage_fields()
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
	if _refuse_unfireable(_staged_attack()):
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
		victim += _shared_victims()
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
	DevWidgets.confirm_overwrite(self, "attack '%s'%s" % [target, _shared_victims()], "the editor's values",
		func() -> void: _update_confirmed(path))


func _update_confirmed(path: String) -> void:
	if not _save_shared_files():
		return
	if DevWidgets.save_over(current, path, status_label):
		_loaded_name = current.display_name   # a rename moves the loaded identity with it
		_refresh_list(current.display_name)


# The main first, then the family. A partial write is possible and is REPORTED rather than rolled
# back -- save_over already puts its own failure in the status label, and the half that landed is
# on disk either way.
func _update_family_confirmed(family_path: String, main_path: String) -> void:
	if not _save_shared_files():
		return
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
	if _refuse_unfireable(_staged_attack()):
		return
	var dir := TransmutationCatalog.CARVING_DIR if _mode == Mode.TRANSMUTATION else WeaponAttackCatalog.LIBRARY_DIR
	var path := dir + chosen_name + ".tres"
	if DevWidgets.refuse_existing_file(path, "attack", status_label):
		return
	if not _save_shared_files():
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
	_draw_sections()


# The form, section by section, in the order the RESOURCE declares (#825).
#
# A field with a bespoke drawer is handed to it, and the drawer says which fields it CONSUMED -- the
# range block owns three -- so the walker skips them wherever they appear later in the list. Every
# other field draws through DevWidgets' reflective row, which is what makes a new @export a
# one-line declaration on the resource rather than an edit here.
#
# `rows` collects field -> the nodes drawing it, for the one bind_hidden_fields call at the end.
# A drawer registers its own rows only where hiding is meaningful; a block nothing can hide (the
# sigils, the shape) simply does not, and an unregistered field is ignored by the binder.
func _draw_sections() -> void:
	var rows := {}
	var drawn := {}
	var headings: Array[Dictionary] = []
	for section: Dictionary in current.call("property_sections"):
		var title: String = section["title"]
		var heading := DevWidgets.add_heading(editor_container, title)
		var before := rows.size()
		var here: PackedStringArray = []
		for field: String in section["fields"]:
			if drawn.has(field):
				continue
			for claimed: String in _draw_field(field, rows):
				drawn[claimed] = true
				here.append(claimed)
		var tail := _section_tail(title)
		# A HEADING HIDES WITH ITS OWN ROWS (#900) -- but only when every row the section drew is one
		# the binder governs. A section whose fields are partly bespoke (the range block owns its own
		# visibility and registers nothing) still has something visible under it, so its title stays;
		# a title drawn over nothing at all is worse than an absent section. Derived here rather than
		# declared on the resource, so a new fully-hideable section needs no second statement.
		if not tail and rows.size() > before and rows.size() - before == here.size():
			headings.append({"nodes": heading, "fields": _registered(here, rows)})
	DevWidgets.bind_hidden_fields(current, rows, headings)


# The registered field names among the ones a section drew, as the binder wants them.
func _registered(drawn_here: PackedStringArray, rows: Dictionary) -> PackedStringArray:
	var named: PackedStringArray = []
	for field in drawn_here:
		if rows.has(field):
			named.append(field)
	return named


# One field, and the names it consumed. The match is the whole list of fields this panel authors
# by hand; anything else is reflective, which is the default rather than the exception.
func _draw_field(field: String, rows: Dictionary) -> PackedStringArray:
	match field:
		"max_range":
			return _populate_range()
		"attack_shape":
			_populate_shape()
			return PackedStringArray(["attack_shape"])
		"effect_looks":
			# REGISTERED EVEN WHEN IT DREW NOTHING, which is the whole point: an attack carrying no
			# lookable element draws no rows, and it is exactly then that the heading has to hide.
			# An unregistered field leaves its title standing over an empty section.
			var first := editor_container.get_child_count()
			_populate_effect_looks()
			rows["effect_looks"] = DevWidgets._added_since(editor_container, first)
			return PackedStringArray(["effect_looks"])
		"heals":
			return _populate_effect()
		"damage_kind":
			_populate_kind(rows)
			return PackedStringArray(["damage_kind"])
		"scaling_blend":
			_populate_blend(rows)
			return PackedStringArray(["scaling_blend"])
		"empowered_form":
			_populate_empowered_form(current as WeaponAttackData, rows)
			return PackedStringArray(["empowered_form"])
		"payload":
			_populate_payload()
			return PackedStringArray(["payload"])
		"sigils":
			_populate_sigils(current as TransmutationData)
			return PackedStringArray(["sigils"])
		"flourishes":
			_populate_flourishes(current as TransmutationData)
			return PackedStringArray(["flourishes"])
	var added := DevWidgets.add_property_row(editor_container, current, field, populate)
	if not added.is_empty():
		rows[field] = added
	return PackedStringArray([field])


# A line this panel adds under a section that is not a field of the attack at all. Carriers answer
# "can anything actually swing this", which is an identity question about the loaded file rather
# than a property, so it belongs under Identity and not in a section of its own.
#
# TRUE when it added something, which is what stops that section's heading joining the hide rule
# above: a tail is not a registered field, so it would go on drawing under a hidden title.
func _section_tail(title: String) -> bool:
	if title == "Identity" and _mode == Mode.WEAPON_ATTACK:
		_populate_carriers()
		return true
	return false


# The RANGE fork as ONE toggle (#825; dev, 2026-09-07: "there should be a toggle here between max
# range being 0, which means its a melee hit, and if it is greater than 0, the min/max options
# appear... except when the max range is 0, it should reflect more clearly what is going on").
#
# THE TOGGLE STORES NOTHING. It renders `max_range > 0`, because the anchor is DERIVED from the
# range and is never a flag (#802 ruling 1) -- a stored "is placed" bool would be the second answer
# that ruling exists to refuse. Off writes 0; on writes whatever the Max spinbox is showing, and the
# range a self-anchored attack had before is deliberately not remembered (one keystroke, in a dev
# tool). The label avoids the word MELEE on purpose: VerticalRule.MELEE is a different axis
# entirely, and a range-1 spear thrust is a placed attack under the melee height rule.
#
# THIS BLOCK OWNS ITS OWN ROWS' VISIBILITY and registers nothing with bind_hidden_fields. The Min
# spinbox shows only when the attack is placed AND the custom-minimum box is ticked, and that
# conjunction is not something hidden_fields can express -- registering min_range in both would let
# the binder win on the next `changed` and silently drop the tick.
func _populate_range() -> PackedStringArray:
	var attack := current
	var max_tip := DevWidgets.property_tip(attack, "max_range")
	var min_tip := DevWidgets.property_tip(attack, "min_range")

	var placed := _check("Placed at range", attack.max_range > 0, max_tip)

	var facing_note := Label.new()
	facing_note.text = "Fires from the attacker: the aim is a FACING, and the whole shape turns to it."
	facing_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor_container.add_child(facing_note)

	# maxi(1, ...) rather than the stored value: at range 0 this row is hidden, and what it shows is
	# what ticking the toggle would write. Setting min_value on a SpinBox already holding 0 would
	# CLAMP it and emit value_changed, i.e. silently make a facing attack ranged just by opening it.
	var max_at := editor_container.get_child_count()
	var max_spin := DevWidgets.add_spinbox(editor_container, "Max range", maxi(1, attack.max_range),
		func(v: float) -> void: DevWidgets.write(attack, "max_range", int(v)))
	max_spin.min_value = 1
	var max_row := editor_container.get_child(max_at)
	DevWidgets._tip_rows_from(editor_container, max_at, max_tip)

	# Ticked when the stored minimum is not the ordinary 1 -- which covers both authored shapes, a
	# self-targetable heal at 0 and a carbine's dead zone at 2+. Derived at BUILD time only: once
	# the box is on screen its tick is the dev's, so re-deriving it on `changed` would untick it the
	# instant it was ticked (min_range is still 1 until they type a new one).
	var custom := _check("Custom minimum range", attack.min_range != 1, min_tip)

	var min_at := editor_container.get_child_count()
	var min_spin := DevWidgets.add_spinbox(editor_container, "Min range", attack.min_range,
		func(v: float) -> void: DevWidgets.write(attack, "min_range", int(v)))
	min_spin.min_value = 0
	var min_row := editor_container.get_child(min_at)
	DevWidgets._tip_rows_from(editor_container, min_at, min_tip)

	var half_at := editor_container.get_child_count()
	DevWidgets.add_checkbox(editor_container, "Max and a half", attack.max_and_a_half,
		func(on: bool) -> void: DevWidgets.write(attack, "max_and_a_half", on),
		DevWidgets.property_tip(attack, "max_and_a_half"))
	var half_row := editor_container.get_child(half_at)

	var sync := func() -> void:
		var is_placed: bool = attack.max_range > 0
		placed.set_pressed_no_signal(is_placed)
		facing_note.visible = not is_placed
		max_row.visible = is_placed
		custom.visible = is_placed
		min_row.visible = is_placed and custom.button_pressed
		half_row.visible = is_placed
		if is_placed:
			max_spin.set_value_no_signal(attack.max_range)

	placed.toggled.connect(func(on: bool) -> void:
		DevWidgets.write(attack, "max_range", int(max_spin.value) if on else 0))
	# Ticking writes nothing -- the minimum is already whatever it is -- so this calls sync itself;
	# UNticking writes 1 and reaches sync through `changed` like every other edit.
	custom.toggled.connect(func(on: bool) -> void:
		if on:
			sync.call()
		else:
			DevWidgets.write(attack, "min_range", 1))

	# The rows follow the range live, off the write hook -- add_cell_grid's caption idiom, and the
	# connection is dropped with the block for the same reason (a lambda has no object to
	# auto-disconnect against).
	attack.changed.connect(sync)
	placed.tree_exiting.connect(func() -> void:
		if attack.changed.is_connected(sync):
			attack.changed.disconnect(sync))
	sync.call()
	return PackedStringArray(["max_range", "min_range", "max_and_a_half"])


# A CheckBox this panel keeps a handle on, for a toggle whose state is DERIVED rather than stored.
# DevWidgets.add_checkbox returns void because a plain bool row needs no handle; these two do.
func _check(text: String, pressed: bool, tip: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = pressed
	editor_container.add_child(box)
	DevWidgets.apply_tooltip(box, tip)
	return box


# EITHER damage OR a heal OR neither, as one control (#825, dev ruling 2026-09-07). The two bools
# stay exactly as they are -- `heals` has eight production readers and this changes nothing about
# what is stored -- but authoring them separately let both be ticked, which is a state no rule has
# an answer for. Both are written before ONE emit_changed rather than through two write() calls:
# the pair is a single decision, and writing them one at a time makes the impossible state briefly
# real for every listener in between.
func _populate_effect() -> PackedStringArray:
	var attack := current
	var first := editor_container.get_child_count()
	var picked := EFFECT_DAMAGE
	if attack.heals:
		picked = EFFECT_HEAL
	elif attack.deals_no_damage:
		picked = EFFECT_NONE
	DevWidgets.add_option(editor_container, "Effect", [EFFECT_DAMAGE, EFFECT_HEAL, EFFECT_NONE], picked,
		func(choice: String) -> void:
			attack.heals = choice == EFFECT_HEAL
			attack.deals_no_damage = choice == EFFECT_NONE
			attack.emit_changed())
	DevWidgets._tip_rows_from(editor_container, first, DevWidgets.wrap_tooltip(
		"What the power number MEANS. Damage: it is dealt as damage of the kind below.\n"
		+ "Heal: it is restored as HP instead, capped at the target's maximum.\n"
		+ "No damage: a pure-utility attack -- scaling is suppressed entirely, so neither aura nor a "
		+ "weapon's stat blend can sneak damage into a damageless effect. A shove or an element still lands."))
	return PackedStringArray(["heals", "deals_no_damage"])


# The damage-kind row (#424), bespoke rather than reflective for one reason: NONE is on the roster
# so delivered_kind() can answer it, and must never be OFFERED -- a heal or a no-damage attack reads
# as None by rule. The reflective row would list all eight.
#
# BOTH the picker and the sentence standing in for it are built (#825), and the picker is registered
# so the binder hides it; the sentence is its exact inverse, off the same `changed` signal and the
# same rule (delivered_kind), so the two can never both be showing or both be gone. Before this the
# fork was made once at build time and a heal picked afterwards left the old picker on screen.
func _populate_kind(rows: Dictionary) -> void:
	var attack := current
	var note := Label.new()
	note.text = "Damage kind: None -- a heal or a no-damage attack delivers no kind."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor_container.add_child(note)

	var first := editor_container.get_child_count()
	var names: Array[String] = []
	for key: String in AttackData.Kind.keys():
		var value: int = AttackData.Kind[key]
		if value != AttackData.Kind.NONE:
			names.append("%s:%d" % [key.capitalize(), value])
	DevWidgets.add_enum_option(editor_container, "Damage kind", ",".join(names), attack.damage_kind,
		func(v: int) -> void: DevWidgets.write(attack, "damage_kind", v as AttackData.Kind))
	rows["damage_kind"] = DevWidgets._added_since(editor_container, first)
	DevWidgets._tip_rows_from(editor_container, first, DevWidgets.property_tip(attack, "damage_kind"))

	var sync := func() -> void:
		note.visible = attack.delivered_kind() == AttackData.Kind.NONE
	attack.changed.connect(sync)
	note.tree_exiting.connect(func() -> void:
		if attack.changed.is_connected(sync):
			attack.changed.disconnect(sync))
	sync.call()

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
		# A mode banner rather than a row, so it reads before the first heading rather than buried
		# between two fields of the Identity section.
		DevWidgets.add_label(editor_container, "Editing the MAIN attack for %s — changes every weapon of this family." % family_label)
		_draw_sections()
	_populate_extras(family_label)


# The SHAPE row (#808): pick one from the shared library, start a new one, name one, or delete one,
# with the stamp grid underneath. Bespoke rather than reflective because none of those verbs is a
# property edit -- and because the grid's caption has to come from the ATTACK, the shape having no
# range to derive an anchor from.
#
# The pick/name/fork/delete flow itself is `LibraryField` since #900, shared with the look rows
# below; what stays here is the part that is about SHAPES -- the caption, the grid, and the sentence
# a shapeless attack gets.
func _populate_shape() -> void:
	if current == null:
		return
	var tip := DevWidgets.property_tip(current, "attack_shape")
	_shape.draw_picker(editor_container, "Shape", tip)
	if _shape.staged == null:
		DevWidgets.add_label(editor_container, "No shape: this attack covers the cell it is aimed at.")
		return
	_shape.draw_users(editor_container, "Unnamed shape -- this attack alone. Save it to share it.")
	var first := editor_container.get_child_count()
	DevWidgets.add_cell_grid(editor_container, "Stamp", _shape.staged, "stamp", current, "path_cells", "path_lengths")
	DevWidgets._tip_rows_from(editor_container, first, tip)
	_shape.draw_save_row(editor_container)


# The LOOK rows (#900): per element this attack carries that HAS an attack-scoped effect, a picker
# over the shared look library and then every knob that effect owns, each with an inherit tick.
#
# The rows are a PROJECTION of GameKnobs.CLASS_KNOBS, never a table of this panel's own -- label,
# tooltip and range are already declared there for the Game tab, and a second copy would drift the
# first time a row was reworded. They are drawn through DevWidgets.add_knob_row for the same reason:
# one answer to how a bool, a colour and a float are drawn, whichever panel is asking.
#
# The SUB-HEADINGS are that table's own group names, which is what the #900 split bought: the Game
# tab and this form arrange the same values identically without either holding the arrangement.
func _populate_effect_looks() -> void:
	if current == null:
		return
	for element in current.lookable_elements():
		var field: LibraryField = _looks.get(element)
		if field == null:
			continue
		var name := Elemental.display_name(element)
		field.draw_picker(editor_container, "%s look" % name,
			DevWidgets.property_tip(current, "effect_looks"))
		if field.staged == null:
			DevWidgets.add_label(editor_container,
				"No look: %s plays exactly as the Game tab has it tuned." % name.to_lower())
			continue
		field.draw_users(editor_container,
			"Unnamed look -- this attack alone. Save it to share it.")
		_populate_look_rows(field, element)
		field.draw_save_row(editor_container)


# One look's rows, in the knob table's own order, grouped by its own group names.
func _populate_look_rows(field: LibraryField, element: Elemental.Element) -> void:
	var look := field.staged as EffectLook
	if look == null:
		return
	var heading := ""
	for knob: Dictionary in GameKnobs.look_rows(element):
		var group: String = knob["group"]
		if group != heading:
			heading = group
			DevWidgets.add_heading(editor_container, group)
		_populate_look_row(look, knob)


# An override row is TWO controls, ObjectTool's idiom and for its reason: the tick says whether this
# look has an opinion, the control says what it is, and an inheriting row SHOWS what it falls back
# to rather than an empty slot -- a row that cannot name its default sends you to the other panel.
#
# Unticking adopts the value the row currently RESOLVES to, so switching a row to authored never
# moves the effect by itself; re-ticking ERASES the key rather than writing a sentinel, which is the
# whole reason this storage has none (#660's trap cannot arise where absence is representable).
func _populate_look_row(look: EffectLook, knob: Dictionary) -> void:
	var key: String = knob["static"]
	var label: String = knob["label"]
	var tip: String = DevWidgets.wrap_tooltip(knob.get("tip", ""))
	var default: Variant = GameKnobs.read_static(key)
	var authored: bool = look.overrides.has(key)
	var first := editor_container.get_child_count()
	DevWidgets.add_checkbox(editor_container, "%s - inherit" % label, not authored,
		func(on: bool) -> void: _write_look(look, knob, on))
	if not authored:
		DevWidgets.add_label(editor_container, "    inherits %s" % _shown(default))
	else:
		DevWidgets.add_knob_row(editor_container, knob, look.overrides[key],
			func(moved: Variant) -> void: _set_look_value(look, key, moved), tip)
	DevWidgets._tip_rows_from(editor_container, first, tip)


# The tick. Ticking gives the row back to the Game tab; unticking adopts what it resolves to now.
func _write_look(look: EffectLook, knob: Dictionary, inherit: bool) -> void:
	var key: String = knob["static"]
	if inherit:
		look.overrides.erase(key)
	else:
		look.overrides[key] = GameKnobs.read_static(key)
	populate()


# A slider hands back a float whatever the value's own kind is, so the write is COERCED to the type
# the default wears -- read off the storage rather than from a list of which rows are ints, which is
# a second answer waiting to go stale.
func _set_look_value(look: EffectLook, key: String, moved: Variant) -> void:
	var default: Variant = GameKnobs.read_static(key)
	match typeof(default):
		TYPE_INT: look.overrides[key] = int(moved)
		TYPE_BOOL: look.overrides[key] = bool(moved)
		TYPE_COLOR: look.overrides[key] = Color(moved)
		_: look.overrides[key] = float(moved)


# What an inherited value reads as beside its tick. Colours as their hex, everything else plainly.
func _shown(value: Variant) -> String:
	if typeof(value) == TYPE_COLOR:
		return "#" + (value as Color).to_html(false)
	return str(value)


# Everything the form edits that is NOT a property of the attack itself: the staged stamp, and one
# staged look per element this attack can author for. Rebuilt whenever the loaded attack changes,
# because which look slots exist is the attack's own answer and it moves when its element does.
func _stage_fields() -> void:
	_shape.stage()
	_looks.clear()
	if current == null:
		return
	for element in current.lookable_elements():
		_looks[element] = _make_look_field(element)


# One element's look slot, bound to that key of the attack's dictionary. The picker offers only
# looks authored for THIS element and a new one is stamped with it, so the mismatch AttackLint
# reports cannot be produced by the panel at all -- only by hand-editing a file.
func _make_look_field(element: Elemental.Element) -> LibraryField:
	var field := LibraryField.new(self, status_label)
	field.noun = "look"
	field.library_dir = EffectLookCatalog.LIBRARY_DIR
	field.none_key = NO_LOOK_KEY
	field.new_key = NEW_LOOK_KEY
	field.unnamed_key = UNNAMED_LOOK_KEY
	field.list = func() -> Dictionary: return EffectLookCatalog.for_element(element)
	field.held = func() -> Resource: return null if current == null else current.look_for(element)
	field.assign = func(picked: Resource) -> void: _assign_look(element, picked as EffectLook)
	field.make = func() -> Resource:
		var fresh := EffectLook.new()
		fresh.element = element
		return fresh
	field.refresh = populate
	field.stage()
	return field


# An absent slot and a null slot are the same state, so a (none) pick ERASES rather than storing a
# null -- one spelling of "this attack authors no look for this element", which is what keeps the
# saved .tres free of rows that mean nothing.
func _assign_look(element: Elemental.Element, picked: EffectLook) -> void:
	if current == null:
		return
	if picked == null:
		current.effect_looks.erase(element)
		return
	current.effect_looks[element] = picked


# The attack as it would be SAVED -- the editor's own values plus the staged stamp. The lint has to
# judge this rather than `current`, whose shape is still the library object the grid is not editing.
# The looks need no substitution: a staged look is reached through the same dictionary either way.
func _staged_attack() -> AttackData:
	if current == null or _shape.staged == null:
		return current
	var probe := current.duplicate() as AttackData   # shallow: only the shape reference differs
	probe.attack_shape = _shape.staged as AttackShape
	return probe


# The clause an overwrite confirm appends for every shared file this save will also write -- the
# stamp and each named look. Each one is a real second file, and a confirm that named only the
# attack would understate what an Update reaches.
func _shared_victims() -> String:
	var clause := _shape.victim_clause()
	for element in _looks:
		var field: LibraryField = _looks[element]
		clause += field.victim_clause()
	return clause


# Write every shared file the form has staged, at the COMMIT point. False only on a real write
# failure, which save_over has already reported.
func _save_shared_files() -> bool:
	if not _shape.save_named():
		return false
	for element in _looks:
		var field: LibraryField = _looks[element]
		if not field.save_named():
			return false
	return true

# The empowered-form picker (#97), and it is `replaces_main`'s row rather than the reflective one
# for that row's exact two reasons. A lone object @export auto-renders as a resource swapper that
# can only ever `.new()`, which EMBEDS an inline sub-resource -- invisible to every catalog and to
# the reachability law, and unshareable between attacks. And the nested editor it then draws writes
# into the live charged object while Update saves only the file we loaded, so the dev's range edits
# would vanish at relaunch with no symptom at all.
func _populate_empowered_form(attack: WeaponAttackData, rows: Dictionary) -> void:
	if attack == null:
		return
	var first := editor_container.get_child_count()
	var choices := _attack_choices(NO_EMPOWERED_KEY)
	choices.erase(attack.display_name)   # never itself; AttackLint refuses it, this never offers it
	var current_key := NO_EMPOWERED_KEY
	for k: String in choices:
		if choices[k] == attack.empowered_form:
			current_key = k
	DevWidgets.add_option(editor_container, "Empowered form", choices.keys(), current_key,
		func(s: String):
			attack.empowered_form = choices[s]
			populate()
	)
	rows["empowered_form"] = DevWidgets._added_since(editor_container, first)
	DevWidgets._tip_rows_from(editor_container, first, DevWidgets.property_tip(attack, "empowered_form"))


# THE PAYLOAD SECTION (#1058, layout B of the mockup rounds): a pick over the authored attacks, the
# payload's own plate, where it goes off, and the worst case the chain fans out to. A PICKER, never a
# nested editor, for empowered_form's reason: the payload is its own file and is edited where it
# lives. A pick rebuilds the form, since the tick under it asks the payload's shape.
#
# The pick is not registered with the binder -- it is never hidden -- which also keeps the section's
# heading standing when the tick below it hides.
func _populate_payload() -> void:
	var first := editor_container.get_child_count()
	var choices := _payload_choices()
	var held_key := NO_PAYLOAD_KEY
	for k: String in choices:
		if choices[k] == current.payload:
			held_key = k
	DevWidgets.add_option(editor_container, "Payload attack", choices.keys(), held_key,
		func(s: String):
			current.payload = choices[s]
			populate()
	)
	DevWidgets._tip_rows_from(editor_container, first, DevWidgets.property_tip(current, "payload"))
	if current.payload == null:
		return
	_payload_plate = ShapePlate.new()
	editor_container.add_child(_payload_plate)
	_payload_where = Label.new()
	_payload_where.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor_container.add_child(_payload_where)
	_payload_fanout = Label.new()
	_payload_fanout.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	editor_container.add_child(_payload_fanout)
	_refresh_payload_readouts()
	if not current.changed.is_connected(_refresh_payload_readouts):
		current.changed.connect(_refresh_payload_readouts)


func _refresh_payload_readouts() -> void:
	if current == null or current.payload == null:
		return
	if is_instance_valid(_payload_plate):
		_payload_plate.show_payload(current.payload, current.attack_shape != null or current.payload_turns)
	if is_instance_valid(_payload_where):
		_payload_where.text = payload_where_text(current)
	if is_instance_valid(_payload_fanout):
		var levels := current.payload_fanout()
		_payload_fanout.text = payload_fanout_text(levels)
		var total := 0
		for count in levels:
			total += count
		if total > FANOUT_WARN:
			_payload_fanout.add_theme_color_override("font_color", FANOUT_WARN_COLOR)
		else:
			_payload_fanout.remove_theme_color_override("font_color")


# Where this attack's payload goes off -- _drops_of's rule in words, read from `targets` (#1058).
static func payload_where_text(attack: AttackData) -> String:
	if attack.hits_map():
		return "Goes off on every tile this attack strikes, whether or not anyone is on it."
	return "Goes off on every unit this attack hits, on the tile the hit leaves them. A miss drops nothing."


static func payload_fanout_text(levels: Array[int]) -> String:
	var parts: Array[String] = []
	var total := 0
	for i in levels.size():
		parts.append("%d at level %d" % [levels[i], i + 1])
		total += levels[i]
	return "Worst case: %s (%d in all)." % [", ".join(parts), total]


# Every attack a payload may name (#1058): the weapon attacks the empowered form offers, then every
# carving, one taking a " (carving)" suffix where a weapon attack already has its name so one name is
# one entry. Watch-only attacks are left out -- they are never fired, so dropping one means nothing --
# and so is anything that would make a loop (ruling 46), asked of the FILE this form edits: a pool
# mode edits a copy, and no chain on disk can lead back to a copy. The payload already held stays
# listed whatever it is, or the picker would claim a different one.
func _payload_choices() -> Dictionary:
	var choices := {NO_PAYLOAD_KEY: null}
	var file := _loaded_file()
	var weapon := _attack_choices(NO_PAYLOAD_KEY)
	weapon.erase(NO_PAYLOAD_KEY)
	for source: Dictionary in [weapon, TransmutationCatalog.get_all()]:
		for k: String in source:
			var candidate: AttackData = source[k]
			if candidate == null or candidate.can_overwatch:
				continue
			if current.payload_would_loop(candidate) or (file != null and file.payload_would_loop(candidate)):
				continue
			var key := k if not choices.has(k) else "%s (carving)" % k
			choices[key] = candidate
	if current.payload != null and not choices.values().has(current.payload):
		choices["%s (held)" % current.payload.display_name] = current.payload
	return choices


# The attack FILE this form is editing, or null for a New one. FAMILY edits the main live; the pool
# modes edit a copy of the catalog entry they loaded.
func _loaded_file() -> AttackData:
	if _mode == Mode.FAMILY:
		return current
	if _loaded_name == "" or not _items.has(_loaded_name):
		return null
	return _items[_loaded_name] as AttackData


# Every authored weapon attack, by display name -- ItemEditorTool._main_choices' shape, and a
# library attack sharing a main's name loses so one name is one entry.
func _attack_choices(none_key: String) -> Dictionary:
	var choices := {none_key: null}
	for source: Dictionary in [WeaponAttackCatalog.get_mains(), WeaponAttackCatalog.get_library()]:
		for k in source:
			if not choices.has(k):
				choices[k] = source[k]
	return choices

# The scaling sliders (#485). Drawn in both attack modes and NOT for a carving, which scales off
# the wielder's aura and has no blend to edit -- the cast is what says so rather than a mode check.
# This is the family-scaling surface the ticket asked for: a family's blend IS its main attack's,
# so editing it in FAMILY mode is editing the family, with no separate template field to keep.
func _populate_blend(rows: Dictionary) -> void:
	var weapon_attack := current as WeaponAttackData
	if weapon_attack == null:
		return
	var first := editor_container.get_child_count()
	DevWidgets.add_label(editor_container, "Damage scaling — the four always total %d%%:" % Stats.BLEND_TOTAL)
	DevWidgets.add_blend_sliders(editor_container, weapon_attack.scaling_blend, func(): pass,
		DevWidgets.property_tip(weapon_attack, "scaling_blend"))
	# Registered so the whole block goes with `power` on a no-damage attack: scaling is suppressed
	# there, so four sliders that cannot move the number are worse than no sliders at all.
	rows["scaling_blend"] = DevWidgets._added_since(editor_container, first)

# The family's extra_attacks, in the rune editor's inscribe-list idiom. Entries are DIRECT REFS,
# never copies: Springspear.tres and Kinetic_Mace.tres already store theirs as ext_resource, so a
# duplicate here would fork the file the Weapon Attack mode edits.
#
# The lint mark beside an entry is safe to draw where a mark on the main's own fields would not be
# (see _refuse_unfireable): an extra is a library file this form does not edit, so nothing on this
# panel can make the mark stale.
func _populate_extras(family_label: String) -> void:
	var extras := current_template.extra_attacks
	DevWidgets.add_heading(editor_container, "Extra attacks")
	DevWidgets.add_label(editor_container, "Every weapon of %s gets these (%d):" % [family_label, extras.size()])
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
	var first := editor_container.get_child_count()
	DevWidgets.add_label(editor_container, "Sigils (weight per element):")
	for e in Elemental.SIGIL_ELEMENTS:
		var element: Elemental.Element = e
		var on_weight := func(v):
			_set_sigil_weight(carving, element, int(v))
		DevWidgets.add_spinbox(editor_container, Elemental.display_name(element), carving.sigils.count(element), on_weight)
	DevWidgets.add_label(editor_container, "Cost %d | Tier %d | Flourish slots %d" % [carving.cost(), carving.tier(), carving.flourish_slots()])
	DevWidgets.add_label(editor_container, "Resolves to: %s" % _tags_label(carving))
	DevWidgets._tip_rows_from(editor_container, first, DevWidgets.property_tip(carving, "sigils"))

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
	var first := editor_container.get_child_count()
	DevWidgets.add_label(editor_container, "Flourishes (%d / %d slots):" % [carving.flourishes.size(), carving.flourish_slots()])
	DevWidgets._tip_rows_from(editor_container, first, DevWidgets.property_tip(carving, "flourishes"))
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
