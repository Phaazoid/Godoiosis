extends Object
class_name AttackLint

# "Can this authored attack actually be fired?" -- the one answer to that (#473), asked by the
# Attack Editor before it writes a file and again in CI over every shipped attack
# (tests/dev/test_attack_lint.gd). BoardLint's shape, and its discipline: BORROW the rule rather
# than restate one.
#
# The verdict comes from Reach, never from the pattern's own numbers, and that is the whole design.
# Reach carries the bare-fists fallback, so a pattern-less attack reads as fireable at adjacency
# instead of being flagged. The rule is "an attack must be able to select at least one cell", NOT
# "min must not exceed max" -- the second is one way to break the first. Its twin since #803 is
# "and land on at least one": a stamp can be empty while the ring is not.
#
# Both faults are AUTHORING mistakes and both are entirely silent, which is why they need a lint at
# all. An impossible range pair simply selects nothing, so the attack stops showing any range in
# game with no error anywhere -- the dev hit it on the Carbine's main and again on a fresh library
# attack, and could not tell which of the two boxes he had typed into.
#
# `carriers_of` sits here rather than on a catalog because it answers the second half of the same
# question: an attack nobody carries cannot be fired either, however good its geometry is. That was
# #473's part 1 -- the library had exactly one reader in the project and it was the editor that
# wrote it.

enum Severity { BLOCKS, DEGRADES }

# The origin every geometry question is asked from. Any cell does -- every pattern is relative to
# its own origin -- so this is arbitrary rather than meaningful, and named so nobody reads
# significance into it.
const PROBE_ORIGIN := Vector2i.ZERO


# One row per fault: {"severity": Severity, "text": String}. Empty means nothing found, which is a
# RESULT -- callers say so out loud rather than staying silent.
static func check(attack: AttackData) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if attack == null:
		return found
	_check_reaches_anything(attack, found)
	_check_affects_anything(attack, found)
	_check_paths_are_sound(attack, found)
	_check_swing_spares_its_wielder(attack, found)
	_check_blend_totals(attack, found)
	_check_kind_is_authored(attack, found)
	_check_empowered_form_is_flat(attack, found)
	_check_effect_looks_match(attack, found)
	return found


# A look slot that has come loose from the attack wearing it (#900) -- two faults, both silent.
#
# A look stamps the ELEMENT it describes and the picker only ever offers matching ones, so a
# mismatch means the .tres was hand-edited or an element was retyped underneath it; the effect
# reading that slot would wear another element's numbers. And a slot for an element this attack no
# longer carries is simply never read -- harmless, but it is also the tell that the sigils or the
# damage type moved and somebody's authored look went quiet.
#
# DEGRADES for both: the attack fires correctly either way, it just does not look the way its file
# says. A BLOCKS here would also refuse the one panel that can repair it, which is the tier ruling
# `_check_blend_totals` already made for the same reason.
static func _check_effect_looks_match(attack: AttackData, found: Array[Dictionary]) -> void:
	var carried := attack.authored_elements()
	for element: Elemental.Element in attack.effect_looks:
		var look: EffectLook = attack.effect_looks[element]
		if look == null:
			continue
		var name := Elemental.display_name(element)
		if look.element != element:
			_add(found, Severity.DEGRADES, "the %s look is authored for %s -- it would play %s's values"
				% [name, Elemental.display_name(look.element), Elemental.display_name(look.element)])
		elif not carried.has(element):
			_add(found, Severity.DEGRADES,
				"a %s look is attached but this attack carries no %s -- nothing will read it" % [name, name])


# The supercharge substitution reads ONE level (#97): WeaponInstance.effective_main swaps the main
# for its empowered_form and never asks that form for one of its own. A chain therefore authors a
# shape the game will not fire -- silently, since the second link simply never appears.
#
# BLOCKS: unlike a bad blend, nothing about this degrades gracefully. The author believes they have
# built two tiers and has built one. A carving has no empowered form and is skipped.
static func _check_empowered_form_is_flat(attack: AttackData, found: Array[Dictionary]) -> void:
	var weapon_attack := attack as WeaponAttackData
	if weapon_attack == null or weapon_attack.empowered_form == null:
		return
	var name := attack.display_name if attack.display_name != "" else "This attack"
	if weapon_attack.empowered_form == weapon_attack:
		_add(found, Severity.BLOCKS, "%s is its own empowered form, which would fire forever." % name)
		return
	if weapon_attack.empowered_form.empowered_form != null:
		_add(found, Severity.BLOCKS,
			"%s's empowered form carries an empowered form of its own, and only one level is ever read." % name)


