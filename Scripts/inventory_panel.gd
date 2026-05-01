extends Panel

@onready var slots_container = $MarginContainer/InventorySlots

var unit: Unit = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_create_slots()
	
func _create_slots():
	for i in range(Unit.MAX_INVENTORY_SIZE):
		var slot_panel := Panel.new()
		slot_panel.custom_minimum_size = Vector2i(180, 48)
		
		#Inventory styling
		var style := StyleBoxFlat.new()
		style.bg_color = Color(.15, .15, .15, 1)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1		
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_left = 4
		style.corner_radius_bottom_right = 4
		style.border_color = Color(.3, .3, .3, 1)
		slot_panel.add_theme_stylebox_override("panel", style)
		
		# Layout inside slot
		var hbox := HBoxContainer.new()
		hbox.name = "SlotHBox"
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
		hbox.set("theme_override_constants/separation", 6)
		
		#Icon stuff
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2i(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.name = "Icon"
		
		#Name Label
		var name_label := Label.new()
		name_label.text = ""
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.name = "ItemName"
		
		hbox.add_child(icon)
		hbox.add_child(name_label)
		slot_panel.add_child(hbox)
		
		slots_container.add_child(slot_panel)
		
func set_unit(new_unit: Unit):
	unit = new_unit
	_refresh()
	
func _refresh():
	for i in range (Unit.MAX_INVENTORY_SIZE):
		var slot = slots_container.get_child(i)
		var icon = slot.get_node("SlotHBox/Icon")
		var name_label = slot.get_node("SlotHBox/ItemName")
		
		if unit and i < unit.inventory.size() and unit.inventory[i] != null:
			var item = unit.inventory[i]
			icon.texture = item.icon
			name_label.text = item.item_name
		else:
			icon.texture = null
			name_label.text = "Empty"
			name_label.modulate = Color(0.6, 0.616, 0.6, 1.0)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
