extends Object
class_name ReactionLint

# "Does this reaction's chemistry hold?" (docs/design/deep-alchemy.md) -- asked of every shipped
# reaction and substance in CI (tests/dev/test_reaction_lint.gd). AttackLint's shape: one row per
# fault, {"severity": Severity, "text": String}, and empty is a result.
#
# BLOCKS: the books do not balance, or a term names nothing real.
# DEGRADES: the equation is about different stuff than the reaction it sits on -- the incoming
# element or a required state missing from the inputs, an added state or gas missing from the
# outputs. Read through SubstanceMap; an empty row is skipped, not faulted. A row naming several
# substances is satisfied by ANY one of them (dev ruling 2026-10-30, #1532): Burning is flame and
# heat, and an ignition that makes flame is about Burning.
#
# The other direction -- what an equation makes that its reaction does not do -- is the lint suite's
# to judge: unreleased_gases and unapplied_states.
#
# An EMPTY equation is not a fault here. The test's pending ledger owns which reactions may still
# lack one, so a missing equation is a declared gap rather than a quiet warning.
#
# `map` is what each thing is made of: the authored one unless a caller hands its own.

enum Severity { BLOCKS, DEGRADES }


static func check(reaction: Resource, catalog: Dictionary = {}, map: SubstanceMap = null) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if reaction == null:
		return found
	var equation: String = reaction.get("equation") if reaction.get("equation") != null else ""
	if equation.strip_edges() == "":
		return found
	if catalog.is_empty():
		catalog = SubstanceCatalog.get_all()
	if map == null:
		map = SubstanceMap.authored()
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
	for wanted: Dictionary in _expected_inputs(reaction, map):
		_check_named(found, inputs, wanted, "inputs")
	for wanted: Dictionary in _expected_outputs(reaction, map):
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


# {ids, what}: the substances the inputs must name one of, and the game thing they stand for.
static func _expected_inputs(reaction: Resource, map: SubstanceMap) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if reaction is ElementalReaction:
		var r := reaction as ElementalReaction
		_expect(out, _one(SubstanceMap.of_element(r.incoming_element)), "the incoming %s" % Elemental.display_name(r.incoming_element))
		_expect(out, map.of_state(r.required_state), "the required %s" % Elemental.state_display_name(r.required_state))
	elif reaction is TerrainReaction:
		var r := reaction as TerrainReaction
		_expect(out, _one(SubstanceMap.of_element(r.incoming_element)), "the incoming %s" % Elemental.display_name(r.incoming_element))
		_expect(out, map.of_kind(r.required_kind), "the %s ground" % Terrain.Kind.keys()[r.required_kind].capitalize())
		_expect(out, map.of_tile_state(r.required_tile_state), "the required %s" % Terrain.TileState.keys()[r.required_tile_state].capitalize())
	return out


static func _expected_outputs(reaction: Resource, map: SubstanceMap) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if reaction is ElementalReaction:
		var r := reaction as ElementalReaction
		for state: Elemental.State in r.add_states:
			_expect(out, map.of_state(state), "the added %s" % Elemental.state_display_name(state))
		_expect_gases(out, r.gases, map)
	elif reaction is TerrainReaction:
		var r := reaction as TerrainReaction
		for state: Terrain.TileState in r.add_tile_states:
			_expect(out, map.of_tile_state(state), "the added %s" % Terrain.TileState.keys()[state].capitalize())
		_expect_gases(out, r.gases, map)
	return out


# Every gas a reaction releases must be in its outputs, the added states' rule.
static func _expect_gases(out: Array[Dictionary], gases: Dictionary[Gas.Kind, Gas.Level], map: SubstanceMap) -> void:
	for kind: Gas.Kind in Gas.released(gases):
		_expect(out, map.of_gas(kind), "the released %s" % Gas.display_name(kind))


# The gases this reaction's equation MAKES that it does not release (#1329) -- what the lint suite's
# NOT_YET_FOLLOWED ledger has to list. A gas is made when the equation makes any of its substances.
static func unreleased_gases(reaction: Resource, catalog: Dictionary = {}, map: SubstanceMap = null) -> Array[Gas.Kind]:
	var missing: Array[Gas.Kind] = []
	if map == null:
		map = SubstanceMap.authored()
	var made := _made(reaction, catalog)
	for kind: Gas.Kind in Gas.Kind.values():
		if _any_in(map.of_gas(kind), made) and not _releases(reaction, kind):
			missing.append(kind)
	return missing


# The unit states a UNIT reaction's equation MAKES that it does not apply (#1423): what it leaves on
# the body, unreleased_gases' twin. A terrain reaction's products land on the ground, so it owes none.
# A substance the reaction releases as a gas is accounted for there (smoke is a gas and Smoked both).
static func unapplied_states(reaction: Resource, catalog: Dictionary = {}, map: SubstanceMap = null) -> Array[Elemental.State]:
	var missing: Array[Elemental.State] = []
	if not reaction is ElementalReaction:
		return missing
	if map == null:
		map = SubstanceMap.authored()
	var r := reaction as ElementalReaction
	var made := _made(r, catalog)
	for state: Elemental.State in Elemental.State.values():
		if r.add_states.has(state):
			continue
		for id: String in map.of_state(state):
			if made.has(id) and not _releases_substance(r, id, map):
				missing.append(state)
				break
	return missing


# The substance ids an equation MAKES: named in its outputs and not its inputs. An equation that will
# not parse makes nothing here; check() reports it.
static func _made(reaction: Resource, catalog: Dictionary) -> Array[String]:
	var made: Array[String] = []
	if reaction == null or reaction.get("equation") == null:
		return made
	var halves := String(reaction.get("equation")).split(AlchemyFormula.ARROW)
	if halves.size() != 2:
		return made
	if catalog.is_empty():
		catalog = SubstanceCatalog.get_all()
	var inputs := AlchemyFormula.side(halves[0], catalog)
	var outputs := AlchemyFormula.side(halves[1], catalog)
	if inputs.error != "" or outputs.error != "":
		return made
	for id: String in outputs.ids:
		if not inputs.ids.has(id) and not made.has(id):
			made.append(id)
	return made


static func _releases_substance(reaction: ElementalReaction, id: String, map: SubstanceMap) -> bool:
	for kind: Gas.Kind in Gas.released(reaction.gases):
		if map.of_gas(kind).has(id):
			return true
	return false


static func _releases(reaction: Resource, kind: Gas.Kind) -> bool:
	if reaction is ElementalReaction:
		return Gas.released((reaction as ElementalReaction).gases).has(kind)
	if reaction is TerrainReaction:
		return Gas.released((reaction as TerrainReaction).gases).has(kind)
	return false


static func _expect(out: Array[Dictionary], ids: Array[String], what: String) -> void:
	if not ids.is_empty():
		out.append({"ids": ids, "what": what})


static func _one(id: String) -> Array[String]:
	var ids: Array[String] = []
	if id != "":
		ids.append(id)
	return ids


static func _any_in(ids: Array[String], among: Array[String]) -> bool:
	for id: String in ids:
		if among.has(id):
			return true
	return false


static func _check_named(found: Array[Dictionary], half: AlchemyFormula.Sum, wanted: Dictionary, label: String) -> void:
	var ids: Array[String] = wanted["ids"]
	if not _any_in(ids, half.ids):
		_add(found, Severity.DEGRADES, "the %s never name %s, which %s is made of" % [label, " or ".join(ids), wanted["what"]])


static func _add(found: Array[Dictionary], severity: Severity, text: String) -> void:
	found.append({"severity": severity, "text": text})
