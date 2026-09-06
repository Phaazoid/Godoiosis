extends VBoxContainer

# The stats body of the inspect panel ("StatsSection" in UnitInfoPanel.tscn): HP/Will bars,
# limb readout, derived-stat grid (effective stats, MOV/WT/DEF/LDR/squad) and the live-ability
# list, all with breakdown tooltips (#68, absorbing #66's display scope). Skeleton rows live
# in the scene; per-unit rows are generated here. Tooltip text builders are static, which lets
# tests/ui/test_info_panel_text.gd assert what each line states without standing up a panel;
# tests/ui/test_tooltip_rendering.gd covers the other half -- that this panel feeds them the
# inspected unit's own numbers -- against a real populated scene.
#
# Its LIMB VOCABULARY moved to UnitInstance in #740, beside the enum it names: the pre-mission card
# reads the same short and long labels, and this file has no class_name for a second surface to
# reach. What stays here is the CHIP -- the battle-scoped at-risk colour is not the card's question.

const DIM_COLOR := Color(0.6, 0.62, 0.6)
const NATURAL_COLOR := Color(0.75, 0.78, 0.75)
const EMPTY_COLOR := Color(0.9, 0.3, 0.3)
const PROSTHETIC_COLOR := Color(0.45, 0.8, 0.95)
const AT_RISK_COLOR := Color(0.95, 0.8, 0.25)
const CRISIS_COLOR := Color(0.95, 0.35, 0.3)
const TERRAIN_BUFF_COLOR := Color(0.95, 0.85, 0.3)   # a TEMPORARY source (terrain you stand on)
const NO_TINT := Color(0, 0, 0, 0)                   # alpha 0 = leave the theme's colour alone


@onready var hp_bar: ProgressBar = $HPRow/HPBar
@onready var hp_value: Label = $HPRow/HPValue
@onready var will_bar: ProgressBar = $WillRow/WillBar
@onready var will_value: Label = $WillRow/WillValue
@onready var limbs_row: HBoxContainer = $LimbsRow
@onready var stats_grid: GridContainer = $StatsGrid
@onready var abilities_list: VBoxContainer = $AbilitiesList

var unit: Unit
var board: BoardContext   # for board-dependent readouts (terrain Cover DEF); null = armor only

func set_unit(target: Unit, context: BoardContext = null):
	board = context
	if unit != null and is_instance_valid(unit):
		unit.unit_instance.hp_changed.disconnect(_on_hp_changed)
		unit.unit_instance.will_changed.disconnect(_on_will_changed)
		unit.unit_instance.died.disconnect(_on_unit_died)
		unit.downed_countdown_changed.disconnect(_on_countdown_changed)
		unit.stats_changed.disconnect(_on_stats_changed)
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
	unit.stats_changed.connect(_on_stats_changed)
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
	chip.text = UnitInstance.LIMB_SHORT[slot]
	chip.mouse_filter = Control.MOUSE_FILTER_STOP
	var fitting: UnitInstance.LimbFitting = inst.limbs[slot]
	match fitting.state:
		UnitInstance.LimbState.EMPTY:
			chip.add_theme_color_override("font_color", EMPTY_COLOR)
			chip.tooltip_text = "%s: maimed" % UnitInstance.LIMB_FULL[slot]
		UnitInstance.LimbState.PROSTHETIC:
			chip.add_theme_color_override("font_color", PROSTHETIC_COLOR)
			chip.tooltip_text = "%s: prosthetic (stat %d)" % [UnitInstance.LIMB_FULL[slot], inst.limb_stat(slot)]
		_:
			chip.add_theme_color_override("font_color", NATURAL_COLOR)
			chip.tooltip_text = "%s: natural" % UnitInstance.LIMB_FULL[slot]
	if slot == at_risk:
		chip.add_theme_color_override("font_color", AT_RISK_COLOR)
		chip.tooltip_text += " — NEXT AT RISK (Will can't cover another down)"
	chip.tooltip_text = UiText.wrap(chip.tooltip_text)
	return chip

func _badge(text: String, color: Color, tip: String) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", color)
	lbl.tooltip_text = UiText.wrap(tip)
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	return lbl

