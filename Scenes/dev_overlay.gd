extends CanvasLayer

@onready var faction_group := ButtonGroup.new()

var valid = false
var stat_MHP 
var stat_STR 
var stat_SPD 
var stat_WIL 
var unit_name
var posX = 0
var posY = 0
var faction: Team.Faction
var error_message = ""
var game: Node = null
var unitInfo: Dictionary = {}
var data : UnitData 
var mousepos: Vector2i

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	game = get_parent()
	assert(game != null)
	stat_MHP = $Panel/MarginContainer/HBoxContainer/SpawnSection/StatInput/MHPSpinBox.value
	stat_STR = $Panel/MarginContainer/HBoxContainer/SpawnSection/StatInput/STRSpinBox.value
	stat_SPD = $Panel/MarginContainer/HBoxContainer/SpawnSection/StatInput/SPDSpinBox.value
	stat_WIL = $Panel/MarginContainer/HBoxContainer/SpawnSection/StatInput/WILSpinBox.value
	unit_name = $Panel/MarginContainer/HBoxContainer/SpawnSection/UnitNameInput.text
	faction = Team.Faction.PLAYER
	
	$Panel/MarginContainer/HBoxContainer/SpawnSection/FactionCheckBoxes/PlayerCheckBox.button_group = faction_group
	$Panel/MarginContainer/HBoxContainer/SpawnSection/FactionCheckBoxes/EnemyCheckBox.button_group = faction_group
	$Panel/MarginContainer/HBoxContainer/SpawnSection/FactionCheckBoxes/OtherCheckBox.button_group = faction_group
	

	
		
func _validate():
	set_selected_faction()
	valid = true
			
	if unit_name == "":
		unit_name = "Error_Soldier"
		
	if stat_MHP < 0 or stat_MHP > 100:
		error_message += "and invalid MHP "
		valid = false
	if stat_SPD < 0 or stat_SPD > 100:
		error_message += "and invalid SPD "
		valid = false
	if stat_STR < 0 or stat_STR > 100:
		error_message += "and invalid STR "
		valid = false
	if stat_WIL < 0 or stat_WIL > 100:
		error_message += "and invalid WIL "
		valid = false
	#Enums don't default to null but their first value when unassigned so this should never trigger
	if faction == null:
		error_message += "and invalid faction "
		valid = false

	#TODO Portrait Check when portrait selection implemented, or perhaps just assign one


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func set_mousepos(pos: Vector2i):
	mousepos = pos
	posX = pos.x
	posY = pos.y

func _on_wil_spin_box_value_changed(value: float) -> void:
	stat_WIL = value

func _on_spd_spin_box_value_changed(value: float) -> void:
	stat_SPD = value

func _on_str_spin_box_value_changed(value: float) -> void:
	stat_STR = value

func _on_mhp_spin_box_value_changed(value: float) -> void:
	stat_MHP = value


func set_selected_faction():
	#0 = Player
	#1 = Enemy
	#2 = Other
	var pressed = faction_group.get_pressed_button()
	
	match pressed.name:
		"PlayerCheckBox":
			faction = Team.Faction.PLAYER
		"EnemyCheckBox":
			faction = Team.Faction.ENEMY
		"OtherCheckBox": 
			faction = Team.Faction.OTHER
			
func build_unit_dictionary():
	#TODO add portrait stuff to unitdata here
	data = UnitData.new()
	data.display_name = unit_name
	data.base_stats = {
		"MHP" : stat_MHP,
		"STR" : stat_STR,
		"SPD" : stat_SPD,
		"WIL" : stat_WIL
	}
	unitInfo["data"] = data
	unitInfo["pos"] = Vector2i(posX, posY)
	unitInfo["faction"] = faction



func _unhandled_input(event) -> void:
	if self.visible:
		if event.is_action_pressed("dev_spawn_unit"):
			_validate()
			if valid:
				build_unit_dictionary()
				var new_unit = UnitFactory.create_unit(unitInfo)
				if new_unit == null:
					push_error("Unit factory returned null")
					return
			#TODO move this out to a UnitSpawner or Game manager - sanatize unit spawning.  
			#TODO Also make sure unit can only spawn on viable tiles, right now units can stack and spawn on rocks, etc
			#TODO And this also has to be in Game, so we can check to see if we're in DEV move.  Currently spawns in regular mode.  
				game.spawn_unit_properly(new_unit, Vector2i(posX, posY))
			else: 
				print(error_message)
				error_message = ""


func _on_unit_name_input_text_changed(new_text: String) -> void:
	unit_name = new_text
