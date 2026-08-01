# ArmorCatalog (#65) and the authored roster in Resources/Armor/.
#
# POLICY (rewritten 2026-08-01, suite audit): this suite asserts the MODEL, never the tuning. Every
# threshold, DEF term and tax it reasons about is read out of the resource under test, so retuning a
# piece -- which is meant to be cheap and frequent -- costs zero test edits. The previous version
# hard-coded the balance table (the CON 8 gate, def_power 3, DEX -1, expected DEF of 6/2/4), which
# turned a balance pass into a test-fixing pass. It was also the tree's largest violation of
# tests/README's own rule 4 ("Build content ad hoc -- never load a .tres"), and it disagreed with
# the weapon suites next door, which correctly reference MAGAZINE_SIZE / MAX_CHARGE / REV_DURATION.
#
# That leaves this suite three jobs, none of which an ad-hoc suite can do:
#   * the SCAN itself -- disk -> name-keyed map -- including its keying rule;
#   * a COVERAGE tripwire: the authored roster must keep exercising every axis of ArmorData, so no
#     half of the model can quietly become dead content that nothing on disk uses;
#   * the gate and DEF-composition RULES, driven generically over whatever is authored, so a new
#     piece is covered the day it lands rather than when someone remembers to add a case.
#
# Deliberately NOT here: the equip surface and the wear-gate chokepoint (tests/items/
# test_armor_equip.gd, on ad-hoc armor) and elemental immunity (tests/elemental/test_insulation.gd,
# which owns Unit.is_immune_to end to end). This suite is the catalog and the content in it.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

const ENEMY := Team.Faction.ENEMY

# Spread used to prove the CON term is actually wired. Wide enough that the 0.2 factor plus
# rounding still separates the two readings at def_power 1, the weakest authorable scaled piece.
const CON_SPREAD := 10

var _cell_seq := 0


func _armors() -> Dictionary:
	return ArmorCatalog.get_editable()


# A distinct cell per spawn: nothing here reads the board, but two units on one tile is a
# confusing fixture to inherit.
func _next_cell() -> Vector2i:
	_cell_seq += 1
	return Vector2i(_cell_seq, 0)


# A unit whose BODY satisfies every gate `piece` declares, with `stat` then forced to `value`.
# Gates read get_body_stat (never gear), so seeding base stats is the whole story.
func _wearer_for(piece: ArmorData, stat: Stats.Stat, value: int) -> Unit:
	var overrides: Dictionary = {}
	for gated: Stats.Stat in piece.stat_minimums:
		overrides[gated] = piece.stat_minimums[gated]
	for gated: Stats.Stat in piece.stat_maximums:
		overrides[gated] = piece.stat_maximums[gated]
	overrides[stat] = value
	return H.spawn_unit(self, ENEMY, _next_cell(), overrides, false)


# A wearer with a given CON and nothing else specified. Used by the DEF-math cases, which set
# worn_armor DIRECTLY on purpose: the arithmetic must be checkable on a body that could not
# legally wear the piece (CON 0 against a CON-gated plate). The gate-at-the-chokepoint contract
# belongs to test_armor_equip.gd; mixing the two here would make neither provable.
func _body_with_con(con: int) -> Unit:
	return H.spawn_unit(self, ENEMY, _next_cell(), {Stats.Stat.CON: con}, false)


# --- the scan ---

func test_the_catalog_is_populated() -> void:
	# Vacuity guard. Every loop below iterates the catalog, so an empty scan would turn this whole
	# file green while pinning nothing -- exactly the failure a coverage suite must not have.
	assert_dict(_armors()).override_failure_message(
		"ArmorCatalog scanned nothing -- every roster and rule case in this file is now vacuous."
		).is_not_empty()


func test_every_entry_is_armor_data() -> void:
	var armors := _armors()
	for name: String in armors:
		assert_object(armors[name]).is_instanceof(ArmorData)


