# What an action-queue ROW says, on the real game scene (#685).
#
# The redesign's whole premise is that four facts had been stacked into three 32px squares through
# `show_behind_parent` -- the state icons under the verb, the hp readout over it, the fired
# reaction's art under the target -- so every elemental consequence was drawn and invisible. These
# cases pin what replaced that, and each one is a rule rather than a look: nothing shares a slot,
# a channel that can go quiet can still speak, and the two colour channels stay on their own
# meanings.
#
# NO CASE ASSERTS WHAT A COLOUR IS. ElementPalette's seven are GameKnobs rows the dev drags, so a
# case pinning a hex would turn the suite red the first time he tuned one (the tuning razor,
# tests/README.md #8). Every colour assertion here compares against the palette's own answer.
#
# Fixture is tests/ui/test_queue_row_drag.gd's -- see tests/README.md -> Testing the game scene.
extends GdUnitTestSuite

const MAIN_SCENE := "res://Scenes/Main.tscn"
const H := preload("res://tests/support/squad_fixtures.gd")
const GRASS_SOURCE := 0
const GRASS_ATLAS := Vector2i(5, 0)

var _main: Node
var game: Node2D


func before_test() -> void:
	_main = (load(MAIN_SCENE) as PackedScene).instantiate()
	_main.name = "Main"
	get_tree().root.add_child(_main)
	await await_idle_frame()
	game = _main.get_node("GameContainer/GameView/Game")
	game.scenario_manager.clear_board()
	game.game_state = game.GameState.IDLE
	for x in range(8):
		for y in range(4):
			game.grid.set_cell(Vector2i(x, y), GRASS_SOURCE, GRASS_ATLAS)
	await await_idle_frame()


func after_test() -> void:
	get_tree().root.remove_child(_main)
	_main.free()
	await await_idle_frame()   # #93/#114: let the freed subtree settle before the orphan sample


# --- fixture -------------------------------------------------------------------------------------

func _spawn(faction: Team.Faction, cell: Vector2i) -> Unit:
	var unit: Unit = game.spawn_unit(H.make_unit_data({}, faction), cell)
	assert_object(unit).is_not_null()
	return unit


# An attacker whose main attack carries `element`, and a victim beside it. Queued through the real
# door (SquadManager.queue_action) so the panel is fed by the same resolve the game feeds it.
func _queue_elemental_attack(element: Elemental.Element, victim_states: Array[Elemental.State]) -> Unit:
	var attacker := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var victim := _spawn(Team.Faction.ENEMY, Vector2i(2, 1))
	for state in victim_states:
		victim.add_element_state(state)

	var weapon := H.make_weapon(4)
	(weapon.template.main_attack as WeaponAttackData).elemental_damage_type = element
	attacker.equipped_weapon = weapon

	game.squad_manager.active_squad = attacker.squad
	game.squad_manager.queue_action(attacker.squad, H.stamped_attack(attacker, victim))
	game.refresh_action_queue(attacker.squad)
	await await_idle_frame()
	return attacker


# Every ActionQueueRow the panel is showing, walked by TYPE -- the panel's nesting is not what
# these cases are about, and #592's lesson is that a path-based reach can read a hidden node.
func _rows() -> Array[ActionQueueRow]:
	var out: Array[ActionQueueRow] = []
	_collect(game.squad_action_queue_control, out)
	return out


func _collect(node: Node, out: Array[ActionQueueRow]) -> void:
	if node is ActionQueueRow:
		out.append(node as ActionQueueRow)
		return
	for child in node.get_children():
		_collect(child, out)


func _attack_row() -> ActionQueueRow:
	for row in _rows():
		if row.action is AttackAction:
			return row
	return null


# The pills on a row's consequence line, as (text, font colour) pairs.
func _consequence_entries(row: ActionQueueRow) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for pill in row.consequence.get_children():
		var label := _first_label(pill)
		if label != null:
			out.append({"text": label.text, "color": label.get_theme_color("font_color"),
					"tip": label.tooltip_text})
	return out


func _first_label(node: Node) -> Label:
	if node is Label:
		return node as Label
	for child in node.get_children():
		var hit := _first_label(child)
		if hit != null:
			return hit
	return null


