extends BaseAction
class_name AttackAction

var target: Unit
var damage: int
var attack_range: Array[Vector2i] = []
var origin_cell: Vector2i
var target_cell: Vector2i
var target_texture: Texture2D
var target_name := "Target"
var is_secondary_hit := false
var volley: Array[AttackAction] = []


var preview_sprites: Array[Node2D] = []

const ATTACK_ICON := preload("res://Art/Icons/FightActionIcon.png")

func init(attacker: Unit, origin: Vector2i, target_unit: Unit, target_location: Vector2i, predicted_damage: int):
	actor = attacker
	target = target_unit
	target_cell = target_location
	damage = predicted_damage
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
		
	var direction = GridUtils.cardinal_direction_between(actor.get_projected_destination(), target_cell)	
	
	if not is_secondary_hit:
		await actor.visuals.play_attack_lunge(direction)
		
	target.combat.apply_damage(damage)
	
	finish_execution()
		
func get_action_icon() -> Texture2D:
	return ATTACK_ICON
	
func get_target_texture() -> Texture2D:
	if target != null and is_instance_valid(target) and not target.is_queued_for_deletion():
		return target.get_map_sprite_texture()

	return target_texture  #OR UNIT SPRITE IF ATTACKING SOMEONE I GUESS

func get_description() -> String:
	return "%s attacks" % actor.get_unit_name() + " it was super effective"

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
	var weapon := attacker.get_equipped_weapon()
	var damage := attacker.get_base_stat("STR")
	if weapon != null:
		damage = weapon.power + attacker.get_base_stat(weapon.scaling_stat)

	var action := AttackAction.new()
	action.init(attacker, origin, target, target_cell, damage)
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
