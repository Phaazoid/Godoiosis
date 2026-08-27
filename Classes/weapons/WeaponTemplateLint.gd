extends Object
class_name WeaponTemplateLint

# "Can this authored template actually become a weapon?" -- the one answer to that (#486), asked by
# the Item Editor's Prototype mode before it writes a file and again in CI over every shipped
# template. AttackLint's shape and BoardLint's discipline: BORROW the rule rather than restate one,
# and report in two tiers so "cannot exist" is not buried under "is missing a swing".
#
# Both faults are silent, which is why they need a lint rather than a comment. An unset weapon_type
# makes WeaponInstance.make() push_error and return NULL, so the template loads fine, lists fine in
# every dropdown, and produces nothing when anyone tries to carry it. A dead space simply refuses
# every mod forever, with the fitting UI still drawing it.
#
# SCOPED to what the authoring door can produce. A template with no spaces at all is not listed:
# that is a legal design (predetermined power, no customization) rather than a mistake, and a check
# that fires on a deliberate choice trains you to ignore the panel.

enum Severity { BLOCKS, DEGRADES }


# One row per fault: {"severity": Severity, "text": String}. Empty means nothing found, which is a
# RESULT -- callers say so out loud rather than staying silent.
static func check(template: WeaponData) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if template == null:
		return found
	_check_has_a_family(template, found)
	_check_has_a_main(template, found)
	_check_spaces_can_hold_anything(template, found)
	_check_main_is_fireable(template, found)
	return found


# BLOCKS: WeaponInstance._instance_for maps every real family to a concrete subclass and answers
# NONE with null, deliberately loudly (#82) -- an unmapped type is a failure, not a generic weapon.
# So a template left on NONE cannot be carried by anybody, and nothing before this point says so.
static func _check_has_a_family(template: WeaponData, found: Array[Dictionary]) -> void:
	if template.weapon_type == WeaponData.WeaponType.NONE:
		_add(found, Severity.BLOCKS, "No weapon family -- WeaponInstance.make() cannot build an instance of this, so nobody can carry it.")


# DEGRADES rather than BLOCKS, matching the Attack Editor's Weapon Families mode, which treats a
# main-less family as a legitimate intermediate state and saves it anyway. Contradicting that here
# would be one rule with two answers depending on which panel you happened to be in.
static func _check_has_a_main(template: WeaponData, found: Array[Dictionary]) -> void:
	if template.main_attack == null:
		_add(found, Severity.DEGRADES, "No main attack -- default aim and counters have nothing to fire until one is picked.")


# BLOCKS: since #590 can_overwatch is not a capability an attack carries alongside firing, it is
# what the attack IS -- a watch attack is declared as a standing watch and never fired. A main
# authored that way leaves the weapon with NO fireable attack at all: default aim has nothing,
# counters have nothing, and every fire surface skips it while the menu still draws the family.
# The fix is content, and it is the one the Carbine takes -- keep the main fireable and give the
# family a separate watch-only attack in extra_attacks.
static func _check_main_is_fireable(template: WeaponData, found: Array[Dictionary]) -> void:
	if template.main_attack != null and template.main_attack.can_overwatch:
		_add(found, Severity.BLOCKS, "Main attack \"%s\" is a watch attack -- an overwatch attack is never fired, so this weapon has nothing to attack with. Move it to extra_attacks and give the family a fireable main." % template.main_attack.display_name)


# DEGRADES: the weapon works, that space does not. can_fit compares against the capacity, so a
# capacity below 1 refuses every mod including a size-1 one, leaving a space the fitting UI still
# draws and nothing can ever go into. The Prototype mode's SpinBox floors at 1, so this catches the
# door it does not own -- a hand-edited .tres -- exactly as AttackLint's blend rule does.
static func _check_spaces_can_hold_anything(template: WeaponData, found: Array[Dictionary]) -> void:
	for i in range(template.mod_spaces.size()):
		if template.mod_spaces[i] < 1:
			_add(found, Severity.DEGRADES, "Space %d has capacity %d -- no mod is small enough to fit it." % [i + 1, template.mod_spaces[i]])


static func _add(found: Array[Dictionary], severity: Severity, text: String) -> void:
	found.append({"severity": severity, "text": text})


# The tier as a word, for a panel row. Here rather than at the consumer because it is a pure
# projection of this file's own enum, and a second speller would drift the moment a tier is added.
static func severity_word(finding: Dictionary) -> String:
	return "BLOCKS" if finding["severity"] == Severity.BLOCKS else "DEGRADES"