# The weights are read as a WEIGHTED AVERAGE, so any total works arithmetically and only a total of
# BLEND_TOTAL makes the numbers mean what they say: {STR: 100, DEX: 30} is really 77/23, and a
# reader who trusts the file is wrong by 23 points. The editor's sliders cannot author anything
# else, so this catches the two doors it does not own -- a hand-edited .tres, and content that
# predates the sliders.
#
# DEGRADES rather than BLOCKS: the attack still fires and still scales, it just is not the mix its
# own numbers claim. A carving has no blend and is skipped rather than passed vacuously.
static func _check_blend_totals(attack: AttackData, found: Array[Dictionary]) -> void:
	var weapon_attack := attack as WeaponAttackData
	if weapon_attack == null:
		return
	var total := 0
	for stat: Stats.Stat in weapon_attack.scaling_blend:
		total += weapon_attack.scaling_blend[stat]
	if total == Stats.BLEND_TOTAL:
		return
	var name := attack.display_name if attack.display_name != "" else "This attack"
	_add(found, Severity.DEGRADES, "%s's scaling blend totals %d, not %d, so what it really scales off is %s -- not what the numbers say." % [
		name, total, Stats.BLEND_TOTAL, Stats.blend_text(weapon_attack.scaling_blend)])


# NONE is the kind of a heal or a utility attack and nothing else -- delivered_kind() answers it from
# those flags, so the stored field never needs to say it, and the editor never offers it. The one door
# left is a hand-edited .tres, and a damaging attack stored as NONE would read as armour-proof to
# every piece that lists its kinds, silently. BLOCKS, like the range fault: it is a file that lies.
static func _check_kind_is_authored(attack: AttackData, found: Array[Dictionary]) -> void:
	if attack.damage_kind != AttackData.Kind.NONE:
		return
	if attack.deliver(AttackData.Kind.BLUNT) == AttackData.Kind.NONE:
		return   # a heal or a utility attack delivers NONE by rule, whatever the field says
	var name := attack.display_name if attack.display_name != "" else "This attack"
	_add(found, Severity.BLOCKS, "%s deals damage but its kind is None -- None is only for heals and no-damage attacks. Pick how the damage arrives." % name)


# Reach's own union-over-facings query, so a directional spread is judged by the same call the red
# overlay draws with. A null user is safe: no geometry reads it.
static func _check_reaches_anything(attack: AttackData, found: Array[Dictionary]) -> void:
	if not Reach.get_all_attack_cells_from(null, PROBE_ORIGIN, attack).is_empty():
		return
	var name := attack.display_name if attack.display_name != "" else "This attack"
	var text := "%s can be aimed at NO cells at all -- it will not show any range in game, and nothing will refuse to fire it." % name
	# The hint names the pair that has actually bitten rather than making the reader find it.
	# A self-anchored attack (max range 0) has no ring to empty; only its shape can be.
	if attack.is_directional():
		text += " Its shape's stamp is empty, so no facing covers anything."
	elif attack.min_range > attack.max_range:
		text += " Min Range (%d) is above Max Range (%d)." % [attack.min_range, attack.max_range]
	_add(found, Severity.BLOCKS, text)


# The fault the check above cannot see (#803): an attack aimed at a CELL whose shape covers nothing.
# Its ring is intact, so it can be aimed anywhere in range and then lands on nothing. Self-anchored
# attacks are the check above's business (an empty stamp is an empty union there), so this asks only
# the anchored half and the two never both fire for one fault. A NULL shape is not this fault --
# since #808 that means the aimed cell alone, which is what most attacks author.
static func _check_affects_anything(attack: AttackData, found: Array[Dictionary]) -> void:
	var shape := attack.attack_shape
	if shape == null or attack.is_directional() or not shape.tiles().is_empty():
		return
	var name := attack.display_name if attack.display_name != "" else "This attack"
	_add(found, Severity.BLOCKS, "%s can be aimed but its stamp is empty, so it lands on no cells at all -- add at least 0,0." % name)


# A shape's path pair that is not sound (#1056, #1079). Only a hand edit can do
# it -- the grid keeps every rule -- and AttackShape.path_fault is the one judge, so this asks
# rather than restating. BLOCKS, unlike a look or a blend: Reach walks these paths (#1057), and a
# pair that cannot be split says nothing a rule could act on.
static func _check_paths_are_sound(attack: AttackData, found: Array[Dictionary]) -> void:
	var shape := attack.attack_shape
	if shape == null:
		return
	var fault := shape.path_fault()
	if fault == "":
		return
	var name := shape.display_name if shape.display_name != "" else "This attack's shape"
	_add(found, Severity.BLOCKS, "%s has malformed paths: %s. Redraw them on the grid." % [name, fault])