func test_entries_are_keyed_by_item_name() -> void:
	# The catalog's keying rule, and the reason a piece can be renamed without breaking this suite:
	# the key IS the authored item_name (filename only as a fallback for unnamed content).
	var armors := _armors()
	for name: String in armors:
		var piece: ArmorData = armors[name]
		if piece.item_name != "":
			assert_str(name).is_equal(piece.item_name)


func test_get_variants_returns_a_map_rather_than_null() -> void:
	# Mirrors WeaponCatalog._scan's guard: a fresh checkout with no armor authored yet must read as
	# "nothing yet". This can only check the shape -- the missing-directory branch itself is not
	# reachable while Resources/Armor/ exists.
	assert_dict(ArmorCatalog.get_variants()).is_not_null()


# --- coverage: the authored roster must keep exercising every axis of the model ---
#
# These name no piece and assert no number. They fail when the CONTENT stops covering a half of
# ArmorData, which is the real signal -- "nothing on disk gates on a maximum any more" is worth
# knowing; "Ballast Harness was renamed" is not.

func test_roster_covers_both_gate_directions() -> void:
	var armors := _armors()
	var has_minimum := false
	var has_maximum := false
	for name: String in armors:
		var piece: ArmorData = armors[name]
		has_minimum = has_minimum or not piece.stat_minimums.is_empty()
		has_maximum = has_maximum or not piece.stat_maximums.is_empty()

	assert_bool(has_minimum).override_failure_message(
		"No authored armor declares a stat_minimums floor -- the min-gate half of can_equip has no content behind it."
		).is_true()
	assert_bool(has_maximum).override_failure_message(
		"No authored armor declares a stat_maximums ceiling -- the inverted gate (bulky rigs only a slow unit can wear) is now untested by content."
		).is_true()


func test_roster_covers_a_live_stat_tax() -> void:
	var armors := _armors()
	var taxes := false
	for name: String in armors:
		var piece: ArmorData = armors[name]
		taxes = taxes or not piece.stat_modifiers.is_empty()
	assert_bool(taxes).override_failure_message(
		"No authored armor carries stat_modifiers -- the gear stage of the effective-stat chain has no content exercising it."
		).is_true()


func test_roster_covers_a_piece_whose_value_is_not_def() -> void:
	# The Weave shape: pays zero DEF and earns its slot some other way. If every piece paid DEF,
	# nothing on disk would prove a 0-DEF piece is still worth wearing (or renders sanely).
	var armors := _armors()
	var pays_nothing_but_grants := false
	for name: String in armors:
		var piece: ArmorData = armors[name]
		if piece.def_power == 0 and piece.flat_def == 0 and not piece.granted_abilities.is_empty():
			pays_nothing_but_grants = true
	assert_bool(pays_nothing_but_grants).override_failure_message(
		"No authored armor pays zero DEF while granting an ability -- gear-as-a-capability has no content behind it."
		).is_true()


func test_roster_covers_a_scaled_plus_flat_piece() -> void:
	# Both DEF terms on one piece is the only content shape that can catch the two being conflated.
	var armors := _armors()
	var composed := false
	for name: String in armors:
		var piece: ArmorData = armors[name]
		if piece.def_power > 0 and piece.flat_def > 0:
			composed = true
	assert_bool(composed).override_failure_message(
		"No authored armor carries BOTH def_power and flat_def -- nothing on disk distinguishes the scaled term from the un-scaled one."
		).is_true()


# --- the gate rule, at each piece's OWN threshold ---

func test_every_minimum_gate_admits_at_its_threshold_and_refuses_below() -> void:
	var armors := _armors()
	var checked := 0
	for name: String in armors:
		var piece: ArmorData = armors[name]
		for stat: Stats.Stat in piece.stat_minimums:
			var floor_value: int = piece.stat_minimums[stat]
			if floor_value <= 0:
				continue   # a floor of 0 gates nothing; there is no "below" to test
			checked += 1
			var stat_name: String = Stats.Stat.keys()[stat]
			assert_bool(piece.can_equip(_wearer_for(piece, stat, floor_value))) \
				.override_failure_message("%s must admit a wearer at exactly %s %d" % [name, stat_name, floor_value]) \
				.is_true()
			assert_bool(piece.can_equip(_wearer_for(piece, stat, floor_value - 1))) \
				.override_failure_message("%s must refuse a wearer one short of %s %d" % [name, stat_name, floor_value]) \
				.is_false()
	assert_int(checked).is_greater(0)


