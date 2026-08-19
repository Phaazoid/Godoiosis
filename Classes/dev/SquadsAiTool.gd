extends VBoxContainer
class_name SquadsAiTool

# The Squads & AI page (#382): who is standing on this board and how it behaves -- per-faction AI
# toggles (#150) and per-squad archetype/zone rows. Carved out of the Scenario tab when the window
# went to a scope tree: these were the only sections about the board's OCCUPANTS rather than what
# the mission declares, one subject at two scopes.
#
# Everything here is board content a load replaces, so DevOverlay refreshes this page on show and
# on the header's file_changed -- squads also form and rename outside this page (Unit Editor,
# actual play).

const NO_ZONE_LABEL := "(no zone)"

@onready var ai_toggle_list: VBoxContainer = %AIToggleList
@onready var squad_list: VBoxContainer = %SquadList

var game
var _header: ScenarioHeader
var _ai_boxes: Dictionary[Team.Faction, CheckBox] = {}


func init(p_game, header: ScenarioHeader) -> void:
	game = p_game
	_header = header
	_build_ai_toggles()
	refresh_squads()


func refresh_on_show() -> void:
	refresh_squads()
	refresh_ai_toggles()


func _mark() -> void:
	if _header != null:
		_header.mark_modified()


func _build_ai_toggles() -> void:
	for child in ai_toggle_list.get_children():
		child.queue_free()
	_ai_boxes.clear()
	for faction in Team.all_factions():
		var box := CheckBox.new()
		box.text = Team.faction_name(faction)
		box.button_pressed = game.ai_controller.is_faction_ai_enabled(faction)
		box.tooltip_text = "AI-controlled at this faction's turn"
		box.toggled.connect(func(pressed):
			game.ai_controller.set_faction_ai_enabled(faction, pressed)
			_mark())
		ai_toggle_list.add_child(box)
		_ai_boxes[faction] = box


# The flags are board content since #150, so a load changes them without this page's involvement.
# set_pressed_no_signal, never button_pressed: the latter fires `toggled`, and a refresh that
# writes back into AIController would author state instead of displaying it.
func refresh_ai_toggles() -> void:
	for faction in _ai_boxes:
		var enabled: bool = game.ai_controller.is_faction_ai_enabled(faction)
		_ai_boxes[faction].set_pressed_no_signal(enabled)


func refresh_squads() -> void:
	for child in squad_list.get_children():
		child.queue_free()

	var squads_by_faction := {}
	for squad in game.squad_manager.squads:
		if not is_instance_valid(squad) or squad.leader == null:
			continue
		var faction = squad.leader.get_faction()
		if not squads_by_faction.has(faction):
			squads_by_faction[faction] = []
		squads_by_faction[faction].append(squad)

	for faction in Team.all_factions():
		if not squads_by_faction.has(faction):
			continue
		DevWidgets.add_label(squad_list, Team.faction_name(faction))
		for squad in squads_by_faction[faction]:
			squad_list.add_child(_build_squad_row(squad))


func _build_squad_row(squad: Squad) -> HBoxContainer:
	var row := HBoxContainer.new()

	var label := Label.new()
	label.text = squad.squad_name if squad.squad_name != "" else "(unnamed, leader: %s)" % squad.leader.get_unit_name()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var archetype := OptionButton.new()
	var type_names := AIArchetype.Type.keys()
	for i in type_names.size():
		archetype.add_item(type_names[i])
	archetype.select(squad.archetype)
	archetype.item_selected.connect(func(idx):
		squad.archetype = AIArchetype.Type.values()[idx]
		_mark())
	row.add_child(archetype)

	var zone := OptionButton.new()
	var zone_options: Array[String] = [NO_ZONE_LABEL]
	zone_options.append_array(game.zone_manager.zone_names())
	# A squad can point at a zone that's since been fully erased -- keep the stale name
	# selectable so the binding stays visible instead of silently reading as "(no zone)".
	if squad.zone_name != "" and not zone_options.has(squad.zone_name):
		zone_options.append(squad.zone_name)
	var current := squad.zone_name if squad.zone_name != "" else NO_ZONE_LABEL
	for i in zone_options.size():
		zone.add_item(zone_options[i])
		if zone_options[i] == current:
			zone.select(i)
	zone.item_selected.connect(func(idx):
		squad.zone_name = "" if idx == 0 else zone_options[idx]
		_mark())
	row.add_child(zone)

	return row
