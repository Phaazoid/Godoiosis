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
# THE JOB PICKER IS THE ONE THING ON THIS CARD THAT WRITES (#742), and it writes through the screen,
# not from here -- the card judges nothing and owns no state, exactly as it does not judge a gear move.
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
# A row was clicked -- the item under the cursor, or null for an empty slot. The screen holds the
# selection, because a selection that outlives a redraw cannot live on a row the redraw frees (#107).
signal gear_clicked(item: EquippableData, owner_unit: Unit)
# The cursor entered or left one of the item rows (#745). The SCREEN decides what a hover means,
# because only it knows whether something is already in hand.
signal gear_hovered(item: EquippableData, card: PreMissionCard)
signal gear_unhovered(card: PreMissionCard)
# A job was chosen from this card's picker (#742). The SCREEN performs it, for the same reason it owns
# every gear move: the card judges nothing and writes nothing.
signal job_picked(target: Unit, job_id: String)

# The inspect panel owns the ability tooltip wording and its builders are static for exactly this
# reason -- one sentence, two surfaces. Preloaded because that file is a scene script with no
# class_name; tests/ui/test_info_panel_text.gd reaches it the same way.
const InfoPanel := preload("res://Classes/ui/panels/info_panel.gd")

const CARD_HEIGHT := 208
const ITEM_COLUMN := 128
const SPRITE := 52
const CHIP_MIN_W := 30
const JOB_PICKER_MIN_W := 84
const NO_JOB_LABEL := "— none —"

# The eight, in Stats.Stat declaration order, two columns of four. Read off the enum rather than
# listed here, so a ninth stat appears without an edit.
const STAT_COLUMNS := 2

var unit: Unit
# Set by the screen, which owns the Loadout and therefore the only judgement about a move (#741).
# The card wires them into every row it draws rather than judging anything itself.
var judge_move: Callable = Callable()
var perform_move: Callable = Callable()
# What the screen currently has in hand, so a picked-up row reads as picked up on this side too.
# Told rather than asked: the card has no business knowing the screen exists.
var selected_item: EquippableData

var _deploy_button: Button
var _controller: MissionController
var _limbs_row: HFlowContainer
var _job_picker: OptionButton
var _abilities_row: HFlowContainer
var _stats_grid: GridContainer
var _items_column: VBoxContainer
# The stat value labels, by stat, so a preview can rewrite them IN PLACE (#745). Re-captured on every
# _refresh_stats, which is the only thing that builds them.
var _stat_values: Dictionary[Stats.Stat, Label] = {}
var _previewing := false
var _derived_label: Label


# The move callables are arguments rather than fields set afterwards, and that is not style: _build
# draws the item rows, so a card built first and wired second renders its whole inventory with dead
# Callables and only recovers on the next refresh.
static func build(target: Unit, controller: MissionController,
		judge := Callable(), perform := Callable()) -> PreMissionCard:
	var card := PreMissionCard.new()
	card.unit = target
	card._controller = controller
	card.judge_move = judge
	card.perform_move = perform
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

	meta.add_child(_build_job_picker())

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


# --- the job picker (#742) ------------------------------------------------------------------------

# BUILT ONCE AND NEVER REBUILT. _refresh_job below only moves the selection, because the refresh that
# follows a pick would otherwise replace the very control the pick came out of.
#
# fit_to_longest_item is the knob that matters here, not clip_text: it defaults TRUE, which makes an
# OptionButton's minimum width its widest ITEM — one long job name and the card's column walks out of
# the region, which is the law in this file's header and the #685 failure one surface over.
func _build_job_picker() -> Control:
	_job_picker = OptionButton.new()
	_job_picker.flat = true            # it is the job ROW with a caret, not a widget dropped on the card
	_job_picker.clip_text = true
	_job_picker.fit_to_longest_item = false
	_job_picker.custom_minimum_size.x = JOB_PICKER_MIN_W
	_job_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_job_picker.focus_mode = Control.FOCUS_NONE   # Tab belongs to the board swap (#774)
	_job_picker.add_theme_font_size_override("font_size", 11)
	# ALL the states, because a Button falls back to the THEME's hover/pressed/focus inks
	# independently — a normal-state-only override comes undone the moment the cursor lands on it,
	# which is the parchment bug #774 had to fix on the board's own buttons. Disabled keeps the dimmer
	# ink deliberately: greyed has to READ as greyed in both palettes.
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_job_picker.add_theme_color_override(state, QueueStyle.ink(QueueStyle.Role.TITLE_TEXT))
	_job_picker.add_theme_color_override("font_disabled_color",
		QueueStyle.ink(QueueStyle.Role.HEADER_TEXT))

	# Sorted by display name: get_jobs() is a filesystem scan, so an unsorted list would order itself
	# differently on a different machine. "None" leads, and it is a real choice — every roster
	# character today authors no starting job, so it is the state the control opens in.
	_job_picker.add_item(NO_JOB_LABEL)
	_job_picker.set_item_metadata(0, "")
	var ids: Array[String] = []
	for id: String in JobCatalog.get_jobs():
		ids.append(id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		return _job_name(a).naturalnocasecmp_to(_job_name(b)) < 0)
	for id: String in ids:
		_job_picker.add_item(_job_name(id))
		_job_picker.set_item_metadata(_job_picker.item_count - 1, id)

	_job_picker.item_selected.connect(_on_job_item_selected)
	# The POPUP owns about_to_popup, not the OptionButton — it is a Window of its own.
	_job_picker.get_popup().about_to_popup.connect(_refresh_job_options)
	return _job_picker


