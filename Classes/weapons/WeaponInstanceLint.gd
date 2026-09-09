extends Object
class_name WeaponInstanceLint

# "Is this weapon's fitting still LEGAL?" -- the one answer to that (#837), asked by the Item Editor
# before it writes a carried weapon, by the Check board button over a live board, and in CI over every
# weapon on disk. The third member of the lint family, and the split is the same one #486 drew between
# a template and an instance: WeaponTemplateLint answers whether a template can BECOME a weapon,
# this answers whether a weapon the dev already has is still wearing a legal set of mods.
#
# WHY IT EXISTS. fit_block_reason is asked once, when the mod goes on, and never again -- while every
# rule it applies is measured against the TEMPLATE, which is a shared resource the Prototype editor
# edits live. So a one-click template edit can leave an already-fitted mod in a state the model would
# refuse today, with the weapon still carried and still playable and nothing anywhere saying so. Four
# are reachable through shipped doors: Remove a mod space and its mod is stranded past space_count()
# (#837, the one that has a ticket -- it also goes UNREMOVABLE, since space_holding scans only the
# spaces the template still has, so unfit can never reach it); drag a capacity spinner below what a
# space holds; retype a prototype's family under a family-locked mod; hand-edit a second main-replacer
# into a .tres, which base_main silently resolves by taking the first.
#
# ONE RULE, BORROWED -- BoardLint's discipline, and the reason those four cost one clause rather than
# four. Every sentence is fit_block_reason's own, so a fifth clause added there is caught here for
# free and no wording can drift from the door that enforces it.
#
# DEGRADES, all of it. The weapon is carried and it plays; the mod is inert. BLOCKS would refuse the
# save in the Item Editor and leave the only tool that can repair the file unable to write it, which
# is _refuse_template's stated reasoning one content type over.

enum Severity { BLOCKS, DEGRADES }


# One row per illegally-fitted mod: {"severity": Severity, "text": String}. Empty means nothing found,
# which is a RESULT -- callers say so out loud rather than staying silent.
#
# A COLLISION reports BOTH of its mods, because each is asked without itself and finds the other. That
# is the borrow being symmetric rather than a miscount: naming only the one base_main discards would
# mean restating its first-in-space-order rule here, and what is worth saying is that the two collide.
static func check(weapon: WeaponInstance) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	if weapon == null or weapon.template == null:
		return found
	# An unmapped weapon_type is the TEMPLATE's fault and WeaponTemplateLint already BLOCKS it. Asking
	# anyway would be worse than useless: make() answers null there, so the probe below would deref it.
	if WeaponInstance.make(weapon.template) == null:
		return found
	for index in range(weapon.spaces.size()):
		var fitted: Array = weapon.spaces[index]
		for mod: WeaponModData in fitted:
			if mod == null:
				continue
			var reason := _refit_reason(weapon, index, mod)
			if reason != "":
				_add(found, Severity.DEGRADES, "%s is fitted to space %d but would be refused there now: %s"
						% [_name_of(mod), index + 1, reason])
	_check_fitted_main_is_fireable(weapon, found)
	return found


# DEGRADES, deliberately: the weapon is already on disk in this state and the Item Editor is what
# repairs it -- a BLOCKS refuses that save (_refuse_instance), which is the trap this whole file
# stays DEGRADES to avoid. Quieter than the template's BLOCKS on the same rule, and correctly so:
# a template fault is fixed in another tab, a fitting fault is fixed right here.
#
# The OTHER two doors onto effective_main, and the pair WeaponTemplateLint structurally
# cannot see -- a fitted mod's `replaces_main`, and that replacement's own empowered form. Same
# #590 rule as the template's authored main: a watch attack is never fired, so a weapon whose
# effective main is one has nothing to attack with. Nothing referenced `replaces_main` in tests
# before this, so the mod door was open the whole time the template door was guarded.
#
# base_main() rather than effective_main(): the replacement is what a mod actually installs, and
# asking the supercharged form separately is what lets the message name WHICH of the two is wrong.
# Passed a null wielder deliberately -- active_space_count reads UNREDUCED for an unheld weapon
# (#732), so the lint sees every fitted mod rather than only a particular carrier's active spaces.
static func _check_fitted_main_is_fireable(weapon: WeaponInstance, found: Array[Dictionary]) -> void:
	var base := weapon.base_main(null)
	if base == null or base == weapon.template.main_attack:
		return   # the template's own main is WeaponTemplateLint's finding, not a second copy of it
	if base.can_overwatch:
		_add(found, Severity.DEGRADES, "A fitted mod replaces the main attack with \"%s\", which is a watch attack -- an overwatch attack is never fired, so this weapon has nothing to attack with." % base.display_name)
	if base.empowered_form != null and base.empowered_form.can_overwatch:
		_add(found, Severity.DEGRADES, "A fitted mod replaces the main attack with \"%s\", which empowers into the watch attack \"%s\" -- so this weapon has nothing to attack with while it is supercharged." % [base.display_name, base.empowered_form.display_name])


# Would this mod be allowed onto this space TODAY? Asked on a PROBE -- a copy of the weapon with this
# mod taken off -- because fit_block_reason trips two of its own clauses against a mod already on the
# weapon: it answers "already fitted to this weapon" for it, and counts its size in used_capacity, so
# a mod occupying exactly its space's capacity would report itself as an overfill.
#
# copy_for_grant is the sanctioned copy door and keeps `template` SHARED, which is what makes the
# probe answer about this weapon's own family rather than a forked one.
#
# A STRANDED mod is the case unfit cannot reach -- space_holding scans only the spaces the template
# still has -- and it needs no reaching: fit_block_reason answers "space does not exist" at its second
# clause, before either self-collision clause is asked.
static func _refit_reason(weapon: WeaponInstance, index: int, mod: WeaponModData) -> String:
	var probe := weapon.copy_for_grant() as WeaponInstance
	if probe == null:
		return ""
	probe.unfit(mod)
	return probe.fit_block_reason(index, mod)


# A mod with no display_name is authored content mid-edit, not a fault worth a second finding.
static func _name_of(mod: WeaponModData) -> String:
	return mod.display_name if mod.display_name != "" else "An unnamed mod"


static func _add(found: Array[Dictionary], severity: Severity, text: String) -> void:
	found.append({"severity": severity, "text": text})


# The tier as a word, for a panel row. Here rather than at the consumer for the reason
# WeaponTemplateLint's is: it is a pure projection of this file's own enum, and a second speller would
# drift the moment a tier is added.
static func severity_word(finding: Dictionary) -> String:
	return "BLOCKS" if finding["severity"] == Severity.BLOCKS else "DEGRADES"
