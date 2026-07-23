extends VBoxContainer

# The stats body of the inspect panel ("StatsSection" in UnitInfoPanel.tscn): HP/Will bars,
# limb readout, derived-stat grid (effective stats, MOV/WT/DEF/LDR/squad) and the live-ability
# list, all with breakdown tooltips (#68, absorbing #66's display scope). Skeleton rows live
# in the scene; per-unit rows are generated here. Tooltip text builders are static so
# tests/ui/test_info_panel_text.gd can cover them headless.

const DIM_COLOR := Color(0.6, 0.62, 0.6)
const NATURAL_COLOR := Color(0.75, 0.78, 0.75)
const EMPTY_COLOR := Color(0.9, 0.3, 0.3)
const PROSTHETIC_COLOR := Color(0.45, 0.8, 0.95)
const AT_RISK_COLOR := Color(0.95, 0.8, 0.25)
const CRISIS_COLOR := Color(0.95, 0.35, 0.3)

const LIMB_SHORT: Dictionary[UnitInstance.LimbSlot, String] = {
	UnitInstance.LimbSlot.ARM_L: "LA",
	UnitInstance.LimbSlot.ARM_R: "RA",
	UnitInstance.LimbSlot.LEG_L: "LL",
	UnitInstance.LimbSlot.LEG_R: "RL",
}
const LIMB_FULL: Dictionary[UnitInstance.LimbSlot, String] = {
	UnitInstance.LimbSlot.ARM_L: "Left arm",
	UnitInstance.LimbSlot.ARM_R: "Right arm",
	UnitInstance.LimbSlot.LEG_L: "Left leg",
	UnitInstance.LimbSlot.LEG_R: "Right leg",
}

@onready var hp_bar: ProgressBar = $HPRow/HPBar
@onready var hp_value: Label = $HPRow/HPValue
@onready var will_bar: ProgressBar = $WillRow/WillBar
@onready var will_value: Label = $WillRow/WillValue
@onready var limbs_row: HBoxContainer = $LimbsRow
@onready var stats_grid: GridContainer = $StatsGrid
@onready var abilities_list: VBoxContainer = $AbilitiesList

var unit: Unit

func set_unit(target: Unit):
	if unit != null and is_instance_valid(unit):
		unit.unit_instance.hp_changed.disconnect(_on_hp_changed)
		unit.unit_instance.will_changed.disconnect(_on_will_changed)
		unit.unit_instance.died.disconnect(_on_unit_died)
		unit.downed_countdown_changed.disconnect(_on_countdown_changed)
	unit = target
	if unit == null:
		_clear_dynamic()
		hp_value.text = ""
		will_value.text = ""
		return
	unit.unit_instance.hp_changed.connect(_on_hp_changed)
	unit.unit_instance.will_changed.connect(_on_will_changed)
	unit.unit_instance.died.connect(_on_unit_died)
	unit.downed_countdown_changed.connect(_on_countdown_changed)
	_refresh()

func _refresh():
	_refresh_bars()
	_refresh_limbs()
	_refresh_stats()
	_refresh_abilities()

func _clear_dynamic():
	for container: Node in [limbs_row, stats_grid, abilities_list]:
		for child in container.get_children():
			child.queue_free()

func _refresh_bars():
	hp_bar.max_value = unit.get_max_hp()
	hp_bar.value = unit.get_current_hp()
	hp_value.text = "%d/%d" % [unit.get_current_hp(), unit.get_max_hp()]
	will_bar.max_value = unit.unit_instance.get_max_will()
	will_bar.value = unit.unit_instance.get_current_will()
	will_value.text = "%d/%d" % [unit.unit_instance.get_current_will(), unit.unit_instance.get_max_will()]

func _refresh_limbs():
	for child in limbs_row.get_children():
		child.queue_free()
	var inst := unit.unit_instance
	var at_risk: int = -1
	if not inst.can_afford_down():
		at_risk = inst.next_maim_slot()
	for slot in UnitInstance.LimbSlot.values():
		limbs_row.add_child(_limb_chip(inst, slot, at_risk))
	if unit.is_downed() and unit.downed_turns_remaining > 0:
		limbs_row.add_child(_badge("DOWN %d" % unit.downed_turns_remaining, EMPTY_COLOR,
			"Dies in %d turn(s) without rescue" % unit.downed_turns_remaining))
	if unit.in_crisis:
		limbs_row.add_child(_badge("CRISIS", CRISIS_COLOR,
			"Will locked at 0 — another down this battle is death"))

func _limb_chip(inst: UnitInstance, slot: UnitInstance.LimbSlot, at_risk: int) -> Label:
	var chip := Label.new()
	chip.text = LIMB_SHORT[slot]
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	var fitting: UnitInstance.LimbFitting = inst.limbs[slot]
	match fitting.state:
		UnitInstance.LimbState.EMPTY:
			chip.add_theme_color_override("font_color", EMPTY_COLOR)
			chip.tooltip_text = "%s: maimed" % LIMB_FULL[slot]
		UnitInstance.LimbState.PROSTHETIC:
			chip.add_theme_color_override("font_color", PROSTHETIC_COLOR)
			chip.tooltip_text = "%s: prosthetic (stat %d)" % [LIMB_FULL[slot], inst.limb_stat(slot)]
		_:
			chip.add_theme_color_override("font_color", NATURAL_COLOR)
			chip.tooltip_text = "%s: natural" % LIMB_FULL[slot]
	if slot == at_risk:
		chip.add_theme_color_override("font_color", AT_RISK_COLOR)
		chip.tooltip_text += " — NEXT AT RISK (Will can't cover another down)"
	return chip