func test_every_maximum_gate_admits_at_its_ceiling_and_refuses_above() -> void:
	var armors := _armors()
	var checked := 0
	for name: String in armors:
		var piece: ArmorData = armors[name]
		for stat: Stats.Stat in piece.stat_maximums:
			var ceiling: int = piece.stat_maximums[stat]
			checked += 1
			var stat_name: String = Stats.Stat.keys()[stat]
			assert_bool(piece.can_equip(_wearer_for(piece, stat, ceiling))) \
				.override_failure_message("%s must admit a wearer at exactly %s %d" % [name, stat_name, ceiling]) \
				.is_true()
			assert_bool(piece.can_equip(_wearer_for(piece, stat, ceiling + 1))) \
				.override_failure_message("%s must refuse a wearer one over %s %d" % [name, stat_name, ceiling]) \
				.is_false()
	assert_int(checked).is_greater(0)


func test_an_ungated_piece_admits_any_body() -> void:
	# The Riveted Mail shape: the tradeoff IS the cost, so there is nothing to qualify for.
	var armors := _armors()
	var checked := 0
	for name: String in armors:
		var piece: ArmorData = armors[name]
		if not piece.stat_minimums.is_empty() or not piece.stat_maximums.is_empty():
			continue
		checked += 1
		var extreme: Unit = H.spawn_unit(self, ENEMY, _next_cell(),
			{Stats.Stat.CON: 0, Stats.Stat.DEX: 99}, false)
		assert_bool(piece.can_equip(extreme)) \
			.override_failure_message("%s declares no gate, so it must admit any body" % name) \
			.is_true()
	assert_int(checked).is_greater(0)


# --- DEF composition, as properties rather than numbers ---
#
# None of these re-derive Stats.armor_def: an assertion against that static would pass even if the
# formula returned a constant. They pin the doctrine instead (stats.md: DEF is gear-only, the
# scaled term has NO base, the flat term is un-scaled), all of which survives any retune.

func test_a_naked_unit_has_no_def_however_strong() -> void:
	assert_int(_body_with_con(CON_SPREAD).get_effective_def()).is_equal(0)


func test_at_zero_con_a_piece_pays_exactly_its_flat_term() -> void:
	# Both halves of the doctrine in one assertion: the scaled term is a multiplier with no base
	# (so it vanishes at CON 0), and flat_def rides on top un-scaled (so it survives).
	var armors := _armors()
	for name: String in armors:
		var piece: ArmorData = armors[name]
		var wearer := _body_with_con(0)
		wearer.worn_armor = piece
		assert_int(wearer.get_effective_stat(Stats.Stat.CON)) \
			.override_failure_message("%s moves the wearer's CON, so it cannot measure the CON-0 case -- give this piece its own case" % name) \
			.is_equal(0)
		assert_int(wearer.get_effective_def()) \
			.override_failure_message("%s at CON 0 must pay its flat term and nothing else" % name) \
			.is_equal(piece.flat_def)


func test_a_scaled_piece_pays_more_on_a_stronger_body() -> void:
	# Proves def_power is actually multiplied by the wearer's CON rather than printed flat.
	var armors := _armors()
	var checked := 0
	for name: String in armors:
		var piece: ArmorData = armors[name]
		if piece.def_power <= 0:
			continue
		checked += 1
		var weak := _body_with_con(0)
		var strong := _body_with_con(CON_SPREAD)
		weak.worn_armor = piece
		strong.worn_armor = piece
		assert_int(strong.get_effective_def()) \
			.override_failure_message("%s carries def_power, so a higher-CON body must get more out of it" % name) \
			.is_greater(weak.get_effective_def())
	assert_int(checked).is_greater(0)


