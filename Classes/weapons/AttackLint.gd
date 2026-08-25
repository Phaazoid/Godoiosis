extends Object
class_name AttackLint

# "Can this authored attack actually be fired?" -- the one answer to that (#473), asked by the
# Attack Editor before it writes a file and again in CI over every shipped attack
# (tests/dev/test_attack_lint.gd). BoardLint's shape, and its discipline: BORROW the rule rather
# than restate one.
#
# The verdict comes from Reach, never from the pattern's own numbers, and that is the whole design.
# Reach carries the bare-fists fallback, so a pattern-less attack reads as fireable at adjacency
# instead of being flagged; and a pattern class added later answers here without this file changing.
# The rule is "an attack must be able to select at least one cell", NOT "min must not exceed max" --
# the second is one way to break the first.
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
	_check_blend_totals(attack, found)
	return found


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


# Reach's own union-over-facings query, so a directional spread is judged by the same call the red
# overlay draws with. A null user is safe: no pattern reads it.
static func _check_reaches_anything(attack: AttackData, found: Array[Dictionary]) -> void:
	if not Reach.get_all_attack_cells_from(null, PROBE_ORIGIN, attack).is_empty():
		return
	var name := attack.display_name if attack.display_name != "" else "This attack"
	var text := "%s can be aimed at NO cells at all -- it will not show any range in game, and nothing will refuse to fire it." % name
	var pattern := attack.attack_pattern
	if pattern is ManhattanRangePattern:
		# The one pattern with two interacting numbers, and the one that has actually bitten: the
		# hint names the pair rather than making the reader find it.
		var manhattan: ManhattanRangePattern = pattern
		if manhattan.min_range > manhattan.max_range:
			text += " Min Range (%d) is above Max Range (%d)." % [manhattan.min_range, manhattan.max_range]
	elif pattern != null:
		text += " Its %s selects nothing at this size." % pattern.get_script().get_global_name()
	_add(found, Severity.BLOCKS, text)


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
