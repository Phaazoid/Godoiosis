extends RefCounted
# Renders PlaySession state as the compact 3-char text view (docs/play-api.md):
# every cell is [actor][terrain][overlay]. Tuned for an LLM player — spatial and
# token-light, no layer ever occluded. Reads PlaySession directly (the structured
# dicts stay internal; this is the channel a player reads).

const PlaySession := preload("res://play/play_session.gd")   # for STASH, the name `kit` shares with `give`

const TERRAIN_GLYPH := {"grass": ".", "tall_grass": ",", "mud": "~", "rock": "#", "offmap": " ", "void": " "}   # offmap = past the board's rect; "void" = a hole, painted or erased (#875) -- both render as empty space; "," is the glyph #895's own map sketch already uses for tall grass

# ---- public renders ----

static func render_overview(session) -> String:
	var bounds := _content_bounds(session)
	var lines: Array[String] = []
	lines.append("Turn: %s" % session._faction_name(session.active_faction()))
	lines.append(_grid_block(session, bounds, _overview_overlay(session)))
	lines.append("")
	lines.append(_legend(session))
	var pre_mission := _pre_mission_block(session)
	if pre_mission != "":
		lines.append("")
		lines.append(pre_mission)
	var mission_str := _mission_block(session)
	if mission_str != "":
		lines.append("")
		lines.append(mission_str)
	return "\n".join(lines)

# Mark every downed-but-alive body on the board ("v"), live watches ("!"),
# mission zones ("C" = capture, "E" = extraction) (#413, #612), and while the pre-mission phase is
# open the deployment zone ("D", #46), which the game hides the moment the battle begins.
# Precedence: downed "v" > watch "!" > zone "C"/"E"/"D".
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
		elif kind == ZoneManager.Kind.DEPLOYMENT and session.is_deploying():
			glyph = "D"
		if glyph != "":
			for cell in zone.get("cells", []):
				overlay[cell] = glyph
	for unit in session.live_units():
		if unit.watch == null or not unit.watch.is_armed():
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

# The enemy ranges view (#46): the game's V key as text. Its two glyphs are its own, unused by the
# overview and focus overlays, and the strike glyph wins a cell both mark.
const STRIKE_GLYPH := "%"
const STAND_GLYPH := "="

static func render_ranges(session, handle := "") -> String:
	var res: Dictionary = session.ranges(handle)
	if not res.ok:
		return "> ERROR: " + str(res.error)
	var overlay := {}
	for cell in res.move:
		overlay[cell] = STAND_GLYPH
	for cell in res.reach:
		overlay[cell] = STRIKE_GLYPH
	var subjects: Array = res.subjects
	var lines: Array[String] = []
	lines.append("ranges of %s, seen by %s" % [", ".join(subjects) if not subjects.is_empty() else "nobody", res.viewer])
	lines.append("  %s an enemy can strike here   %s an enemy can stand here but not strike" % [STRIKE_GLYPH, STAND_GLYPH])
	lines.append(_grid_block(session, _content_bounds(session), overlay))
	lines.append("")
	for row: Dictionary in res.units:
		var unit: Unit = session.unit_by_handle(row.unit)
		var cell: Vector2i = row.cell
		var at := "(%d,%d)" % [cell.x, cell.y]
		if unit != null and unit.movement.cell != cell:
			at += " planned, from (%d,%d)" % [unit.movement.cell.x, unit.movement.cell.y]
		var attackers: Array = row.attackers
		var verdict: String = ("hit by " + ", ".join(attackers)) if not attackers.is_empty() else "out of reach"
		lines.append("  %s at %s: %s" % [row.unit, at, verdict])
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
		lines.append("  ATTACK %s -> %s (%s): %d dmg%s" % [a.actor, a.target, a.attack, a.dmg, _hp_tag(a)])
	for c in plan.counters:
		if c.skipped:
			lines.append("    ctr  %s : none (downed/killed before it could strike back)" % c.actor)
		else:
			lines.append("    ctr  %s -> %s (%s): %d dmg%s" % [c.actor, c.target, c.attack, c.dmg, _hp_tag(c)])
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
	# THE TABLE WINS, and it is consulted BEFORE walkability (#875). Both kinds of nothing live in
	# it -- "offmap" past the board's rect and "void" a hole inside it, which terrain_at now tells
	# apart -- and both are unwalkable, so the `#` branch used to swallow them whole: a painted
	# chasm drew as MASONRY, and TERRAIN_GLYPH's own "void" entry had been unreachable since the
	# day it was written. That is this ticket's confusion in the view the Play API reads.
	#
	# `#` keeps the meaning it always had underneath: the fallback for an unwalkable tile with no
	# glyph of its own -- a wall, a boulder, deep water.
	if TERRAIN_GLYPH.has(t.type):
		return TERRAIN_GLYPH[t.type]
	if not t.walkable:
		return "#"
	return "?"

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