func _refresh_stats():
	for child in stats_grid.get_children():
		child.queue_free()
	var inst := unit.unit_instance
	for stat: Stats.Stat in [Stats.Stat.STR, Stats.Stat.DEX, Stats.Stat.CON, Stats.Stat.PER]:
		var eff := unit.get_effective_stat(stat)
		# Yellow = a TEMPORARY source is contributing — the same language the DEF row already uses
		# for terrain cover. It means this number will move on its own when the effect runs out.
		var stat_color: Color = TERRAIN_BUFF_COLOR if _temporary_delta(stat) != 0 else NO_TINT
		_add_stat(Stats.Stat.keys()[stat], str(eff), Glossary.term_for_stat(stat),
			stat_tooltip(inst.get_base_stat(stat), eff, _stat_sources(stat)), stat_color)
	_add_stat("MOV", str(unit.get_mov()), Glossary.Term.MOV, mov_tooltip(
		UnitInstance.JOBLESS_MOV_BASE,
		Stats.dex_mov_band(unit.get_effective_stat(Stats.Stat.DEX)),
		inst.empty_leg_count()))
	_add_stat("WT", str(unit.get_weight()), Glossary.Term.WEIGHT, weight_tooltip(unit.get_weight()))
	var armor_name := ""
	var armor_power := 0
	var armor_coverage := ""
	if unit.worn_armor != null:
		armor_name = unit.worn_armor.display_name
		armor_power = unit.worn_armor.def_power
		armor_coverage = unit.worn_armor.coverage_text()
	# One shared breakdown (the resolver sums the same call). Yellow = a temporary source is
	# contributing — terrain you're standing on, not gear you own.
	var def := RulesService.def_breakdown(unit, unit.movement.cell, board)
	var def_color: Color = TERRAIN_BUFF_COLOR if def["cover"] > 0 else NO_TINT
	_add_stat("DEF", str(def["total"]), Glossary.Term.DEF, def_tooltip(
		armor_name, armor_power, unit.get_effective_stat(Stats.Stat.CON),
		def["armor"], def["cover"], def["total"], armor_coverage), def_color)
	_add_stat("LDR", str(unit.get_effective_ldr()), Glossary.term_for_stat(Stats.Stat.LDR),
		"LDR %d %+d PER band" % [
			unit.get_effective_stat(Stats.Stat.LDR),
			Stats.per_ldr_band(unit.get_effective_stat(Stats.Stat.PER))])
	_add_stat("SQD", "%d/%d" % [unit.squad.get_members().size(), unit.squad.max_size()],
		Glossary.Term.SQUAD_SIZE,
		"Capacity: 1 + leader eLDR %d / %d per member" % [
			unit.squad.get_leader().get_effective_ldr(), Squad.MEMBER_LDR_COST])

# Every contributor to `stat`, itemized in chain order (stats.md: base -> limb -> jobs -> effects
# -> gear). This is what StatEffect.source_name exists for: before #112 the modifier stage was an
# anonymous bag of ints, so the best a tooltip could do was say "(limbs / jobs / gear)" and shrug.
func _stat_sources(stat: Stats.Stat) -> Array[String]:
	var inst := unit.unit_instance
	var lines: Array[String] = []
	var limb := inst.get_limb_effective_base(stat)
	var limb_delta := limb - inst.get_base_stat(stat)
	if limb_delta != 0:
		lines.append("Limbs %+d" % limb_delta)
	var job_delta := inst.get_effective_stat(stat) - limb
	if job_delta != 0:
		lines.append("Jobs %+d" % job_delta)
	for effect in unit.stat_effects:
		var delta := effect.get_modifier(stat)
		if delta != 0:
			lines.append(effect_source_text(effect.source_name, delta, effect.turns_remaining))
	var gear_delta := unit.get_effective_stat(stat) - unit.get_body_stat(stat)
	if gear_delta != 0 and unit.worn_armor != null:
		lines.append("%s %+d" % [unit.worn_armor.display_name, gear_delta])
	return lines

# How much of `stat` is currently on loan — drives the temporary tint above.
func _temporary_delta(stat: Stats.Stat) -> int:
	var total := 0
	for effect in unit.stat_effects:
		total += effect.get_modifier(stat)
	return total

