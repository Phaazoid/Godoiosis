extends RefCounted
# Renders PlaySession state as the compact 3-char text view (docs/play-api.md):
# every cell is [actor][terrain][overlay]. Tuned for an LLM player — spatial and
# token-light, no layer ever occluded. Reads PlaySession directly (the structured
# dicts stay internal; this is the channel a player reads).

const TERRAIN_GLYPH := {"grass": ".", "mud": "~", "rock": "#", "offmap": " ", "void": " "}   # offmap = NO tile (the #259 rename); "void" = the authored VOID kind -- both render as empty space

# ---- public renders ----

static func render_overview(session) -> String:
	var bounds := _content_bounds(session)
	var lines: Array[String] = []
	lines.append("Turn: %s" % session._faction_name(session.active_faction()))
	lines.append(_grid_block(session, bounds, _overview_overlay(session)))
	lines.append("")
	lines.append(_legend(session))
	var mission_str := _mission_block(session)
	if mission_str != "":
		lines.append("")
		lines.append(mission_str)
	return "\n".join(lines)

# Mark every downed-but-alive body on the board ("v"), live watches ("!"),
# and mission zones ("C" = capture, "E" = extraction) (#413, #612).
# Precedence: downed "v" > watch "!" > zone "C"/"E".
static func _overview_overlay(session) -> Dictionary:
	var overlay := {}
	for zname in session.zones():
		var zone: Dictionary = session.zones()[zname]
		var kind: int = zone.get("kind", ZoneManager.Kind.PATROL)
		var glyph := ""
		if kind == ZoneManager.Kind.CAPTURE:
			glyph = "C"
		elif kind == ZoneManager.Kind.EXTRACTION:
			glyph = "E"
		if glyph != "":
			for cell in zone.get("cells", []):
				overlay[cell] = glyph
	for unit in session.live_units():
		if unit.watch == null or unit.watch.spent or not unit.watch.is_intact():
			continue
		if not unit.watch.is_anchored(unit.movement.cell):
			continue
		for cell in unit.watch.footprint:
			overlay[cell] = "!"
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
		for cell in Reach.get_all_attack_cells_from(unit, unit.get_projected_destination(), unit.get_fired_attack()):
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
	for s in plan.side_actions:
		if s.has("target"):
			lines.append("  %-6s %s -> %s" % [s.type, s.actor, s.target])
		else:
			lines.append("  %-6s %s" % [s.type, s.actor])
	if plan.attacks.is_empty() and plan.counters.is_empty() and plan.moves.is_empty() and plan.side_actions.is_empty():
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
	var notes: Array[String] = []
	if any_downed:
		notes.append("v = downed body on board; finish it or rescue it")
	var has_c := false
	var has_e := false
	for zname in session.zones():
		var kind: int = session.zones()[zname].get("kind", ZoneManager.Kind.PATROL)
		if kind == ZoneManager.Kind.CAPTURE:
			has_c = true
		elif kind == ZoneManager.Kind.EXTRACTION:
			has_e = true
	if has_c:
		notes.append("C = capture zone")
	if has_e:
		notes.append("E = extract zone")
	if not notes.is_empty():
		lines[0] = "Units:   (%s)" % "; ".join(notes)
	return "\n".join(lines)

static func _mission_block(session) -> String:
	if session.scenario_data == null:
		return ""
	var lines: Array[String] = []
	var obj_names: Array[String] = []
	for obj in session.objectives():
		obj_names.append(MissionRules.Objective.keys()[obj])
	var title := "ROUT" if obj_names.is_empty() else " + ".join(obj_names)
	var limit_str := "no limit" if session.round_limit() <= 0 else "limit: %d rounds" % session.round_limit()
	lines.append("Mission: %s      (round %d, %s)" % [title, session.scenario_data.rounds_elapsed + 1, limit_str])
	if session.objectives().is_empty():
		lines.append("  ROUT     defeat all hostile units")
	else:
		for obj in session.objectives():
			match obj:
				MissionRules.Objective.ROUT:
					lines.append("  ROUT     defeat all hostile units")
				MissionRules.Objective.CAPTURE:
					var any_zone := false
					for zname in session.zones():
						var z: Dictionary = session.zones()[zname]
						if z.get("kind") == ZoneManager.Kind.CAPTURE:
							lines.append("  CAPTURE  \"%s\"  %s" % [zname, _format_cells(z.get("cells", []))])
							any_zone = true
					if not any_zone:
						lines.append("  CAPTURE  (no zone painted)")
				MissionRules.Objective.EXTRACT:
					var any_zone := false
					for zname in session.zones():
						var z: Dictionary = session.zones()[zname]
						if z.get("kind") == ZoneManager.Kind.EXTRACTION:
							lines.append("  EXTRACT  \"%s\"  %s" % [zname, _format_cells(z.get("cells", []))])
							any_zone = true
					if not any_zone:
						lines.append("  EXTRACT  (no zone painted)")
	for cond in session.lose_conditions():
		lines.append("  FAIL IF  %s" % MissionRules.defeat_reason(cond))
	lines.append("  (progress: not scored headlessly (#46))")
	return "\n".join(lines)