# The pre-mission phase (#46): how many are placed against the cap, where one more may stand, and
# who is waiting in reserve -- the decisions the loadout screen offers, before anything moves.
static func _pre_mission_block(session) -> String:
	if not session.is_deploying():
		return ""
	var cap: int = session.deployment_cap()
	var lines: Array[String] = []
	lines.append("Pre-mission: deployed %d/%s  -- then begin" % [
		session.deployed_count(), str(cap) if cap > 0 else "any"])
	lines.append("  verbs: deploy undeploy reposition | give job fit unfit kit | equip unequip wear remove_armor use toss | restart")
	lines.append("  open cells: %s" % _format_cells(session.deployment_cells()))
	# A count, not a list: a roster's stash runs to a dozen pieces, and `kit stash` lists them.
	var stash: Array[Item] = session.stash()
	lines.append("  stash: %d items -- kit stash" % stash.size())
	var reserve: Array[Unit] = session.reserve_units()
	if reserve.is_empty():
		lines.append("  reserve: (empty)")
		return "\n".join(lines)
	lines.append("  reserve:")
	for unit: Unit in reserve:
		# Not _unit_line: a reserve unit has no squad and no cell to report.
		var wep := _weapon_str(unit.get_equipped_weapon(), unit) if unit.has_equipped_weapon() else "(unarmed)"
		lines.append("    %s %s  hp%d/%d  %s" % [session.handle_for(unit), unit.get_unit_name(),
			unit.get_current_hp(), unit.get_max_hp(), wep])
	return "\n".join(lines)

# One unit's kit, or the stash (#46): every slot by its index, what is equipped (E) and worn (W), why
# this unit cannot use a piece, each weapon's mod spaces, and while the phase is open the jobs and mods
# this mission offers. The pre-mission card's own readings, so the two cannot disagree.
static func render_kit(session, holder: String) -> String:
	var mods := WeaponModCatalog.get_mods()   # one folder scan for the whole render
	var lines: Array[String] = []
	if holder == PlaySession.STASH:
		if not session.is_deploying():
			return "kit stash: the stash exists only in the pre-mission phase"
		var stash: Array[Item] = session.stash()
		# A list, not a slot grid, as on the screen: a piece leaving moves everything after it up one.
		lines.append("kit stash  (%d items -- positions shift when a piece leaves)" % stash.size())
		for i in stash.size():
			lines.append(_kit_row(session, str(i), stash[i], null, mods))
		return "\n".join(lines)
	var unit: Unit = session.unit_by_handle(holder)
	if unit == null:
		return "no unit '%s'" % holder
	var jobs: Array[String] = unit.unit_instance.jobs
	var head := "kit %s %s  MOV %d  WT %d  DEF %d   job: %s" % [holder, unit.get_unit_name(),
		unit.get_mov(), unit.get_weight(), unit.get_effective_def(),
		", ".join(jobs) if not jobs.is_empty() else "none"]
	if session.is_deploying() and unit.drawn_from_roster:
		var offered: Array[String] = session.offered_jobs_for(unit)
		head += "   offered jobs: %s" % (", ".join(offered) if not offered.is_empty() else "none")
	lines.append(head)
	for i in unit.inventory.size():
		lines.append(_kit_row(session, "slot %d" % i, unit.inventory[i], unit, mods))
	return "\n".join(lines)