# Every row's tooltip leads with WHAT the stat means (Glossary short, #135), then the number's
# provenance when there is any. This deliberately ends the empty-when-unmodified tooltip — that
# emptiness was an anti-noise call about provenance alone, and the meaning line is the content
# it was waiting for. The provenance builders below are unchanged.
func _add_stat(stat_name: String, value: String, term: Glossary.Term, provenance: String,
		value_color := NO_TINT):
	var name_lbl := Label.new()
	name_lbl.text = stat_name
	name_lbl.add_theme_color_override("font_color", DIM_COLOR)
	var value_lbl := Label.new()
	value_lbl.text = value
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if value_color.a > 0.0:
		value_lbl.add_theme_color_override("font_color", value_color)
	var tip: String = Glossary.short(term)
	if provenance != "":
		tip += "\n" + provenance
	var wrapped := UiText.wrap(tip)
	for lbl: Label in [name_lbl, value_lbl]:
		lbl.tooltip_text = wrapped
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	stats_grid.add_child(name_lbl)
	stats_grid.add_child(value_lbl)

func _refresh_abilities():
	for child in abilities_list.get_children():
		child.queue_free()
	var live := unit.get_live_abilities()
	if live.is_empty():
		abilities_list.add_child(_badge("None", DIM_COLOR, ""))
		return
	for ability in live:
		abilities_list.add_child(_ability_row(ability))

func _ability_row(ability: AbilityData) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var kind_name: String = AbilityData.AbilityKind.keys()[ability.kind].capitalize()
	row.tooltip_text = UiText.wrap(ability_tooltip(ability.display_name, kind_name, ability.description))
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

func _on_stats_changed():
	_refresh()   # a stat move can shift bars (max HP), the limb row (a maim fired it) AND the grid

static func mov_tooltip(base: int, dex_band: int, empty_legs: int) -> String:
	var lines: Array[String] = ["Base %d %+d DEX band" % [base, dex_band]]
	match empty_legs:
		1:
			lines.append("Halved: one leg gone")
		2:
			lines.append("Pinned to 1: both legs gone")
	return "\n".join(lines)

# One line per contributor, or nothing at all when the stat is untouched. Sources are listed even
# when they CANCEL OUT — a +2 tonic against a -2 armour tax nets zero, but losing the tonic is
# about to cost 2, and a silent tooltip would make that read as a bug.
static func stat_tooltip(base: int, effective: int, sources: Array[String]) -> String:
	if sources.is_empty():
		return ""
	var lines: Array[String] = ["Base %d  ->  %d" % [base, effective]]
	lines.append_array(sources)
	return "\n".join(lines)

static func effect_source_text(source_name: String, delta: int, turns_remaining: int) -> String:
	if turns_remaining == StatEffect.PERMANENT:
		return "%s %+d" % [source_name, delta]
	var plural := "" if turns_remaining == 1 else "s"
	return "%s %+d (%d turn%s)" % [source_name, delta, turns_remaining, plural]

static func weight_tooltip(carried: int) -> String:
	return "Carried gear %d\nTracked only -- no effect yet" % carried

static func def_tooltip(armor_name: String, def_power: int, con: int, armor_def: int, cover_def: int, total: int, coverage: String = "") -> String:
	# `total` is passed, not re-added: RulesService.def_breakdown already composed it, and a
	# second addition of a number that already exists is a seam waiting to diverge — the next
	# DEF source added there would reach the value and miss this line.
	var lines: Array[String] = []
	if armor_name == "":
		lines.append("No armor worn")
	else:
		lines.append("%s: %d armor x CON %d = %d" % [armor_name, def_power, con, armor_def])
		# Which kinds the piece answers (#424): "" when it covers everything, which is what every piece
		# authored before kinds existed still does. The standing readout shows the full number; the
		# queue row is where a specific hit learns whether the piece covers it.
		if coverage != "":
			lines.append("Covers: %s" % coverage.trim_prefix("vs "))
	if cover_def > 0:
		lines.append("Cover (terrain): +%d" % cover_def)
	lines.append("Total: %d" % total)
	return "\n".join(lines)

static func ability_tooltip(display_name: String, kind_name: String, description: String) -> String:
	var text := "%s (%s)" % [display_name, kind_name]
	if description != "":
		text += "\n" + description
	return text
