extends RefCounted
class_name ThreatIntent

# ONE enemy's declared intention against ONE target, harvested from a previewed AI plan (#710 plan
# tier). `from` is where the player can see the attacker standing now; `to` is where the target will
# be when it is hit, which is its PROJECTED cell -- the two ends of the line the board draws.

var attacker: Unit
var target: Unit
var from: Vector2i
var to: Vector2i
var damage: int = 0
var fells: bool = false


static func make(attacker_unit: Unit, target_unit: Unit, from_cell: Vector2i, to_cell: Vector2i,
		hit: int, is_fatal: bool) -> ThreatIntent:
	var out := ThreatIntent.new()
	out.attacker = attacker_unit
	out.target = target_unit
	out.from = from_cell
	out.to = to_cell
	out.damage = hit
	out.fells = is_fatal
	return out


# Identity for the merge below -- one line per (attacker, target) however many volley rows,
# watch shots and counters the plan spreads across them.
func key() -> String:
	return "%d|%d" % [attacker.get_instance_id(), target.get_instance_id()]