func test_a_piece_with_no_def_terms_never_pays_def() -> void:
	var armors := _armors()
	var checked := 0
	for name: String in armors:
		var piece: ArmorData = armors[name]
		if piece.def_power != 0 or piece.flat_def != 0:
			continue
		checked += 1
		var wearer := _body_with_con(CON_SPREAD)
		wearer.worn_armor = piece
		assert_int(wearer.get_effective_def()) \
			.override_failure_message("%s authors no DEF terms, so no CON may conjure DEF out of it" % name) \
			.is_equal(0)
	assert_int(checked).is_greater(0)


# --- mechanical_text: says what applies, omits what doesn't (#44) ---

func test_mechanical_text_states_a_gate_only_when_one_exists() -> void:
	var armors := _armors()
	for name: String in armors:
		var piece: ArmorData = armors[name]
		var text := piece.mechanical_text(_wearer_for(piece, Stats.Stat.CON, 5))
		var gated: bool = not piece.stat_minimums.is_empty() or not piece.stat_maximums.is_empty()
		if gated:
			assert_str(text).override_failure_message(
				"%s is gated but its readout never says so -- the player cannot tell why they can't wear it" % name
				).contains("Requires:")
		else:
			assert_str(text).override_failure_message(
				"%s declares no gate, so its readout must not carry an empty Requires line" % name
				).not_contains("Requires:")


func test_mechanical_text_states_a_tax_only_when_one_exists() -> void:
	var armors := _armors()
	for name: String in armors:
		var piece: ArmorData = armors[name]
		var text := piece.mechanical_text(_wearer_for(piece, Stats.Stat.CON, 5))
		if piece.stat_modifiers.is_empty():
			assert_str(text).not_contains("While worn:")
		else:
			assert_str(text).override_failure_message(
				"%s taxes a stat but its readout hides it -- the cost has to be visible before you put it on" % name
				).contains("While worn:")


func test_mechanical_text_names_grants_only_when_they_exist() -> void:
	# The zero-DEF piece's whole value lives here: without this line it reads as strictly worthless.
	var armors := _armors()
	for name: String in armors:
		var piece: ArmorData = armors[name]
		var text := piece.mechanical_text(_wearer_for(piece, Stats.Stat.CON, 5))
		if piece.granted_abilities.is_empty():
			assert_str(text).not_contains("Grants:")
		else:
			assert_str(text).override_failure_message(
				"%s grants an ability but its readout never names it" % name
				).contains("Grants:")


func test_mechanical_text_previews_the_def_the_wearer_would_actually_get() -> void:
	# "DEF 6" is meaningless without saying 6 for WHOM, and worse than meaningless if it's wrong:
	# the equip readout is a PREVIEW, so its number must be the DEF the unit ends up with once the
	# piece is on. Checked on two bodies because the scaled term rides CON.
	#
	# Scope, stated honestly: mechanical_text and get_effective_def both route through
	# Stats.armor_def, so this cannot catch a broken FORMULA -- that is
	# test_a_scaled_piece_pays_more_on_a_stronger_body's job, and it was written after an earlier
	# draft of this case passed a mutation that stripped CON out of armor_def entirely (the printed
	# CON made the strings differ even though the totals no longer did). What this DOES catch is the
	# two call sites drifting: the readout reaching for the wrong piece's fields, printing a stale
	# total, or reading body CON where the DEF seam reads effective CON.
	var armors := _armors()
	var checked := 0
	for name: String in armors:
		var piece: ArmorData = armors[name]
		for con: int in [0, CON_SPREAD]:
			checked += 1
			var wearer := _body_with_con(con)
			wearer.worn_armor = piece
			assert_str(piece.mechanical_text(wearer)) \
				.override_failure_message(
					"%s's readout disagrees with the DEF its wearer actually gets (%d) at CON %d"
					% [name, wearer.get_effective_def(), con]) \
				.contains("DEF %d" % wearer.get_effective_def())
	assert_int(checked).is_greater(0)