func _job_name(id: String) -> String:
	var job: JobData = JobCatalog.get_job(id)
	return job.display_name if job != null and job.display_name != "" else id


func _on_job_item_selected(index: int) -> void:
	job_picked.emit(unit, String(_job_picker.get_item_metadata(index)))


# What picking each option would DO, refreshed every time the list opens because the unit's gear and
# stats move underneath it.
#
# A TOOLTIP rather than #745's in-place annotation on the stat grid, and the reason is physical: the
# popup is its own window and it opens OVER that grid, so an annotation under the list is one the
# player cannot see while choosing.
func _refresh_job_options() -> void:
	var popup: PopupMenu = _job_picker.get_popup()
	for i in _job_picker.item_count:
		popup.set_item_tooltip(i, UiText.wrap(job_option_text(String(_job_picker.get_item_metadata(i)))))


# Every number here is DERIVED at read time from the same walk the change itself makes, never authored
# (the Glossary's rule) — so retuning a nudge rewords this for free. The gear line is the one that
# earns the tooltip: a pick can take armour off, and picking the old job back does not put it on.
func job_option_text(job_id: String) -> String:
	var held: Array[String] = unit.unit_instance.jobs
	if held.size() == 1 and held[0] == job_id:
		return "%s — held now." % _job_name(job_id)
	if held.is_empty() and job_id == "":
		return "No job — held now."

	var ids: Array[String] = []
	if job_id != "":
		ids.append(job_id)

	var lines: Array[String] = []
	var deltas: Array[String] = []
	for stat: Stats.Stat in Stats.STAT_DEFAULTS:
		var now := unit.get_effective_stat(stat)
		var then := unit.previewed_stat_for_jobs(stat, ids)
		if now != then:
			deltas.append("%s %d → %d" % [String(Stats.Stat.keys()[stat]), now, then])
	var def_now := unit.get_effective_def()
	var def_then := unit.previewed_def_for_jobs(ids)
	if def_now != def_then:
		deltas.append("DEF %d → %d" % [def_now, def_then])
	lines.append(", ".join(deltas) if not deltas.is_empty() else "No change to the numbers.")

	for piece: EquippableData in unit.gear_lost_under_jobs(ids):
		var armor := piece as ArmorData
		var demand := armor.requirement_text() if armor != null else ""
		lines.append("%s comes off%s, and picking the old job back does not put it on." % [
			piece.display_name, "" if demand == "" else " (needs %s)" % demand])

	lines.append_array(_ability_deltas(ids))
	return "
".join(lines)


# Gained and lost, by ability ID — the same key AbilityData.add_live dedupes on, so a job and a worn
# piece granting the same thing reads as no change rather than as both.
func _ability_deltas(ids: Array[String]) -> Array[String]:
	var now_live: Array[AbilityData] = unit.get_live_abilities()
	var then_live: Array[AbilityData] = unit.previewed_abilities_for_jobs(ids)
	var now_ids: Dictionary[Abilities.Id, bool] = {}
	for ability: AbilityData in now_live:
		now_ids[ability.id] = true
	var then_ids: Dictionary[Abilities.Id, bool] = {}
	for ability: AbilityData in then_live:
		then_ids[ability.id] = true

	var lines: Array[String] = []
	var gained: Array[String] = []
	for ability: AbilityData in then_live:
		if not now_ids.has(ability.id):
			gained.append(ability.display_name)
	if not gained.is_empty():
		lines.append("Gains %s." % ", ".join(gained))
	var lost: Array[String] = []
	for ability: AbilityData in now_live:
		if not then_ids.has(ability.id):
			lost.append(ability.display_name)
	if not lost.is_empty():
		lines.append("Loses %s." % ", ".join(lost))
	return lines


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


