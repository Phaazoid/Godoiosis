extends RefCounted
class_name ThreatField

# Which cells a faction's units could attack NEXT turn, and who could reach each -- the hover
# tier of the enemy-intent preview (#710). An upper bound per archetype: Hold stands where it is,
# Sentry stands only inside its leash and hits anyone it can reach from there (#1377: its zone limits
# where it walks, not what it hits), Rushdown takes its whole move range. Cohesion is genuinely
# ignored as of slice 4 -- it used to be applied, which under-stated every follower.
#
# TWO MORE WAYS TO BE HIT since #1197, both of which this field used to paint safe: the lanes a
# watcher could arm, since a watch armed over somebody fires on the spot (#1003) and a watch attack
# is never in the fire view (#590); and where a SHOCK hit's current runs, through water and through
# anyone wet -- counting whoever the viewer's own PENDING plan will soak (dev, 2026-10-03).
# A placed blast's splash and a payload's landing ARE drawn, dilated as an upper bound (_add_splash,
# #1207). Declared, not drawn: a wet unit HOVERING a dry cell (per cell, not per unit -- queue the
# move and it is drawn); and a soaking the enemy's own turn deals before its shock.
#
# WHICH BOARD it is built on is the CALLER's decision. The danger view's two hosts (game.threat_field()
# and the Play API's `ranges`, #46) and AIController.preview_turn pick the same one: the projected
# board, every unit stood on its get_projected_destination(). for_viewer opens that snapshot for the
# two hosts, and preview_turn holds one open across its whole planning pass. The AI's own reads in
# AITactics build on whatever board their decision already stands on. The two tiers answering
# about different boards is what let a threat LINE name a victim these tones said was out of reach
# (slice 4).

var cells: Dictionary = {}     # Vector2i -> Array[Unit] that can attack it
var by_unit: Dictionary = {}   # Unit -> Dictionary[Vector2i, true]
# ...and where each could STAND to do it -- the archetype's own envelope, which is the FE danger
# zone's other tone (#710 slice 3). It was always computed and thrown away; keeping it is what
# lets the board say "a body can be here" beside "a body can hit here", and it is honest by
# construction rather than by a second rule: a Hold unit yields its own cell because that is
# where its archetype fires from.
var move_by_unit: Dictionary = {}   # Unit -> Dictionary[Vector2i, true]
var traces := 0   # sight traces this build ran (#1344) -- the cost regression check counts these


# ONE BUILD'S SIGHT-TRACE VERDICTS (#1344): attack -> origin -> {cell: bool}. A verdict reads the attack,
# the two cells and the board, and no unit, so every unit with that attack shares it. It lives exactly
# one build, the dev's pick over a cache carried between builds: that would outlive an attack or a tile
# edited in the dev tools. If line of sight ever reads a unit, this can no longer be shared.
class TraceMemo:
	var verdicts := {}
	var count := 0

	func at(attack: AttackData, origin: Vector2i) -> Dictionary:
		var by_origin: Dictionary = verdicts.get_or_add(attack, {})
		return by_origin.get_or_add(origin, {})

	func aim_ok(known: Dictionary, attack: AttackData, origin: Vector2i, cell: Vector2i, board: BoardContext) -> bool:
		if not known.has(cell):
			known[cell] = Reach.vertical_aim_ok(attack, origin, cell, board)
			count += 1
		return known[cell]


