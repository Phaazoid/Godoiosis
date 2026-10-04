extends PanelContainer

# Inventory section of the inspect panel (UnitInfoPanel.tscn): one column of full-width item slots
# (code-generated, #966), with an action popup -- equip/unequip/toss when the inspected unit is
# controllable (can_act), and Inspect for any item with a detail card, whoever holds it (#1152: the
# card is a read, so an enemy's weapon opens too). Slot rows show the computed weapon view (elements
# incl. mods). The slots are the action queue's rows, in the player's palette (#1105).
#
# A slot is a PanelContainer, never a Panel: a Panel lays out nothing, so its row sat at the top
# edge at its own minimum width and ran past the border (#966).

@onready var slots_container = $MarginContainer/InventorySlots
signal loadout_changed
# WHAT THE PLAYER DID, beside the staleness announcement above (#53 slice 2). Deliberately a
# SECOND signal rather than a payload on that one: `loadout_changed` means *derived readouts are
# stale* and every listener is a staleness handler that would have to accept arguments it ignores.
# Two questions, two answers -- and both leave from the ONE funnel below, so no door is missed.
signal loadout_acted(unit: Unit, verb: String, index: int)
# The player asked to READ an item (#1152) -- PreMissionCard's signal, and for its reason: the panel
# knows nothing of cards, and ItemDetail decides which one opens. Not a loadout act, so no
# loadout_acted beside it.
signal detail_requested(item: Item, owner: Unit)

var unit: Unit = null
var can_act := false
var selected_index := -1
var action_popup: Control = null

func _ready() -> void:
	_create_slots()

# The player's palette (#1105): the slots are the action queue's rows on paper, re-inked on every
# refresh, so a palette switch needs only a refresh.
func restyle() -> void:
	_refresh()

# A slot NAME is text on paper, so it takes a font colour; `modulate` multiplies the theme's white
# and cannot darken it for parchment.
static func _ink_name(label: Label, role: QueueStyle.Role) -> void:
	label.add_theme_color_override("font_color", QueueStyle.ink(role))

func _create_slots():
	for i in range(Unit.MAX_INVENTORY_SIZE):
		var slot_panel := PanelContainer.new()
		slot_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL   # span the one grid column
		slot_panel.mouse_filter = Control.MOUSE_FILTER_STOP

		slot_panel.add_theme_stylebox_override("panel", QueueStyle.row_box(false, false))

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
		# A guard, not a look: no authored name trims today, but an over-long one must not widen the
		# slot and walk the panel out of its column (the #685 edge). Trimming alone drops the label's
		# minimum width, so no clip_text is needed.
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
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
	if _offers_anything(unit.inventory[index]):
		_show_action_popup(index)
	else:
		_close_action_popup()

# A popup opens for a slot that has any verb in it: the loadout verbs need a controllable unit, and
# Inspect needs only a card (#1152).
func _offers_anything(item: Item) -> bool:
	return can_act or ItemDetail.has_card(item)

func _show_action_popup(index: int):
	_close_action_popup()
	if unit == null:
		return
	var item = unit.inventory[index]
	if item == null or not _offers_anything(item):
		return

	var popup := PanelContainer.new()
	popup.add_theme_stylebox_override("panel", QueueStyle.panel_box())
	popup.z_index = UiLayers.INVENTORY_POPUP
	var vbox := VBoxContainer.new()
	popup.add_child(vbox)

	if ItemDetail.has_card(item):
		var inspect_btn := Button.new()
		inspect_btn.text = "Inspect"
		inspect_btn.pressed.connect(_do_inspect.bind(index))
		vbox.add_child(inspect_btn)

	if can_act:
		_add_loadout_rows(vbox, item, index)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.pressed.connect(_do_cancel)
	vbox.add_child(cancel_btn)

	add_child(popup)
	var slot = slots_container.get_child(index)
	popup.global_position = slot.global_position + Vector2(slot.size.x + 4, 0)
	action_popup = popup

