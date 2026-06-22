extends Panel

@onready var slots_container = $MarginContainer/InventorySlots

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
		slot_panel.custom_minimum_size = Vector2i(180, 48)
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
		icon.custom_minimum_size = Vector2i(32, 32)
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
	popup.z_index = 10
	var vbox := VBoxContainer.new()
	popup.add_child(vbox)

	if item is WeaponData:
		var equip_btn := Button.new()
		if item == unit.get_equipped_weapon():
			equip_btn.text = "Unequip"
			equip_btn.pressed.connect(_do_unequip.bind(index))
		else:
			equip_btn.text = "Equip"
			equip_btn.pressed.connect(_do_equip.bind(index))
		vbox.add_child(equip_btn)

	var toss_btn := Button.new()
	toss_btn.text = "Toss"
	toss_btn.pressed.connect(_do_toss.bind(index))
	vbox.add_child(toss_btn)

	add_child(popup)
	var slot = slots_container.get_child(index)
	popup.global_position = slot.global_position + Vector2(slot.size.x + 4, 0)
	action_popup = popup

func _close_action_popup():
	if action_popup != null and is_instance_valid(action_popup):
		action_popup.queue_free()
	action_popup = null

func _do_equip(index: int):
	if unit != null:
		unit.equip_weapon_from_inventory(index)
	_close_action_popup()
	_refresh()

func _do_unequip(index: int):
	if unit != null:
		unit.unequip_weapon()
	_close_action_popup()
	_refresh()

func _do_toss(index: int):
	if unit != null:
		unit.remove_item(index)
	selected_index = -1
	_close_action_popup()
	_refresh()

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

			var display_name = item.item_name
			if item == unit.get_equipped_weapon():
				display_name += "  (E)"
				name_label.modulate = COLOR_EQUIPPED
			else:
				name_label.modulate = Color(1, 1, 1, 1)

			# Append elemental damage type for weapons that have one.
			if item is WeaponData:
				var elem := (item as WeaponData).elemental_damage_type
				if elem != Elemental.Element.NONE:
					display_name += "  [%s]" % Elemental.Element.keys()[elem].capitalize()

			name_label.text = display_name
		else:
			icon.texture = null
			name_label.text = "Empty"
			name_label.modulate = COLOR_EMPTY