# Every unit hostile to `viewer`, so an ally's board reads the same field the player's does.
# `pending` is the hypo of the viewer's own pending plan (AIController.pending_hypo), which is the
# one place a soaking that has not happened yet exists -- the board only knows who is wet NOW.
static func build(board: BoardContext, viewer: Team.Faction, pending: Dictionary = {}) -> ThreatField:
	var field := ThreatField.new()
	var memo := TraceMemo.new()
	for unit in board.units:
		if not is_instance_valid(unit) or not unit.is_active():
			continue
		if not Team.is_enemy(viewer, unit.get_faction()):
			continue
		var zone: Dictionary = {}
		if _archetype_of(unit.squad) == AIArchetype.Type.SENTRY:
			zone = SentryArchetype._zone_set(unit.squad, board)
		# Origins are computed ONCE and passed down rather than re-derived inside the reach walk:
		# they are the move tone as well as the reach's input, and two derivations of one envelope
		# is the duplicate the board would eventually disagree with itself about.
		var origins := _origins_of(unit, board, zone)
		var moves := {}
		for cell in origins:
			moves[cell] = true
		field.move_by_unit[unit] = moves
		var reach := _threat_of(unit, board, origins, pending, memo)
		field.by_unit[unit] = reach
		for cell in reach:
			if not field.cells.has(cell):
				field.cells[cell] = []
			field.cells[cell].append(unit)
	field.traces = memo.count
	return field


# THE ONE BUILD both hosts call (#46), so the game and the Play API cannot read different boards.
# The pending soak is resolved first, on the live board as every resolve is; then every unit stands
# on its projected cell for the build and is put back. `with_pending` is false mid-pass, where a
# resolve would count the hits that already landed twice.
static func for_viewer(squad_manager: SquadManager, viewer: Team.Faction, with_pending: bool) -> ThreatField:
	var pending: Dictionary = {}
	if with_pending:
		pending = AIController.pending_hypo(AIController.viewer_plans(viewer, squad_manager))
	var saved := AIController.stand_on_projected(squad_manager)
	var field := build(squad_manager.board_source.call() as BoardContext, viewer, pending)
	AIController.restore_cells(saved)
	return field


func attackers_of(cell: Vector2i) -> Array[Unit]:
	var out: Array[Unit] = []
	out.assign(cells.get(cell, []))
	return out


