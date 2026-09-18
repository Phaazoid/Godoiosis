# The rune detail card (#1019), on the real screen it opens from.
#
# WHAT A HEADLESS SUITE CANNOT SEE, said out loud: nothing here proves a hollow tick reads as an
# outline at 116px, that a halo is visible beside its neighbours, or that the cost bars echo the ring's
# own marks. Those are the dev's to play, and AuraRing's own suite says the same thing about the
# marks themselves.
#
# WHAT IS PINNED IS THE WIRE -- that picking another carving moves what is DRAWN. That is precisely
# the assertion #1017 found missing one card over, where every case asserted on `card._attack` and so
# proved a variable had changed while saying nothing about whether a pixel had. A second detail card
# built without it would be the same bug waiting on the same kind of near-identical pair.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const SCRATCH := "user://__rune_card_1019.tres"
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)
const ROW_WIDTH := 10
const ZONE_CELLS := 6

const FIRE := Elemental.Element.FIRE
const WATER := Elemental.Element.WATER
const EARTH := Elemental.Element.EARTH
const AIR := Elemental.Element.AIR

var _main: Node
var game: Node2D
var sm: ScenarioManager
var mc: MissionController
var _squads: SquadManager


func before_test() -> void:
	_main = (load("res://Scenes/Main.tscn") as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	mc = game.mission_controller
	sm = game.scenario_manager
	mc._close_mission_select()
	sm.clear_board()
	game.game_state = game.GameState.IDLE
	_squads = H.make_manager(self)
	await await_idle_frame()


func after_test() -> void:
	await DialogFixtures.end_all_dialog(self)
	sm.clear_board()
	await await_idle_frame()
	get_tree().root.remove_child(_main)
	_main.free()
	if FileAccess.file_exists(SCRATCH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SCRATCH))
	# #473's orphan workaround: a frame for queue_free to land, or the runner reports a non-zero
	# verdict with zero failures.
	await await_idle_frame()


# --- fixtures ---------------------------------------------------------------------------------------

func _alchemist(aura: Dictionary[Elemental.Element, int], cell := Vector2i.ZERO) -> Unit:
	var u: Unit = H.spawn_solo(self, _squads, Team.Faction.PLAYER, cell, {}, false)
	u.unit_instance.aura = aura
	var affinity: Array[Elemental.Element] = []
	for element: Elemental.Element in aura:
		affinity.append(element)
	u.unit_instance.affinity = affinity
	return u


func _circle(sigils: Array[Elemental.Element], name: String) -> TransmutationData:
	var carving := TransmutationData.new()
	carving.display_name = name
	carving.power = 4
	carving.sigils.assign(sigils)
	return carving


# BUILT, never drawn from shipped content: the pairs below differ in exactly one field, and picking
# two authored carvings would pass against a readout that still could not tell a shove from a splash.
# It is also the content razor -- what Resources/TransmutationData holds is the dev's to edit.
func _rune(carvings: Array[TransmutationData]) -> RuneData:
	var rune := RuneData.new()
	rune.size = RuneData.Size.LARGE
	for c: TransmutationData in carvings:
		assert_bool(rune.inscribe(c)).override_failure_message(
			"fixture carving failed to inscribe").is_true()
	return rune


func _blank_rune() -> RuneData:
	var none: Array[TransmutationData] = []
	return _rune(none)


func _open(rune: RuneData, wielder: Unit) -> RuneDetailCard:
	var card := RuneDetailCard.open(game, rune, wielder)
	await await_idle_frame()
	return card


