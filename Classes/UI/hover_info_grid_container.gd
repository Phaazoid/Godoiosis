extends GridContainer

const DOWNED_ICON := preload("res://Art/Icons/Down.png")
const SEVERED_ARM := preload("res://Art/Icons/SeveredArm.png")
const SEVERED_LEG := preload("res://Art/Icons/SeveredLeg.png")
const STATUS_ICON_SIZE := Vector2i(16, 16)
const CRISIS_ICON := preload("res://Art/Icons/DedIcon.png")

var unit: Unit
@onready var portrait_texture = $PortraitTexture
@onready var name_label = $NameRow/NameLabel
@onready var states_row = $NameRow/StatesRow
@onready var hp_label = $HPLabel

func set_unit(target: Unit):
	if unit:
		unit.unit_instance.hp_changed.disconnect(_on_hp_changed)
		unit.unit_instance.died.disconnect(_on_unit_died)
		unit.unit_instance.will_changed.disconnect(_on_will_changed)
		unit.downed_countdown_changed.disconnect(_on_countdown_changed)
	unit = target

	if unit == null:
		name_label.text = ""
		hp_label.text = ""
		portrait_texture.texture = null
		StateIcons.populate(states_row, [])
		return

	if unit.unit_data.portrait == null:
		portrait_texture.texture = load("res://Art/Units/Portraits/faceless_one.png")
	else:
		portrait_texture.texture = unit.unit_data.portrait

	unit.unit_instance.died.connect(_on_unit_died)
	unit.unit_instance.hp_changed.connect(_on_hp_changed)
	unit.unit_instance.will_changed.connect(_on_will_changed)
	unit.downed_countdown_changed.connect(_on_countdown_changed)

	_refresh()

func _on_unit_died():
	hp_label.text = "DED X_X"

func _refresh():
	if unit == null:
		name_label.text = "ERROR"
		hp_label.text = "ERROR"
		return
	name_label.text = unit.unit_data.display_name
	_refresh_hp()
	_refresh_status_icons()

func _refresh_hp():
	if unit == null:
		return
	hp_label.text = "%d/%d  WIL %d/%d" % [
		unit.get_current_hp(), unit.get_max_hp(),
		unit.unit_instance.get_current_will(), unit.unit_instance.get_max_will()]

# Element states first (this CLEARS the row), then lifecycle/maim status icons appended after.
func _refresh_status_icons():
	if unit == null:
		return
	StateIcons.populate(states_row, unit.element_states)
	if unit.is_downed() and unit.downed_turns_remaining > 0:
		_add_status_icon(DOWNED_ICON)
		_add_status_count(unit.downed_turns_remaining)
	if unit.unit_instance.is_maimed():
		_add_status_icon(_maim_icon())
	if unit.in_crisis:
		_add_status_icon(CRISIS_ICON)

func _maim_icon() -> Texture2D:
	if unit.unit_instance.maimed_part == UnitInstance.MaimedPart.LEG_LEFT or unit.unit_instance.maimed_part == UnitInstance.MaimedPart.LEG_RIGHT:
		return SEVERED_LEG
	return SEVERED_ARM

func _add_status_icon(tex: Texture2D):
	var rect := TextureRect.new()
	rect.texture = tex
	rect.custom_minimum_size = STATUS_ICON_SIZE
	rect.expand_mode = TextureRect.EXPAND_KEEP_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	states_row.add_child(rect)

func _add_status_count(n: int):
	var lbl := Label.new()
	lbl.text = str(n)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	states_row.add_child(lbl)

func _on_hp_changed(_current, _max):
	_refresh_hp()

func _on_will_changed(_current, _max):
	_refresh_hp()
	_refresh_status_icons()   # a maim sets Will->0 via this signal — repaint so the severed icon appears

func _on_countdown_changed(_turns: int):
	_refresh_status_icons()
