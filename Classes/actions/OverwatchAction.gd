extends BaseAction
class_name OverwatchAction

# Overwatch (#413, docs/design/standing-reactions.md): a main action that AIMS an attack instead of
# firing it. The aimed cells become a standing watch, and the first ACTIVE enemy to ENTER one during
# another faction's phase takes the shot. Declared through the normal targeting flow — same aim,
# same facing, same overlay — so "tile or line" is not a new choice: a directional pattern watches
# its whole spread, a point-targeted attack watches the aimed cell.
#
# This order only ARMS the watch. The trigger, the shot and everything it costs the crosser belong
# to the resolver (PlanResolver / SquadManager.resolve_plan), exactly as GuardAction only arms a
# ward and the substitution is entirely the resolver's.

# Placeholder art: the board cursor's corner brackets, standing in until the dev picks a cut. The
# doc asks for crosshair/flash-shaped threat marks with their own vocabulary; that is one pick, not
# a guess to make here.
const OVERWATCH_ICON := preload("res://Art/Icons/BoardIcons/CursorIcon.png")

var target_cell: Vector2i         # the aim, frozen at declare (Law #2 provenance)
var fired_attack: AttackData = null   # what will fire, stamped at declare — never re-picked

# The resolver's verdict for THIS pass, rewritten every resolve: did this watch already fire at
# something a LATER order in the same queue shoved into it? Side-channel verbs execute after the
# attack phase, so without it a watch that ate its own shove-combo would arm fresh and unspent —
# the queue would have previewed a spent watch and execution would hand back a live one (Law #2).
# GuardAction.resolved_spent's twin, for the same reason and by the same R8 pattern.
var resolved_spent := false


func init(watching_unit: Unit, aim_cell: Vector2i, attack: AttackData) -> void:
	actor = watching_unit
	target_cell = aim_cell
	fired_attack = attack
	action_type = BaseAction.ActionType.OVERWATCH


# THE footprint rule, and the only spelling of it. The resolver asks it from the actor's PROJECTED
# cell each pass so re-planning the walk that precedes the declaration moves the preview honestly;
# execution asks it from where the actor actually ended up. Same function, two positional sources —
# GuardWard.in_range's shape, and the reason no footprint is stored on this order.
func watched_cells_from(origin: Vector2i) -> Array[Vector2i]:
	return Reach.get_affected_cells_from(actor, origin, target_cell, fired_attack)


func execute() -> void:
	begin_execution()
	var origin := actor.movement.cell
	actor.arm_watch(origin, target_cell, watched_cells_from(origin), fired_attack, resolved_spent)
	finish_execution()


func get_description() -> String:
	var attack_name := fired_attack.display_name if fired_attack != null else "watch"
	if resolved_spent:
		# The queue says so rather than quietly arming a used watch: the player's own shove is what
		# spent it, and sequencing around that is the agency the arms-at-its-slot rule buys.
		return "%s watches with %s (fired this pass)" % [actor.get_unit_name(), attack_name]
	return "%s watches %s with %s" % [actor.get_unit_name(), str(target_cell), attack_name]


func get_action_icon() -> Texture2D:
	return OVERWATCH_ICON
