extends RefCounted
class_name CarvingRecipe

# A carving's recipe line, parsed: `Break(F, A) + Push(F2)` -> two steps, each a verb (Flourish.Type)
# and the substance ids its arguments resolve to (docs/design/deep-alchemy.md -> What is built).
# The verbs are the functions and the substances their arguments; a lone formula does nothing.
#
# Everything a rune, a channel check or a hit reads off a carving is DERIVED here, once per parse:
#   cost      -- how many verbs
#   demand    -- atoms summed across every argument (what the alchemist's aura pays)
#   delivered -- what the last delivering verb leaves at the target
#   fizzle    -- the first argument a cast is missing, given what is present (fizzle_reason)
#   drawn     -- which ambient substances it takes from the air (drawn_from), what Atmosphere scales
# Pure on its catalog (id -> Substance), passed in like AlchemyFormula's, so a test can hand it one.
#
# An argument may carry an AMOUNT, the equations' coefficient (#1328): `Push(3W2)` is a jet's worth of
# water. The air supplies one of what it holds, so a number means a real source in reach. The amount
# is read by the fizzle walk alone: demand ignores it (Phaazoid@, 2026-10-18), as do cost and damage.

class Step:
	var verb: Flourish.Type
	var args: Array[String] = []   # substance ids, resolved
	# How much of each argument the step works on: one for the step, written on both arguments of a
	# Break or Bind. What it makes, it makes at this amount.
	var amount := 1
	# What must be PRESENT for the step to work, resolved at parse: a Break's molecule (the bond it
	# splits), a Bind's two halves, every other verb's one argument.
	var needs: Array[String] = []
	# What the step makes, resolved at parse: a Bind's product, a Break's freed atoms and the pairs
	# lone atoms settle into. Empty for verbs that move or hold rather than make.
	var makes: Array[String] = []
	# What the step leaves at the target -- what a hit carries if this is the last step that leaves
	# anything. Push/Infuse/Focus/Spread send their substance; Bind its product; Break its halves,
	# lone atoms paired (F -> flame). Pull, Extract, Quicken and Still leave nothing there.
	var leaves: Array[String] = []


var steps: Array[Step] = []
var error := ""
var _demand: Dictionary[Elemental.Element, int] = {}
var _delivered: Array[String] = []
var _damage_elements: Array[Elemental.Element] = []
var _hit_elements: Array[Elemental.Element] = []

static var _term := RegEx.create_from_string("^([A-Za-z]+)\\s*\\(([^()]*)\\)$")


static func parse(text: String, catalog: Dictionary = {}) -> CarvingRecipe:
	var out := CarvingRecipe.new()
	if text.strip_edges() == "":
		out.error = "names no verbs"
		return out
	if catalog.is_empty():
		catalog = SubstanceCatalog.get_all()
	for raw: String in text.split("+"):
		var term := raw.strip_edges()
		var m := _term.search(term)
		if m == null:
			out.error = "'%s' is not a verb and its arguments" % term
			return out
		var verb := Flourish.from_name(m.get_string(1))
		if verb < 0:
			out.error = "'%s' is not a verb" % m.get_string(1)
			return out
		var step := Step.new()
		step.verb = verb as Flourish.Type
		var words := m.get_string(2).split(",", false)
		if words.size() != Flourish.arity(step.verb):
			out.error = "%s takes %d argument%s" % [
					Flourish.NAMES[step.verb], Flourish.arity(step.verb), "" if Flourish.arity(step.verb) == 1 else "s"]
			return out
		for i in words.size():
			var parsed := AlchemyFormula.parse_terms(words[i].strip_edges())
			if parsed["error"] != "":
				out.error = parsed["error"]
				return out
			var terms: Array[Dictionary] = parsed["terms"]
			var amount: int = terms[0]["coef"]
			if i > 0 and amount != step.amount:
				out.error = "%s takes the same amount of each argument" % Flourish.NAMES[step.verb]
				return out
			step.amount = amount
			var found := AlchemyFormula.resolve(terms[0]["token"], catalog)
			if found.error != "":
				out.error = found.error
				return out
			step.args.append(found.id)
		out.error = _resolve_makes(step, catalog)
		if out.error != "":
			return out
		out.steps.append(step)
	out._derive(catalog)
	return out


# A Bind must make a real molecule and a Break must split one; both answer what they leave behind.
static func _resolve_makes(step: Step, catalog: Dictionary) -> String:
	if step.verb != Flourish.Type.BREAK:
		step.needs = step.args.duplicate()
	if step.verb != Flourish.Type.BREAK and step.verb != Flourish.Type.BIND:
		match step.verb:
			Flourish.Type.PUSH, Flourish.Type.INFUSE, Flourish.Type.FOCUS, Flourish.Type.SPREAD:
				step.leaves = step.args.duplicate()
		return ""
	var joined := _molecule_with(_sum(step.args, catalog), catalog)
	if joined.error != "":
		var noun := "nothing to break" if step.verb == Flourish.Type.BREAK else "makes nothing real"
		return "%s(%s): %s (%s)" % [Flourish.NAMES[step.verb], ", ".join(step.args), noun, joined.error]
	if step.verb == Flourish.Type.BIND:
		step.makes.append(joined.id)
		step.leaves.append(joined.id)
		return ""
	step.needs.append(joined.id)
	for id: String in step.args:
		var paired := _paired(id, catalog)
		for made: String in [id, paired]:
			if made != "" and not step.makes.has(made):
				step.makes.append(made)
		var left := paired if paired != "" else id
		if not step.leaves.has(left):
			step.leaves.append(left)
	return ""


