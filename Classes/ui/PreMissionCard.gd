extends PanelContainer
class_name PreMissionCard

# One roster member, on the pre-mission screen's card grid (#740). Self-contained by design -- there
# is no drill-down, so everything the player weighs when choosing a force is on the face of it: who
# they are, what shape they are in, what they carry, and whether they are going.
#
# EVERY NUMBER IS READ, NEVER RE-DERIVED. Effective stats come off Unit.get_effective_stat (the full
# base -> limb -> jobs -> effects -> gear chain), DEF off get_effective_def, weight off get_weight,
# abilities off get_live_abilities -- the same answers the inspect panel gives, because #731 ruling 7
# spawns the whole roster as real Units precisely so an undeployed one can be asked. A second
# implementation reading UnitInstance directly is the duplicate seam that ruling exists to prevent.
#
# LAYOUT, from his sketch and three mockup rounds: the unit fills the left, what it CARRIES fills
# the right, and the strip along the bottom is derived numbers plus the deploy toggle. The card is
# deliberately roomier than its content needs -- room to add later is the point (dev, 2026-09-05).
#
# WHY THE ITEM LIST IS THE STASH'S OWN ROW, and why the block reason lives HERE: EquippableData
# .can_equip takes a WIELDER, so the stash -- which has no unit selected -- structurally cannot say
# whether a thing is usable. That reading belongs to the card and nowhere else (dev, 2026-09-05).
#
# NOTHING IN HERE MAY DEMAND WIDTH FROM ITS CONTENT. The grid divides its row three ways and an
# HFlowContainer's minimum width is its widest child, so one long ability name would walk the whole
# column out of the region -- the #685 failure, one surface over. Every content-bearing label is
# clip_text with the full string on hover, so the card's minimum size is a constant.

signal deploy_toggled(unit: Unit)

# The inspect panel owns the ability tooltip wording and its builders are static for exactly this
# reason -- one sentence, two surfaces. Preloaded because that file is a scene script with no
# class_name; tests/ui/test_info_panel_text.gd reaches it the same way.
const InfoPanel := preload("res://Classes/ui/panels/info_panel.gd")

const CARD_HEIGHT := 208
const ITEM_COLUMN := 128
const SPRITE := 52
const CHIP_MIN_W := 30

# The eight, in Stats.Stat declaration order, two columns of four. Read off the enum rather than
# listed here, so a ninth stat appears without an edit.
const STAT_COLUMNS := 2

var unit: Unit

var _deploy_button: Button
var _controller: MissionController
var _limbs_row: HFlowContainer
var _job_label: Label
var _abilities_row: HFlowContainer
var _stats_grid: GridContainer
var _items_column: VBoxContainer
var _derived_label: Label


static func build(target: Unit, controller: MissionController) -> PreMissionCard:
	var card := PreMissionCard.new()
	card.unit = target
	card._controller = controller
	card._build()
	return card


func _build() -> void:
	custom_minimum_size = Vector2(0, CARD_HEIGHT)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip_contents = true
	add_theme_stylebox_override("panel", QueueStyle.section_box())

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 6)
	pad.add_theme_constant_override("margin_right", 6)
	pad.add_theme_constant_override("margin_top", 6)
	pad.add_theme_constant_override("margin_bottom", 6)
	add_child(pad)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	pad.add_child(column)

	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	body.add_child(_build_unit_half())
	body.add_child(_build_carried_half())

	column.add_child(_build_foot())
	refresh()


# --- the unit half -------------------------------------------------------------------------------

func _build_unit_half() -> Control:
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 5)

	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 7)
	left.add_child(who)

	# Sprite with the name under it -- his sketch's top-left, and the name is clipped so a long one
	# cannot widen the column it sits in.
	var identity := VBoxContainer.new()
	identity.custom_minimum_size.x = SPRITE
	identity.add_theme_constant_override("separation", 2)
	who.add_child(identity)

	var portrait := TextureRect.new()
	portrait.texture = unit.unit_data.map_sprite
	portrait.custom_minimum_size = Vector2(SPRITE, SPRITE)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	identity.add_child(portrait)

	var name_label := Label.new()
	name_label.text = unit.get_unit_name()
	name_label.clip_text = true
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.tooltip_text = unit.get_unit_name()
	name_label.mouse_filter = Control.MOUSE_FILTER_STOP
	name_label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.TITLE_TEXT))
	identity.add_child(name_label)

	# Beside the sprite: what shape they are in, what they do, and what that grants them.
	var meta := VBoxContainer.new()
	meta.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meta.add_theme_constant_override("separation", 4)
	who.add_child(meta)

	_limbs_row = HFlowContainer.new()
	_limbs_row.add_theme_constant_override("h_separation", 3)
	_limbs_row.add_theme_constant_override("v_separation", 2)
	meta.add_child(_limbs_row)

	_job_label = Label.new()
	_job_label.clip_text = true
	_job_label.add_theme_font_size_override("font_size", 11)
	meta.add_child(_job_label)

	_abilities_row = HFlowContainer.new()
	_abilities_row.add_theme_constant_override("h_separation", 3)
	_abilities_row.add_theme_constant_override("v_separation", 2)
	meta.add_child(_abilities_row)

	# Pushed to the bottom of the column, so the card's spare room sits between the kit readout and
	# the numbers rather than under everything.
	_stats_grid = GridContainer.new()
	_stats_grid.columns = STAT_COLUMNS
	_stats_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL | Control.SIZE_SHRINK_END
	_stats_grid.add_theme_constant_override("h_separation", 12)
	_stats_grid.add_theme_constant_override("v_separation", 0)
	left.add_child(_stats_grid)
	return left


