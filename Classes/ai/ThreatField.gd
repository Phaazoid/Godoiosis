extends RefCounted
class_name ThreatField

# Which cells a faction's units could attack NEXT turn, and who could reach each -- the hover
# tier of the enemy-intent preview (#710). An upper bound per archetype: Hold stands where it is,
# Sentry opens only on an intruder inside its leash but ANSWERS from anywhere it can stand
# (_add_counter_reach), Rushdown takes its whole move range. Cohesion is genuinely ignored as of
# slice 4 -- it used to be applied, which under-stated every follower.
#
# TWO MORE WAYS TO BE HIT since #1197, both of which this field used to paint safe: the lanes a
# watcher could arm, since a watch armed over somebody fires on the spot (#1003) and a watch attack
# is never in the fire view (#590); and where a SHOCK hit's current runs, through water and through
# anyone wet -- counting whoever the viewer's own PENDING plan will soak (dev, 2026-10-03).
# Declared, not drawn: a placed blast's splash and a payload's landing (#1207, on no shipped enemy);
# a wet unit HOVERING a dry cell (per cell, not per unit -- queue the move and it is drawn); and a
# soaking the enemy's own turn deals before its shock.
#
# WHICH BOARD it is built on is the CALLER's decision and both callers pick the same one: the
# projected board, every unit stood on its get_projected_destination(). game.threat_field() opens
# that snapshot itself, AIController.preview_turn holds one open across its whole planning pass.
# The two tiers answering about different boards is what let a threat LINE name a victim these
# tones said was out of reach (slice 4).

var cells: Dictionary = {}     # Vector2i -> Array[Unit] that can attack it
var by_unit: Dictionary = {}   # Unit -> Dictionary[Vector2i, true]
# ...and where each could STAND to do it -- the archetype's own envelope, which is the FE danger
# zone's other tone (#710 slice 3). It was always computed and thrown away; keeping it is what
# lets the board say "a body can be here" beside "a body can hit here", and it is honest by
# construction rather than by a second rule: a Hold unit yields its own cell because that is
# where its archetype fires from.
var move_by_unit: Dictionary = {}   # Unit -> Dictionary[Vector2i, true]