# The verbs that CHANGE what the unit carries -- only ever built for a controllable unit. Which verb a
# row offers is this surface's; whether it may happen, and why not, is GearVerbs' (#46), the rule the
# replay viewer and the headless Play API ask too.
func _add_loadout_rows(vbox: VBoxContainer, item, index: int) -> void:
	if item is ArmorData:
		var wear_btn := Button.new()
		if item == unit.worn_armor:
			wear_btn.text = "Remove"
			wear_btn.pressed.connect(_do_remove_armor)
		else:
			# The gate, shown rather than silently swallowed -- and since #744 in the SENTENCE the
			# gate itself chose, against this wearer, rather than this surface re-wording the rule
			# from requirement_text (which cannot see who is holding it, so it could only ever say
			# what the piece demands, never how far short you are).
			var refusal := GearVerbs.block_reason(unit, GearVerbs.Verb.WEAR, index)
			wear_btn.text = "Wear" if refusal == "" else "Wear — %s" % refusal
			wear_btn.disabled = refusal != ""
			if refusal == "":
				wear_btn.pressed.connect(_do_wear.bind(index))
		vbox.add_child(wear_btn)
	# Any non-armor equippable: weapons AND runes. Mirrors equip_weapon_from_inventory's
	# own split — armor is caught above and fills a different slot.
	elif item is EquippableData:
		var equip_btn := Button.new()
		if item == unit.get_equipped_weapon():
			equip_btn.text = "Unequip"
			equip_btn.pressed.connect(_do_unequip.bind(index))
		else:
			# The gate, shown rather than silently swallowed — armor's precedent above (#157). This
			# used to hardcode "can't channel", which was true only while runes were the one kind
			# that could refuse; #744 made every kind able to say its own.
			var refusal := GearVerbs.block_reason(unit, GearVerbs.Verb.EQUIP, index)
			equip_btn.text = "Equip" if refusal == "" else "Equip — %s" % refusal
			equip_btn.disabled = refusal != ""
			if refusal == "":
				equip_btn.pressed.connect(_do_equip.bind(index))
		vbox.add_child(equip_btn)

	# A vial is CARRIED, never slotted, so its verb is Use rather than Equip (#697). Same shape as
	# the two branches above: the gate states its own sentence and the button wears it, so the
	# refusal and the label cannot drift (#744). An allowed Use that OVERWRITES an existing charge
	# says so on the button — the trade has to be readable before the item is spent, not after.
	if item is VialData:
		var vial := item as VialData
		var use_btn := Button.new()
		var refusal := GearVerbs.block_reason(unit, GearVerbs.Verb.USE, index)
		if refusal != "":
			use_btn.text = "Use — %s" % refusal
			use_btn.disabled = true
		else:
			var replaced := vial.use_replaces(unit)
			use_btn.text = "Use" if replaced == "" else "Use — replaces %s" % replaced
			use_btn.pressed.connect(_do_use.bind(index))
		vbox.add_child(use_btn)

	# Unit's own rule (#741), not a second reading of the prosthetic fitting -- the gate this used to
	# re-ask is the shape #744 collapsed in the three branches above. Disabled wearing the sentence
	# rather than hidden, for their reason: a row the player cannot use still has to say why (#166).
	var toss_block := GearVerbs.block_reason(unit, GearVerbs.Verb.TOSS, index)
	var toss_btn := Button.new()
	if toss_block != "":
		toss_btn.text = "Toss — %s" % toss_block
		toss_btn.disabled = true
	else:
		toss_btn.text = "Toss"
		toss_btn.pressed.connect(_do_toss.bind(index))
	vbox.add_child(toss_btn)

func _close_action_popup():
	if action_popup != null and is_instance_valid(action_popup):
		action_popup.queue_free()
	action_popup = null

# Every loadout mutation funnels through here: close the popup, redraw the slots, and announce
# that DERIVED readouts are stale -- DEF from armor, MOV from gear weight. The panel that owns
# the stats section listens; this one deliberately doesn't know how to reach it.
func _apply_change(verb := "", index := -1):
	_close_action_popup()
	_refresh()
	loadout_changed.emit()
	if verb != "":
		loadout_acted.emit(unit, verb, index)

# The six acts, each through GearVerbs.perform (the refusal was asked above and wears it on the
# button). What loadout_acted records is unchanged, Remove's missing index included (#46).
func _do_use(index: int):
	_perform(GearVerbs.Verb.USE, index)
	selected_index = -1
	_apply_change(GearVerbs.name_of(GearVerbs.Verb.USE), index)

func _do_equip(index: int):
	_perform(GearVerbs.Verb.EQUIP, index)
	_apply_change(GearVerbs.name_of(GearVerbs.Verb.EQUIP), index)

func _do_unequip(index: int):
	_perform(GearVerbs.Verb.UNEQUIP, index)
	_apply_change(GearVerbs.name_of(GearVerbs.Verb.UNEQUIP), index)

func _do_wear(index: int):
	_perform(GearVerbs.Verb.WEAR, index)
	_apply_change(GearVerbs.name_of(GearVerbs.Verb.WEAR), index)

func _do_remove_armor():
	_perform(GearVerbs.Verb.REMOVE_ARMOR, -1)
	_apply_change(GearVerbs.name_of(GearVerbs.Verb.REMOVE_ARMOR))

func _do_toss(index: int):
	_perform(GearVerbs.Verb.TOSS, index)
	selected_index = -1
	_apply_change(GearVerbs.name_of(GearVerbs.Verb.TOSS), index)

func _perform(verb: GearVerbs.Verb, index: int) -> void:
	if unit != null:
		GearVerbs.perform(unit, verb, index)

func _do_inspect(index: int):
	var item: Item = unit.inventory[index] if unit != null else null
	_do_cancel()   # the card goes over the dock; the slot it was asked from lets go
	if item != null:
		detail_requested.emit(item, unit)

func _do_cancel():
	selected_index = -1
	_close_action_popup()
	_refresh()

# Hover readout for one slot. ItemText owns the composition -- since #137 the pre-mission surfaces
# say the same words, and a panel wording an item its own way is what that door exists to stop.
func _tooltip_for(item: Item) -> String:
	return ItemText.hover(item, unit)

func _refresh():
	for i in range(Unit.MAX_INVENTORY_SIZE):
		var slot = slots_container.get_child(i)
		var icon = slot.get_node("SlotHBox/Icon")
		var name_label = slot.get_node("SlotHBox/ItemName")
		# The selected slot wears the row's hover look. Swapped, never edited: QueueStyle's boxes are
		# shared, so writing a border into one would recolour every row in the game.
		slot.add_theme_stylebox_override("panel", QueueStyle.row_box(false, i == selected_index))

		if unit and i < unit.inventory.size() and unit.inventory[i] != null:
			var item = unit.inventory[i]
			icon.texture = item.icon

			var display_name = item.shown_name()
			if item is WeaponInstance:
				if icon.texture == null and item.template != null:
					icon.texture = item.template.icon

			if item == unit.get_equipped_weapon():
				display_name += "  (E)"
				_ink_name(name_label, QueueStyle.Role.EMPHASIS_TEXT)
			elif item == unit.worn_armor:
				display_name += "  (W)"
				_ink_name(name_label, QueueStyle.Role.EMPHASIS_TEXT)
			else:
				_ink_name(name_label, QueueStyle.Role.BODY_TEXT)
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
			_ink_name(name_label, QueueStyle.Role.HEADER_TEXT)
			slot.tooltip_text = ""
