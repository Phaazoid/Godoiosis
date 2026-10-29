extends BaseAction
class_name RescueAction

# Pick a downed ally back up (#33): one of the SIDE_CHANNEL_ORDER verbs, so it runs after every move,
# attack and reaction in the pass has played back — which is why it meets its target where the pass
# LEAVES it rather than where the plan was authored. Whether a body may be picked up at all is
# RulesService.is_rescueable / adjacent_downed_allies, never here; this order carries it out.
#
# Since #116 a rescue also RELOCATES a body that cannot stand where it lies — deep water — onto a
# cell beside the rescuer, and the PLAYER chooses which (dev, 2026-08-26). See _haul_out.

const RESCUE_ICON := preload("res://Art/Icons/ActionIcons/Rescue.png")

var target: Unit   # the downed ally being picked up

# WHERE the body ends up, stamped at QUEUE time — CaptureAction's precedent, and for its reason: the
# resolver reads a frozen snapshot, so a re-planned move cannot quietly relocate a cell the player
# chose deliberately. It goes RED instead (SquadPlanValidator). For a body that can stand where it
# lies this IS its own cell, so an ordinary rescue moves nobody and needs no special case.
var haul_to: Vector2i = GridUtils.NO_CELL

# The resolver's verdict for THIS pass (#1349): is the rescuer still beside the body when the side
# channel reaches it, on the pass's threaded cells? A counter can shove either of them away after the
# plan was authored, and only the pass knows it. Rewritten every resolve, resolved_spent's rule; the
# validator reds the order on it (SquadPlanValidator._revalidate_rescue_targets).
var resolved_within_reach := true

# ...and does the chosen bank still take the body there (#1498)? Judged at the rescue's slot on the
# pass's own ground, so a bank the pass melted, or a lake it froze under the body, reds the order
# rather than being re-judged on the live board. Rewritten every resolve, read by the same validator.
var resolved_haul_lands := true

# REQUIRED, not defaulted: every caller states its own answer rather than inheriting a pick this
# class made for them — the menu passes what the player clicked, the AI and the Play API pass
# RulesService.rescue_landings(...)[0], which is the deterministic answer that used to be the rule.
func init(rescuer: Unit, downed_ally: Unit, landing: Vector2i) -> void:
	actor = rescuer
	target = downed_ally
	haul_to = landing
	action_type = BaseAction.ActionType.RESCUE

func aimed_at() -> Unit:
	return target   # the body, not the rescuer -- a pickup is read on who comes up

func execute() -> void:
	begin_execution()
	if target != null and is_instance_valid(target) and target.is_downed():
		if _still_adjacent():
			_haul_out()
			target.revive()
			# Spent the turn it's rescued — no actions; resets next turn. A SAME-PASS rescue (#124) reaches here before the ejection
			# sweep has built the target's solo squad — target.squad is still the ACTING squad, and
			# marking it would spend the whole squad early — so SquadManager.settle_downed marks that
			# case after the pass-end sweep ejects it.
			if target.squad != actor.squad:
				target.squad.has_acted = true
		else:
			push_warning("Rescue fizzled: %s is no longer beside %s" % [actor.get_unit_name(), target.get_unit_name()])
	elif target != null and is_instance_valid(target):
		# The queue previewed a pickup and there is nothing to pick up — the lethality prediction
		# was wrong, or two rescues raced one body. Either way preview and execution disagreed,
		# and since the BREAK repeal (#155, 2026-08-09) that is a bug by definition, never a
		# quiet fizzle.
		push_error("Rescue executed against a target that is not down: %s -> %s" % [actor.get_unit_name(), target.get_unit_name()])
	finish_execution()

# A Law #2 BACKSTOP, not a rule (#126). The resolve already asked the same question of the pass's own
# cells (resolved_within_reach, #1349) and a plan that fails it cannot execute. By the time the side
# channel runs, moves, attacks and counters have all landed, so both cells are final. If this ever
# fires, preview and execution disagreed — hence the warning rather than a silent no-op.
func _still_adjacent() -> bool:
	return within_reach(actor.movement.cell, target.movement.cell)

# THE reach rule for a pickup: beside the body, or on it. One spelling for execution, the resolve's
# stamp and the validator, each handing in the cells it trusts.
static func within_reach(rescuer_cell: Vector2i, body_cell: Vector2i) -> bool:
	return GridUtils.manhattan_distance(rescuer_cell, body_cell) <= 1

# Drag the body clear (#116). It goes to the cell STAMPED on this order — the one the player picked —
# never a freshly derived one: execution replays the plan (Law #2, and the BREAK repeal made that
# absolute), and deriving it again here is how the two would come to disagree. The resolve PUBLISHES
# this same cell so the board draws the body there before Execute; the stamp is the truth and the
# projection is its drawing, which is why there is nothing here to keep in sync.
#
# From ordinary ground the stamp IS the body's own cell, so this is a no-op — every rescue before
# #116, unchanged rather than special-cased.
#
# It TELEPORTS, and that is a constraint rather than a preference: the headless Play API runs the
# REAL side-channel executes and does NOT await them ("synchronous pure logic (no animation)",
# play_session.execute), so an awaited slide would resume after that pass had already cleared the
# queue and ejected its downed. One behaviour in both, no per-type headless mirror. Giving the drag
# an animation beat of its own is presentation work and its own ticket.
func _haul_out() -> void:
	if haul_to == GridUtils.NO_CELL or haul_to == target.movement.cell:
		return
	target.movement.set_cell(haul_to)

func actor_block_reason() -> String:
	if actor.can_rescue_carry():   # verb lock (will-and-death.md limb model)
		return ""
	return "%s is missing an arm and cannot carry anyone." % actor.get_unit_name()

func get_description() -> String:
	if target != null and is_instance_valid(target):
		return "%s rescues %s" % [actor.get_unit_name(), target.get_unit_name()]
	return "%s rescues" % actor.get_unit_name()

func get_target_texture() -> Texture2D:
	if target != null and is_instance_valid(target):
		return target.get_map_sprite_texture()
	return null

func get_action_icon() -> Texture2D:
	return RESCUE_ICON
