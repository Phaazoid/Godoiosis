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
	lines.append(_grid_block(session, bounds, {}))
	lines.append("")
	lines.append(_legend(session))
	return "\n".join(lines)

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
	overlay[unit.movement.cell] = "@"
	var lines: Array[String] = []
	lines.append("focus %s (%s)   + move   - breaks leader range   x attack   @ here" % [handle, unit.get_unit_name()])
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
		lines.append("    ctr  %s -> %s : %d dmg%s" % [c.actor, c.target, c.dmg, _hp_tag(c)])
	if plan.attacks.is_empty() and plan.counters.is_empty() and plan.moves.is_empty():
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
	if a.lethal:
		return " -> DIES"
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
	for unit in session.live_units():
		lines.append("  " + _unit_line(session, unit))
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
	return "%s %s  %s  hp%d/%d  %s  %s" % [
		session.handle_for(unit), unit.get_unit_name(), fac,
		unit.get_current_hp(), unit.get_base_stat(Stats.Stat.MHP),
		squad_tag, wep,
	]

static func _weapon_str(w: WeaponData) -> String:
	var s := "%s pow%d" % [WeaponData.WeaponType.keys()[w.weapon_type], w.power]
	if w.elemental_damage_type != Elemental.Element.NONE:
		s += "/" + Elemental.Element.keys()[w.elemental_damage_type]
	if w.can_counter:
		s += "/ctr"
	return s