# A self-anchored single-target swing with Hits Self whose path visits the attacker's own tile
# (#1057). The wielder always stands there and is always a valid target, so the path always stops on
# them and nothing after that tile lands. DEGRADES: it fires, just not the way the arrows say, and a
# swing that hits its wielder can be meant.
static func _check_swing_spares_its_wielder(attack: AttackData, found: Array[Dictionary]) -> void:
	if not attack.hits_self or not attack.is_directional() or not attack.is_single_target_swing():
		return
	var shape := attack.attack_shape
	if shape.path_fault() != "":
		return   # _check_paths_are_sound has already refused it
	var name := attack.display_name if attack.display_name != "" else "This attack"
	for i in shape.path_count():
		var path := shape.path_at(i)
		var step := path.find(Vector2i.ZERO)
		if step < 0:
			continue
		var rest := "" if step == path.size() - 1 else ", and the tiles after it never land"
		_add(found, Severity.DEGRADES, "%s hits its wielder: path %d reaches the attacker's own tile at step %d and Hits Self is on, so it always stops there%s." % [name, i + 1, step + 1, rest])


static func _add(found: Array[Dictionary], severity: Severity, text: String) -> void:
	found.append({"severity": severity, "text": text})


# What holds an attack, for the carriers readout. carrier_text words it.
enum Carrier { FAMILY, PROTOTYPE, MOD, RUNE }


# Who can fire this attack: one row per way it is reached, {"carrier": catalog key, "kind": Carrier,
# "role": String}. Empty means a TRUE orphan -- nothing on disk fires it, so no unit can.
static func carriers_of(attack: AttackData) -> Array[Dictionary]:
	# Each catalog is a disk scan per call -- asked once here, then passed.
	return carriers_among(attack, WeaponCatalog.get_templates(), WeaponModCatalog.get_mods(),
		RuneCatalog.get_variants())


# The walk, over sources PASSED in. The roots are what carries an attack into a fight: a template's
# stock list, a mod's replacement main and grants, a rune's carvings. From each it follows the two
# things that fire something else:
#   - the EMPOWERED FORM of a MAIN only. WeaponInstance.effective_main empowers the base main and
#     never an extra or a grant, so a form hung on one of those reads as the orphan it is. Restated
#     here because effective_main needs an instance and a wielder, and a lint has neither.
#   - the PAYLOAD CHAIN, every level, as PlanResolver.drop_payloads walks it for whatever fired.
# Not ResourceCatalog.users_of, which asks which FILES name a path: an orphan's payload is named
# without ever being fired.
#
# Matched by identity or a shared resource_path: an ext_resource reference is the same cached object
# today, but a path compare cannot be broken by a cache miss. An unsaved attack matches by identity
# alone, so no catalog can be found carrying it.
static func carriers_among(attack: AttackData, templates: Dictionary, mods: Dictionary,
		runes: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	if attack == null:
		return rows
	for key: String in templates:
		var template: WeaponData = templates[key]
		var kind: Carrier = Carrier.PROTOTYPE if template.is_prototype else Carrier.FAMILY
		for carried: WeaponAttackData in template.attacks():
			_reach(attack, carried, "main" if carried == template.main_attack else "extra", key, kind, rows)
		if template.main_attack != null:
			_reach(attack, template.main_attack.empowered_form, "the main's empowered form", key, kind, rows)
	for key: String in mods:
		var mod: WeaponModData = mods[key]
		_reach(attack, mod.replaces_main, "replaces the main", key, Carrier.MOD, rows)
		if mod.replaces_main != null:
			_reach(attack, mod.replaces_main.empowered_form, "the replacement main's empowered form",
				key, Carrier.MOD, rows)
		for granted: WeaponAttackData in mod.granted_attacks:
			_reach(attack, granted, "grants it", key, Carrier.MOD, rows)
	for key: String in runes:
		var rune: RuneData = runes[key]
		for carving: TransmutationData in rune.inscriptions:
			_reach(attack, carving, "carving", key, Carrier.RUNE, rows)
	return rows


# One fired attack: a row if it IS the attack, and one if any level of its payload chain is.
static func _reach(attack: AttackData, fired: AttackData, role: String, carrier: String,
		kind: Carrier, rows: Array[Dictionary]) -> void:
	if fired == null:
		return
	if _same(fired, attack):
		_add_carrier(rows, carrier, kind, role)
	for dropped in fired.payload_chain():
		if _same(dropped, attack):
			var name := fired.display_name if fired.display_name != "" else "an unnamed attack"
			_add_carrier(rows, carrier, kind, "dropped by %s" % name)


static func _same(a: AttackData, b: AttackData) -> bool:
	return a == b or (b.resource_path != "" and a.resource_path == b.resource_path)


static func _add_carrier(rows: Array[Dictionary], carrier: String, kind: Carrier, role: String) -> void:
	var row := {"carrier": carrier, "kind": kind, "role": role}
	if not rows.has(row):
		rows.append(row)


# One row as a panel prints it: "Super Scope (mod: grants it)". Here for severity_word's reason -- a
# projection of this file's own enum, which a second speller would let drift.
static func carrier_text(row: Dictionary) -> String:
	var kind: String = Carrier.keys()[row["kind"]]
	return "%s (%s: %s)" % [row["carrier"], kind.to_lower(), row["role"]]