# --- what they carry -----------------------------------------------------------------------------

func _build_carried_half() -> Control:
	_items_column = VBoxContainer.new()
	_items_column.custom_minimum_size.x = ITEM_COLUMN
	_items_column.size_flags_horizontal = Control.SIZE_SHRINK_END
	_items_column.add_theme_constant_override("separation", 3)
	return _items_column


# --- the derived strip ---------------------------------------------------------------------------

func _build_foot() -> Control:
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 6)

	_derived_label = Label.new()
	_derived_label.add_theme_font_size_override("font_size", 11)
	_derived_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_derived_label.clip_text = true
	_derived_label.mouse_filter = Control.MOUSE_FILTER_STOP
	foot.add_child(_derived_label)

	_deploy_button = Button.new()
	_deploy_button.pressed.connect(func() -> void: deploy_toggled.emit(unit))
	foot.add_child(_deploy_button)
	return foot



# Everything that can change while the screen is open. Called on build and whenever the screen
# refreshes -- deploying somebody changes another card's toggle (the cap), and coming back from the
# board can have changed anyone's.
func refresh() -> void:
	if not is_instance_valid(unit):
		return
	_refresh_limbs()
	_refresh_job()
	_refresh_abilities()
	_refresh_stats()
	_refresh_items()
	_refresh_foot()


func _refresh_limbs() -> void:
	_clear(_limbs_row)
	var inst: UnitInstance = unit.unit_instance
	var hurt := false
	for slot: UnitInstance.LimbSlot in UnitInstance.LIMB_SHORT:
		var fitting: UnitInstance.LimbFitting = inst.limbs.get(slot)
		if fitting == null or fitting.state == UnitInstance.LimbState.NATURAL:
			continue
		hurt = true
		var maimed := fitting.state == UnitInstance.LimbState.EMPTY
		_limbs_row.add_child(_chip(UnitInstance.LIMB_SHORT[slot],
			QueueStyle.ink(QueueStyle.Role.ROW_REFUSED_BORDER) if maimed else Color(0.62, 0.82, 1.0),
			"%s: %s" % [UnitInstance.LIMB_FULL[slot], "maimed" if maimed else "prosthetic"]))
	# A whole body is worth saying out loud -- an empty row reads as a card that failed to draw.
	if not hurt:
		_limbs_row.add_child(_chip("whole", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT),
			"Every limb natural"))


func _refresh_job() -> void:
	var jobs: Array[String] = unit.unit_instance.jobs
	# One job at a time is bound at the ROSTER (#731 ruling 10), not here -- so this reads whatever
	# is authored and names all of them rather than pretending the second does not exist.
	if jobs.is_empty():
		_job_label.text = "Job · none"
		_job_label.tooltip_text = "This unit holds no job."
		_job_label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
		return
	var names: Array[String] = []
	for id: String in jobs:
		var job: JobData = JobCatalog.get_job(id)
		names.append(job.display_name if job != null else id)
	_job_label.text = "Job · " + ", ".join(names)
	_job_label.tooltip_text = _job_label.text
	_job_label.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.TITLE_TEXT))


func _refresh_abilities() -> void:
	_clear(_abilities_row)
	var live: Array[AbilityData] = unit.get_live_abilities()
	if live.is_empty():
		var none := Label.new()
		none.text = "no abilities"
		none.add_theme_font_size_override("font_size", 10)
		none.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
		_abilities_row.add_child(none)
		return
	# Text chips rather than 16x16 badges: AbilityData has no icon field, and the real cost of one
	# is authoring an icon per ability rather than adding the property (#740's own note, confirmed).
	for ability: AbilityData in live:
		var kind := String(AbilityData.AbilityKind.keys()[ability.kind]).capitalize()
		_abilities_row.add_child(_chip(ability.display_name, Color(0.78, 0.74, 0.94),
			InfoPanel.ability_tooltip(ability.display_name, kind, ability.description)))


