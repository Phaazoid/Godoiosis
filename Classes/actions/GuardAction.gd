extends BaseAction
class_name GuardAction

# Guard (#414, docs/design/standing-reactions.md): a main action that makes the actor a bodyguard —
# the next damaging hit that would land on `target` lands on the actor instead, at the actor's own
# DEF, armour and cell, plus their brace bonus. The substitution itself is entirely the resolver's
# (PlanResolver._guard_for / _apply_guards); this order only ARMS the ward.
#
# A basic action everyone has (the doc's working model, and the one fork it left deliberately open),
# so actor_can_perform is the inherited `true`; what kit grants is the brace bonus, not the verb.

# Cut from ProjectUtumno_full row 38 col 30 (dev pick, 2026-08-21), downscaled 32 -> 16 with NEAREST
# — the exact 2:1 every other ActionIcon is sized at, and a smooth filter mushes art this small.
# The only place this action's art comes from.
const GUARD_ICON := preload("res://Art/Icons/ActionIcons/GuardIcon.png")

var target: Unit         # the ward — the unit being bodyguarded
var guard_range: int = 1 # stamped at declare (Law #2 provenance, CaptureAction's shape)

# The resolver's verdict for THIS pass, rewritten every resolve: did this Guard already absorb a hit
# from an attack queued AFTER its own slot? Side-channel verbs execute after the attack phase, so
# without it a Guard that ate your own splash would arm fresh and unspent — the queue would have
# previewed a spent Guard and execution would hand back a live one (Law #2). Same shape as
# AttackAction.resolved: the resolver writes it, execution only plays it back.
var resolved_spent := false

func init(guarding_unit: Unit, warded_unit: Unit) -> void:
	actor = guarding_unit
	target = warded_unit
	guard_range = guarding_unit.get_guard_range()
	action_type = BaseAction.ActionType.GUARD

func aimed_at() -> Unit:
	return target   # the ward -- what a Guard is about is who it covers

func execute() -> void:
	begin_execution()
	if target != null and is_instance_valid(target) and not target.is_queued_for_deletion():
		actor.arm_guard(target, guard_range, resolved_spent)
	finish_execution()

func get_description() -> String:
	if target == null or not is_instance_valid(target):
		return "%s guards" % actor.get_unit_name()
	if resolved_spent:
		# The queue says so rather than quietly arming a used Guard: the player's own splash is
		# what spent it, and sequencing around that is the agency the arms-at-its-slot rule buys.
		return "%s guards %s (spent this pass)" % [actor.get_unit_name(), target.get_unit_name()]
	return "%s guards %s" % [actor.get_unit_name(), target.get_unit_name()]

func get_target_texture() -> Texture2D:
	if target != null and is_instance_valid(target):
		return target.get_map_sprite_texture()
	return null

func get_action_icon() -> Texture2D:
	return GUARD_ICON
