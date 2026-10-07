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
extends GdUnitTestSuite

const PENDING := {
	"res://Resources/TerrainReactions/Melt.tres": "what ice is made of (codev)",
	"res://Resources/TerrainReactions/Frozen.tres": "what ice is made of (codev)",
	"res://Resources/Reactions/ice_sets_chilled.tres": "what ice and cold are (codev)",
	"res://Resources/Reactions/ice_wet_deep_chill.tres": "what ice and cold are (codev)",
	"res://Resources/Reactions/fire_chilled_temp_shock.tres": "what cold is (codev)",
	"res://Resources/TerrainReactions/Burning.tres": "organic matter's proportions (codev)",
	"res://Resources/TerrainReactions/GrassIgnites.tres": "organic matter's proportions (codev)",
	"res://Resources/TerrainReactions/TallGrassIgnites.tres": "organic matter's proportions (codev)",
	"res://Resources/Reactions/shock_wet_electrocute.tres": "what lightning through water makes (codev)",
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


func test_a_pending_map_entry_is_skipped_rather_than_faulted() -> void:
	# ICE has no substance yet, so an ICE reaction cannot be held to naming one.
	assert_array(ReactionLint.check(_elemental("W2 -> W2", Elemental.Element.ICE), _catalog())).is_empty()


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
