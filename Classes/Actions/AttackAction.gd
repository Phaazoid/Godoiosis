extends BaseAction
class_name AttackAction

var target: Unit
var resolved: ResolvedOutcome      # set by PlanResolver each pass (R8) — source of truth for damage
var attack_range: Array[Vector2i] = []
var origin_cell: Vector2i
var target_cell: Vector2i
var target_texture: Texture2D
var target_name := "Target"
var is_secondary_hit := false
var volley: Array[AttackAction] = []


var preview_sprites: Array[Node2D] = []

const ATTACK_ICON := preload("res://Art/Icons/FightActionIcon.png")
const DOWN_ICON := preload("res://Art/Icons/Down.png")
const KILL_ICON := preload("res://Art/Icons/DedIcon.png")

func init(attacker: Unit, origin: Vector2i, target_unit: Unit, target_location: Vector2i):
	actor = attacker
	target = target_unit
	target_cell = target_location
	origin_cell = origin
	action_type = BaseAction.ActionType.ATTACK

	if target_unit != null and is_instance_valid(target_unit):
		target_texture = target_unit.get_map_sprite_texture()
		target_name = target_unit.get_unit_name()

func execute():
	begin_execution()
	if actor == null or target == null:
		finish_execution()
		return

	if not is_instance_valid(actor) or not is_instance_valid(target):
		finish_execution()
		return

	if actor.is_queued_for_deletion() or target.is_queued_for_deletion():
		finish_execution()
		return
		
	if resolved != null and resolved.skipped:
		finish_execution()                          # counter-er went down/dead this pass — no lunge, no damage
		return

	var direction = GridUtils.cardinal_direction_between(actor.get_projected_destination(), target_cell)

	if not is_secondary_hit:
		await actor.visuals.play_attack_lunge(direction)

	# Pure playback of the resolved outcome (R3) — no recomputation. Damage and state
	# deltas both come from the resolver, so execution exactly matches the preview (Law #2).
	if resolved != null:
		target.combat.apply_damage(resolved.damage)
		for s in resolved.states_removed:
			target.remove_element_state(s)
		for s in resolved.states_added:
			target.add_element_state(s)

	finish_execution()

func get_action_icon() -> Texture2D:
	var lethal := _lethality_icon()
	return lethal if lethal != null else ATTACK_ICON

# The down/kill icon for this hit's predicted lethality, or null if it's non-lethal.
# Shared with CounterAttackAction so the rung -> icon mapping lives in one place
# (Law #2: a lethal counter must read the same as a lethal attack).
func _lethality_icon() -> Texture2D:
	if resolved != null:
		match resolved.lethality:
			ResolvedOutcome.Lethality.DOWNED:
				return DOWN_ICON
			ResolvedOutcome.Lethality.KILLED:
				return KILL_ICON
	return null

func get_target_texture() -> Texture2D:
	if target != null and is_instance_valid(target) and not target.is_queued_for_deletion():
		return target.get_map_sprite_texture()

	return target_texture  #OR UNIT SPRITE IF ATTACKING SOMEONE I GUESS

func get_description() -> String:
	return "%s -> %s" % [actor.get_unit_name(), get_target_name()]

func clear_preview_sprites():
	for sprite in preview_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free()

	preview_sprites.clear()

func get_target_name() -> String:
	if target != null and is_instance_valid(target) and not target.is_queued_for_deletion():
		return target.get_unit_name()

	return target_name

func add_preview_sprites(sprite: Node2D):
	preview_sprites.append(sprite)

static func create(attacker: Unit, origin: Vector2i, target: Unit, target_cell: Vector2i) -> AttackAction:
	var action := AttackAction.new()
	action.init(attacker, origin, target, target_cell)
	return action

static func create_volley(attacker: Unit, origin: Vector2i, aim_cell: Vector2i, victims: Array[Unit]) -> Array[AttackAction]:
	var volley_actions: Array[AttackAction] = []

	for victim in victims:
		var attack := AttackAction.create(attacker, origin, victim, aim_cell)
		attack.is_secondary_hit = not volley_actions.is_empty()
		volley_actions.append(attack)

	for attack in volley_actions:
		attack.volley = volley_actions

	return volley_actions

func get_outcome_summary() -> String:
	if resolved == null:
		return ""
	var parts: Array[String] = []
	parts.append("-%d" % resolved.damage)
	for p in resolved.popups:
		parts.append(p)
	for s in resolved.states_added:
		parts.append("+%s" % Elemental.State.keys()[s])
	for s in resolved.states_removed:
		parts.append("-%s" % Elemental.State.keys()[s])
	return "   ".join(parts)