static func _kit_row(session, label: String, item: Item, owner: Unit, mods: Dictionary) -> String:
	if item == null:
		return "  %s  -" % label
	var row := "  %s  %s" % [label, item.shown_name()]
	var equippable := item as EquippableData
	if owner != null and equippable != null:
		if item == owner.get_equipped_weapon():
			row += " (E)"
		elif item == owner.worn_armor:
			row += " (W)"
		var reason := equippable.can_equip_reason(owner)
		if reason != "":
			row += "  ! " + reason
	# The attack line only for what is equipped: _weapon_str reads the WIELDER's live attack views,
	# which belong to the equipped weapon whatever weapon is passed.
	if equippable != null and not equippable is ArmorData:
		row += "  " + _weapon_str(equippable, owner if owner != null and item == owner.get_equipped_weapon() else null)
	var weapon := item as WeaponInstance
	if weapon != null and weapon.space_count() > 0:
		row += "\n      spaces: " + _spaces_str(session, weapon, owner, mods)
		if session.is_deploying():
			var offered: Array[String] = []
			for key in (session.offered_mods_for(weapon) as Dictionary):
				offered.append(str(key))
			offered.sort()
			row += "   offered mods: %s" % (", ".join(offered) if not offered.is_empty() else "none")
	return row

# "1 [1/2: Line Sniper]  2 [0/1 off]" -- each space numbered as `fit` takes it, with its fill, its
# mods by the name `unfit` takes, and "off" past what this wielder's proficiency activates.
static func _spaces_str(session, weapon: WeaponInstance, owner: Unit, mods: Dictionary) -> String:
	var active := weapon.active_space_count(owner)
	var parts: Array[String] = []
	for i in range(weapon.space_count()):
		var names: Array[String] = []
		for mod: WeaponModData in weapon.space(i):
			var key: String = session.mod_key(mod, mods)
			names.append(key)
		parts.append("%d [%d/%d%s%s]" % [i + 1, weapon.used_capacity(i), weapon.template.mod_spaces[i],
			(": " + ", ".join(names)) if not names.is_empty() else "", " off" if i >= active else ""])
	return "  ".join(parts)

static func _mission_block(session) -> String:
	if session.scenario_data == null:
		return ""
	var lines: Array[String] = []
	var obj_names: Array[String] = []
	for obj in session.objectives():
		obj_names.append(MissionRules.Objective.keys()[obj])
	var title := "ROUT" if obj_names.is_empty() else " + ".join(obj_names)
	var limit_str := "no limit" if session.round_limit() <= 0 else "limit: %d rounds" % session.round_limit()
	lines.append("Mission: %s      (round %d, %s)" % [title, session.mission.rounds_elapsed + 1, limit_str])
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
	var progress := _progress_lines(session)
	if not progress.is_empty():
		lines.append("  Progress:")
		lines.append_array(progress)
	return "\n".join(lines)

# The briefing's own rows (#46): MissionStatusPanel.briefing is the ONE wording of a mission's
# progress, so a driver reads it in the words the player does. Its labels never enter a tree here,
# so each is freed the moment its text is read.
static func _progress_lines(session) -> Array[String]:
	var out: Array[String] = []
	var board: BoardContext = session._board()
	for row: MissionStatusPanel.Row in MissionStatusPanel.briefing(session.mission, board):
		out.append("    " + row.label.text)
		row.label.free()
	return out

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

# ---- affordances (#613) ----
#
# What a unit may do, in place of making the caller guess a cell and be refused. A move range is a
# REGION, so it prints grouped by row -- "y=13: 19-23" shows the shape of where you may go, which a
# flat list of forty (x,y) pairs does not, and costs about half the bytes. Deliberately NOT
# _format_cells, which stays the spelling for an ENUMERATION (the mission block's zone cells, read
# off one at a time); the two answer different questions and the split is declared rather than
# accidental.

