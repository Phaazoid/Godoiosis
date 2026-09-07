# Can the player READ the pre-mission menus under either palette (#814)?
#
# WHY THIS IS NOT A CASE IN test_queue_palette.gd. That suite pins PAIRS -- this role against that
# ground -- and a pair test is structurally blind to the failure that produced this ticket: a label
# with NO font_color override at all. There is no colour to look up, so nothing can be compared, and
# five of the twelve reported sites were exactly that. The only way to see them is to build the real
# screen and ask each control what it will actually DRAW with.
#
# So this walks the live tree, and both halves of every comparison are read off the running node:
#   * the INK is Control.get_theme_color, i.e. override -> theme -> engine default, which is the one
#     read that cannot tell a styled label from an unstyled one apart by accident.
#   * the GROUND is COMPOSITED down the ancestor chain, because a stylebox may be translucent --
#     ModalCard's frame is the engine theme's panel at alpha 0.6, and parchment's own SECTION_BG is
#     opaque exactly where slate's is 0.7. Reading only the nearest panel gets both wrong.
#
# ONE CASE, MANY FINDINGS, deliberately: a failing case truncates the rest of its suite file in
# gdUnit4, and a contrast sweep whose first finding hides the other six is a sweep you have to run
# seven times. Every failure is collected and reported together, named by node path.
#
# It runs against PARCHMENT *and* slate. The element cases in test_queue_palette are parchment-only
# because their ink is derived and no knob may be constrained; every colour here is an authored
# chrome const, so a floor over both palettes constrains nothing the dev drags.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const SCRATCH := "user://__pre_mission_814.tres"

const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const ROW_WIDTH := 10
const ZONE_CELLS := 6

# test_queue_palette's floor and its metric, restated rather than imported: that suite is a plain
# Object with no seam to borrow from, and a second spelling of one subtraction is cheaper than the
# coupling. If the two ever disagree the pair cases and these will disagree loudly.
const CONTRAST_FLOOR := 0.25

# What the screens are drawn OVER. PreMissionScreen's own backdrop is opaque, so it is the bottom of
# every composite on that surface; the fitting card adds ModalCard's 70% black on top of it.
const SCREEN_BASE := Color(0.06, 0.06, 0.09)

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController


func before_test() -> void:
	PlayerSettings.reset_for_test()
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	mc = game.mission_controller
	sm = game.scenario_manager
	mc._close_mission_select()
	sm.clear_board()
	game.game_state = game.GameState.IDLE
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	PlayerSettings.reset_for_test()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))


# --- the fixture, borrowed from test_pre_mission_screen ------------------------------------------

func _a_roster() -> String:
	var names: Array[String] = RosterCatalog.saved_rosters()
	return "" if names.is_empty() else names[0]


func _author(roster: String, cap: int) -> String:
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	sm.current_roster = roster
	sm.current_deployment_cap = cap
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT]
	mc.set_objectives(objectives)
	var scenario := sm.capture_scenario("pre_mission_814", true)
	assert_int(ResourceSaver.save(scenario, SCRATCH)).is_equal(OK)
	return SCRATCH


func _screen() -> PreMissionScreen:
	for child in game.ui_layer.get_children():
		if child is PreMissionScreen:
			return child
	return null


# --- the metric ----------------------------------------------------------------------------------

static func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


static func _contrast(ink: Color, ground: Color) -> float:
	return absf(_luma(ink) - _luma(ground))


static func _over(top: Color, under: Color) -> Color:
	var a := top.a
	return Color(top.r * a + under.r * (1.0 - a),
			top.g * a + under.g * (1.0 - a),
			top.b * a + under.b * (1.0 - a), 1.0)


# The bg a stylebox contributes, or null-ish when it paints none. A StyleBoxEmpty and a flat button
# both draw nothing, which is what makes the ancestor chain rather than the node itself the answer.
static func _box_bg(box: StyleBox) -> Variant:
	var flat := box as StyleBoxFlat
	return null if flat == null else flat.bg_color


# Everything painted UNDER this control, composited outermost-first. A translucent panel over a
# translucent panel is the case a nearest-ancestor read gets wrong, and both palettes ship one.
static func _ground_under(node: Control, base: Color) -> Color:
	var chain: Array[Control] = []
	var walk: Node = node.get_parent()
	while walk != null:
		var as_control := walk as Control
		if as_control != null:
			chain.append(as_control)
		walk = walk.get_parent()
	chain.reverse()

	var ground := base
	for host: Control in chain:
		if not host.has_theme_stylebox_override("panel") and not (host is PanelContainer or host is Panel):
			continue
		var bg: Variant = _box_bg(host.get_theme_stylebox("panel"))
		if bg != null:
			ground = _over(bg, ground)
	return ground


