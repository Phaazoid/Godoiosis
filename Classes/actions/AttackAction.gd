extends BaseAction
class_name AttackAction

# A queued (or resolved) attack order — one instance per victim in an AoE volley (see
# create_volley), all sharing a `volley` array so a re-aim or a downed victim is derived, never
# stored twice. Carries the aim (origin/target_cell) and the chosen attack to fire (`fired_attack`
# — a carving or a specific WeaponAttackData, #72); PlanResolver fills in `resolved` each pass
# (R8) as the sole source of damage truth (Law #2 — the queue previews exactly what plays back).
# CounterAttackAction extends this for the reactive case.

var target: Unit
var resolved: ResolvedOutcome      # set by PlanResolver each pass (R8) — source of truth for damage
var attack_range: Array[Vector2i] = []
var origin_cell: Vector2i
var target_cell: Vector2i
var target_texture: Texture2D
var target_name := "Target"
var is_secondary_hit := false
var volley: Array[AttackAction] = []
 # the specific attack chosen to fire — a carving (rune) or a WeaponAttackData; null = the weapon's main attack 
 # (#30, generalized #72)
var fired_attack: AttackData = null  

var preview_sprites: Array[Node2D] = []

const ATTACK_ICON := preload("res://Art/Icons/ActionIcons/FightActionIcon.png")
const DOWN_ICON := preload("res://Art/Icons/StateIcons/Down.png")
const KILL_ICON := preload("res://Art/Icons/StateIcons/DedIcon.png")
const MAIM_ICON := preload("res://Art/Icons/StateIcons/DownMaim.png")
const CRISIS_ICON := preload("res://Art/Icons/ActionIcons/CrisisIcon.png")

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
		# Knockback (#84): shove the target to the resolved landing cell. set_cell is instant (a
		# tweened slide is polish, TODO); the resolver already stopped it at any wall/unit/edge.
		if resolved.knockback_applied and is_instance_valid(target):
			target.movement.set_cell(resolved.knockback_to)
	# Readiness spend (#73): the ACT of firing consumes it, hit or whiff — lead volley member
	# only (mirrors the is_secondary_hit gate PlanResolver uses for cell-effect deposits).
	# Counters always fire main (#72), which never consumes, so this never fires on a counter.
	if not is_secondary_hit and fired_attack is WeaponAttackData:
		var weapon := actor.get_equipped_weapon() as WeaponInstance
		if weapon != null:
			weapon.consume_readiness_for(fired_attack as WeaponAttackData)

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
			ResolvedOutcome.Lethality.CRISIS:
				return CRISIS_ICON
	return null

func get_target_texture() -> Texture2D:
	if target != null and is_instance_valid(target) and not target.is_queued_for_deletion():
		return target.get_map_sprite_texture()

	return target_texture  #OR UNIT SPRITE IF ATTACKING SOMEONE I GUESS

func actor_can_perform() -> bool:
	# Verb lock (will-and-death.md limb model) + readiness gate (#73) — an unfireable pick
	# (a sprung Spring, or Stab too if the family locks the whole weapon) can't be queued even
	# bypassing the menu (Law #3; the menu merely hides/disables what this refuses).
	return actor.can_wield_equipped() and actor.is_attack_fireable(fired_attack)

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

# Declare-time factory (Law #2): stamps the actor's current pick so player and AI declare
# sites can't diverge -- the rune-fists bug (#78) was exactly a forgotten stamp. Bare create()
# stays for derived actions, where the resolver COPIES the stored aim's stamp instead.
static func declare(attacker: Unit, origin: Vector2i, aim_cell: Vector2i) -> AttackAction:
	var action := AttackAction.create(attacker, origin, null, aim_cell)
	action.fired_attack = attacker.get_fired_attack()
	return action

static func create_volley(attacker: Unit, origin: Vector2i, aim_cell: Vector2i, victims: Array[Unit], fired_attack: AttackData = null) -> Array[AttackAction]:
	var volley_actions: Array[AttackAction] = []

	for victim in victims:
		var attack := AttackAction.create(attacker, origin, victim, aim_cell)
		attack.fired_attack = fired_attack
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
	# HP context: "before -> after". A CRISIS row breaks the subtraction arithmetic (the
	# target stands back up at revive HP), so it gets its own honest form.
	if resolved.lethality == ResolvedOutcome.Lethality.CRISIS:
		parts.append("(CRISIS -> up at %d, surged)" % resolved.target_hp_after)
	else:
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