static func render_legal_moves(session, handle: String) -> String:
	var res: Dictionary = session.legal_moves(handle)
	if not res.ok:
		return "> ERROR: " + str(res.error)
	var head := "moves %s from (%d,%d): %d cells" % [res.unit, res.from.x, res.from.y, res.cells.size()]
	var body := _cell_rows(res.cells)
	if not res.leashed.is_empty():
		# Named, because "too far to walk" and "your leader is too far" want different fixes.
		body += "\n  outside leader range (%d): %s" % [res.leashed.size(), _cell_rows(res.leashed).strip_edges()]
	if not res.stranding.is_empty():
		# A leader's: walkable, and refused because a squadmate could not follow there (#1069).
		body += "\n  would strand a squadmate (%d): %s" % [res.stranding.size(), _cell_rows(res.stranding).strip_edges()]
	return head + "\n" + body


static func render_legal_targets(session, handle: String, attack_name := "") -> String:
	var res: Dictionary = session.legal_targets(handle, attack_name)
	if not res.ok:
		return "> ERROR: " + str(res.error)
	if res.aims.is_empty():
		return "targets %s with %s from (%d,%d): none" % [res.unit, res.attack, res.from.x, res.from.y]
	var lines: Array[String] = ["targets %s with %s from (%d,%d): %d aims" % [res.unit, res.attack, res.from.x, res.from.y, res.aims.size()]]
	for aim: Dictionary in res.aims:
		lines.append("  (%d,%d) hits %s" % [aim.cell.x, aim.cell.y, ", ".join(aim.victims)])
	return "\n".join(lines)


# The turn's own state, on EVERY frame including the failures -- a refusal is exactly when the
# caller needs to know whose turn it is and what is already spent.
static func render_status(session) -> String:
	if session == null:
		return "[no board]"
	var st: Dictionary = session.status()
	var parts: Array[String] = ["turn=" + str(st.faction)]
	if st.get("pre_mission", false):
		parts.push_front("phase=PRE_MISSION")
	if int(st.active_squad) < 0:
		parts.append("active=none")
	else:
		parts.append("active=sq%d(%d queued)" % [int(st.active_squad), int(st.queued)])
	if not st.free.is_empty():
		parts.append("free=" + _squad_list(st.free))
	if not st.acted.is_empty():
		parts.append("acted=" + _squad_list(st.acted))
	return "[" + "  ".join(parts) + "]"


static func _squad_list(ids: Array) -> String:
	var parts: Array[String] = []
	for i in ids:
		parts.append("sq%d" % int(i))
	return ",".join(parts)


# Grouped by row, contiguous runs collapsed: "y=13: 19-23 25".
static func _cell_rows(cells: Array) -> String:
	var by_row := {}
	for c in cells:
		if not (c is Vector2i):
			continue
		var row: int = (c as Vector2i).y
		if not by_row.has(row):
			by_row[row] = [] as Array[int]
		by_row[row].append((c as Vector2i).x)
	var rows := by_row.keys()
	rows.sort()
	var lines: Array[String] = []
	for row in rows:
		var xs: Array = by_row[row]
		xs.sort()
		var runs: Array[String] = []
		var i := 0
		while i < xs.size():
			var j := i
			while j + 1 < xs.size() and int(xs[j + 1]) == int(xs[j]) + 1:
				j += 1
			runs.append(str(xs[i]) if j == i else "%d-%d" % [int(xs[i]), int(xs[j])])
			i = j + 1
		lines.append("  y=%d: %s" % [int(row), " ".join(runs)])
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
		wep = _weapon_str(unit.get_equipped_weapon(), unit)
	var state := "  [DOWNED]" if unit.is_downed() else ""
	# Whose watch the "!" cells belong to, and what it fires (#413). Named on the unit line rather
	# than in a second block: the footprint is on the board, this says who is behind it.
	if unit.watch != null and unit.watch.is_armed() and unit.watch.is_anchored(unit.movement.cell):
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
	# Show the GEOMETRY, not just the weapon_type enum — two "CHAINSWORD"s can be a wildly different
	# shape (an omnidirectional point attack at range vs a one-cell-deep cleave), which decides reach
	# AND who can counter. Hiding it once made a correct no-counter look like a bug.
	var s := "%s pow%d %s" % [WeaponData.WeaponType.keys()[w.weapon_type], main_power, _pattern_str(main)]
	if main != null and main.elemental_damage_type != Elemental.Element.NONE:
		s += "/" + Elemental.Element.keys()[main.elemental_damage_type]
	if main != null and main.can_ever_counter():
		s += "/ctr"
	if main != null and main.hits_allies:
		s += "/ff"   # friendly-fire: its blast hits allies in range too
	# Its live state in the family's own words (#663) -- a dry magazine or a sprung spear gates the next
	# order, and the ring shows the same count off the same answer (#1045).
	var status := inst.status_text()
	if status != "":
		s += " [%s]" % status
	# Every other attack BY NAME, off the unit's live views rather than the template's extras, so a
	# mod-granted attack lists and a watch-only one reads as a watch -- the names `attack` and
	# `overwatch` take (#615). A weapon counters with its main alone, so no alternate carries /ctr.
	if wielder != null:
		for attack: AttackData in wielder.get_weapon_secondary_attacks():
			s += "; " + _attack_str(inst, wielder, attack, false)
		for attack: AttackData in wielder.overwatch_attacks():
			s += "; watch: " + _attack_str(inst, wielder, attack, false)
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
		parts.append(_attack_str(rune, wielder, attack, attack.can_ever_counter()))
	if parts.is_empty():
		return head
	return head + "  " + "; ".join(parts)

