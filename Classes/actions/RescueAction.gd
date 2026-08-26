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

# REQUIRED, not defaulted: every caller states its own answer rather than inheriting a pick this
# class made for them — the menu passes what the player clicked, the AI and the Play API pass
# RulesService.rescue_landings(...)[0], which is the deterministic answer that used to be the rule.
func init(rescuer: Unit, downed_ally: Unit, landing: Vector2i) -> void:
	actor = rescuer
	target = downed_ally
	haul_to = landing
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
