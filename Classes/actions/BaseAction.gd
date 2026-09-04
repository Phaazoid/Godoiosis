extends RefCounted
class_name BaseAction

# Base of every player order: actor + ActionType + validation state + the execute()
# lifecycle, plus the display hooks (icon/description/textures) the queue panel reads.

var actor: Unit
var action_type: ActionType

# Which orders were ONE player decision -- SquadManager.batching made durable, so a LIFO undo
# (#228) can pop a group move whole. Stamped only by queue_action, the Law #3 chokepoint, so
# 0 means "never went through it": the hold-position fillers, which are not orders anybody gave.
# Declared second representation (Law #4): AttackAction.volley answers the same question for
# RESOLVE-DERIVED actions inside a ResolvedPlan. In action_queue this is the authority -- a
# volley never enters the queue.
var batch_id := 0

var execution_complete := false
var is_valid := true
var validation_errors: Array[String] = []

enum ActionType {
	MOVE,
	ATTACK,
	COUNTER_ATTACK,
	RESCUE,
	RALLY,
	INTIMIDATE,
	RELOAD,
	REV,
	BURROW,
	CAPTURE,
	GUARD,
	OVERWATCH,
	TILE_HIT   # derived, never queued (#419) — the tile's own end-of-turn damage
}

# The action registry: a new action type is added to the enum + whichever lists apply.
# Menu gating, execution phases, queue-panel sections, and the Play API all key off
# these lists instead of keeping their own.

# Main actions are the mutually-exclusive headline orders — a unit gets at most ONE per
# turn, and it must come after any move. MOVE stays separate.
const MAIN_ACTION_TYPES: Array[ActionType] = [
	ActionType.ATTACK,
	ActionType.RESCUE,
	ActionType.RALLY,
	ActionType.INTIMIDATE,
	ActionType.RELOAD,
	ActionType.REV,
	ActionType.BURROW,
	ActionType.CAPTURE,
	ActionType.GUARD,
	ActionType.OVERWATCH
]

# Execution order of the side-channel tail — stored orders that bypass PlanResolver
# (resolver-backed attacks/counters run between MOVE and these). execute_orders, the
# queue panel's sections, and the Play API iterate THIS list.
const SIDE_CHANNEL_ORDER: Array[ActionType] = [
	ActionType.RESCUE,
	ActionType.RALLY,
	ActionType.INTIMIDATE,
	ActionType.RELOAD,
	ActionType.REV,
	ActionType.BURROW,
	ActionType.CAPTURE,
	# A watch armed this pass must arm AFTER every hit it was resolved against has played back
	# (#413) -- a same-pass shove combo can already have spent it, and re-arming here would hand
	# execution a live watch the queue previewed as fired. GuardAction's rule, one slot up.
	ActionType.OVERWATCH,
	# LAST in the tail deliberately (#414): a Guard armed this pass must arm AFTER every hit it was
	# resolved against has played back, or the ward it just absorbed for would be re-armed live.
	ActionType.GUARD
]

func is_main_action() -> bool:
	return MAIN_ACTION_TYPES.has(action_type)

# May the queue panel resequence the row this order draws (#412)? Queue order is the pass's clock —
# resolve_plan walks action_queue and nothing else — so a row standing for an order somebody GAVE
# is draggable, while a derived row (a counter) and a filler (hold position) are not. Asked of the
# order rather than of the row, because only the order knows which it is; Squad.reorder_by_actor
# asks the same question of the queue.
func is_reorderable() -> bool:
	return true

# Actor-intrinsic requirement for queueing this action; subclasses override (move ordering,
# verb locks, ability gates). SquadManager.queue_action is the sole enforcement point
# (Law #3). Plan-context checks (adjacency, occupancy) belong to plan validation instead.
func actor_can_perform() -> bool:
	return true

# Who this order is AIMED AT -- the unit it is done TO, rather than the one doing it. The default
# is the actor, which is the honest answer for a verb that acts on itself (move, rally, reload);
# Attack/Rescue/Intimidate/Guard override it with the `target` they each already store.
#
# Declared per Law #4: those four have held a private `var target: Unit` each, with no shared door,
# since they were written -- this is the door, not a fifth copy. It exists because BeatSheet has to
# ask the question of an order whose class it does not know (#520): a beat frames what is being
# done to whom, and only the order can say who that is.
func aimed_at() -> Unit:
	return actor

# The resolved outcome this order carries, or null — aimed_at's sibling door (#419). The queue row's
# HP readout asks here rather than testing for AttackAction.
func resolved_outcome() -> ResolvedOutcome:
	return null

func get_actor_texture() -> Texture2D:
	if actor == null or not is_instance_valid(actor):
		return null
	return actor.get_map_sprite_texture()

func get_action_icon() -> Texture2D:
	return null
	
func get_target_texture() -> Texture2D:
	return null
	
func get_description() -> String:
	return "Action"

func reset_validation():
	is_valid = true
	validation_errors.clear()
	
func add_validation_error(message: String):
	is_valid = false
	validation_errors.append(message)

func get_action_name() -> String:
	return ActionType.keys()[action_type]

func get_actor_modulate() -> Color:
	if actor == null:
		return Color.WHITE
		
	return actor.modulate
	
# Is this order REFUSED? The one predicate; get_ui_modulate below is derived from it, and #685's
# queue row draws its border off the same answer -- the tint and the border cannot disagree about
# whether a row is broken.
func is_refused() -> bool:
	return not is_valid

func get_ui_modulate() -> Color:
	if not is_refused():
		return Color.WHITE

	return Color(1, .25, .25, 1)
	
func begin_execution():
	execution_complete = false
	
func finish_execution():
	execution_complete = true

func execute():
	finish_execution()
	
func clear_validation_messages():
	validation_errors.clear()
