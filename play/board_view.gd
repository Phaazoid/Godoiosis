extends RefCounted
# Renders PlaySession state as the compact 3-char text view (docs/play-api.md):
# every cell is [actor][terrain][overlay]. Tuned for an LLM player — spatial and
# token-light, no layer ever occluded. Reads PlaySession directly (the structured
# dicts stay internal; this is the channel a player reads).

const TERRAIN_GLYPH := {"grass": ".", "mud": "~", "rock": "#", "void": " "}

# ---- public renders ----

static func render_overview(session) -> String:
	var bounds := _content_bounds(session)
	var lines: Array[String] = []
	lines.append("Turn: %s" % session._faction_name(session.active_faction()))
	lines.append(_grid_block(session, bounds, _downed_overlay(session)))
	lines.append("")
	lines.append(_legend(session))
	return "\n".join(lines)

# Mark every downed-but-alive body on the board ("v"). Downed units cling at 1 HP, are out
# of action, and have been ejected into solo squads — but they still occupy their cell.
static func _downed_overlay(session) -> Dictionary:
	var overlay := {}
	for unit in session.live_units():
		if unit.is_downed():
			overlay[unit.movement.cell] = "v"
	return overlay

static func render_focus(session, handle: String) -> String:
	var unit: Unit = session.unit_by_handle(handle)
	if unit == null:
		return "no unit '%s'" % handle
	var overlay := {}
	var range_info: Dictionary = RulesService.compute_move_range(unit, session._board())
	for cell in range_info.reachable.keys():
		overlay[cell] = "+"
	for cell in range_info.squad_unreachable.keys():
		overlay[cell] = "-"
	if unit.has_equipped_weapon():
		for cell in unit.combat.get_all_attack_cells_from(unit.get_projected_destination()):
			overlay[cell] = "*" if overlay.has(cell) else "x"
	for other in session.live_units():
		if other.is_downed() and not overlay.has(other.movement.cell):
			overlay[other.movement.cell] = "v"
	overlay[unit.movement.cell] = "@"
	var lines: Array[String] = []
	lines.append("focus %s (%s)   + move   - breaks leader range   x attack   v downed   @ here" % [handle, unit.get_unit_name()])
	lines.append(_grid_block(session, _content_bounds(session), overlay))
	lines.append("")
	lines.append("  " + _unit_line(session, unit))
	return "\n".join(lines)

static func render_preview(session) -> String:
	var res: Dictionary = session.preview()
	if not res.ok:
		var msg := "preview: " + str(res.error)
		if res.has("invalid"):
			for e in res.invalid:
				msg += "\n  - " + str(e)
		return msg
	var plan: Dictionary = res.plan
	var lines: Array[String] = ["Plan preview (squad %d):" % session._squad_id(session.squad_manager.active_squad)]
	for m in plan.moves:
		lines.append("  MOVE   %s -> %s" % [m.actor, str(m.dest)])
	for a in plan.attacks:
		lines.append("  ATTACK %s -> %s : %d dmg%s" % [a.actor, a.target, a.dmg, _hp_tag(a)])
	for c in plan.counters:
		if c.skipped:
			lines.append("    ctr  %s : none (downed/killed before it could strike back)" % c.actor)
		else:
			lines.append("    ctr  %s -> %s : %d dmg%s" % [c.actor, c.target, c.dmg, _hp_tag(c)])
	for r in plan.rescues:
		lines.append("  RESCUE %s -> %s (revives to 1 hp)" % [r.actor, r.target])
	if plan.attacks.is_empty() and plan.counters.is_empty() and plan.moves.is_empty() and plan.rescues.is_empty():
		lines.append("  (empty plan)")
	return "\n".join(lines)

static func render_result(events: Array) -> String:
	if events.is_empty():
		return "Result: (no effects)"
	var lines: Array[String] = ["Result:"]
	for e in events:
		lines.append("  " + str(e))
	return "\n".join(lines)

# ---- internals ----

static func _hp_tag(a: Dictionary) -> String:
	if a.lethality == ResolvedOutcome.Lethality.KILLED:
		return " -> DIES"
	if a.lethality == ResolvedOutcome.Lethality.DOWNED:
		return " -> DOWNED (clings at 1 hp)"
	if a.hp_after >= 0:
		return " -> %d hp" % a.hp_after
	return ""

static func _content_bounds(session) -> Rect2i:
	var rect: Rect2i = session.grid.get_used_rect()
	for unit in session.live_units():
		rect = rect.expand(unit.movement.cell)
	return rect

