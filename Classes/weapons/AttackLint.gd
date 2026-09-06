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
	_check_blend_totals(attack, found)
	_check_kind_is_authored(attack, found)
	_check_empowered_form_is_flat(attack, found)
	return found


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
	if shape == null or attack.is_directional() or not shape.stamp.is_empty():
		return
	var name := attack.display_name if attack.display_name != "" else "This attack"
	_add(found, Severity.BLOCKS, "%s can be aimed but its stamp is empty, so it lands on no cells at all -- add at least 0,0." % name)


static func _add(found: Array[Dictionary], severity: Severity, text: String) -> void:
	found.append({"severity": severity, "text": text})


# Which weapon families carry this attack, by display name -- as a main or as an extra. Matched on
# resource_path rather than identity: a family's extras are ext_resource references, so the two
# loads are the same cached object today, but a path compare cannot be broken by a cache miss.
# An unsaved attack (no path) has no carriers by construction.
static func carriers_of(attack: AttackData) -> Array[String]:
	var carriers: Array[String] = []
	if attack == null or attack.resource_path == "":
		return carriers
	var templates := WeaponCatalog.get_templates()   # a disk scan per call -- hoisted, not re-asked
	for key in templates:
		var family: WeaponData = templates[key]
		for carried: WeaponAttackData in family.attacks():
			if carried != null and carried.resource_path == attack.resource_path:
				carriers.append(key)
				break
	return carriers