# A lone atom settles into its pair (F -> F2 flame); anything else stays as it is.
static func _paired(id: String, catalog: Dictionary) -> String:
	var atoms := AlchemyFormula.atoms_of(catalog.get(id) as Substance, catalog)
	if atoms.error != "" or atoms.counts.size() != 1:
		return ""
	var element: Elemental.Element = atoms.counts.keys()[0]
	if atoms.counts[element] != 1:
		return ""
	var doubled: Dictionary[Elemental.Element, int] = {element: 2}
	var found := _molecule_with(doubled, catalog)
	return found.id if found.error == "" else ""


static func _sum(ids: Array[String], catalog: Dictionary) -> Dictionary[Elemental.Element, int]:
	var total: Dictionary[Elemental.Element, int] = {}
	for id: String in ids:
		var atoms := AlchemyFormula.atoms_of(catalog.get(id) as Substance, catalog)
		for element: Elemental.Element in atoms.counts:
			total[element] = total.get(element, 0) + atoms.counts[element]
	return total


static func _molecule_with(counts: Dictionary[Elemental.Element, int], catalog: Dictionary) -> AlchemyFormula.Resolved:
	var token := ""
	for letter: String in AlchemyFormula.ORDER:
		var count: int = counts.get(AlchemyFormula.LETTERS[letter], 0)
		if count > 0:
			token += letter if count == 1 else "%s%d" % [letter, count]
	return AlchemyFormula.resolve(token, catalog)


func _derive(catalog: Dictionary) -> void:
	for step: Step in steps:
		for id: String in step.args:
			var atoms := AlchemyFormula.atoms_of(catalog.get(id) as Substance, catalog)
			for element: Elemental.Element in atoms.counts:
				_demand[element] = _demand.get(element, 0) + atoms.counts[element]
	for i in range(steps.size() - 1, -1, -1):
		if not steps[i].leaves.is_empty():
			_delivered = steps[i].leaves.duplicate()
			break
	for id: String in _delivered:
		var hit := SubstanceMap.element_carried_by(id)
		if hit != Elemental.Element.NONE and not _hit_elements.has(hit):
			_hit_elements.append(hit)
		var atoms := AlchemyFormula.atoms_of(catalog.get(id) as Substance, catalog)
		for element: Elemental.Element in atoms.counts:
			if not _damage_elements.has(element):
				_damage_elements.append(element)


func is_legal() -> bool:
	return error == ""


func verb_count() -> int:
	return steps.size()


# Atoms summed across every argument: `Break(F, A) + Push(F2)` asks Fire 3, Air 1.
func demand() -> Dictionary[Elemental.Element, int]:
	return _demand


func delivered() -> Array[String]:
	return _delivered


# The elements a hit scales its damage off: those in what it delivers, ONCE each.
func damage_elements() -> Array[Elemental.Element]:
	return _damage_elements


# What a hit carries into the combinatrix: each delivered substance read backwards through SubstanceMap.
func hit_elements() -> Array[Elemental.Element]:
	return _hit_elements


# Why a cast FIZZLES given how much of each substance is present (CellSubstances.available_near), or
# "" when every step finds what it needs. Walked in order over a working copy: a step that passes adds
# what it makes AT ITS OWN AMOUNT, so `Break(A, W) + Push(W2)` works anywhere -- the Break frees the
# water the Push needs -- while `Break(A, W) + Push(3W2)` does not: the air's one vapor makes one water.
# Nothing is used up, so `Focus(3W2) + Push(3W2)` needs three at each step, not six. The FIRST
# shortfall is named. Asked of a legal parse; an illegal one has no steps to miss.
func fizzle_reason(available: Dictionary[String, int], catalog: Dictionary = {}) -> String:
	var have: Dictionary[String, int] = {}
	have.assign(available)
	for step: Step in steps:
		for id: String in step.needs:
			if have.get(id, 0) < step.amount:
				if step.amount > 1:
					return "Fizzles: needs a source of %s nearby" % _named(id, catalog)
				return "Fizzles: needs %s nearby" % _named(id, catalog)
		for id: String in step.makes:
			have[id] = maxi(have.get(id, 0), step.amount)
	return ""


# Which of `ambient` the recipe takes from the AIR: every need that is ambient and that no earlier
# step made, once each. `Break(F, A) + Bind(Q, F)` draws vital air and aether; its heat comes from
# its own Break. Fizzle_reason's walk, asking where a need came from rather than whether it is there.
# A need of more than one is never the air's: the air holds one, so a real source supplied it.
func drawn_from(ambient: Array[String]) -> Array[String]:
	var made: Array[String] = []
	var drawn: Array[String] = []
	for step: Step in steps:
		for id: String in step.needs:
			if step.amount == 1 and ambient.has(id) and not made.has(id) and not drawn.has(id):
				drawn.append(id)
		for id: String in step.makes:
			if not made.has(id):
				made.append(id)
	return drawn


static func _named(id: String, catalog: Dictionary) -> String:
	if catalog.is_empty():
		catalog = SubstanceCatalog.get_all()
	var substance := catalog.get(id) as Substance
	if substance == null or substance.display_name == "":
		return id
	return substance.display_name.to_lower()