static func _walk(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in root.get_children():
		out.append(child)
		out.append_array(_walk(child))
	return out


func _screen() -> PreMissionScreen:
	for child in game.ui_layer.get_children():
		if child is PreMissionScreen:
			return child
	return null


func _enter_phase() -> bool:
	var names: Array[String] = RosterCatalog.saved_rosters()
	if names.is_empty():
		return false
	for x in range(ROW_WIDTH):
		game.grid.paint(Vector2i(x, 0), GRASS_SOURCE, GRASS_ATLAS)
	for x in range(ZONE_CELLS):
		game.zone_manager.paint_cell("landing", ZoneManager.Kind.DEPLOYMENT, Vector2i(x, 0))
	sm.current_roster = names[0]
	sm.current_deployment_cap = 2
	var objectives: Array[MissionRules.Objective] = [MissionRules.Objective.ROUT]
	mc.set_objectives(objectives)
	assert_int(ResourceSaver.save(sm.capture_scenario("rune_1019", true), SCRATCH)).is_equal(OK)
	mc.begin_mission(SCRATCH)
	await await_idle_frame()
	return mc.is_deploying()


# --- reading what is on screen ----------------------------------------------------------------------

# Every line the readout carries about the picked carving, joined -- the picture a player reads,
# rather than the variable behind it.
static func _readout_text(card: RuneDetailCard) -> String:
	var parts: Array[String] = [card._damage.text, card._range.text, card._aura.text]
	parts.append(_channel_text(card))
	return "\n".join(parts)


static func _channel_text(card: RuneDetailCard) -> String:
	var parts: Array[String] = []
	for child in card._channels.get_children():
		parts.append((child as Label).text)
	return "\n".join(parts)


static func _list_text(card: RuneDetailCard) -> String:
	var parts: Array[String] = []
	for node: Node in _walk(card._list):
		var label := node as Label
		if label != null:
			parts.append(label.text)
	return "\n".join(parts)


static func _list_tooltips(card: RuneDetailCard) -> String:
	var parts: Array[String] = []
	for child in card._list.get_children():
		parts.append((child as Control).tooltip_text)
	return "\n".join(parts)


# The bars beside one row's name. Reached STRUCTURALLY -- row > body > line > its last child --
# rather than by scanning the list for Panels: since #1022 the legend above is made of them and the
# row's own name label shares the line, so a scan would answer with whatever it met first.
static func _bars_of(row: Control) -> HBoxContainer:
	var body := row.get_child(0) as VBoxContainer
	var line := body.get_child(0) as HBoxContainer
	return line.get_child(line.get_child_count() - 1) as HBoxContainer


# How one row's marks split: the recipe's own bars, then the spare ones past the `+`. The Label IS
# the separator, which is what lets a case read the split without the card exposing anything for it.
static func _marks_of(row: Control) -> Dictionary[String, int]:
	var cost := 0
	var spare := 0
	var hollow := 0
	var past_plus := false
	for child: Node in _bars_of(row).get_children():
		if child is Label:
			past_plus = true
			continue
		var bar := child as Panel
		if bar == null:
			continue
		if past_plus:
			spare += 1
			continue
		cost += 1
		var box := bar.get_theme_stylebox("panel") as StyleBoxFlat
		if box != null and box.border_width_left > 0:
			hollow += 1
	return {"cost": cost, "spare": spare, "hollow": hollow}


static func _rows_of(card: RuneDetailCard) -> Array[Control]:
	var out: Array[Control] = []
	for child: Node in card._list.get_children():
		var row := child as PanelContainer
		if row != null:
			out.append(row)
	return out


static func _wanted(card: RuneDetailCard, element: Elemental.Element) -> int:
	for row: AuraRing.Row in AuraRing.rows(card._ring.unit, card._ring.carving):
		if row.element == element:
			return row.wanted
	return -1


# --- the wire ---------------------------------------------------------------------------------------

# THE ASSERTION #1017 WAS MISSING, made here before this card can grow the same hole. Two carvings on
# one rune, identical in every field the recipe-and-damage line reads and differing only in KNOCKBACK,
# must not render the same picture.
func test_picking_another_carving_moves_what_is_drawn() -> void:
	var shove := _circle([FIRE], "Shove")
	shove.knockback = 2
	var carvings: Array[TransmutationData] = [_circle([FIRE], "Tap"), shove]
	var rune := _rune(carvings)
	var card := await _open(rune, _alchemist({FIRE: 3}))

	var seen: Array[String] = []
	for i in range(rune.inscriptions.size()):
		card._on_carving_picked(i)
		seen.append(_readout_text(card))

	assert_str(seen[0]).override_failure_message(
		"two carvings differing only in knockback rendered identically -- #1017, one card over"
		).is_not_equal(seen[1])


# The shared enumeration has to be WIRED here, not merely available: AttackChannelText exists so this
# card and the weapon one cannot drift, and a card that never called it would look exactly like one
# that had, until the first pair of near-identical carvings.
func test_a_carvings_own_channels_reach_the_readout() -> void:
	var splash := _circle([FIRE], "Splash")
	splash.hits_allies = true
	var carvings: Array[TransmutationData] = [_circle([FIRE], "Plain"), splash]
	var card := await _open(_rune(carvings), _alchemist({FIRE: 3}))

	card._on_carving_picked(0)
	assert_str(_channel_text(card)).not_contains("Splashes allies")
	card._on_carving_picked(1)
	assert_str(_channel_text(card)).contains("Splashes allies")


# The ring is the element half of that same wire. Asserted through rows() rather than through pixels,
# which is AuraRing's own division: rows() is the model and _draw only renders it.
func test_the_ring_follows_the_picked_carving() -> void:
	var carvings: Array[TransmutationData] = [_circle([FIRE], "Tap"), _circle([FIRE, EARTH], "Split")]
	var rune := _rune(carvings)
	var card := await _open(rune, _alchemist({FIRE: 3}))

	card._on_carving_picked(1)
	assert_object(card._ring.carving).is_same(rune.inscriptions[1])
	assert_int(_wanted(card, EARTH)).is_equal(1)

	card._on_carving_picked(0)
	assert_object(card._ring.carving).is_same(rune.inscriptions[0])
	assert_int(_wanted(card, EARTH)).override_failure_message(
		"the ring kept the previous carving's demand").is_equal(0)


# --- the verdict ------------------------------------------------------------------------------------

# The card prints the ladder's OWN WORDS, never a second wording of the same refusal -- which is the
# whole reason aura_text asks the ladder before it builds anything.
func test_a_carving_the_carrier_cannot_channel_says_the_ladders_own_words() -> void:
	var alch := _alchemist({FIRE: 3})
	var carvings: Array[TransmutationData] = [_circle([WATER, WATER], "Douse")]
	var rune := _rune(carvings)
	var card := await _open(rune, alch)

	assert_str(card._aura.text).is_equal(
		rune.inscriptions[0].channel_block_reason(alch, rune.temper))
	assert_str(card._aura.text).contains("Water")
	# ...and the row in the list below carries that same refusal rather than inventing one.
	assert_str(_list_tooltips(card)).contains("Water")


# Surplus aura is real damage and the card says how much -- the number the halo beside it is drawn
# for. Fire 3 against a one-sigil Fire circle is two spare points, weighted once.
func test_a_channelable_carving_names_the_damage_its_spare_aura_buys() -> void:
	var carvings: Array[TransmutationData] = [_circle([FIRE], "Ember")]
	var card := await _open(_rune(carvings), _alchemist({FIRE: 3}))

	assert_str(card._aura.text).contains("Channels on")
	assert_str(card._aura.text).contains("adds 2 damage")


# --- the two states with nobody in the middle -------------------------------------------------------

# A rune in the stash is held by NOBODY, so the ring shows demand with nothing paid and the card gives
# no verdict at all: channeling is a property of the pairing, not of either half.
func test_a_rune_nobody_holds_shows_the_demand_and_gives_no_verdict() -> void:
	var carvings: Array[TransmutationData] = [_circle([FIRE, FIRE], "Ember")]
	var card := await _open(_rune(carvings), null)

	assert_int(_wanted(card, FIRE)).is_equal(2)
	for row: AuraRing.Row in AuraRing.rows(card._ring.unit, card._ring.carving):
		assert_int(row.depth).override_failure_message(
			"a rune nobody holds reported aura for somebody").is_equal(0)

	assert_object(card._ring.portrait).override_failure_message(
		"an empty centre was asked for -- demand only, nothing paid").is_null()
	assert_bool(card._aura.visible).is_false()
	assert_str(card._damage.text).is_empty()
	assert_str(card._headline.text).contains("in the stash")


# A blank rune OPENS rather than being a card with nothing on it: what it has room for, and that its
# temper is still unspent, are the two facts a player opens it to learn.
func test_a_blank_rune_opens_and_says_it_is_blank() -> void:
	var card := await _open(_blank_rune(), _alchemist({FIRE: 3}))

	assert_object(card._carving).is_null()
	assert_str(card._hint.text).contains("0 of 6")
	assert_str(card._hint.text).contains("not tempered")
	assert_str(_list_text(card)).contains("Nothing is carved")
	assert_bool(card._ring.visible).is_true()


# --- the list ---------------------------------------------------------------------------------------

# The recipe as MARKS, one per sigil, so weight is visible rather than written. cost() is the raw
# sigil count (#60: cost is derived from the recipe, never author-set), and the bars ARE that count --
# which is what stops the picture and the capacity line under it from disagreeing.
func test_a_carvings_cost_bars_are_one_per_sigil() -> void:
	var carvings: Array[TransmutationData] = [_circle([FIRE, FIRE, EARTH], "Cinder")]
	var rune := _rune(carvings)
	var card := await _open(rune, _alchemist({FIRE: 3, EARTH: 1}))

	var marks := _marks_of(_rows_of(card)[0])
	assert_int(marks["cost"]).is_equal(rune.inscriptions[0].cost())
	assert_int(marks["cost"]).is_equal(3)
	assert_str(card._hint.text).contains("3 of 6")


# THE BARS CARRY THE RING'S OWN STATES (#1022). Shipped flat at #1019 -- one rectangle per sigil in
# the element's colour and nothing else -- which is why they said so little: the shape was right and
# the vocabulary was missing. A carrier who covers half a recipe must see which half.
func test_a_cost_bar_says_whether_that_sigil_is_paid() -> void:
	# Fire 1 against a 2-Fire recipe: one paid, one asked-for-and-unpaid.
	var carvings: Array[TransmutationData] = [_circle([FIRE, FIRE], "Ember")]
	var card := await _open(_rune(carvings), _alchemist({FIRE: 1}))

	var marks := _marks_of(_rows_of(card)[0])
	assert_int(marks["cost"]).is_equal(2)
	assert_int(marks["hollow"]).override_failure_message(
		"the unpaid sigil drew the same bar as the paid one").is_equal(1)


# The SPARE, past a `+` -- the halo's own number said again in the list, so the ring and the row
# cannot disagree about how much aura is going spare.
func test_spare_aura_gets_its_own_marks_after_the_recipe() -> void:
	# Fire 3 against a one-sigil Fire circle: one paid, two spare.
	var carvings: Array[TransmutationData] = [_circle([FIRE], "Ember")]
	var card := await _open(_rune(carvings), _alchemist({FIRE: 3}))

	var marks := _marks_of(_rows_of(card)[0])
	assert_int(marks["cost"]).is_equal(1)
	assert_int(marks["hollow"]).is_equal(0)
	assert_int(marks["spare"]).is_equal(2)

	# ...and a carrier who covers the recipe exactly has none, rather than a zero drawn as nothing.
	var same: Array[TransmutationData] = [_circle([FIRE], "Ember")]
	var exact := await _open(_rune(same), _alchemist({FIRE: 1}, Vector2i(1, 0)))
	assert_int(_marks_of(_rows_of(exact)[0])["spare"]).is_equal(0)


# A ROW SAYS HOW COMFORTABLY IT CHANNELS, in three states (dev: "red for pressure spray since the
# unit cannot cast, yellow for zap cannon since it can only be cast with the extra slot, none for
# fireball since it can be comfortably cast"). Asserted through the LADDER's own answer rather than
# through a colour -- the tint is chrome, and which of the three a carving is in is the rule.
func test_a_row_says_how_comfortably_it_channels() -> void:
	var alch := _alchemist({FIRE: 2})
	var comfortable := _circle([FIRE], "Fireball")
	var leaning := _circle([FIRE, FIRE, AIR], "Zap Cannon")      # Air 0: one wildcard covers it
	var refused := _circle([WATER, WATER], "Pressure Spray")     # no Water anywhere: no anchor

	assert_that(comfortable.channel_state(alch, FIRE)).override_failure_message(
		"a recipe paid outright read as anything but clear"
		).is_equal(TransmutationData.Channel.CLEAR)
	assert_that(leaning.channel_state(alch, FIRE)).override_failure_message(
		"a carving leaning on a wildcard read the same as one paid outright"
		).is_equal(TransmutationData.Channel.WILDCARD)
	assert_that(refused.channel_state(alch, FIRE)).is_equal(TransmutationData.Channel.REFUSED)

	# ...and the three do not collapse onto two boxes on the way to the row.
	var boxes := {}
	for state: TransmutationData.Channel in [TransmutationData.Channel.CLEAR,
			TransmutationData.Channel.WILDCARD, TransmutationData.Channel.REFUSED]:
		boxes[QueueStyle.channel_box(RuneDetailCard._box_state(state), false)] = true
	assert_int(boxes.size()).override_failure_message(
		"two of the three channel states share one box").is_equal(3)


# WHAT IT DOES, under the name -- and NOT what it costs, because the bars above are that (dev:
# "perhaps get rid of the cost X though, since we're already visualizing that with the bars").
func test_a_row_prints_what_it_does_and_never_what_it_costs() -> void:
	# A carrier one Air short, so the WILDCARD half of mechanical_text is genuinely present to be
	# left out -- a fixture with no deficit cannot tell the two readouts apart, which is how the
	# first version of this case passed against a mutant printing the whole sentence.
	var recipe: Array[Elemental.Element] = [FIRE, FIRE, AIR]
	var carvings: Array[TransmutationData] = [_circle(recipe, "Zap")]
	var rune := _rune(carvings)
	var alch := _alchemist({FIRE: 2})
	var card := await _open(rune, alch)

	assert_int(rune.inscriptions[0].total_deficit(alch)).override_failure_message(
		"the fixture has no shortfall, so the wildcard half is absent either way").is_greater(0)

	var text := _list_text(card)
	assert_str(text).override_failure_message(
		"the row never said what the carving does").contains("Damage")
	# THE RECIPE is the bars' job and THE SHORTFALL is the row tint's, so neither may be printed
	# again underneath -- that is the same fact twice on one row (dev).
	assert_str(text).override_failure_message(
		"the row printed the recipe the bars beside it already draw"
		).not_contains(rune.inscriptions[0].sigil_text())
	assert_str(text).override_failure_message(
		"the row printed the wildcard count its own tint already says").not_contains("Wildcards")


# --- the door ---------------------------------------------------------------------------------------

# ONE chip builder for every kind, so a rune reaches an affordance through the SAME call the gear rows
# make -- a second builder beside it is what would leave one surface with rune chips and the other
# without, which is how #732's chip reached only half the surfaces it was meant to.
func test_a_rune_gets_its_chip_from_the_same_fork_a_weapon_does() -> void:
	var carvings: Array[TransmutationData] = [_circle([FIRE], "Ember")]
	var chip: Button = auto_free(ItemDetail.chip_for(_rune(carvings)))
	assert_object(chip).is_not_null()
	assert_str(chip.text).is_equal("1/6")

	# A BLANK rune gets one too (dev), which is where this parts from the weapon chip -- that one
	# answers null for a weapon with no spaces. "0/6" is how a player learns a rune is blank without
	# equipping it and reading the refusal off the gate.
	var blank: Button = auto_free(ItemDetail.chip_for(_blank_rune()))
	assert_object(blank).is_not_null()
	assert_str(blank.text).is_equal("0/6")

	# ...and a kind with no card still gets none, which is what keeps an armour row clean.
	assert_object(ItemDetail.chip_for(ArmorData.new())).is_null()


# THE SCREEN'S OWN DOOR, not RuneDetailCard.open: one signal carries every kind now, so the half worth
# pinning is that the dispatch behind it sends a rune to the rune card. Both cards are reachable from
# the same handler, and a fork that fell through would open the wrong one in silence.
func test_the_screens_own_door_opens_the_rune_card_and_not_the_weapons() -> void:
	if not await _enter_phase():
		return
	var carvings: Array[TransmutationData] = [_circle([FIRE], "Ember")]
	_screen()._on_detail_requested(_rune(carvings), null)
	await await_idle_frame()

	var opened: RuneDetailCard = null
	for child in game.ui_layer.get_children():
		if child is RuneDetailCard:
			opened = child
		assert_bool(child is ModFittingCard).override_failure_message(
			"a rune reached the weapon fitting card").is_false()
	assert_object(opened).override_failure_message("the screen opened no card").is_not_null()


# --- the two the dev reported by eye -----------------------------------------------------------------

# THE BARS SIT BESIDE THE NAME, not at the far edge (dev: "the bars in the titles are right aligned").
# Asserted against the row's own geometry rather than against a size flag: the flag is how it was
# broken, the POSITION is what was wrong with it, and a case pinned to the flag would go green the
# next time the same mistake arrives wearing a spacer instead.
func test_the_cost_bars_sit_beside_the_name_rather_than_at_the_far_edge() -> void:
	var carvings: Array[TransmutationData] = [_circle([FIRE], "Ember")]
	var card := await _open(_rune(carvings), _alchemist({FIRE: 2}))
	await await_idle_frame()

	var row := _rows_of(card)[0]
	var line := (row.get_child(0) as VBoxContainer).get_child(0) as HBoxContainer
	var name_label := line.get_child(0) as Label
	var bars := _bars_of(row)

	var slack := line.size.x - (bars.position.x + bars.size.x)
	var gap := bars.position.x - (name_label.position.x + name_label.size.x)
	assert_float(gap).override_failure_message(
		"the bars are %.0fpx from the name -- they are not beside it" % gap).is_less(20.0)
	assert_float(slack).override_failure_message(
		"the row's empty space is before the bars rather than after them, so they read as a second "
		+ "column instead of what the name costs").is_greater(gap)


# THE CHIP PAINTS ITS OWN GROUND (#1022, dev: the buttons "don't really visually read as buttons").
# A bare Button takes the engine's chrome and vanishes on this panel -- the diagnosis EXECUTE_BG
# already carries -- so what is pinned is that it HAS a box and that the box MOVES when the pointer
# lands, which together are the whole of "this is pressable". Which colours those are is the dev's.
func test_the_detail_chip_paints_its_own_chrome_and_answers_the_pointer() -> void:
	var carvings: Array[TransmutationData] = [_circle([FIRE], "Ember")]
	var chip: Button = auto_free(ItemDetail.chip_for(_rune(carvings)))

	# ASK FOR THE OVERRIDE, NOT FOR A BOX. `get_theme_stylebox` falls back to the THEME's own Button
	# box when nothing is overridden -- which is a real StyleBoxFlat, and is precisely the chrome that
	# disappears on this panel -- so a case asking merely "is there a box" passes against the bug it
	# was written for. A mutant deleting the override went green until this line said `override`.
	assert_bool(chip.has_theme_stylebox_override("normal")).override_failure_message(
		"the chip inherits the engine's button chrome, which is the thing that disappeared"
		).is_true()
	assert_bool(chip.has_theme_stylebox_override("hover")).is_true()

	var resting := chip.get_theme_stylebox("normal") as StyleBoxFlat
	var hovered := chip.get_theme_stylebox("hover") as StyleBoxFlat
	assert_object(resting).is_not_null()
	assert_object(hovered).is_not_null()
	assert_bool(resting.bg_color == QueueStyle.ink(QueueStyle.Role.ROW_BG)).override_failure_message(
		"the chip's fill is the row it sits on, so there is nothing to see").is_false()
	assert_bool(resting.bg_color == hovered.bg_color).override_failure_message(
		"the chip looks identical under the pointer").is_false()
	# ...and it says so before the click, at no cost in width.
	assert_int(chip.mouse_default_cursor_shape).is_equal(Control.CURSOR_POINTING_HAND)


# ONE BUILDER FOR BOTH CARDS, so "make it pop" stays a one-place change. A weapon chip and a rune
# chip differ in what they COUNT and in nothing else.
func test_both_kinds_of_chip_wear_the_same_chrome() -> void:
	var carvings: Array[TransmutationData] = [_circle([FIRE], "Ember")]
	var rune_chip: Button = auto_free(ItemDetail.chip_for(_rune(carvings)))
	var plain: Button = auto_free(ItemDetail.chip("1/3", "whatever"))

	var a := rune_chip.get_theme_stylebox("normal") as StyleBoxFlat
	var b := plain.get_theme_stylebox("normal") as StyleBoxFlat
	assert_bool(a.bg_color == b.bg_color).is_true()
	assert_bool(a.border_color == b.border_color).is_true()
