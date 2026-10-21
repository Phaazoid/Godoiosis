# "Does this reaction's chemistry hold?" -- ReactionLint (Deep Alchemy phase 1), AttackLint's shape.
#
# The teeth cases build their own reactions and catalogs, so they answer whether the LINT works; the
# sweep then asks every shipped reaction. A sweep alone passes happily against a lint that finds
# nothing, which is why the split.
#
# The PENDING ledger is the one place a shipped reaction may lack an equation, each line saying what
# it waits on. It only shrinks honestly: a listed reaction that gains an equation reds the sweep until
# its line goes, and a line naming a file that is gone reds too. A NEW reaction with no equation reds
# until it gets one or a line here.
#
# NOT_YET_FOLLOWED is codev's list (#claude-sessions, 2026-10-08) of what an equation says that the game
# does not do yet, to work through one by one or all together later. Each line names a reaction that
# exists and has an equation, and no reaction is both pending and listed. Its GAS half is checked
# (#1329): a gas an equation makes that its reaction does not release reds until it is released or
# listed here.
extends GdUnitTestSuite

const PENDING := {}

const NOT_YET_FOLLOWED := {
	"res://Resources/TerrainReactions/Melt.tres": "the heat is not released (the essence is, #1324)",
	"res://Resources/Reactions/fire_chilled_temp_shock.tres": "the heat is not released and the meltwater does not wet the unit (the essence is, #1324); the +5 is the temperature change, not chemistry (Phaazoid)",
	"res://Resources/TerrainReactions/Burning.tres": "the steam and smoke are not released",
	"res://Resources/TerrainReactions/GrassIgnites.tres": "the steam and smoke are not released",
	"res://Resources/TerrainReactions/TallGrassIgnites.tres": "the smoke is not released",
	"res://Resources/Reactions/shock_wet_electrocute.tres": "the thunder, ozone and heat are not made",
}


func _sub(formula: String) -> Substance:
	var s := Substance.new()
	s.formula = formula
	return s


# Ids the real SubstanceMap names, so the consistency rule has something to find.
func _catalog() -> Dictionary:
	return {"flame": _sub("F2"), "water": _sub("W2"), "steam": _sub("FW")}


func _elemental(equation: String, element := Elemental.Element.NONE) -> ElementalReaction:
	var r := ElementalReaction.new()
	r.incoming_element = element
	r.equation = equation
	return r


func _severities(findings: Array[Dictionary]) -> Array[int]:
	var out: Array[int] = []
	for f: Dictionary in findings:
		out.append(int(f["severity"]))
	return out


func test_a_balanced_equation_is_clean() -> void:
	assert_array(ReactionLint.check(_elemental("F2 + W2 -> 2FW"), _catalog())).is_empty()


func test_an_unbalanced_equation_blocks_and_shows_both_sides() -> void:
	var found := ReactionLint.check(_elemental("F2 + W2 -> FW"), _catalog())
	assert_array(_severities(found)).contains([ReactionLint.Severity.BLOCKS])
	var text: String = found[0]["text"]
	assert_str(text).contains("unbalanced")
	assert_str(text).contains("F2 W2")
	assert_str(text).contains("F W")


func test_an_empty_equation_is_left_to_the_ledger() -> void:
	assert_array(ReactionLint.check(_elemental(""), _catalog())).is_empty()
	assert_array(ReactionLint.check(null, _catalog())).is_empty()


func test_an_equation_needs_exactly_one_arrow() -> void:
	for equation: String in ["F2 + W2", "F2 -> W2 -> FW"]:
		var found := ReactionLint.check(_elemental(equation), _catalog())
		assert_array(_severities(found)).contains([ReactionLint.Severity.BLOCKS])


func test_a_term_naming_nothing_blocks() -> void:
	var found := ReactionLint.check(_elemental("F2 + phlogiston -> 2FW"), _catalog())
	assert_array(_severities(found)).contains([ReactionLint.Severity.BLOCKS])
	assert_str(found[0]["text"]).contains("phlogiston")


func test_inputs_that_leave_out_the_incoming_element_degrade() -> void:
	# A FIRE reaction whose equation never mentions flame is about some other reaction.
	var found := ReactionLint.check(_elemental("W2 -> W2", Elemental.Element.FIRE), _catalog())
	assert_array(_severities(found)).is_equal([ReactionLint.Severity.DEGRADES])
	assert_str(found[0]["text"]).contains("flame")


func test_outputs_that_leave_out_the_released_gas_degrade() -> void:
	var r := TerrainReaction.new()
	r.incoming_element = Elemental.Element.FIRE
	r.gas = Gas.Kind.STEAM
	r.gas_level = Gas.Level.MEDIUM
	r.equation = "F2 + W2 -> F2 + W2"
	var found := ReactionLint.check(r, _catalog())
	assert_array(_severities(found)).is_equal([ReactionLint.Severity.DEGRADES])
	assert_str(found[0]["text"]).contains("steam")


