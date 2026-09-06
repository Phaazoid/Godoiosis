extends PanelContainer

# Inventory section of the inspect panel (UnitInfoPanel.tscn): the fixed grid of item slots
# (code-generated), with an equip/unequip/toss action popup when the inspected unit is
# controllable (can_act). Slot rows show the computed weapon view (elements incl. mods).

@onready var slots_container = $MarginContainer/InventorySlots
signal loadout_changed

var unit: Unit = null
var can_act := false
var selected_index := -1
var action_popup: Control = null

const COLOR_BORDER_DEFAULT := Color(0.3, 0.3, 0.3, 1)
const COLOR_BORDER_SELECTED := Color(0.9, 0.78, 0.32, 1)
const COLOR_EQUIPPED := Color(1, 0.85, 0.3, 1)
const COLOR_EMPTY := Color(0.6, 0.616, 0.6, 1.0)

func _ready() -> void:
	_create_slots()

func _create_slots():
	for i in range(Unit.MAX_INVENTORY_SIZE):
		var slot_panel := Panel.new()
		slot_panel.custom_minimum_size = Vector2i(130, 40)
		slot_panel.mouse_filter = Control.MOUSE_FILTER_STOP

		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.15, 1)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		style.border_color = COLOR_BORDER_DEFAULT
		slot_panel.add_theme_stylebox_override("panel", style)

		var hbox := HBoxContainer.new()
		hbox.name = "SlotHBox"
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hbox.set("theme_override_constants/separation", 6)
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2i(24, 24)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.name = "Icon"
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var name_label := Label.new()
		name_label.text = ""
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.name = "ItemName"
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

		hbox.add_child(icon)
		hbox.add_child(name_label)
		slot_panel.add_child(hbox)

		slot_panel.gui_input.connect(_on_slot_gui_input.bind(i))
		slots_container.add_child(slot_panel)

func set_unit(new_unit: Unit, p_can_act := false):
	unit = new_unit
	can_act = p_can_act
	selected_index = -1
	_close_action_popup()
	_refresh()

func _on_slot_gui_input(event: InputEvent, index: int):
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select_slot(index)

func _select_slot(index: int):
	if unit == null or index >= unit.inventory.size() or unit.inventory[index] == null:
		selected_index = -1
		_close_action_popup()
		_refresh()
		return
	if selected_index == index and action_popup != null:
		selected_index = -1        # clicking the open slot again = "never mind"
		_close_action_popup()
		_refresh()
		return
	selected_index = index
	_refresh()
	if can_act:
		_show_action_popup(index)
	else:
		_close_action_popup()

func _show_action_popup(index: int):
	_close_action_popup()
	if unit == null or not can_act:
		return
	var item = unit.inventory[index]
	if item == null:
		return
		

	var popup := PanelContainer.new()
	popup.z_index = UiLayers.INVENTORY_POPUP
	var vbox := VBoxContainer.new()
	popup.add_child(vbox)

	if item is ArmorData:
		var wear_btn := Button.new()
		if item == unit.worn_armor:
			wear_btn.text = "Remove"
			wear_btn.pressed.connect(_do_remove_armor)
		elif item.can_equip(unit):
			wear_btn.text = "Wear"
			wear_btn.pressed.connect(_do_wear.bind(index))
		else:
			# The gate, shown rather than silently swallowed -- and since #744 in the SENTENCE the
			# gate itself chose, against this wearer, rather than this surface re-wording the rule
			# from requirement_text (which cannot see who is holding it, so it could only ever say
			# what the piece demands, never how far short you are).
			wear_btn.text = "Wear — %s" % item.can_equip_reason(unit)
			wear_btn.disabled = true
		vbox.add_child(wear_btn)
	# Any non-armor equippable: weapons AND runes. Mirrors equip_weapon_from_inventory's
	# own split — armor is caught above and fills a different slot.
	elif item is EquippableData:
		var equip_btn := Button.new()
		if item == unit.get_equipped_weapon():
			equip_btn.text = "Unequip"
			equip_btn.pressed.connect(_do_unequip.bind(index))
		elif item.can_equip(unit):
			equip_btn.text = "Equip"
			equip_btn.pressed.connect(_do_equip.bind(index))
		else:
			# The gate, shown rather than silently swallowed — armor's precedent above (#157). This
			# used to hardcode "can't channel", which was true only while runes were the one kind
			# that could refuse; #744 made every kind able to say its own.
			equip_btn.text = "Equip — %s" % item.can_equip_reason(unit)
			equip_btn.disabled = true
		vbox.add_child(equip_btn)

	# A vial is CARRIED, never slotted, so its verb is Use rather than Equip (#697). Same shape as
	# the two branches above: the gate states its own sentence and the button wears it, so the
	# refusal and the label cannot drift (#744). An allowed Use that OVERWRITES an existing charge
	# says so on the button — the trade has to be readable before the item is spent, not after.
	if item is VialData:
		var vial := item as VialData
		var use_btn := Button.new()
		var refusal := vial.use_block_reason(unit)
		if refusal != "":
			use_btn.text = "Use — %s" % refusal
			use_btn.disabled = true
		else:
			var replaced := vial.use_replaces(unit)
			use_btn.text = "Use" if replaced == "" else "Use — replaces %s" % replaced
			use_btn.pressed.connect(_do_use.bind(index))
		vbox.add_child(use_btn)

	if not (item is WeaponInstance and unit.unit_instance.is_installed_prosthetic(item.template)):
		var toss_btn := Button.new()
		toss_btn.text = "Toss"
		toss_btn.pressed.connect(_do_toss.bind(index))
		vbox.add_child(toss_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_do_cancel)
	vbox.add_child(cancel_btn)

	add_child(popup)
	var slot = slots_container.get_child(index)
	popup.global_position = slot.global_position + Vector2(slot.size.x + 4, 0)
	action_popup = popup

