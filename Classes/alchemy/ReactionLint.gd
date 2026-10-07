extends Object
class_name ReactionLint

# "Does this reaction's chemistry hold?" (docs/design/deep-alchemy.md) -- asked of every shipped
# reaction and substance in CI (tests/dev/test_reaction_lint.gd). AttackLint's shape: one row per
# fault, {"severity": Severity, "text": String}, and empty is a result.
#
# BLOCKS: the books do not balance, or a term names nothing real.
# DEGRADES: the equation is about different stuff than the reaction it sits on -- the incoming
# element or a required state missing from the inputs, an added state or gas missing from the
# outputs. Read through SubstanceMap; a PENDING or NONE entry is skipped, not faulted.
#
# An EMPTY equation is not a fault here. The test's pending ledger owns which reactions may still
# lack one, so a missing equation is a declared gap rather than a quiet warning.

enum Severity { BLOCKS, DEGRADES }


static func check(reaction: Resource, catalog: Dictionary = {}) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if reaction == null:
		return found
	var equation: String = reaction.get("equation") if reaction.get("equation") != null else ""
	if equation.strip_edges() == "":
		return found
	if catalog.is_empty():
		catalog = SubstanceCatalog.get_all()
	var halves := equation.split(AlchemyFormula.ARROW)
	if halves.size() != 2:
		_add(found, Severity.BLOCKS, "'%s' needs exactly one %s" % [equation, AlchemyFormula.ARROW])
		return found
	var inputs := AlchemyFormula.side(halves[0], catalog)
	var outputs := AlchemyFormula.side(halves[1], catalog)
	for half: AlchemyFormula.Sum in [inputs, outputs]:
		if half.error != "":
			_add(found, Severity.BLOCKS, half.error)
	if not found.is_empty():
		return found
	if inputs.counts != outputs.counts:
		_add(found, Severity.BLOCKS, "unbalanced: the inputs hold %s, the outputs %s" % [
				AlchemyFormula.format_atoms(inputs.counts), AlchemyFormula.format_atoms(outputs.counts)])
	for wanted: Dictionary in _expected_inputs(reaction):
		_check_named(found, inputs, wanted, "inputs")
	for wanted: Dictionary in _expected_outputs(reaction):
		_check_named(found, outputs, wanted, "outputs")
	return found


static func check_substance(substance: Substance, catalog: Dictionary = {}) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if substance == null:
		return found
	if catalog.is_empty():
		catalog = SubstanceCatalog.get_all()
	if substance.formula.strip_edges() == "":
		_add(found, Severity.BLOCKS, "no formula")
		return found
	var atoms := AlchemyFormula.atoms_of(substance, catalog)
	if atoms.error != "":
		_add(found, Severity.BLOCKS, atoms.error)
		return found
	if not substance.is_compound() and not AlchemyFormula.in_alchemical_order(substance.formula):
		_add(found, Severity.DEGRADES, "%s is not written in Q F A W E order" % substance.formula)
	return found


# {id, what}: a substance the inputs must name, and the game thing it stands for.
static func _expected_inputs(reaction: Resource) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if reaction is ElementalReaction:
		var r := reaction as ElementalReaction
		_expect(out, SubstanceMap.of_element(r.incoming_element), "the incoming %s" % Elemental.display_name(r.incoming_element))
		_expect(out, SubstanceMap.of_state(r.required_state), "the required %s" % Elemental.state_display_name(r.required_state))
	elif reaction is TerrainReaction:
		var r := reaction as TerrainReaction
		_expect(out, SubstanceMap.of_element(r.incoming_element), "the incoming %s" % Elemental.display_name(r.incoming_element))
		_expect(out, SubstanceMap.of_kind(r.required_kind), "the %s ground" % Terrain.Kind.keys()[r.required_kind].capitalize())
		_expect(out, SubstanceMap.of_tile_state(r.required_tile_state), "the required %s" % Terrain.TileState.keys()[r.required_tile_state].capitalize())
	return out


static func _expected_outputs(reaction: Resource) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if reaction is ElementalReaction:
		var r := reaction as ElementalReaction
		for state: Elemental.State in r.add_states:
			_expect(out, SubstanceMap.of_state(state), "the added %s" % Elemental.state_display_name(state))
	elif reaction is TerrainReaction:
		var r := reaction as TerrainReaction
		for state: Terrain.TileState in r.add_tile_states:
			_expect(out, SubstanceMap.of_tile_state(state), "the added %s" % Terrain.TileState.keys()[state].capitalize())
		if r.gas_level != Gas.Level.NONE:
			_expect(out, SubstanceMap.of_gas(r.gas), "the released %s" % Gas.display_name(r.gas))
	return out


static func _expect(out: Array[Dictionary], id: String, what: String) -> void:
	if id != "":
		out.append({"id": id, "what": what})


static func _check_named(found: Array[Dictionary], half: AlchemyFormula.Sum, wanted: Dictionary, label: String) -> void:
	var id: String = wanted["id"]
	if not half.ids.has(id):
		_add(found, Severity.DEGRADES, "the %s never name %s, which %s is made of" % [label, id, wanted["what"]])


static func _add(found: Array[Dictionary], severity: Severity, text: String) -> void:
	found.append({"severity": severity, "text": text})
