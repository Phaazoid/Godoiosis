extends RefCounted
class_name ThreatField

# Which cells a faction's units could attack NEXT turn, and who could reach each -- the hover
# tier of the enemy-intent preview (#710). An upper bound per archetype: Hold stands where it is,
# Sentry opens only on an intruder inside its leash but ANSWERS from anywhere it can stand
# (_add_counter_reach), Rushdown takes its whole move range. Cohesion is genuinely ignored as of
# slice 4 -- it used to be applied, which under-stated every follower.
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
static func build(board: BoardContext, viewer: Team.Faction) -> ThreatField:
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
		var reach := _reach_of(unit, board, origins, zone)
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
static func _reach_of(unit: Unit, board: BoardContext, origins: Array[Vector2i], zone: Dictionary) -> Dictionary:
	var out := {}
	var attacks: Array[AttackData] = unit.get_selectable_attacks()
	if attacks.is_empty():
		attacks = [null]   # unarmed: bare-fist Manhattan-1, Reach's own fallback
	for origin in origins:
		for attack in attacks:
			if not unit.is_attack_fireable(attack):
				continue
			for cell in Reach.get_all_attack_cells_from(unit, origin, attack):
				if not zone.is_empty() and not zone.has(cell):
					continue   # a Sentry only answers an intruder inside its zone
				if not Reach.is_directional_attack(attack) and not Reach.vertical_aim_ok(attack, origin, cell, board):
					continue
				out[cell] = true
	_add_counter_reach(unit, board, origins, out)
	return out


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
# It deliberately does NOT ask is_standing_watch(), which can_counter does: an armed watch is a
# threat by a different mechanism this field cannot draw at all, so dropping the rim there would
# under-state exactly where the warning matters.
static func _add_counter_reach(unit: Unit, board: BoardContext, origins: Array[Vector2i], out: Dictionary) -> void:
	if not unit.attack_source_can_counter():
		return
	var counter := unit.get_counter_attack()
	for origin in origins:
		for cell in Reach.get_all_attack_cells_from(unit, origin, counter):
			if not Reach.is_directional_attack(counter) and not Reach.vertical_aim_ok(counter, origin, cell, board):
				continue
			out[cell] = true
