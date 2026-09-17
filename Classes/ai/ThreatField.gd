extends RefCounted
class_name ThreatField

# Which cells a faction's units could attack NEXT turn, and who could reach each -- the hover
# tier of the enemy-intent preview (#710). An upper bound per archetype: Hold stands where it is,
# Sentry stays on its leash and only answers an intruder inside its zone, Rushdown takes its whole
# move range. Cohesion is ignored and occupancy is read live, exactly as FE's danger zone does.

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
	var reachable: Dictionary = RulesService.compute_move_range(unit, board)["reachable"]
	for cell in reachable:
		if archetype == AIArchetype.Type.SENTRY and not zone.has(cell) and cell != post:
			continue
		if not origins.has(cell):
			origins.append(cell)
	return origins


# Every cell any fireable attack reaches from any origin, under the same two filters the AI's own
# candidate builder applies (AITactics._attack_candidates): fireable, and vertically aimable.
# Origins and zone arrive as parameters because build() already holds both -- looking them up
# again here would be a second derivation of the envelope the move tone draws.
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
	return out