func _badge(text: String, color: Color, tip: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.tooltip_text = tip
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	return lbl

func _refresh_stats():
	for child in stats_grid.get_children():
		child.queue_free()
	var inst := unit.unit_instance
	for stat: Stats.Stat in [Stats.Stat.STR, Stats.Stat.DEX, Stats.Stat.CON, Stats.Stat.PER]:
		var eff := unit.get_effective_stat(stat)
		var base := inst.get_base_stat(stat)
		var tip := ""
		if eff != base:
			tip = "Base %d, effective %d (limbs / jobs / gear)" % [base, eff]
		_add_stat(Stats.Stat.keys()[stat], str(eff), tip)
	_add_stat("MOV", str(unit.get_mov()), mov_tooltip(
		UnitInstance.JOBLESS_MOV_BASE,
		Stats.dex_mov_band(unit.get_effective_stat(Stats.Stat.DEX)),
		unit.get_weight(), UnitInstance.WEIGHT_MOV_THRESHOLD,
		UnitInstance.WEIGHT_MOV_PENALTY, inst.empty_leg_count()))
	var body := inst.get_base_stat(Stats.Stat.CON)
	_add_stat("WT", str(unit.get_weight()), weight_tooltip(
		body, unit.get_weight() - body,
		UnitInstance.WEIGHT_MOV_THRESHOLD, UnitInstance.WEIGHT_MOV_PENALTY))
	var armor_name := ""
	var armor_power := 0
	if unit.worn_armor != null:
		armor_name = unit.worn_armor.item_name
		armor_power = unit.worn_armor.def_power
	_add_stat("DEF", str(unit.get_effective_def()), def_tooltip(
		armor_name, armor_power, unit.get_effective_stat(Stats.Stat.CON)))
	_add_stat("LDR", str(unit.get_effective_ldr()), "LDR %d %+d PER band" % [
		unit.get_effective_stat(Stats.Stat.LDR),
		Stats.per_ldr_band(unit.get_effective_stat(Stats.Stat.PER))])
	_add_stat("SQD", "%d/%d" % [unit.squad.get_members().size(), unit.squad.max_size()],
		"Capacity: 1 + leader eLDR %d / %d per member" % [
			unit.squad.get_leader().get_effective_ldr(), Squad.MEMBER_LDR_COST])

func _add_stat(stat_name: String, value: String, tip: String):
	var name_lbl := Label.new()
	name_lbl.text = stat_name
	name_lbl.add_theme_color_override("font_color", DIM_COLOR)
	var value_lbl := Label.new()
	value_lbl.text = value
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if tip != "":
		for lbl: Label in [name_lbl, value_lbl]:
			lbl.tooltip_text = tip
			lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	stats_grid.add_child(name_lbl)
	stats_grid.add_child(value_lbl)

func _refresh_abilities():
	for child in abilities_list.get_children():
		child.queue_free()
	var live := unit.unit_instance.get_live_abilities()
	if live.is_empty():
		abilities_list.add_child(_badge("None", DIM_COLOR, ""))
		return
	for ability in live:
		abilities_list.add_child(_ability_row(ability))

func _ability_row(ability: AbilityData) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var kind_name: String = AbilityData.AbilityKind.keys()[ability.kind].capitalize()
	row.tooltip_text = ability_tooltip(ability.display_name, kind_name, ability.description)
	var name_lbl := Label.new()
	name_lbl.text = ability.display_name
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var kind_lbl := Label.new()
	kind_lbl.text = kind_name
	kind_lbl.add_theme_color_override("font_color", DIM_COLOR)
	row.add_child(name_lbl)
	row.add_child(kind_lbl)
	return row

func _on_hp_changed(_current, _max):
	_refresh_bars()

func _on_will_changed(_current, _max):
	_refresh()   # a maim rides this signal — bars, limbs AND stats can all shift

func _on_unit_died():
	hp_bar.value = 0
	hp_value.text = "DED X_X"

func _on_countdown_changed(_turns: int):
	_refresh_limbs()

static func mov_tooltip(base: int, dex_band: int, weight: int, threshold: int, penalty: int, empty_legs: int) -> String:
	var lines: Array[String] = ["Base %d %+d DEX band" % [base, dex_band]]
	if weight >= threshold:
		lines.append("-%d heavy load (WT %d >= %d)" % [penalty, weight, threshold])
	match empty_legs:
		1:
			lines.append("Halved: one leg gone")
		2:
			lines.append("Pinned to 1: both legs gone")
	return "\n".join(lines)

static func weight_tooltip(body: int, gear: int, threshold: int, penalty: int) -> String:
	return "Body (CON) %d + gear %d\nAt %d+ MOV takes -%d" % [body, gear, threshold, penalty]

static func def_tooltip(armor_name: String, def_power: int, con: int) -> String:
	if armor_name == "":
		return "No armor worn"
	return "%s: %d armor x CON %d" % [armor_name, def_power, con]

static func ability_tooltip(display_name: String, kind_name: String, description: String) -> String:
	var text := "%s (%s)" % [display_name, kind_name]
	if description != "":
		text += "\n" + description
	return text
