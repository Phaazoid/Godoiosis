extends BaseAction
class_name RescueAction

# Pick a downed ally back up (#33): one of the SIDE_CHANNEL_ORDER verbs, so it runs after every move,
# attack and reaction in the pass has played back — which is why it meets its target where the pass
# LEAVES it rather than where the plan was authored. Whether a body may be picked up at all is
# RulesService.is_rescueable / adjacent_downed_allies, never here; this order carries it out.
#
# Since #116 a rescue also RELOCATES a body that cannot stand where it lies — deep water — onto the
# cell the resolve published beside the rescuer. See _haul_out.

const RESCUE_ICON := preload("res://Art/Icons/ActionIcons/Rescue.png")

var target: Unit   # the downed ally being picked up

func init(rescuer: Unit, downed_ally: Unit) -> void:
	actor = rescuer
	target = downed_ally
	action_type = BaseAction.ActionType.RESCUE

func execute() -> void:
	begin_execution()
	if target != null and is_instance_valid(target) and target.is_downed():
		if _still_adjacent():
			_haul_out()
			target.revive()
			# Spent the turn it's rescued — no actions; resets next turn. (Future: Will could buy
			# back movement/attack here.) A SAME-PASS rescue (#124) reaches here before the ejection
			# sweep has built the target's solo squad — target.squad is still the ACTING squad, and
			# marking it would spend the whole squad early — so OrderExecutor._process_downed_pending
			# marks that case after it ejects.
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

# A Law #2 BACKSTOP, not a rule (#126). The validator's stamp is the only other guard and it is
# computed before the pass runs, so a mid-pass shove is exactly what could separate the two between
# the stamp and the act. By the time the side channel runs, moves, attacks and counters have all
# landed, so both cells are final. If this ever fires, preview and execution disagreed — hence the
# warning rather than a silent no-op.
func _still_adjacent() -> bool:
	return GridUtils.manhattan_distance(actor.movement.cell, target.movement.cell) <= 1

# Drag the body clear (#116). It goes to the cell the RESOLVE published, never a freshly derived one:
# execution replays the plan (Law #2, and the BREAK repeal made that absolute), and the board has
# been drawing the body on that cell since the order was queued — deriving it again here is how the
# two would come to disagree. RulesService.rescue_landing is the rule; this is only its playback.
#
# A rescue from ordinary ground publishes NOTHING, so this is a no-op — which is every rescue before
# #116, unchanged rather than special-cased.
#
# It TELEPORTS, and that is a constraint rather than a preference: the headless Play API runs the
# REAL side-channel executes and does NOT await them ("synchronous pure logic (no animation)",
# play_session.execute), so an awaited slide would resume after that pass had already cleared the
# queue and ejected its downed. One behaviour in both, no per-type headless mirror. Giving the drag
# an animation beat of its own is presentation work and its own ticket.
func _haul_out() -> void:
	var haul := target.projected_rescue()
	if haul == GridUtils.NO_CELL or haul == target.movement.cell:
		return
	target.movement.set_cell(haul)

func actor_can_perform() -> bool:
	return actor.can_rescue_carry()   # verb lock (will-and-death.md limb model)

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
