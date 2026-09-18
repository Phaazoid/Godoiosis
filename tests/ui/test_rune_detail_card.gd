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


static func _cost_bars(card: RuneDetailCard) -> Array[ColorRect]:
	var out: Array[ColorRect] = []
	for node: Node in _walk(card._list):
		var bar := node as ColorRect
		if bar != null:
			out.append(bar)
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

	assert_int(_cost_bars(card).size()).is_equal(rune.inscriptions[0].cost())
	assert_int(_cost_bars(card).size()).is_equal(3)
	assert_str(card._hint.text).contains("3 of 6")


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