# MOVES THE SELECTION, BUILDS NOTHING. See _build_job_picker.
func _refresh_job() -> void:
	var jobs: Array[String] = unit.unit_instance.jobs
	var refusal := unit.job_change_block_reason("")
	_job_picker.disabled = refusal != ""
	if refusal != "":
		# More than one job held. One-job-at-a-time binds at the ROSTER (#731 ruling 10), so a picker
		# that replaced here would perform the exact silent truncation that ruling rejected: it names
		# all of them and declines instead. RosterLint files the authoring mistake behind it.
		# select(-1) comes FIRST — it clears the text this line then writes.
		_job_picker.select(-1)
		var names: Array[String] = []
		for id: String in jobs:
			names.append(_job_name(id))
		_job_picker.text = ", ".join(names)
		_job_picker.tooltip_text = UiText.wrap(refusal)
		return

	var held := jobs[0] if not jobs.is_empty() else ""
	var matched := false
	for i in _job_picker.item_count:
		if String(_job_picker.get_item_metadata(i)) == held:
			_job_picker.select(i)
			matched = true
			break
	if not matched:
		# A job id no catalogue file answers -- apply_unit_state assigns jobs directly, so a save or a
		# roster entry can carry one. Show the raw id rather than claiming "none"; picking replaces it,
		# which is the repair.
		_job_picker.select(-1)
		_job_picker.text = held
	_job_picker.tooltip_text = UiText.wrap(
		"The job this unit fights under. One at a time — picking another replaces it.")


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
	_stat_values.clear()
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
		_stat_values[stat] = value
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
	var row := GearRow.new()
	row.custom_minimum_size.y = 20
	row.wire(unit, judge_move, perform_move)
	row.clicked.connect(func(gear: EquippableData, owner_unit: Unit) -> void:
		gear_clicked.emit(gear, owner_unit))
	row.mouse_entered.connect(func() -> void: gear_hovered.emit(row.item, self))
	row.mouse_exited.connect(func() -> void: gear_unhovered.emit(self))
	if item == null:
		row.add_theme_stylebox_override("panel", QueueStyle.section_box())
		row.modulate = Color(1, 1, 1, 0.45)
		var empty := Label.new()
		empty.text = ""
		row.add_child(empty)
		return row

	var equippable := item as EquippableData
	var reason := _equip_block_reason(equippable)
	row.carry(equippable)
	row.add_theme_stylebox_override("panel",
		QueueStyle.row_box(reason != "", equippable != null and equippable == selected_item))

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


# THE one place the card asks "can this unit use this", and since #744 it is a pass-through: the gate
# itself owns the sentence, so every tooltip and warning above improved without an edit here. That is
# also where the dev's ruling landed -- an invalid readout needs a unit to be validated against, so
# it lives on the card and never in the stash.
func _equip_block_reason(equippable: EquippableData) -> String:
	if equippable == null:
		return ""   # a non-equippable carried item has no gate to fail
	return equippable.can_equip_reason(unit)


static func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.free()


# --- preview-at-decision (#745) -------------------------------------------------------------------

# "STR 6 -> 4" written over the numbers the player is already reading, rather than in a second
# readout somewhere else: the value they compare against has to be the one in front of them.
#
# IT REBUILDS NOTHING. A hover that went through refresh() would free the very row the cursor is on,
# and mouse_exited never fires on a freed node -- so the preview would stick for ever, one frame
# after it appeared. Labels are rewritten in place and put back the same way (#741's law, arriving
# from the other direction).
func show_preview(candidate: EquippableData, incoming: bool) -> void:
	if candidate == null:
		clear_preview()
		return
	_previewing = true
	for stat: Stats.Stat in _stat_values:
		var now := unit.get_effective_stat(stat)
		var then := unit.previewed_stat(stat, candidate)
		var label: Label = _stat_values[stat]
		if now == then:
			label.text = str(now)
			label.remove_theme_color_override("font_color")
			continue
		label.text = "%d → %d" % [now, then]
		label.add_theme_color_override("font_color", QueueStyle.ink(
			QueueStyle.Role.READOUT_ALLY if then > now else QueueStyle.Role.READOUT_ENEMY))
	_derived_label.text = "WT %d → %d  ·  DEF %d → %d" % [
		unit.get_weight(), unit.previewed_weight(candidate, incoming),
		unit.get_effective_def(), unit.previewed_def(candidate)]


# Back to the live numbers. Called on every mouse_exited, and cheap enough to call unconditionally --
# a clear with nothing to clear must be silent, because the exit and the enter of two adjacent rows
# arrive in an order no surface should have to reason about.
func clear_preview() -> void:
	if not _previewing:
		return
	_previewing = false
	for stat: Stats.Stat in _stat_values:
		var label: Label = _stat_values[stat]
		label.text = str(unit.get_effective_stat(stat))
		label.remove_theme_color_override("font_color")
	_refresh_foot()
