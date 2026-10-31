extends VBoxContainer
class_name AlchemyTool

# THE ALCHEMY PAGE (#1532): what Deep Alchemy is authored from, one leaf with three tabs.
#   Sources     what each ground, tile state, gas and unit state is MADE of (AlchemySources), edited live
#   Substances  each substance's formula, phase and whether it lends its parts (AlchemySubstances)
#   Reactions   every unit and ground reaction, whole (AlchemyReactions)
# The last two edit a COPY that Update writes back, the Attack Editor's idiom.
#
# The host owns nothing but the tabs. A tab coming into view re-reads what it shows, so a Substances
# Update reaches Sources' readout, and a Save As reaches the other tabs' pickers.

var sources: AlchemySources
var substances: AlchemySubstances
var reactions: AlchemyReactions
var _tabs: TabContainer


func _ready() -> void:
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.tab_focus_mode = Control.FOCUS_NONE   # only the mouse changes the page (#1184)
	add_child(_tabs)
	sources = AlchemySources.new()
	sources.name = "Sources"   # a TabContainer titles a tab by its child's name
	_tabs.add_child(sources)
	substances = AlchemySubstances.new()
	substances.name = "Substances"
	_tabs.add_child(substances)
	reactions = AlchemyReactions.new()
	reactions.name = "Reactions"
	_tabs.add_child(reactions)
	_tabs.tab_changed.connect(func(_tab: int) -> void: refresh_on_show())


func init(game) -> void:
	sources.init(game)
	substances.init(game)
	reactions.init(game)


func refresh_on_show() -> void:
	var shown := _tabs.get_current_tab_control()
	if shown != null:
		shown.call("refresh_on_show")


func show_tab(section: Control) -> void:
	_tabs.current_tab = _tabs.get_tab_idx_from_control(section)


# A save on any tab may have moved whether a queued cast fizzles or what a reaction does, and an enemy's
# reach with it: re-resolve the open plan and drop the enemy-range cache (#1360). Null game = no board.
static func redraw_plan(game) -> void:
	if game == null:
		return
	game.refresh_action_queue(game.squad_manager.active_squad)
	game.drop_threat_field()