static func _format_cells(cells: Array) -> String:
	var list: Array[Vector2i] = []
	for c in cells:
		if c is Vector2i:
			list.append(c)
	list.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.y < b.y if a.y != b.y else a.x < b.x
	)
	var parts: Array[String] = []
	for c in list:
		parts.append("(%d,%d)" % [c.x, c.y])
	return " ".join(parts)

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
		wep = _weapon_str(unit.get_equipped_weapon(), unit)
	var state := "  [DOWNED]" if unit.is_downed() else ""
	# Whose watch the "!" cells belong to, and what it fires (#413). Named on the unit line rather
	# than in a second block: the footprint is on the board, this says who is behind it.
	if unit.watch != null and not unit.watch.spent and unit.watch.is_intact() \
			and unit.watch.is_anchored(unit.movement.cell):
		state += "  [WATCHING %s]" % (unit.watch.attack.display_name if unit.watch.attack != null else "?")
	return "%s %s  %s  hp%d/%d  %s  %s%s" % [
		session.handle_for(unit), unit.get_unit_name(), fac,
		unit.get_current_hp(), unit.get_max_hp(),
		squad_tag, wep, state,
	]

static func _weapon_str(e: EquippableData, wielder: Unit) -> String:
	var rune := e as RuneData
	if rune != null:
		return _rune_str(rune, wielder)
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

# A rune gets the same treatment the weapon branch above gets, for the reason stated there (#614):
# a line naming only the rune's SIZE hides power, reach and who can counter, which is most of what
# a carving is. Lists the CATALOGUE (choice_attacks) rather than the channelable subset, and marks
# what cannot fire with its own reason — the law RuneData.choice_attacks states for the menu.
static func _rune_str(rune: RuneData, wielder: Unit) -> String:
	var head := "rune[%s x%d]" % [RuneData.Size.keys()[rune.size], rune.inscriptions.size()]
	if wielder == null:
		return head
	var parts: Array[String] = []
	for attack in rune.choice_attacks(wielder):
		parts.append(_carving_str(rune, wielder, attack))
	if parts.is_empty():
		return head
	return head + "  " + "; ".join(parts)

static func _carving_str(rune: RuneData, wielder: Unit, attack: AttackData) -> String:
	var s := "%s pow%d %s" % [attack.display_name, attack.power, _pattern_str(attack.attack_pattern)]
	# A carving's element is its SIGILS (repeats = weight, so dedupe). elemental_damage_type is
	# WeaponAttackData-only — reading it on a TransmutationData is a runtime error, not a blank.
	var carving := attack as TransmutationData
	if carving != null:
		var seen: Array[Elemental.Element] = []
		for sigil in carving.sigils:
			if sigil == Elemental.Element.NONE or seen.has(sigil):
				continue
			seen.append(sigil)
			s += "/" + Elemental.Element.keys()[sigil]
	# heals/deals_no_damage reinterpret the power printed above, so a line without them misreads.
	if attack.heals:
		s += "/heal"
	if attack.deals_no_damage:
		s += "/nodmg"
	if attack.can_counter:
		s += "/ctr"
	if attack.hits_allies:
		s += "/ff"
	var reason := rune.attack_block_reason(wielder, attack)
	if reason != "":
		s += " (blocked: %s)" % reason
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