static func _grid_block(session, bounds: Rect2i, overlay: Dictionary) -> String:
	var lines: Array[String] = []
	var header := "      "
	for x in range(bounds.position.x, bounds.end.x):
		header += "%3d" % x
	lines.append(header)
	for y in range(bounds.position.y, bounds.end.y):
		var row := "y=%3d " % y
		for x in range(bounds.position.x, bounds.end.x):
			row += _cell_str(session, Vector2i(x, y), overlay)
		lines.append(row)
	return "\n".join(lines)

static func _cell_str(session, cell: Vector2i, overlay: Dictionary) -> String:
	var actor := " "
	var unit: Unit = _unit_at(session, cell)
	if unit != null:
		actor = session.handle_for(unit)
	return actor + _terrain_glyph(session, cell) + str(overlay.get(cell, " "))

static func _terrain_glyph(session, cell: Vector2i) -> String:
	var t: Dictionary = session.terrain_at(cell)
	if not t.exists:
		return " "
	if not t.walkable:
		return "#"
	return TERRAIN_GLYPH.get(t.type, "?")

static func _unit_at(session, cell: Vector2i) -> Unit:
	for unit in session.live_units():
		if unit.movement.cell == cell:
			return unit
	return null

static func _legend(session) -> String:
	var lines: Array[String] = ["Units:"]
	var any_downed := false
	for unit in session.live_units():
		lines.append("  " + _unit_line(session, unit))
		if unit.is_downed():
			any_downed = true
	if any_downed:
		lines[0] = "Units:   (v = downed body on board; finish it or rescue it)"
	return "\n".join(lines)

static func _unit_line(session, unit: Unit) -> String:
	var fac := "P"
	if unit.get_faction() == Team.Faction.ENEMY:
		fac = "E"
	elif unit.get_faction() != Team.Faction.PLAYER:
		fac = "O"
	var squad_tag := "solo"
	if unit.has_squad():
		squad_tag = "sq%d%s" % [session._squad_id(unit.squad), "(lead)" if unit.is_leader() else ""]
	var wep := "(unarmed)"
	if unit.has_equipped_weapon():
		wep = _weapon_str(unit.get_equipped_weapon())
	var state := "  [DOWNED]" if unit.is_downed() else ""
	return "%s %s  %s  hp%d/%d  %s  %s%s" % [
		session.handle_for(unit), unit.get_unit_name(), fac,
		unit.get_current_hp(), unit.get_max_hp(),
		squad_tag, wep, state,
	]

static func _weapon_str(e: EquippableData) -> String:
	var rune := e as RuneData
	if rune != null:
		return "rune[%s x%d]" % [RuneData.Size.keys()[rune.size], rune.inscriptions.size()]
	var inst := e as WeaponInstance
	if inst == null or inst.template == null:
		return "(equip)"
	var w := inst.template
	var main: WeaponAttackData = w.main_attack
	var main_power: int = main.power if main != null else 0
	var main_pattern: AttackPattern = main.attack_pattern if main != null else null
	# Show the PATTERN, not just the weapon_type enum — two "CHAINSWORD"s can be a wildly
	# different shape (omnidirectional Manhattan vs a 1-tile directional ForwardWide), which
	# decides reach AND who can counter. Hiding it once made a correct no-counter look like a bug.
	var s := "%s pow%d %s" % [WeaponData.WeaponType.keys()[w.weapon_type], main_power, _pattern_str(main_pattern)]
	if w.extra_attacks.size() > 0:
		s += " +%datk" % w.extra_attacks.size()   # stock alternates beyond the main (#72)
	if main != null and main.elemental_damage_type != Elemental.Element.NONE:
		s += "/" + Elemental.Element.keys()[main.elemental_damage_type]
	if main != null and main.can_counter:
		s += "/ctr"
	if main != null and main.hits_allies:
		s += "/ff"   # friendly-fire: its blast hits allies in range too
	return s

static func _pattern_str(p: AttackPattern) -> String:
	if p == null:
		return "melee[1]"
	if p is ManhattanRangePattern:
		return "Manhattan[%d-%d%s]" % [p.min_range, p.max_range, ("+" if p.max_and_a_half else "")]
	if p is ForwardWidePattern:
		return "ForwardWide[L%d W%d]" % [p.length, p.width]
	if p is ForwardLinePattern:
		return "ForwardLine[L%d]" % p.length
	return "pattern?"
