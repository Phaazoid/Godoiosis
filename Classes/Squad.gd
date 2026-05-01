extends Node
class_name Squad

var leader: Unit
var members: Array[Unit] = []

func set_leader(unit: Unit):
	leader = unit
	add_member(unit)
	
func get_leader() -> Unit:
	return leader

func get_members() -> Array:
	return members
	
func contains_unit(unit: Unit) -> bool:
	if members.has(unit):
		return true
	else:
		return false
	
func add_member(unit: Unit):
	if not members.has(unit):
		members.append(unit)
		unit.squad = self
		
func remove_member(unit: Unit):
	members.erase(unit)
	unit.reset_squad()
	
func reassign_leader():
	members.erase(leader)
	leader.reset_squad()
	var newLeader: Unit = members[0]
	for member in members:
		if member.get_base_stat("LDR") > newLeader.get_base_stat("LDR"):
			newLeader = member
	leader = newLeader 

	for member in members:
		if not validate_member_distance(member):
			remove_member(member)


func validate_member_distance(unit: Unit) -> bool:
	var dist = unit.movement.cell.distance_to(leader.movement.cell)
	if dist > get_max_range():
		return false
	else:
		return true
	
func get_max_range() -> int:
	return leader.get_base_stat("LDR") #This is a placeholder value for now

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