func _close_action_popup():
	if action_popup != null and is_instance_valid(action_popup):
		action_popup.queue_free()
	action_popup = null

# Every loadout mutation funnels through here: close the popup, redraw the slots, and announce
# that DERIVED readouts are stale -- DEF from armor, MOV from gear weight. The panel that owns
# the stats section listens; this one deliberately doesn't know how to reach it.
func _apply_change():
	_close_action_popup()
	_refresh()
	loadout_changed.emit()

func _do_use(index: int):
	if unit != null:
		unit.use_vial(index)   # the refusal was asked above and wears it on the button
	selected_index = -1
	_apply_change()

func _do_equip(index: int):
	if unit != null:
		unit.equip_weapon_from_inventory(index)
	_apply_change()

func _do_unequip(index: int):
	if unit != null:
		unit.unequip_weapon()
	_apply_change()

func _do_wear(index: int):
	if unit != null:
		unit.wear_armor(index)
	_apply_change()

func _do_remove_armor():
	if unit != null:
		unit.remove_armor()
	_apply_change()

func _do_toss(index: int):
	if unit != null:
		unit.remove_item(index)
	selected_index = -1
	_apply_change()

func _do_cancel():
	selected_index = -1
	_close_action_popup()
	_refresh()

# Hover readout for one slot. Leads with the numbers a decision actually turns on -- live weapon
# state, or armor's itemized DEF -- and puts flavour text last.
func _tooltip_for(item) -> String:
	var lines: Array[String] = []
	if item is WeaponInstance:
		lines.append(item.shown_name())
		if unit != null:
			# The headline view is the weapon's MAIN attack, asked for explicitly — base_damage
			# no longer defaults to it, because null there means "no attack" now (#102).
			var main_atk: WeaponAttackData = item.default_attack(unit) as WeaponAttackData
			lines.append("Damage %d" % item.base_damage(unit, main_atk))
		var status: String = item.status_text()
		if status != "":
			lines.append(status)
	elif item is ArmorData:
		lines.append(item.display_name)
		var mech: String = item.mechanical_text(unit)
		if mech != "":
			lines.append(mech)
	elif item is RuneData:
		# What a decision actually turns on (#167): temper + capacity headline, then one line per
		# inscribed carving -- readout only, composed from #166's attack_detail/attack_block_reason
		# pair (the same detail-then-reason order the Transmutation submenu's rows already use).
		lines.append(item.display_name)
		var temper_text := "Untempered" if item.temper == Elemental.Element.NONE \
			else "%s temper" % Elemental.display_name(item.temper)
		lines.append("%s  ·  %s  ·  %d/%d capacity" % [
			RuneData.Size.keys()[item.size].capitalize(), temper_text,
			item.used_capacity(), item.capacity()])
		for t in item.inscriptions:
			lines.append("")
			lines.append(t.display_name)
			var detail: String = item.attack_detail(unit, t)
			if detail != "":
				lines.append(detail)
			var reason: String = item.attack_block_reason(unit, t)
			if reason != "":
				lines.append(reason)
	else:
		lines.append(item.display_name)
	# describe(), never the field: a weapon inherits its family's wording when it carries none (#745).
	if item.describe() != "":
		lines.append("")
		lines.append(item.describe())
	return "\n".join(lines)

func _refresh():
	for i in range(Unit.MAX_INVENTORY_SIZE):
		var slot = slots_container.get_child(i)
		var icon = slot.get_node("SlotHBox/Icon")
		var name_label = slot.get_node("SlotHBox/ItemName")
		var style: StyleBoxFlat = slot.get_theme_stylebox("panel")

		style.border_color = COLOR_BORDER_SELECTED if i == selected_index else COLOR_BORDER_DEFAULT

		if unit and i < unit.inventory.size() and unit.inventory[i] != null:
			var item = unit.inventory[i]
			icon.texture = item.icon

			var display_name = item.display_name
			if item is WeaponInstance:
				display_name = item.shown_name()
				if icon.texture == null and item.template != null:
					icon.texture = item.template.icon

			if item == unit.get_equipped_weapon():
				display_name += "  (E)"
				name_label.modulate = COLOR_EQUIPPED
			elif item == unit.worn_armor:
				display_name += "  (W)"
				name_label.modulate = COLOR_EQUIPPED
			else:
				name_label.modulate = Color(1, 1, 1, 1)
			if item is ArmorData and item.modifier_text() != "":
				display_name += "  [%s]" % item.modifier_text()

			# Append elemental damage — the computed view, so mod-added elements show too.
			if item is WeaponInstance and unit != null:
				var slot_main: WeaponAttackData = item.default_attack(unit) as WeaponAttackData
				var elems: Array[Elemental.Element] = item.get_elements(unit, slot_main)
				if not elems.is_empty():
					display_name += "  [%s]" % Elemental.display_name(elems[0])

			name_label.text = display_name
			slot.tooltip_text = UiText.wrap(_tooltip_for(item))
		else:
			icon.texture = null
			name_label.text = "Empty"
			name_label.modulate = COLOR_EMPTY
			slot.tooltip_text = ""