func _texts(entries: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for e in entries:
		out.append(String(e["text"]))
	return out


# ------------------------------------------------------------------------------------------------
#  1. Nothing shares a slot
# ------------------------------------------------------------------------------------------------

# THE defect this ticket exists to remove. The two slots that used to carry foreign passengers must
# now be empty, and the line's own children must not overlap on screen.
#
# The ACTOR slot is the one declared exception: the leader's crown rides behind the sprite, and the
# two together answer ONE question ("what is this unit") rather than two facts sharing a square --
# so this case asks about the icon and the target, which carried the hp readout and the reaction art.
func test_no_row_element_is_drawn_on_top_of_another() -> void:
	await _queue_elemental_attack(Elemental.Element.WATER, [])
	var row := _attack_row()
	assert_object(row).is_not_null()

	assert_int(row.action_icon.get_child_count()) \
		.override_failure_message("the action icon is carrying a passenger again — that slot held the hp readout AND the state icons before #685") \
		.is_equal(0)
	assert_int(row.target_texture.get_child_count()) \
		.override_failure_message("the target sprite is carrying a passenger again — that slot held the fired reaction's art before #685") \
		.is_equal(0)

	var line: Array[Control] = []
	for child in row.actor_texture.get_parent().get_children():
		var control := child as Control
		if control != null and control.visible:
			line.append(control)
	for i in line.size():
		for j in range(i + 1, line.size()):
			var a := line[i].get_global_rect()
			var b := line[j].get_global_rect()
			assert_bool(a.intersects(b)) \
				.override_failure_message("%s and %s overlap on the row's line (%s vs %s)"
					% [line[i].name, line[j].name, a, b]) \
				.is_false()


# ------------------------------------------------------------------------------------------------
#  2. The chip can speak
# ------------------------------------------------------------------------------------------------

# A channel whose failure mode is SILENCE needs a case proving it can talk: a chip that never
# renders and a chip whose tooltip is empty look identical in a screenshot.
func test_a_state_the_hit_applies_becomes_a_chip_that_explains_itself() -> void:
	await _queue_elemental_attack(Elemental.Element.WATER, [])
	var row := _attack_row()
	assert_object(row).is_not_null()
	assert_bool(row.consequence.visible) \
		.override_failure_message("a hit that applies WET drew no consequence line at all") \
		.is_true()

	var entries := _consequence_entries(row)
	assert_array(_texts(entries)) \
		.override_failure_message("expected a WET chip, got %s" % [_texts(entries)]) \
		.contains([Elemental.state_display_name(Elemental.State.WET)])

	for e in entries:
		if String(e["text"]) == Elemental.state_display_name(Elemental.State.WET):
			assert_str(String(e["tip"])) \
				.override_failure_message("the WET chip has no hover readout — the tooltip doctrine is what keeps the elemental table off the player's memory") \
				.is_not_empty()
			assert_that(e["color"]).is_equal(
					QueueStyle.state_ink(Elemental.State.WET))


# A status lands on the unit RECEIVING it, so its chip sits AFTER the target sprite and before the
# damage — in the gap the line already had. Round 2 put it on a second line under the target, which
# the dev then read as wasted height; either way the rule is the same one, and it is not a layout
# preference: a chip beside the ATTACKER is a lie about who is wet.
func test_a_status_chip_sits_between_the_target_and_the_damage() -> void:
	await _queue_elemental_attack(Elemental.Element.WATER, [])
	var row := _attack_row()
	assert_object(row).is_not_null()
	assert_int(row.consequence.get_child_count()) \
		.override_failure_message("the hit applied WET and no chip was built").is_greater(0)

	var chip: Control = row.consequence.get_child(0)
	var chip_left := chip.get_global_rect().position.x
	var target_right := row.target_texture.get_global_rect().end.x
	var readout_left := row.readout_card.get_global_rect().position.x
	assert_float(chip_left) \
		.override_failure_message("the status chip starts at %.0f, before the target sprite ends at %.0f — it reads as the ATTACKER's status, not the receiver's"
			% [chip_left, target_right]) \
		.is_greater_equal(target_right)
	assert_float(chip.get_global_rect().end.x) \
		.override_failure_message("the status chip runs to %.0f, past the damage readout at %.0f"
			% [chip.get_global_rect().end.x, readout_left]) \
		.is_less_equal(readout_left)


# A hit with SEVERAL consequences wraps its chips rather than clipping or pushing the cancel X off
# the panel. The wrap is the graceful half of putting the chips in the line at all: the row buys a
# second line only when it genuinely needs one, and never loses a word.
func test_a_crowded_row_wraps_its_chips_instead_of_overflowing() -> void:
	var states: Array[Elemental.State] = [Elemental.State.WET]
	await _queue_elemental_attack(Elemental.Element.ICE, states)   # deep chill: a state AND a combo
	var row := _attack_row()
	assert_object(row).is_not_null()
	assert_int(row.consequence.get_child_count()) \
		.override_failure_message("this hit produced %d chips, so it is not the crowded case it claims to be"
			% row.consequence.get_child_count()) \
		.is_greater(1)

	# MEASURED AGAINST THE DOCK, not the section -- see test_the_widest_row_still_fits_inside_its_section.
	# This case's own blind spot was separate and worse: an HFlowContainer's minimum width is its
	# WIDEST CHILD, so wrapping only ever happens BETWEEN chips and a crowd of SHORT ones can never
	# trip it. The single over-wide chip is what broke the dock, and tests/ui/test_queue_badge_widths.gd
	# is the law that covers it; this case keeps the crowd half.
	var dock: Control = game.squad_action_queue_control.background_panel
	assert_float(row.get_global_rect().end.x) \
		.override_failure_message("the row reaches %.0f and the dock ends at %.0f -- the chips are pushing the row out of the panel instead of wrapping"
			% [row.get_global_rect().end.x, dock.get_global_rect().end.x]) \
		.is_less_equal(dock.get_global_rect().end.x)


# The chips take the slack the line already had, so a hit with one consequence must NOT cost a
# second visual line -- that is the whole of what round 3 bought back.
func test_one_status_does_not_grow_the_row() -> void:
	var plain := _spawn(Team.Faction.PLAYER, Vector2i(1, 3))
	var move := MoveAction.new()
	move.init(plain, [plain.movement.cell, plain.movement.cell + Vector2i(1, 0)], null)
	plain.squad._queue_action(move)
	game.refresh_action_queue(plain.squad)
	await await_idle_frame()
	var bare_height := _rows()[0].size.y

	await _queue_elemental_attack(Elemental.Element.WATER, [])
	var row := _attack_row()
	assert_object(row).is_not_null()
	assert_int(row.consequence.get_child_count()).is_greater(0)
	assert_float(row.size.y) \
		.override_failure_message("a row with one status is %.0fpx tall against a bare row's %.0f — the chip wrapped to its own line instead of taking the slack"
			% [row.size.y, bare_height]) \
		.is_equal_approx(bare_height, 1.0)


# The row's own header claims the X keeps its slot on every row so content stays aligned, and the
# readout CARD nearly broke that: the card carried the line's horizontal expand, so a MOVE row --
# which has no number and hides it -- packed the X in tight against the target sprite. The Consequence
# container holds the expand now, present whether or not it has chips, and this is what says so.
func test_the_cancel_x_holds_the_right_edge_on_a_row_with_no_number() -> void:
	var attacker := await _queue_elemental_attack(Elemental.Element.WATER, [])
	var walker := _spawn(Team.Faction.PLAYER, Vector2i(1, 3))
	var move := MoveAction.new()
	move.init(walker, [walker.movement.cell, walker.movement.cell + Vector2i(1, 0)], null)
	attacker.squad._queue_action(move)
	game.refresh_action_queue(attacker.squad)
	await await_idle_frame()

	var with_number: ActionQueueRow = null
	var without: ActionQueueRow = null
	for row in _rows():
		if row.readout_card.visible:
			with_number = row
		else:
			without = row
	assert_object(with_number).override_failure_message(
			"no row showed a readout card, so there is nothing to compare against").is_not_null()
	assert_object(without).override_failure_message(
			"every row showed a readout card, so the hidden-card case is untested").is_not_null()

	assert_float(without.cancel_button.get_global_rect().end.x) \
		.override_failure_message("the X on a numberless row sits at %.0f while a numbered row's is at %.0f — hiding the readout card let the line collapse"
			% [without.cancel_button.get_global_rect().end.x, with_number.cancel_button.get_global_rect().end.x]) \
		.is_equal_approx(with_number.cancel_button.get_global_rect().end.x, 1.0)


# The dock is 465px tall and a section used to start scrolling at 160 of it. A queue that fits must
# show no scrollbar at all -- "if there is space available, we shouldn't be using scrollbars".
func test_a_queue_that_fits_the_dock_scrolls_nothing() -> void:
	await _queue_elemental_attack(Elemental.Element.WATER, [])
	var panel = game.squad_action_queue_control
	var outer: ScrollContainer = panel.sections_box.get_parent()
	assert_object(outer).is_not_null()
	# Non-vacuity: with nothing rendered, "no section scrolls" and "the content fits" are both
	# trivially true and the case could never fail.
	assert_int(_rows().size()).override_failure_message(
			"nothing rendered, so this case cannot see what it claims to").is_greater(0)
	assert_float(outer.size.y).override_failure_message(
			"the dock has no measured height, so 'it fits' means nothing").is_greater(0.0)

	var scrolls: Array[ScrollContainer] = []
	_collect_scrolls(panel.sections_box, scrolls)
	assert_int(scrolls.size()) \
		.override_failure_message("a section owns its own ScrollContainer again — a section that scrolls before the dock is full is what #685 round 2 removed") \
		.is_equal(0)

	assert_float(panel.sections_box.get_combined_minimum_size().y) \
		.override_failure_message("this small a queue does not fit the dock (%.0f needed, %.0f available), so the case cannot see what it claims to"
			% [panel.sections_box.get_combined_minimum_size().y, outer.size.y]) \
		.is_less_equal(outer.size.y)


func _collect_scrolls(node: Node, out: Array[ScrollContainer]) -> void:
	for child in node.get_children():
		var scroll := child as ScrollContainer
		if scroll != null:
			out.append(scroll)
		_collect_scrolls(child, out)


# A consequence the WORLD caused -- "Insulated!" here, and "Fell 2!" / "Drowning!" / "Into the void!"
# on the same path -- must not wear the rail's structural grey. That value is chosen to DISAPPEAR,
# which is exactly wrong for text: the dev read it off the screen as grey on grey (2026-09-03).
#
# Asserts the DEFECT, not a hue: EVENT_TINT is a knob he drags, so a pinned colour would red the
# first time he tuned it. What cannot come back is it being the neutral, or vanishing into the row.
func test_a_world_event_pill_is_readable_against_the_row() -> void:
	var insulated := _spawn_insulated_to(Elemental.Element.SHOCK, Vector2i(2, 1))
	var attacker := _spawn(Team.Faction.PLAYER, Vector2i(1, 1))
	var weapon := H.make_weapon(4)
	(weapon.template.main_attack as WeaponAttackData).elemental_damage_type = Elemental.Element.SHOCK
	attacker.equipped_weapon = weapon
	game.squad_manager.active_squad = attacker.squad
	game.squad_manager.queue_action(attacker.squad, H.stamped_attack(attacker, insulated))
	game.refresh_action_queue(attacker.squad)
	await await_idle_frame()

	var row := _attack_row()
	assert_object(row).is_not_null()
	var entries := _consequence_entries(row)
	# THE BADGE is what the row prints; the dramatic word moved to the tooltip (2026-09-04), because
	# a pill sized for the board's floating text does not fit this line. Both halves are asserted --
	# a badge with no tooltip would have lost the wording rather than relocated it.
	assert_array(_texts(entries)) \
		.override_failure_message("the hit was fully insulated and the row said nothing about it — got %s"
			% [_texts(entries)]) \
		.contains([ActionQueueRow.BADGE_INSULATED])

	for e in entries:
		if String(e["text"]) != ActionQueueRow.BADGE_INSULATED:
			continue
		assert_str(String(e["tip"])) \
			.override_failure_message("the badge shortened the word and dropped it: the dramatic wording has to survive on hover") \
			.contains(PlanResolver.INSULATED_POPUP)
		var tint: Color = e["color"]
		assert_that(tint) \
			.override_failure_message("the world-event pill is wearing the rail's off-state grey again — it is chosen to disappear, and text in it is grey on grey") \
			.is_not_equal(QueueStyle.ink(QueueStyle.Role.RAIL_NEUTRAL))
		# A generous floor: every readable choice clears it by miles, and only a near-row-coloured
		# one trips it, which is the bug itself coming back.
		var contrast: float = absf(_luma(tint) - _luma(QueueStyle.ink(QueueStyle.Role.ROW_BG)))
		assert_float(contrast) \
			.override_failure_message("the world-event pill sits at luma %.2f against a row at %.2f — that is the grey-on-grey the dev reported"
				% [_luma(tint), _luma(QueueStyle.ink(QueueStyle.Role.ROW_BG))]) \
			.is_greater(0.25)


func _luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# A unit that shrugs off `element` entirely, so the resolver records its INSULATED popup — the one
# world-event pill reachable without a shove, a cliff or deep water.
func _spawn_insulated_to(element: Elemental.Element, cell: Vector2i) -> Unit:
	var data := H.make_unit_data({}, Team.Faction.ENEMY)
	var ability := AbilityData.new()
	ability.id = Abilities.INSULATION[element]
	ability.display_name = "Insulated"
	var abilities: Array[AbilityData] = [ability]
	data.innate_abilities = abilities
	var unit: Unit = game.spawn_unit(data, cell)
	assert_object(unit).is_not_null()
	assert_bool(unit.is_immune_to(element)) \
		.override_failure_message("the fixture unit is not actually insulated, so this case cannot see what it claims to") \
		.is_true()
	return unit


# ------------------------------------------------------------------------------------------------
#  3. A fired combo says its authored word
# ------------------------------------------------------------------------------------------------

# The reaction's `popup` has existed since the elemental system was built and the queue has never
# shown it. Read off the live catalog rather than typed here — the content razor: the dev may
# re-word "Electrocuted!" without turning this red.
func test_a_fired_combo_says_its_own_word_in_its_element_colour() -> void:
	var combo := _first_combo()
	if combo == null:
		# Not a skip in disguise: it says the authored catalog no longer contains a combo at all,
		# which is a content fact worth surfacing rather than passing over.
		assert_object(combo).override_failure_message(
				"no authored reaction requires a state — this case has nothing to exercise").is_not_null()
		return

	var victim_states: Array[Elemental.State] = [combo.required_state]
	await _queue_elemental_attack(combo.incoming_element, victim_states)
	var row := _attack_row()
	assert_object(row).is_not_null()

	var entries := _consequence_entries(row)
	assert_array(_texts(entries)) \
		.override_failure_message("the fired combo never said its word — got %s" % [_texts(entries)]) \
		.contains([combo.badge_name()])

	for e in entries:
		if String(e["text"]) == combo.badge_name():
			assert_that(e["color"]).is_equal(
					QueueStyle.element_ink(combo.incoming_element))
			assert_str(String(e["tip"])) \
				.override_failure_message("the combo's word has no hover explanation") \
				.is_not_empty()


func _first_combo() -> ElementalReaction:
	for reaction in ReactionCatalog.get_all():
		if reaction.is_combo() and reaction.popup != "":
			return reaction
	return null


# ------------------------------------------------------------------------------------------------
#  4. A SETUP is a chip, not a line
# ------------------------------------------------------------------------------------------------

# The split-by-weight ruling, pinned against the obvious future edit of "just show every popup".
# water_sets_wet carries the popup "Wet" AND deposits the WET state; showing both says one fact
# twice, which is the noise the split exists to prevent.
func test_a_setup_reaction_is_said_once_by_its_chip_and_not_again_as_a_line() -> void:
	var setup := _first_setup()
	if setup == null:
		assert_object(setup).override_failure_message(
				"no authored reaction is a pure setup — this case has nothing to exercise").is_not_null()
		return

	var none: Array[Elemental.State] = []
	await _queue_elemental_attack(setup.incoming_element, none)
	var row := _attack_row()
	assert_object(row).is_not_null()

	var occurrences := 0
	for text in _texts(_consequence_entries(row)):
		if text == setup.badge_name():
			occurrences += 1
	assert_int(occurrences) \
		.override_failure_message("the setup's word '%s' was drawn as a line beside the chip that already says it — entries were %s"
			% [setup.badge_name(), _texts(_consequence_entries(row))]) \
		.is_equal(0)


func _first_setup() -> ElementalReaction:
	for reaction in ReactionCatalog.get_all():
		if not reaction.is_combo() and reaction.popup != "" and not reaction.add_states.is_empty():
			return reaction
	return null


# ------------------------------------------------------------------------------------------------
#  5. The rail reads the RESOLVED element
# ------------------------------------------------------------------------------------------------

# Off the recorded outcome, never the authored attack: `ResolvedOutcome.elements` is post-insulation,
# so a hit the target shrugged off must wear no rail. Falsified by deleting the resolver's
# `outcome.elements` assignment, which leaves every rail neutral.
func test_the_rail_wears_the_element_that_reached_the_target() -> void:
	await _queue_elemental_attack(Elemental.Element.FIRE, [])
	var row := _attack_row()
	assert_object(row).is_not_null()

	var outcome := row.action.resolved_outcome()
	assert_object(outcome).is_not_null()
	assert_array(outcome.elements) \
		.override_failure_message("the resolve recorded no surviving elements, so the rail has nothing to read") \
		.is_not_empty()
	assert_that(row.rail.color).is_equal(
			QueueStyle.element_ink(outcome.elements[0]))


# A MOVE carries no element and must not borrow one.
func test_a_row_with_no_element_wears_the_neutral_rail() -> void:
	var walker := _spawn(Team.Faction.PLAYER, Vector2i(1, 2))
	var move := MoveAction.new()
	move.init(walker, [walker.movement.cell, walker.movement.cell + Vector2i(1, 0)], null)
	game.squad_manager.active_squad = walker.squad
	walker.squad._queue_action(move)
	game.refresh_action_queue(walker.squad)
	await await_idle_frame()

	var rows := _rows()
	assert_int(rows.size()).is_greater(0)
	assert_that(rows[0].rail.color).is_equal(QueueStyle.ink(QueueStyle.Role.RAIL_NEUTRAL))


# ------------------------------------------------------------------------------------------------
#  6. Colour coverage
# ------------------------------------------------------------------------------------------------

# A new element or state must not ship as a black chip. Pure statics, no scene needed.
func test_every_element_and_state_resolves_to_a_colour() -> void:
	for element: Elemental.Element in Elemental.Element.values():
		if element == Elemental.Element.NONE:
			continue
		assert_that(ElementPalette.color_for_element(element)) \
			.override_failure_message("%s falls through to the neutral rail — add it to ElementPalette"
				% Elemental.display_name(element)) \
			.is_not_equal(ElementPalette.NEUTRAL)
	for state: Elemental.State in Elemental.State.values():
		if state == Elemental.State.NONE:
			continue
		assert_that(ElementPalette.color_for_state(state)) \
			.override_failure_message("%s falls through to the neutral chip — add it to ElementPalette"
				% Elemental.state_display_name(state)) \
			.is_not_equal(ElementPalette.NEUTRAL)


# ------------------------------------------------------------------------------------------------
#  7. The row fits the panel it is drawn in
# ------------------------------------------------------------------------------------------------

# THE clipping guard, and the reason it is measured rather than eyeballed: the panel's width was
# chosen by arithmetic over the container chain, and arithmetic is exactly what goes stale when a
# slot is added. Driven with a 3-digit readout and a populated consequence line -- the widest row
# the panel can be asked to draw -- against the width its section actually leaves.
func test_the_widest_row_still_fits_inside_its_section() -> void:
	# Built imperatively, not with a ternary: a Variant ternary yields an untyped Array and the
	# typed assignment fails at RUNTIME (feedback_gdscript_ternary_inference).
	var combo := _first_combo()
	var states: Array[Elemental.State] = []
	var element := Elemental.Element.WATER
	if combo != null:
		states.append(combo.required_state)
		element = combo.incoming_element
	var attacker := await _queue_elemental_attack(element, states)
	# Push the readout to three digits on both sides, the widest form it has.
	var row := _attack_row()
	assert_object(row).is_not_null()
	row.readout.text = "100->128"
	await await_idle_frame()

	# MEASURED AGAINST THE DOCK, not the section. BackgroundPanel is anchored in the .tscn and is the
	# one width here that does not move; a section GROWS to whatever its row demands, so the earlier
	# form of this assertion could not fail (reported 2026-09-04).
	var dock: Control = game.squad_action_queue_control.background_panel
	assert_float(row.get_global_rect().end.x) \
		.override_failure_message("the widest row reaches %.0f and the dock ends at %.0f -- the panel's width no longer covers its slots"
			% [row.get_global_rect().end.x, dock.get_global_rect().end.x]) \
		.is_less_equal(dock.get_global_rect().end.x)
	assert_object(attacker).is_not_null()