# One attack by name, for a carving or a weapon's alternate: the name is what `attack` takes.
static func _attack_str(source: EquippableData, wielder: Unit, attack: AttackData, counters: bool) -> String:
	var s := "%s pow%d %s" % [attack.display_name, attack.power, _pattern_str(attack)]
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
	var swing := attack as WeaponAttackData
	if swing != null and swing.elemental_damage_type != Elemental.Element.NONE:
		s += "/" + Elemental.Element.keys()[swing.elemental_damage_type]
	# heals/deals_no_damage reinterpret the power printed above, so a line without them misreads.
	if attack.heals:
		s += "/heal"
	if attack.deals_no_damage:
		s += "/nodmg"
	if counters:
		s += "/ctr"
	if attack.hits_allies:
		s += "/ff"
	var reason := source.attack_block_reason(wielder, attack)
	if reason != "":
		s += " (blocked: %s)" % reason
	return s

# Range plus shape (#803, re-split at #808 -- the range is the attack's, the shape its own resource).
# A self-anchored attack is "Facing[...]"; an anchored one keeps the "Manhattan[min-max+]" spelling
# and adds its stamp only when it covers more than the aimed cell.
static func _pattern_str(a: AttackData) -> String:
	if a == null:
		return "melee[1]"
	var shape := a.attack_shape
	if a.is_directional():
		return "Facing[%s]" % (_stamp_str(shape) if shape != null else "@")
	var s := "Manhattan[%d-%d%s]" % [a.min_range, a.max_range, ("+" if a.max_and_a_half else "")]
	if shape != null:
		var covered := shape.tiles()
		if covered.size() != 1 or covered[0] != Vector2i.ZERO:
			s += " " + _stamp_str(shape)
	return s


# The stamp as rows, forward-most first, '/' between rows: '#' a covered cell, '.' a gap, and the
# centre '@' when covered or '+' when not, so the orientation reads. The box always includes the
# centre. A cleave is "###/.+.", a three-cell line "#/#/#/+", a cross ".#./#@#/.#.".
static func _stamp_str(p: AttackShape) -> String:
	var lo := Vector2i.ZERO
	var hi := Vector2i.ZERO
	var covered := p.tiles()
	for c in covered:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var rows: PackedStringArray = []
	for y in range(lo.y, hi.y + 1):
		var row := ""
		for x in range(lo.x, hi.x + 1):
			var c := Vector2i(x, y)
			var filled := covered.has(c)
			if c == Vector2i.ZERO:
				row += "@" if filled else "+"
			else:
				row += "#" if filled else "."
		rows.append(row)
	return "/".join(rows)