# Every unit hostile to `viewer`, so an ally's board reads the same field the player's does.
# `pending` is the hypo of the viewer's own pending plan (AIController.pending_hypo), which is the
# one place a soaking that has not happened yet exists -- the board only knows who is wet NOW.
static func build(board: BoardContext, viewer: Team.Faction, pending: Dictionary = {}) -> ThreatField:
	var field := ThreatField.new()
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
		var reach := _threat_of(unit, board, origins, zone, pending)
		field.by_unit[unit] = reach
		for cell in reach:
			if not field.cells.has(cell):
				field.cells[cell] = []
			field.cells[cell].append(unit)
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
# actually be ordered to and no others. No zone either: a leash is a fact about an AI archetype's
# aggression and says nothing about a unit you command.
static func reach_from(unit: Unit, board: BoardContext, origins: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if unit == null or not is_instance_valid(unit) or board == null or origins.is_empty():
		return out
	out.assign(_reach_of(unit, board, origins, {}).keys())
	return out


# A Sentry squad's painted zone; empty for every other archetype and for an unzoned sentry.
static func leash_of(squad: Squad, board: BoardContext) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if squad == null or _archetype_of(squad) != AIArchetype.Type.SENTRY:
		return out
	out.assign(SentryArchetype._zone_set(squad, board).keys())
	return out


static func _archetype_of(squad: Squad) -> AIArchetype.Type:
	if squad == null or squad.archetype == AIArchetype.Type.FACTION_DEFAULT:
		return AIArchetype.DEFAULT
	return squad.archetype


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
# Origins and zone arrive as parameters because build() already holds both -- looking them up
# again here would be a second derivation of the envelope the move tone draws.
#
# TWO PASSES since slice 4: what this unit would OPEN with (zone-clipped, below) and what it would
# ANSWER with (the counter, unclipped -- see _add_counter_reach).
#
# This is reach_from's walk too, and deliberately ONLY these two passes: the watch lanes and the
# current are predictions about an enemy turn (_threat_of), and your own red is a permission.
static func _reach_of(unit: Unit, board: BoardContext, origins: Array[Vector2i], zone: Dictionary) -> Dictionary:
	var out := {}
	for cells: Dictionary in _reach_by_attack(unit, board, origins, zone).values():
		out.merge(cells)
	return out


# What this unit could hit on its next turn -- _reach_of plus the two mechanisms #1197 found it
# painting safe. The lanes come first so the current is traced from them as well.
static func _threat_of(unit: Unit, board: BoardContext, origins: Array[Vector2i], zone: Dictionary,
		pending: Dictionary) -> Dictionary:
	var by_attack := _reach_by_attack(unit, board, origins, zone)
	_add_watch_reach(unit, board, origins, by_attack)
	var out := {}
	for attack: AttackData in by_attack:
		var cells: Dictionary = by_attack[attack]
		out.merge(cells)
		_add_arc(unit, attack, cells, board, pending, out)
	return out


# KEYED BY ATTACK, because the current depends on the element of the attack that made the hit -- a
# non-shock swing that reaches the lake must not light it (#1197). Nothing selectable (unarmed, an
# aura-dry rune) reaches nothing, as it can fire nothing (#1215).
static func _reach_by_attack(unit: Unit, board: BoardContext, origins: Array[Vector2i], zone: Dictionary) -> Dictionary:
	var by_attack := {}
	var attacks: Array[AttackData] = unit.get_selectable_attacks()
	for origin in origins:
		for attack in attacks:
			if not unit.is_attack_fireable(attack):
				continue
			var out: Dictionary = by_attack.get_or_add(attack, {})
			for cell in Reach.get_all_attack_cells_from(unit, origin, attack):
				if not zone.is_empty() and not zone.has(cell):
					continue   # a Sentry only answers an intruder inside its zone
				if not Reach.is_directional_attack(attack) and not Reach.vertical_aim_ok(attack, origin, cell, board):
					continue
				out[cell] = true
	_add_counter_reach(unit, board, origins, by_attack)
	return by_attack


# A COUNTER DOES NOT ASK ABOUT THE LEASH (#710 slice 4, dev: "technically they can attack one tile
# outside of their range if already there in counter situations"). The zone clip above is a fact
# about a Sentry's AGGRESSION -- it will not OPEN from outside its zone -- and because the clipped
# reach is a subset of the zone while the origins cover the zone, nearly the whole red layer ended
# up underneath the blue: a melee patrol showed 2 of 30 reach cells, a bow 5 of 36, so the outer
# silhouette of the threat was the MOVEMENT tone.
#
# This is the same walk unclipped, over the counter attack alone. It borrows SquadManager.can_counter's
# own gates rather than restating them, so a dry weapon and an unauthored AttackData.can_counter both
# fall out for free. It adds NOTHING for a non-sentry -- their counter is already inside
# get_selectable_attacks() -- which is measured rather than assumed.
#
# It deliberately does NOT ask is_standing_watch(), which can_counter does: a watch standing NOW
# fires during your own move, on the cells you walk through, which is the watch overlay's to draw
# rather than this field's -- so dropping the rim there would under-state exactly where the warning
# matters.
static func _add_counter_reach(unit: Unit, board: BoardContext, origins: Array[Vector2i], by_attack: Dictionary) -> void:
	if not unit.attack_source_can_counter():
		return
	var counter := unit.get_counter_attack()
	var out: Dictionary = by_attack.get_or_add(counter, {})
	for origin in origins:
		for cell in Reach.get_all_attack_cells_from(unit, origin, counter):
			if not Reach.is_directional_attack(counter) and not Reach.vertical_aim_ok(counter, origin, cell, board):
				continue
			out[cell] = true


# THE LANES A WATCHER COULD ARM (#1197). A watch armed over a cell somebody already stands in fires on
# the spot (#1003), so every lane this unit could arm next turn is somewhere it can hit -- and since
# #590 a watch attack is never in the fire view, so the pass above never saw one. The live case is the
# Carbine: Shot fires at exactly 2, the watch lane runs 1 to 4, so the watch is its point-blank shot.
#
# Asked of the ARCHETYPE'S declared list, so Rushdown (OVERWATCH is NEVER) marks none, and of
# AITactics' own two doors, so these are the lanes the builder could arm. From EVERY origin and NOT
# zone-clipped: the shot takes anyone in the lane, and a Sentry at its post aims at the nearest enemy
# wherever that enemy stands.
static func _add_watch_reach(unit: Unit, board: BoardContext, origins: Array[Vector2i], by_attack: Dictionary) -> void:
	if not AIArchetype.main_action_priority(_archetype_of(unit.squad)).has(BaseAction.ActionType.OVERWATCH):
		return
	var attack := AITactics.watch_attack_for(unit)
	if attack == null:
		return
	var out: Dictionary = by_attack.get_or_add(attack, {})
	for origin in origins:
		var lanes := AITactics.watch_lanes(unit, origin, attack, board)
		for dir in lanes:
			for cell: Vector2i in lanes[dir]:
				out[cell] = true


# WHERE THE CURRENT RUNS (#1197): Conduction's own flood, seeded with every cell this attack reaches.
# One flood over the union is the union of one flood per aim -- it is a bounded multi-source search --
# and the flood gates on SHOCK itself, so any other attack adds nothing. Not zone-clipped: a current
# does not respect a leash. `pending` is the viewer's pending hypo, so a unit their own plan soaks
# conducts as if it already were wet.
static func _add_arc(unit: Unit, attack: AttackData, cells: Dictionary, board: BoardContext,
		pending: Dictionary, out: Dictionary) -> void:
	var seeds: Array[Vector2i] = []
	seeds.assign(cells.keys())
	for cell in Conduction.arc_cells(unit, attack, seeds, board, pending):
		out[cell] = true
