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
const MAIM_ICON := preload("res://Art/Icons/DownMaim.png")

func init(attacker: Unit, origin: Vector2i, target_unit: Unit, target_location: Vector2i):
	actor = attacker
	target = target_unit
	target_cell = target_location
	origin_cell = origin
	action_type = BaseAction.ActionType.ATTACK

	if target_unit != null and is_instance_valid(target_unit):
		target_texture = target_unit.get_map_sprite_texture()
		target_name = target_unit.get_unit_name()
	else:
		target_name = "Tile %s" % target_location   # cell-targeted attack (#47)

func execute():
	begin_execution()
	# Actor must be live to swing. (target may be null = a cell-targeted attack, #47.)
	if actor == null or not is_instance_valid(actor) or actor.is_queued_for_deletion():
		finish_execution()
		return

	# A UNIT attack whose target vanished this pass — nothing to hit, no lunge (unchanged).
	# A null target is intentional (a cell attack) and falls through to the lunge.
	if target != null and (not is_instance_valid(target) or target.is_queued_for_deletion()):
		finish_execution()
		return

	if resolved != null and resolved.skipped:
		finish_execution()                          # counter-er went down/dead this pass — no lunge, no damage
		return

	var direction = GridUtils.cardinal_direction_between(actor.get_projected_destination(), target_cell)

	if not is_secondary_hit:
		await actor.visuals.play_attack_lunge(direction)

	# Pure playback of the resolved outcome (R3) — no recomputation. A cell attack (target
	# null) has no unit consequence; it still plays out and (later, #50) deposits terrain effects.
	if target != null and resolved != null:
		target.combat.apply_damage(resolved.damage)
		for s in resolved.states_removed:
			target.remove_element_state(s)
		for s in resolved.states_added:
			target.add_element_state(s)

	finish_execution()

func get_action_icon() -> Texture2D:
	var lethal := _lethality_icon()
	return lethal if lethal != null else ATTACK_ICON

func _lethality_icon() -> Texture2D:
	if resolved != null:
		match resolved.lethality:
			ResolvedOutcome.Lethality.DOWNED:
				return DOWN_ICON
			ResolvedOutcome.Lethality.MAIMED:
				return MAIM_ICON
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
	if resolved == null or target == null:   # cell attack (#47) — no unit outcome to summarize
		return ""
	var parts: Array[String] = []
	parts.append("-%d" % resolved.damage)
	# HP context: "before -> after". Attacks only subtract HP, so before = after + damage
	# (R4 threads target_hp_after). Shows whether the hit actually matters, not just its size.
	var hp_before: int = resolved.target_hp_after + resolved.damage
	parts.append("(%d->%d)" % [hp_before, resolved.target_hp_after])
	match resolved.lethality:
		ResolvedOutcome.Lethality.DOWNED:
			parts.append("DOWNS")
		ResolvedOutcome.Lethality.MAIMED:
			parts.append("MAIMS (no Will)")
		ResolvedOutcome.Lethality.KILLED:
			parts.append("KILLS")
	for p in resolved.popups:
		parts.append(p)
	for s in resolved.states_added:
		parts.append("+%s" % Elemental.State.keys()[s])
	for s in resolved.states_removed:
		parts.append("-%s" % Elemental.State.keys()[s])
	return "   ".join(parts)
