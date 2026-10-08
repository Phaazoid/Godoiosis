extends Object
class_name AlchemyFormula

# Deep Alchemy's notation (docs/design/deep-alchemy.md): formulas, compounds and equations, read into
# counts of the five elements. Pure: a catalog of substances (id -> Substance) is passed in, never
# looked up, so a test can hand it a fake one.
#
# A formula TOKEN is upper-case letters, digits and `*` (`FW`, `QE*FE*WE`); anything else is a
# substance ID, i.e. a file name in Resources/Substances/. A formula token resolves to the ONE
# molecule with those atoms; two molecules sharing a formula (ice and water could) must be named by
# id. A compound is only ever named by id.

const LETTERS: Dictionary[String, Elemental.Element] = {
	"Q": Elemental.Element.AETHER,
	"F": Elemental.Element.FIRE,
	"A": Elemental.Element.AIR,
	"W": Elemental.Element.WATER,
	"E": Elemental.Element.EARTH,
}
const ORDER := "QFAWE"
const ARROW := "->"


class Atoms:
	var counts: Dictionary[Elemental.Element, int] = {}
	var error := ""


class Resolved:
	var id := ""
	var substance: Substance
	var error := ""


class Sum:
	var counts: Dictionary[Elemental.Element, int] = {}
	var ids: Array[String] = []
	var error := ""


static var _group := RegEx.create_from_string("^([QFAWE][0-9]*)+$")
static var _atom := RegEx.create_from_string("([QFAWE])([0-9]*)")
static var _token := RegEx.create_from_string("^[QFAWE][QFAWE0-9*]*$")
static var _term := RegEx.create_from_string("^([0-9]*)\\s*(\\S+)$")


static func is_formula_token(token: String) -> bool:
	return _token.search(token) != null


# A molecule's atoms. `QE*FE*WE` sums its parts.
static func molecule_atoms(formula: String) -> Atoms:
	var out := Atoms.new()
	var text := formula.strip_edges()
	if text == "":
		out.error = "empty formula"
		return out
	for raw: String in text.split("*"):
		var group := raw.strip_edges()
		if _group.search(group) == null:
			out.error = "'%s' is not a formula" % formula
			return out
		for m: RegExMatch in _atom.search_all(group):
			var element: Elemental.Element = LETTERS[m.get_string(1)]
			var count := 1 if m.get_string(2) == "" else int(m.get_string(2))
			if count < 1:
				out.error = "'%s' counts an element zero times" % formula
				return out
			out.counts[element] = out.counts.get(element, 0) + count
	return out


# Each `*` group lists its elements once each, in Q F A W E order: `FW`, never `WF` or `FFW`.
static func in_alchemical_order(formula: String) -> bool:
	for raw: String in formula.split("*"):
		var last := -1
		for m: RegExMatch in _atom.search_all(raw.strip_edges()):
			var at := ORDER.find(m.get_string(1))
			if at <= last:
				return false
			last = at
	return true


# `2FW + steam` -> [{coef: 2, token: "FW"}, {coef: 1, token: "steam"}]. Empty `terms` with no error
# never happens: an empty side is an error.
static func parse_terms(side: String) -> Dictionary:
	var terms: Array[Dictionary] = []
	if side.strip_edges() == "":
		return {"terms": terms, "error": "a side of the equation is empty"}
	for raw: String in side.split("+"):
		var part := raw.strip_edges()
		var m := _term.search(part)
		if m == null:
			return {"terms": terms, "error": "'%s' is not a term" % part}
		var coef := 1 if m.get_string(1) == "" else int(m.get_string(1))
		if coef < 1:
			return {"terms": terms, "error": "'%s' takes something zero times" % part}
		terms.append({"coef": coef, "token": m.get_string(2)})
	return {"terms": terms, "error": ""}


static func resolve(token: String, catalog: Dictionary) -> Resolved:
	var out := Resolved.new()
	if not is_formula_token(token):
		if catalog.has(token):
			out.id = token
			out.substance = catalog[token] as Substance
		else:
			out.error = "no substance has the id '%s'" % token
		return out
	var wanted := molecule_atoms(token)
	if wanted.error != "":
		out.error = wanted.error
		return out
	var matches: Array[String] = []
	for id: String in catalog:
		var substance := catalog[id] as Substance
		if substance == null or substance.is_compound():
			continue
		var atoms := molecule_atoms(substance.formula)
		if atoms.error == "" and atoms.counts == wanted.counts:
			matches.append(id)
	if matches.is_empty():
		out.error = "no substance has the formula %s" % token
	elif matches.size() > 1:
		matches.sort()
		out.error = "%s is the formula of %s; name one by id" % [token, ", ".join(matches)]
	else:
		out.id = matches[0]
		out.substance = catalog[out.id] as Substance
	return out


# A substance's atoms, a compound's summed through its parts.
static func atoms_of(substance: Substance, catalog: Dictionary, visiting: Array[String] = []) -> Atoms:
	if substance == null:
		var missing := Atoms.new()
		missing.error = "no substance"
		return missing
	if not substance.is_compound():
		return molecule_atoms(substance.formula)
	var side := _side(substance.formula, catalog, visiting)
	var out := Atoms.new()
	out.counts = side.counts
	out.error = side.error
	return out


# One side of an equation (or a compound's parts): its atoms and the ids it names.
static func side(text: String, catalog: Dictionary) -> Sum:
	var visiting: Array[String] = []
	return _side(text, catalog, visiting)


static func _side(text: String, catalog: Dictionary, visiting: Array[String]) -> Sum:
	var out := Sum.new()
	var parsed := parse_terms(text)
	if parsed["error"] != "":
		out.error = parsed["error"]
		return out
	var terms: Array[Dictionary] = parsed["terms"]
	for term: Dictionary in terms:
		var token: String = term["token"]
		var coef: int = term["coef"]
		var found := resolve(token, catalog)
		if found.error != "":
			out.error = found.error
			return out
		if visiting.has(found.id):
			out.error = "'%s' contains itself" % found.id
			return out
		var inner: Array[String] = visiting.duplicate()
		inner.append(found.id)
		var atoms := atoms_of(found.substance, catalog, inner)
		if atoms.error != "":
			out.error = "%s: %s" % [found.id, atoms.error]
			return out
		for element: Elemental.Element in atoms.counts:
			out.counts[element] = out.counts.get(element, 0) + coef * atoms.counts[element]
		out.ids.append(found.id)
	return out


# `F2 W2`, in alchemical order; "nothing" when empty.
static func format_atoms(counts: Dictionary[Elemental.Element, int]) -> String:
	var parts: Array[String] = []
	for letter: String in ORDER:
		var count: int = counts.get(LETTERS[letter], 0)
		if count > 0:
			parts.append(letter if count == 1 else "%s%d" % [letter, count])
	return " ".join(parts) if not parts.is_empty() else "nothing"