func reach_of(unit: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(by_unit.get(unit, {}).keys())
	return out


func move_of(unit: Unit) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(move_by_unit.get(unit, {}).keys())
	return out


func all_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.assign(cells.keys())
	return out


# The union over the units named, or over EVERY enemy when the list is empty -- one function for
# the toggle's whole-board answer and the pinned/hovered subset, so the two cannot drift.
func move_cells_of(units: Array[Unit]) -> Array[Vector2i]:
	return _union(move_by_unit, units)


func reach_cells_of(units: Array[Unit]) -> Array[Vector2i]:
	return _union(by_unit, units)


func _union(store: Dictionary, units: Array[Unit]) -> Array[Vector2i]:
	var seen := {}
	var subjects: Array = units if not units.is_empty() else store.keys()
	for unit: Unit in subjects:
		for cell in store.get(unit, {}):
			seen[cell] = true
	var out: Array[Vector2i] = []
	out.assign(seen.keys())
	return out


# The same reach walk, for ONE unit, over origins the CALLER names (#1066). The player's own red
# range rides this rather than a bespoke walk: it is the identical question -- which cells could this
# body hit from anywhere in that set -- and re-deriving it beside build() is how the two would
# eventually disagree about a counter rim or a vertical-aim refusal.
#
# The origins are a parameter and that is the whole point of the door. _origins_of unions `reachable`
# with `squad_unreachable` on purpose (slice 4: cohesion clamps a follower to where its leader stands
# NOW, while the enemy turn moves the leader first), which is right for a PREDICTION about an enemy
# and wrong for a PERMISSION about your own unit -- your red must grow from the cells you may
# actually be ordered to and no others.
static func reach_from(unit: Unit, board: BoardContext, origins: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if unit == null or not is_instance_valid(unit) or board == null or origins.is_empty():
		return out
	out.assign(_reach_of(unit, board, origins, TraceMemo.new()).keys())
	return out


# A Sentry squad's painted zone; empty for every other archetype and for an unzoned sentry.
static func leash_of(squad: Squad, board: BoardContext) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if squad == null or _archetype_of(squad) != AIArchetype.Type.SENTRY:
		return out
	out.assign(SentryArchetype._zone_set(squad, board).keys())
	return out


static func _archetype_of(squad: Squad) -> AIArchetype.Type:
	if squad == null:
		return AIArchetype.DEFAULT
	return AIArchetype.effective(squad.archetype)


# The cells this unit may fire FROM. Same envelope the archetype walks: Hold never moves, a Sentry
# with no zone falls through to Hold, a zoned Sentry keeps to zone + post.
static func _origins_of(unit: Unit, board: BoardContext, zone: Dictionary) -> Array[Vector2i]:
	var origins: Array[Vector2i] = [unit.movement.cell]
	var archetype := _archetype_of(unit.squad)
	if archetype == AIArchetype.Type.HOLD or (archetype == AIArchetype.Type.SENTRY and zone.is_empty()):
		return origins
	var post: Vector2i = unit.movement.cell
	if archetype == AIArchetype.Type.SENTRY:
		var leader: Unit = unit.squad.get_leader()
		post = unit.squad.home_cell if unit.squad.home_cell != Squad.NO_HOME else leader.movement.cell
	# BOTH buckets, never `reachable` alone (#710 slice 4). compute_move_range moves every cell
	# outside the member's cohesion bubble into squad_unreachable, measured against where its leader
	# stands NOW -- but on the enemy's own turn the leader moves FIRST, and GroupMoveSolver measures
	# each member against the leader's DESTINATION. So the clamped half is exactly the ground a
	# follower walks, and a field whose whole contract is an UPPER BOUND was under-stating it. The
	# pair is the standable footprint followable_destinations already unions for the same reason.
	# A leader is unaffected either way: that filter is gated on `not unit.is_leader()`.
	var walk: Dictionary = RulesService.compute_move_range(unit, board)
	var standable: Dictionary = walk["reachable"]
	for cell: Vector2i in (walk["squad_unreachable"] as Dictionary):
		standable[cell] = true
	for cell in standable:
		if archetype == AIArchetype.Type.SENTRY and not zone.has(cell) and cell != post:
			continue
		if not origins.has(cell):
			origins.append(cell)
	return origins


# Every cell any fireable attack reaches from any origin, under the same two filters the AI's own
# candidate builder applies (AITactics._attack_candidates): fireable, and vertically aimable.
# Origins arrive as a parameter because build() already holds them -- looking them up again here
# would be a second derivation of the envelope the move tone draws. Nothing is clipped to a zone:
# a Sentry's leash is its origins (#1377).
#
# TWO PASSES since slice 4: what this unit would OPEN with (below) and what it would ANSWER with
# (the counter -- see _add_counter_reach).
#
# This is reach_from's walk too, and deliberately ONLY these two passes: the watch lanes and the
# current are predictions about an enemy turn (_threat_of), and your own red is a permission.
static func _reach_of(unit: Unit, board: BoardContext, origins: Array[Vector2i], memo: TraceMemo) -> Dictionary:
	var out := {}
	for cells: Dictionary in _reach_by_attack(unit, board, origins, memo).values():
		out.merge(cells)
	return out


# What this unit could hit on its next turn -- _reach_of plus the two mechanisms #1197 found it
# painting safe. The lanes come first so the current is traced from them as well.
static func _threat_of(unit: Unit, board: BoardContext, origins: Array[Vector2i], pending: Dictionary,
		memo: TraceMemo) -> Dictionary:
	var by_attack := _reach_by_attack(unit, board, origins, memo)
	_add_watch_reach(unit, board, origins, by_attack)
	_add_splash(by_attack)
	var out := {}
	for attack: AttackData in by_attack:
		var cells: Dictionary = by_attack[attack]
		out.merge(cells)
		_add_arc(unit, attack, cells, board, pending, out)
	return out


# KEYED BY ATTACK, because the current depends on the element of the attack that made the hit -- a
# non-shock swing that reaches the lake must not light it (#1197). Nothing selectable (unarmed, an
# aura-dry rune) reaches nothing, as it can fire nothing (#1215).
#
# A UNION, so a cell one origin already reaches is never traced again (#1344): most of a big board's
# cost was the same cell re-traced from every origin in range.
static func _reach_by_attack(unit: Unit, board: BoardContext, origins: Array[Vector2i], memo: TraceMemo) -> Dictionary:
	var by_attack := {}
	var attacks: Array[AttackData] = []
	for attack in unit.get_selectable_attacks():
		if unit.is_attack_fireable(attack):   # reads the kit, never the origin
			attacks.append(attack)
	var fizzled := {}   # this unit's, shared with the rim: a fizzle reads the caster
	for origin in origins:
		for attack in attacks:
			# A carving that fizzles from this origin threatens nothing from it -- the AI's own candidate
			# filter (AITactics._attack_candidates), asked of the same cell, so the field stays a superset
			# of what it could aim.
			if _fizzles(unit, attack, origin, board, fizzled):
				continue
			var out: Dictionary = by_attack.get_or_add(attack, {})
			var known := memo.at(attack, origin)
			for cell in Reach.get_all_attack_cells_from(unit, origin, attack):
				if out.has(cell):
					continue
				if not Reach.is_directional_attack(attack) and not memo.aim_ok(known, attack, origin, cell, board):
					continue
				out[cell] = true
	_add_counter_reach(unit, board, origins, by_attack, memo, fizzled)
	return by_attack


# Asked once per attack and origin within a unit's walk: the counter rim re-asks the opening pass's.
static func _fizzles(unit: Unit, attack: AttackData, origin: Vector2i, board: BoardContext, asked: Dictionary) -> bool:
	var by_origin: Dictionary = asked.get_or_add(attack, {})
	if not by_origin.has(origin):
		by_origin[origin] = CellSubstances.fizzle_reason(attack, origin, board, unit) != ""
	return by_origin[origin]


# THE COUNTER, walked on its own (#710 slice 4). It was born to answer the zone clip the pass above
# used to apply to a Sentry -- a patrol painted almost pure blue, 2 of 30 reach cells -- and #1377
# deleted that clip, so for a unit whose counter is among its selectable attacks this now adds
# nothing (measured in tests/ai/test_threat_field.gd rather than assumed). It was kept for the one
# counter that view left out, a watch main, which never counters since #1440; whether it now adds
# anything at all is that suite's measurement to make, not yet made.
#
# It borrows SquadManager.can_counter's own gates rather than restating them, so a dry weapon and an
# unauthored AttackData.can_counter both fall out for free.
#
# It deliberately does NOT ask is_standing_watch(), which can_counter does: a watch standing NOW
# fires during your own move, on the cells you walk through, which is the watch overlay's to draw
# rather than this field's -- so dropping the rim there would under-state exactly where the warning
# matters.
static func _add_counter_reach(unit: Unit, board: BoardContext, origins: Array[Vector2i], by_attack: Dictionary,
		memo: TraceMemo, fizzled: Dictionary) -> void:
	if not unit.attack_source_can_counter():
		return
	var counter := unit.get_counter_attack()
	var out: Dictionary = by_attack.get_or_add(counter, {})
	for origin in origins:
		if _fizzles(unit, counter, origin, board, fizzled):
			continue   # a counter that would fizzle there lands nothing (PlanResolver.resolve_counters)
		var known := memo.at(counter, origin)
		for cell in Reach.get_all_attack_cells_from(unit, origin, counter):
			if out.has(cell):
				continue
			if not Reach.is_directional_attack(counter) and not memo.aim_ok(known, counter, origin, cell, board):
				continue
			out[cell] = true


# THE LANES A WATCHER COULD ARM (#1197). A watch armed over a cell somebody already stands in fires on
# the spot (#1003), so every lane this unit could arm next turn is somewhere it can hit -- and since
# #590 a watch attack is never in the fire view, so the pass above never saw one. The live case is the
# Carbine: Shot fires at exactly 2, the watch lane runs 1 to 4, so the watch is its point-blank shot.
#
# Asked of the ARCHETYPE'S declared list, so Rushdown (OVERWATCH is NEVER) marks none, and of
# AITactics' own two doors, so these are the lanes the builder could arm. From EVERY origin: the shot
# takes anyone in the lane, and a Sentry at its post aims at the nearest enemy wherever that enemy
# stands. Every watch the builder may try, not only its first (#1433). The lanes skip the builder's
# aim gate (Reach.can_aim_at), so they can only over-state what it arms.
static func _add_watch_reach(unit: Unit, board: BoardContext, origins: Array[Vector2i], by_attack: Dictionary) -> void:
	if not AIArchetype.main_action_priority(_archetype_of(unit.squad)).has(BaseAction.ActionType.OVERWATCH):
		return
	for attack in AITactics.watch_attacks_for(unit):
		var out: Dictionary = by_attack.get_or_add(attack, {})
		for origin in origins:
			if CellSubstances.fizzle_reason(attack, origin, board, unit) != "":
				continue   # AITactics._try_overwatch arms no watch that would fizzle there
			var lanes := AITactics.watch_lanes(unit, origin, attack, board)
			for dir in lanes:
				for cell: Vector2i in lanes[dir]:
					out[cell] = true


# WHERE A PLACED BLAST AND ITS PAYLOADS LAND (#1207). The ring is where an attack may be AIMED; a
# shaped attack placed at range also strikes the cells around each aim, and a payload goes off
# wherever the hit leaves its victim. The AI aims BESIDE a target since #1220, and this field must
# stay a superset of every aim it can take (AIController._squad_can_reach_anyone reads a false as a
# proof), so each ring is dilated as an upper bound: by the shape as drawn (a placed shape never
# turns), then for payloads by the parent's shove and each payload's shape under every facing.
static func _add_splash(by_attack: Dictionary) -> void:
	for attack: AttackData in by_attack.keys():
		if attack == null:
			continue
		var cells: Dictionary = by_attack[attack]
		if not attack.is_directional() and attack.attack_shape != null:
			cells.merge(_dilated(cells, attack.attack_shape.place(Vector2i.ZERO, AttackShape.FORWARD)))
		if attack.payload == null:
			continue
		var landed := cells
		if attack.knockback > 0:
			landed = _dilated(landed, GridUtils.cells_within_manhattan_range(Vector2i.ZERO, attack.knockback))
		for payload in attack.payload_chain():
			landed = _dilated(landed, _any_facing(payload))
			cells.merge(landed)


static func _dilated(cells: Dictionary, offsets: Array[Vector2i]) -> Dictionary:
	var out := {}
	for cell: Vector2i in cells:
		for offset in offsets:
			out[cell + offset] = true
	return out


# A payload's footprint about the cell it went off on, under every facing it could be turned to.
static func _any_facing(payload: AttackData) -> Array[Vector2i]:
	var out: Array[Vector2i] = [Vector2i.ZERO]
	if payload.attack_shape == null:
		return out
	for dir in GridUtils.CARDINAL_DIRECTIONS:
		for offset in payload.attack_shape.place(Vector2i.ZERO, dir):
			if not out.has(offset):
				out.append(offset)
	return out


# WHERE THE CURRENT RUNS (#1197): Conduction's own flood, seeded with every cell this attack reaches.
# One flood over the union is the union of one flood per aim -- it is a bounded multi-source search --
# and the flood gates on SHOCK itself, so any other attack adds nothing. `pending` is the viewer's
# pending hypo, so a unit their own plan soaks
# conducts as if it already were wet.
static func _add_arc(unit: Unit, attack: AttackData, cells: Dictionary, board: BoardContext,
		pending: Dictionary, out: Dictionary) -> void:
	var seeds: Array[Vector2i] = []
	seeds.assign(cells.keys())
	for cell in Conduction.arc_cells(unit, attack, seeds, board, pending):
		out[cell] = true