# A BUTTON USUALLY STANDS ON ITS OWN CHROME, and that is why the exit buttons pass while the labels
# beside them failed: the engine's own dark button box travels with its own light font colour. A
# FLAT button paints nothing, though -- the card's job picker is one -- so it falls through to the
# chain like a label, which is exactly where it was found to be cream on cream.
#
# ITS OWN BOX IS COMPOSITED, NEVER SUBSTITUTED, and getting that wrong is what this suite's first run
# reported: the engine's button box is dark at alpha 0.6, so treating it as the whole ground made
# every Deploy button read as white-on-cream and the real answer is the blend of the two.
static func _ground_for(node: Control, base: Color) -> Color:
	var under := _ground_under(node, base)
	var button := node as Button
	if button == null or button.flat:
		return under
	var bg: Variant = _box_bg(button.get_theme_stylebox("normal"))
	return under if bg == null else _over(bg, under)


# Which font colours a control will actually draw. A Button resolves hover independently, which is
# the half #774's fix needed and the half a normal-state-only override still gets wrong.
static func _ink_states(node: Control) -> Array:
	if node is Button:
		return [["font_color", node.get_theme_color("font_color")],
				["font_hover_color", node.get_theme_color("font_hover_color")]]
	return [["font_color", node.get_theme_color("font_color")]]


static func _readable_text(node: Control) -> String:
	if node is Label:
		return (node as Label).text
	if node is Button:
		return (node as Button).text
	return ""


static func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


# Every finding under one root, as sentences. Empty means everything on it can be read.
func _findings(root: Node, base: Color, label: String) -> Array[String]:
	var out: Array[String] = []
	for node in _walk(root):
		var control := node as Control
		if control == null:
			continue
		if _readable_text(control).strip_edges() == "":
			continue   # a spacer, or an empty inventory slot's placeholder
		var ground := _ground_for(control, base)
		for pair: Array in _ink_states(control):
			var ink: Color = pair[1]
			var gap := _contrast(ink, ground)
			if gap > CONTRAST_FLOOR:
				continue
			out.append("%s: %s \"%s\" draws %s at luma %.2f on a ground at %.2f (gap %.2f)" % [
				label, control.get_path(), _readable_text(control).substr(0, 24),
				pair[0], _luma(ink), _luma(ground), gap])
	return out


# --- the law -------------------------------------------------------------------------------------

# The whole reported bug, as a property. Every palette, every label and button the two pre-mission
# surfaces build, against whatever is really painted behind it.
func test_every_word_on_the_pre_mission_menus_can_be_read_in_both_palettes() -> void:
	var roster := _a_roster()
	if roster == "":
		push_warning("no rosters are shipped, so the screens cannot be exercised")
		return

	for palette: int in [PlayerSettings.QueuePalette.DEFAULT, PlayerSettings.QueuePalette.PARCHMENT]:
		PlayerSettings.set_choice(PlayerSettings.Setting.QUEUE_PALETTE, palette)
		# The boxes are cached per palette, and the cache outlives a test -- a case that skipped this
		# would measure whichever palette ran first and agree with itself perfectly.
		QueueStyle._cache.clear()

		mc.begin_mission(_author(roster, 2))
		await await_idle_frame()
		var screen := _screen()
		assert_object(screen).override_failure_message(
			"the pre-mission phase did not open its screen, so nothing was measured").is_not_null()

		var found: Array[String] = _findings(screen, SCREEN_BASE, "palette %d" % palette)

		# The fitting card stacks over the screen, and carries BOTH grounds -- the engine's dark
		# frame plus parchment's cream zones -- so it is where a role picked by weight alone shows.
		var weapon := _a_stashed_weapon()
		if weapon != null:
			var card := ModFittingCard.open(game, weapon, null)
			await await_idle_frame()
			found.append_array(_findings(card, _over(Color(0, 0, 0, 0.7), SCREEN_BASE),
					"palette %d / fitting card" % palette))
			card.queue_free()
			await await_idle_frame()

		assert_array(found).override_failure_message(
			"unreadable text on the pre-mission menus:\n  %s" % "\n  ".join(found)).is_empty()

		sm.clear_board()
		await await_idle_frame()


func _a_stashed_weapon() -> WeaponInstance:
	for item: Item in mc.loadout().stash:
		var weapon := item as WeaponInstance
		if weapon != null:
			return weapon
	for unit: Unit in mc.roster_units():
		for item: Item in unit.inventory:
			var weapon := item as WeaponInstance
			if weapon != null:
				return weapon
	return null
