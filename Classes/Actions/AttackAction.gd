extends BaseAction
class_name AttackAction

var target: Unit
var damage: int
var attack_range: Array[Vector2i] = []
var target_cell: Vector2i

var preview_sprites: Array[Node2D] = []

const ATTACK_ICON := preload("res://Art/Icons/FightActionIcon.png")

func init(attacker: Unit, target_unit: Unit, target_location: Vector2i, predicted_damage: int):
	actor = attacker
	target = target_unit
	target_cell = target_location
	damage = predicted_damage
	action_type = BaseAction.ActionType.ATTACK
	
func execute():
	if actor == null or target == null:
		return
		
	target.combat.apply_damage(actor.get_base_stat("STR"))
	
func get_action_icon() -> Texture2D:
	return ATTACK_ICON
	
func get_target_texture() -> Texture2D:
	return target.get_map_sprite_texture() #OR UNIT SPRITE IF ATTACKING SOMEONE I GUESS
	
func get_description() -> String:
	return "%s attacks" % actor.get_unit_name() + " it was super effective"

func clear_preview_sprites():
	for sprite in preview_sprites:
		if is_instance_valid(sprite):
			sprite.queue_free
		
	preview_sprites.clear()
	
func add_preview_sprites(sprite: Node2D):
	preview_sprites.append(sprite)