func test_a_unit_reaction_whose_released_gas_is_missing_from_the_outputs_degrades() -> void:
	var r := _elemental("F2 + W2 -> F2 + W2", Elemental.Element.FIRE)
	r.gas_level = Gas.Level.THIN
	var found := ReactionLint.check(r, _catalog())
	assert_array(_severities(found)).is_equal([ReactionLint.Severity.DEGRADES])
	assert_str(found[0]["text"]).contains("steam")


# Made = named in the outputs and not the inputs; released = that kind at a level above NONE. A
# reaction releasing the WRONG gas still owes the one its equation makes.
func test_a_gas_the_equation_makes_is_unreleased_until_the_reaction_releases_it() -> void:
	var made: Array[Gas.Kind] = [Gas.Kind.STEAM]
	var r := _elemental("F2 + W2 -> 2FW", Elemental.Element.FIRE)
	assert_array(ReactionLint.unreleased_gases(r, _catalog())).is_equal(made)
	r.gas = Gas.Kind.SMOKE
	r.gas_level = Gas.Level.THIN
	assert_array(ReactionLint.unreleased_gases(r, _catalog())).is_equal(made)
	r.gas = Gas.Kind.STEAM
	assert_array(ReactionLint.unreleased_gases(r, _catalog())).is_empty()

	var t := TerrainReaction.new()
	t.equation = "F2 + W2 -> 2FW"
	assert_array(ReactionLint.unreleased_gases(t, _catalog())).is_equal(made)
	t.gas_level = Gas.Level.MEDIUM
	assert_array(ReactionLint.unreleased_gases(t, _catalog())).is_empty()


func test_a_gas_on_both_sides_is_not_made() -> void:
	var r := _elemental("FW + W2 -> FW + W2", Elemental.Element.WATER)
	assert_array(ReactionLint.unreleased_gases(r, _catalog())).is_empty()


func test_a_map_entry_with_no_substance_is_skipped_rather_than_faulted() -> void:
	# COVER is a shape dug in the ground (a NONE line), so a reaction on it cannot be held to naming one.
	var r := TerrainReaction.new()
	r.required_tile_state = Terrain.TileState.COVER
	r.equation = "W2 -> W2"
	assert_array(ReactionLint.check(r, _catalog())).is_empty()


func _shipped() -> Array[Resource]:
	ReactionCatalog.refresh()
	TerrainReactionCatalog.refresh()
	var all: Array[Resource] = []
	all.append_array(ReactionCatalog.get_all())
	all.append_array(TerrainReactionCatalog.get_all())
	return all


func test_every_shipped_reaction_balances_or_is_declared_pending() -> void:
	var reactions := _shipped()
	assert_bool(reactions.is_empty()).override_failure_message(
			"no reactions scanned -- the scan is broken, not the content").is_false()
	var broken: Array[String] = []
	for reaction: Resource in reactions:
		var path := reaction.resource_path
		var equation: String = reaction.get("equation")
		if PENDING.has(path):
			if equation.strip_edges() != "":
				broken.append("%s now has an equation: take it off PENDING" % path)
			continue
		if equation.strip_edges() == "":
			broken.append("%s has no equation: write one, or add it to PENDING with what it waits on" % path)
			continue
		for finding: Dictionary in ReactionLint.check(reaction):
			broken.append("%s: %s" % [path, finding["text"]])
	assert_array(broken).is_empty()


func test_every_pending_line_names_a_reaction_that_exists() -> void:
	var paths: Array[String] = []
	for reaction: Resource in _shipped():
		paths.append(reaction.resource_path)
	var stale: Array[String] = []
	for path: String in PENDING:
		if not paths.has(path):
			stale.append(path)
	assert_array(stale).is_empty()


func test_every_not_yet_followed_line_names_a_reaction_with_an_equation() -> void:
	var equations := {}
	for reaction: Resource in _shipped():
		equations[reaction.resource_path] = String(reaction.get("equation")).strip_edges()
	var stale: Array[String] = []
	for path: String in NOT_YET_FOLLOWED:
		if not equations.has(path):
			stale.append("%s is listed but no such reaction exists" % path)
		elif equations[path] == "":
			stale.append("%s is listed but has no equation for the game to follow" % path)
		if PENDING.has(path):
			stale.append("%s is both pending and listed" % path)
	assert_array(stale).is_empty()


# The ledger's gas half, checked rather than trusted: a line cannot come off while its gas still stays
# in the equation alone.
func test_every_gas_an_equation_makes_is_released_or_on_the_ledger() -> void:
	var unlisted: Array[String] = []
	for reaction: Resource in _shipped():
		var path := reaction.resource_path
		if NOT_YET_FOLLOWED.has(path) or PENDING.has(path):
			continue
		for kind: Gas.Kind in ReactionLint.unreleased_gases(reaction):
			unlisted.append("%s makes %s and does not release it: release it, or say so on NOT_YET_FOLLOWED" % [
					path, Gas.display_name(kind)])
	assert_array(unlisted).is_empty()