func _refresh_stats() -> void:
	_clear(_stats_grid)
	for stat: Stats.Stat in Stats.STAT_DEFAULTS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var key := Label.new()
		key.text = String(Stats.Stat.keys()[stat])
		key.add_theme_font_size_override("font_size", 11)
		key.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))
		key.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key)
		var value := Label.new()
		value.text = str(unit.get_effective_stat(stat))
		value.add_theme_font_size_override("font_size", 11)
		row.add_child(value)
		_stats_grid.add_child(row)


func _refresh_items() -> void:
	_clear(_items_column)
	for i in range(Unit.MAX_INVENTORY_SIZE):
		var item: Item = unit.inventory[i] if i < unit.inventory.size() else null
		_items_column.add_child(_item_row(item))


func _refresh_foot() -> void:
	# WEIGHT IS INERT TODAY and shipping it anyway is the dev's call (2026-09-05): Item.weight and
	# Unit.get_weight() both work, but every authored weight is 0 until #120's pass, so this reads
	# WT 0 for everyone. Showing the slot is what makes the gap visible rather than forgotten.
	_derived_label.text = "WT %d  ·  DEF %d" % [unit.get_weight(), unit.get_effective_def()]
	_derived_label.tooltip_text = UiText.wrap(
		"Weight is the whole inventory's; every item currently weighs 0 until weight is authored. "
		+ "DEF is the effective value, armour included.")

	var deployed: bool = unit.get_parent() == _controller.game.units_root   # game is untyped: no inference
	_deploy_button.text = "✓ Deployed" if deployed else "Deploy"
	_deploy_button.add_theme_font_size_override("font_size", 11)
	var blocked := _deploy_block_reason() if not deployed else ""
	_deploy_button.disabled = blocked != ""
	_deploy_button.tooltip_text = UiText.wrap(blocked) if blocked != "" else (
		"Take this unit back off the board." if deployed else "Place this unit on the deployment zone.")


# Why this unit cannot be placed right now -- "" when it can. Both halves are real and neither
# implies the other: a full cap with room on the zone, and a full zone under an unreached cap.
func _deploy_block_reason() -> String:
	if not _controller.can_deploy_another():
		return "Your force is full — %d of %d placed. Take someone off first." % [
			_controller.deployed_roster_count(), _controller.game.scenario_manager.current_deployment_cap]
	if _controller.open_deployment_cells().is_empty():
		return "The deployment zone has no free cell left."
	return ""


# --- small builders ------------------------------------------------------------------------------

# A bounded chip. custom_minimum_size plus clip_text is what stops a long name widening the card:
# the minimum is a constant, and the full string is on hover.
func _chip(text: String, tint: Color, tip: String) -> Label:
	var chip := Label.new()
	chip.text = text
	chip.clip_text = true
	chip.custom_minimum_size.x = CHIP_MIN_W
	chip.add_theme_font_size_override("font_size", 10)
	chip.add_theme_color_override("font_color", tint)
	chip.tooltip_text = UiText.wrap(tip)
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	return chip


# The stash's own row shape, so an item reads the same wherever it is (dev, 2026-09-05). An empty
# slot is drawn rather than skipped: it is the drop target #741 will need, and six of them is what
# MAX_INVENTORY_SIZE means.
func _item_row(item: Item) -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size.y = 20
	if item == null:
		row.add_theme_stylebox_override("panel", QueueStyle.section_box())
		row.modulate = Color(1, 1, 1, 0.45)
		var empty := Label.new()
		empty.text = ""
		row.add_child(empty)
		return row

	var equippable := item as EquippableData
	var reason := _equip_block_reason(equippable)
	row.add_theme_stylebox_override("panel", QueueStyle.row_box(reason != "", false))

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	row.add_child(line)

	var name_label := Label.new()
	name_label.text = item.display_name
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 10)
	line.add_child(name_label)

	if reason != "":
		var warn := Label.new()
		warn.text = "!"
		warn.add_theme_font_size_override("font_size", 11)
		warn.add_theme_color_override("font_color", QueueStyle.ink(QueueStyle.Role.ROW_REFUSED_BORDER))
		line.add_child(warn)

	row.tooltip_text = UiText.wrap(item.display_name if reason == "" else
		"%s — %s" % [item.display_name, reason])
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	return row


# THE one place the card asks "can this unit use this", so #744 has one line to widen. can_equip is
# a bare bool today, so the sentence is generic; when that ticket gives it a reason string this
# returns it and every tooltip above improves with no edit here.
func _equip_block_reason(equippable: EquippableData) -> String:
	if equippable == null:
		return ""   # a non-equippable carried item has no gate to fail
	return "" if equippable.can_equip(unit) else "This unit cannot equip it."


static func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.free()
