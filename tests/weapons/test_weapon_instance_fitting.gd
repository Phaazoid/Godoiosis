# WeaponInstance fitting, proficiency-gated activation, and the effective-weapon math
# (#59 weapon parts core — the one gap the item-6 pass didn't touch). Covers: space
# capacities/fit validation, active-space gating by proficiency, the mass-is-physical
# rule (get_effective_weight counts every fitted mod, active or not), and the
# scaling_blend + per-mod scaling_change weighted-average math feeding base_damage.
#
# Since #486 it also covers AUTHORED spaces: how many a template has, that one past the third is
# real, that space() writes through, and that "unreduced" means every space rather than three.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")

func _template(power: int = 0, blend: Dictionary[Stats.Stat, int] = {Stats.Stat.STR: 100}, weight: int = 0, mod_spaces: Array[int] = [1, 2, 3], elemental: Elemental.Element = Elemental.Element.NONE) -> WeaponData:
	var t := WeaponData.new()
	t.main_attack = WeaponAttackData.new()
	t.main_attack.power = power
	t.main_attack.elemental_damage_type = elemental
	t.main_attack.scaling_blend = blend
	t.weight = weight
	t.mod_spaces = mod_spaces
	t.weapon_type = WeaponData.WeaponType.CHAINSWORD
	return t

func _mod(size: int = 1, power_delta: int = 0, weight: int = 0, scaling_change: Dictionary[Stats.Stat, int] = {}, added_element: Elemental.Element = Elemental.Element.NONE) -> WeaponModData:
	var m := WeaponModData.new()
	m.size = size
	m.power_delta = power_delta
	m.weight = weight
	m.scaling_change = scaling_change
	m.added_element = added_element
	return m

func _wielder(overrides: Dictionary = {}) -> Unit:
	return H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), overrides, false)

func _set_proficiency(unit: Unit, n: int) -> void:
	unit.unit_instance.set_proficiency(WeaponData.WeaponType.CHAINSWORD, n)

# --- Fitting / capacity ---

func test_space_count_matches_template_capacities() -> void:
	var w := WeaponInstance.make(_template())
	assert_int(w.space_count()).is_equal(3)

# #486: how many spaces a weapon has is AUTHORED, not forked off is_prototype. One space is what
# a prototype used to be forced to; five is the case that used to be unrepresentable, since the
# instance stored exactly three named arrays.
func test_a_template_authors_how_many_spaces_it_has() -> void:
	assert_int(WeaponInstance.make(_template(0, {}, 0, [1])).space_count()).is_equal(1)
	assert_int(WeaponInstance.make(_template(0, {}, 0, [1, 1, 2, 2, 3])).space_count()).is_equal(5)

# The claim the storage change exists for: a space past the third is a real space — it holds a
# mod, reports its capacity, and refuses an overfill exactly like the first three.
func test_a_space_past_the_third_holds_mods_and_enforces_its_capacity() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, [1, 1, 1, 1, 2]))
	assert_bool(w.fit(4, _mod(2))).is_true()
	assert_int(w.used_capacity(4)).is_equal(2)
	assert_bool(w.can_fit(4, _mod(1))).is_false()   # 2 + 1 > capacity 2
	assert_bool(w.fit(3, _mod(1))).is_true()
	assert_int(w.used_capacity(3)).is_equal(1)

# space() hands back the LIVE array, not a re-typed copy — the fitting UI's Remove button mutates
# straight through it, so a copy would leave every Remove silently doing nothing.
func test_space_hands_back_the_live_array_so_removing_through_it_writes() -> void:
	var w := WeaponInstance.make(_template())
	# The PRECONDITION is asserted, and it is what gives this case teeth. A space() that returned a
	# copy would break fit() too, leaving the space empty -- so the two assertions below would read
	# exactly the same as a successful removal and pass against the very bug they exist to catch.
	assert_bool(w.fit(1, _mod(1))).is_true()
	assert_int(w.used_capacity(1)).is_equal(1)
	var fitted := w.space(1)
	fitted.remove_at(0)
	assert_int(w.used_capacity(1)).is_equal(0)
	assert_int(w.space(1).size()).is_equal(0)

# A const Array is READ-ONLY in Godot 4, and that flag travels with an assignment -- so a default
# of `= SPACE_CAPACITIES` gives every un-overridden template an array nothing can edit in place.
# The Prototype editor's Add space button and every capacity spinner write in place, so they would
# raise a runtime error and silently do nothing, on a panel that looks like it works. Measured
# 2026-08-25 rather than assumed: the guess was cross-template bleed, and the engine refuses the
# write instead of propagating it.
func test_a_fresh_templates_spaces_are_writable_rather_than_the_read_only_const() -> void:
	var t := WeaponData.new()
	assert_bool(t.mod_spaces.is_read_only()).is_false()
	t.mod_spaces.append(9)                            # what Add space does
	t.mod_spaces[0] = 2                               # what a capacity spinner does
	assert_array(t.mod_spaces).is_equal([2, 2, 3, 9])
	# ...and none of it reached the const or the next template built from it.
	assert_array(WeaponData.new().mod_spaces).is_equal([1, 2, 3])

func test_can_fit_true_within_capacity_false_over() -> void:
	var w := WeaponInstance.make(_template())
	assert_bool(w.can_fit(2, _mod(1))).is_true()    # space index 2 -> capacity 3
	assert_bool(w.fit(2, _mod(1))).is_true()
	assert_bool(w.fit(2, _mod(2))).is_true()        # 1 + 2 = 3, exactly fits
	assert_int(w.used_capacity(2)).is_equal(3)
	assert_bool(w.can_fit(2, _mod(1))).is_false()   # 3 + 1 = 4 > capacity 3
	assert_bool(w.fit(2, _mod(1))).is_false()
	assert_int(w.used_capacity(2)).is_equal(3)      # a refused fit doesn't mutate the space

func test_can_fit_false_for_out_of_range_index() -> void:
	var w := WeaponInstance.make(_template())
	assert_bool(w.can_fit(-1, _mod(1))).is_false()
	assert_bool(w.can_fit(3, _mod(1))).is_false()   # only indices 0..2 exist

func test_can_fit_false_with_no_template() -> void:
	var w := WeaponInstance.new()
	assert_bool(w.can_fit(0, _mod(1))).is_false()
	assert_int(w.space_count()).is_equal(0)

# --- The family lock and its reason (#74) ---

func _family_mod(family: WeaponData.WeaponType, size: int = 1) -> WeaponModData:
	var m := _mod(size)
	m.family = family
	return m

# _template() builds a CHAINSWORD, so a Carbine-locked mod is the off-family case.
func test_a_mod_locked_to_another_family_is_refused() -> void:
	var w := WeaponInstance.make(_template())
	assert_bool(w.can_fit(0, _family_mod(WeaponData.WeaponType.CARBINE))).is_false()
	assert_bool(w.fit(0, _family_mod(WeaponData.WeaponType.CARBINE))).is_false()
	assert_int(w.used_capacity(0)).is_equal(0)

func test_a_mod_locked_to_this_family_fits_and_an_unlocked_one_fits_anything() -> void:
	var w := WeaponInstance.make(_template())
	assert_bool(w.can_fit(1, _family_mod(WeaponData.WeaponType.CHAINSWORD))).is_true()
	assert_bool(w.can_fit(2, _mod(1))).is_true()   # family NONE

# can_fit is DERIVED from the reason, so the two cannot disagree about anything -- which is the
# whole point of the channel. Asserted over every refusal this weapon can produce, not one of them.
func test_can_fit_agrees_with_the_reason_on_every_refusal() -> void:
	var w := WeaponInstance.make(_template())
	w.fit(0, _mod(1))   # space 0 has capacity 1, so it is now full
	# The wrong-family case must sit in a space with ROOM (index 1, capacity 2, empty). Asked at
	# space 0 it proves nothing: that space is full, so a can_fit that had stopped consulting the
	# reason would refuse on capacity and the two would agree by coincidence -- measured, the
	# divergence mutant passed against exactly that fixture.
	var cases: Array[Array] = [
		[0, _mod(1)],                                          # full
		[1, _family_mod(WeaponData.WeaponType.CARBINE)],       # wrong family, room to spare
		[9, _mod(1)],                                          # no such space
		[1, _mod(1)],                                          # allowed
	]
	for case in cases:
		var index: int = case[0]
		var mod: WeaponModData = case[1]
		assert_bool(w.can_fit(index, mod)).is_equal(w.fit_block_reason(index, mod) == "")

# A refusal that cannot say WHY is what the channel exists to prevent, and the two refusals must
# not wear each other's words -- a full space reading "fits Carbine only" is the bug this replaces.
func test_each_refusal_explains_itself_in_its_own_terms() -> void:
	var w := WeaponInstance.make(_template())
	assert_str(w.fit_block_reason(0, _family_mod(WeaponData.WeaponType.CARBINE))).contains("Carbine")

	w.fit(0, _mod(1))   # capacity 1, now full
	var full := w.fit_block_reason(0, _mod(1))
	assert_str(full).is_not_empty()
	assert_str(full).not_contains("Carbine")
	assert_str(w.fit_block_reason(1, _mod(1))).is_empty()   # an allowed fit says nothing

# FAMILY is asked first: a wrong-family mod that would ALSO overflow reports the permanent
# refusal, not the one you could fix by emptying the space.
func test_the_family_refusal_outranks_the_capacity_one() -> void:
	var w := WeaponInstance.make(_template())
	w.fit(0, _mod(1))   # space 0 full as well
	assert_str(w.fit_block_reason(0, _family_mod(WeaponData.WeaponType.CARBINE, 3))).contains("Carbine")

# --- Proficiency-gated activation ---

func test_active_space_count_capped_by_proficiency() -> void:
	var w := WeaponInstance.make(_template())
	var wielder := _wielder()
	_set_proficiency(wielder, 1)
	assert_int(w.active_space_count(wielder)).is_equal(1)
	_set_proficiency(wielder, 2)
	assert_int(w.active_space_count(wielder)).is_equal(2)
	_set_proficiency(wielder, 0)
	assert_int(w.active_space_count(wielder)).is_equal(0)

# #486: the DEFAULT means "no reduction", not the number 3 — a wielder nobody has deliberately
# reduced reaches every space a template authors, however many that is. Spelled as 3 it silently
# capped a five-space weapon at three, and the last two could never have been used by anyone.
func test_an_unreduced_wielder_activates_every_space_however_many() -> void:
	var wielder := _wielder()
	assert_int(WeaponInstance.make(_template(0, {}, 0, [1, 1, 1, 1, 1])).active_space_count(wielder)).is_equal(5)
	assert_int(WeaponInstance.make(_template()).active_space_count(wielder)).is_equal(3)

# The other half of the fork: a DELIBERATE reduction still caps, and still caps at its own number
# rather than at the space count.
func test_a_reduced_wielder_still_caps_below_a_wide_weapon() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, [1, 1, 1, 1, 1]))
	var wielder := _wielder()
	_set_proficiency(wielder, 2)
	assert_int(w.active_space_count(wielder)).is_equal(2)

# Setting a negative value ERASES the key, which is the only way back to unreduced once a
# reduction has been authored.
func test_setting_a_negative_proficiency_returns_the_family_to_unreduced() -> void:
	var wielder := _wielder()
	_set_proficiency(wielder, 1)
	assert_int(wielder.get_weapon_proficiency(WeaponData.WeaponType.CHAINSWORD)).is_equal(1)
	_set_proficiency(wielder, UnitInstance.UNREDUCED)
	assert_int(wielder.get_weapon_proficiency(WeaponData.WeaponType.CHAINSWORD)).is_equal(UnitInstance.UNREDUCED)
	assert_bool(wielder.unit_instance.weapon_proficiency.has(WeaponData.WeaponType.CHAINSWORD)).is_false()

func test_active_modules_only_pulls_from_activated_spaces() -> void:
	var w := WeaponInstance.make(_template())
	var mod_0 := _mod(1, 2)
	var mod_1 := _mod(1, 3)
	var mod_2 := _mod(1, 5)
	w.fit(0, mod_0)
	w.fit(1, mod_1)
	w.fit(2, mod_2)
	var wielder := _wielder()

	_set_proficiency(wielder, 1)
	assert_array(w.active_modules(wielder)).contains_exactly([mod_0])

	_set_proficiency(wielder, 2)
	assert_array(w.active_modules(wielder)).contains_exactly([mod_0, mod_1])

	_set_proficiency(wielder, 3)
	assert_array(w.active_modules(wielder)).contains_exactly([mod_0, mod_1, mod_2])

# --- Effective weight: ALL fitted mods count, active or not (mass is physical) ---

func test_effective_weight_counts_inactive_mods_too() -> void:
	var w := WeaponInstance.make(_template(0, {Stats.Stat.STR: 100}, 2))   # family weight 2
	w.fit(0, _mod(1, 0, 3))   # weight 3, in the one space that stays active below
	w.fit(2, _mod(1, 0, 4))   # weight 4, in a space that stays INACTIVE below
	var wielder := _wielder()
	_set_proficiency(wielder, 1)
	assert_int(w.active_space_count(wielder)).is_equal(1)         # confirms space 2 is inactive
	assert_int(w.get_effective_weight()).is_equal(9)               # 2 + 3 + 4 regardless

# --- base_damage / scaling: only ACTIVE mods contribute ---

func test_base_damage_pure_str_blend() -> void:
	var w := WeaponInstance.make(_template(10, {Stats.Stat.STR: 100}))
	var wielder := _wielder({Stats.Stat.STR: 6})
	_set_proficiency(wielder, 3)
	assert_int(w.base_damage(wielder, w.template.main_attack)).is_equal(16)   # 10 power + 6 STR (100% blend)

func test_base_damage_ignores_inactive_space_power_delta() -> void:
	var w := WeaponInstance.make(_template(10, {Stats.Stat.STR: 100}))
	w.fit(0, _mod(1, 2))     # active at proficiency 1
	w.fit(2, _mod(1, 100))   # inactive at proficiency 1 — must NOT count
	var wielder := _wielder({Stats.Stat.STR: 5})
	_set_proficiency(wielder, 1)
	assert_int(w.base_damage(wielder, w.template.main_attack)).is_equal(17)   # 10 + 2 (active mod) + 5 (STR) — the +100 never applies

func test_scaling_change_from_active_mod_shifts_blend() -> void:
	var w := WeaponInstance.make(_template(0, {Stats.Stat.STR: 100}))
	w.fit(0, _mod(1, 0, 0, {Stats.Stat.DEX: 50}))   # active mod adds a DEX slice to the blend
	var wielder := _wielder({Stats.Stat.STR: 8, Stats.Stat.DEX: 2})
	_set_proficiency(wielder, 1)
	# blend becomes {STR:100, DEX:50}; weighted = (8*100 + 2*50) / 150 = 900/150 = 6
	assert_int(w.base_damage(wielder, w.template.main_attack)).is_equal(6)

func test_inactive_mod_scaling_change_is_ignored() -> void:
	var w := WeaponInstance.make(_template(0, {Stats.Stat.STR: 100}))
	w.fit(2, _mod(1, 0, 0, {Stats.Stat.DEX: 100}))   # sits in a space that never activates here
	var wielder := _wielder({Stats.Stat.STR: 7, Stats.Stat.DEX: 20})
	_set_proficiency(wielder, 1)
	assert_int(w.base_damage(wielder, w.template.main_attack)).is_equal(7)   # pure STR — the DEX nudge never entered the blend

# --- Elements: main attack + active mods, deduped ---

func test_get_elements_includes_main_attack_element() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, [1, 2, 3], Elemental.Element.FIRE))
	var wielder := _wielder()
	assert_array(w.get_elements(wielder, w.template.main_attack)).contains_exactly([Elemental.Element.FIRE])

func test_get_elements_includes_active_mod_elements_and_dedupes() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, [1, 2, 3], Elemental.Element.FIRE))
	w.fit(0, _mod(1, 0, 0, {}, Elemental.Element.FIRE))   # duplicate of the template's own element
	w.fit(1, _mod(1, 0, 0, {}, Elemental.Element.WATER))
	var wielder := _wielder()
	_set_proficiency(wielder, 2)
	assert_array(w.get_elements(wielder, w.template.main_attack)).contains_exactly([Elemental.Element.FIRE, Elemental.Element.WATER])

func test_get_elements_excludes_inactive_mod_elements() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, [1, 2, 3], Elemental.Element.NONE))
	w.fit(2, _mod(1, 0, 0, {}, Elemental.Element.WATER))   # inactive at proficiency 1
	var wielder := _wielder()
	_set_proficiency(wielder, 1)
	assert_array(w.get_elements(wielder, w.template.main_attack)).is_empty()

# --- One of a kind, coming off, and what a mod NEEDS (#732) ---

# Fitting is unlimited from the catalog now, so nothing but this stopped three Line Snipers stacking
# +15 power on one weapon for nothing (dev, 2026-09-06: "Let's refuse"). The second assertion is what
# keeps the clause from being a ban on SIZE: a different mod of the same size still fits.
func test_one_weapon_takes_one_of_any_given_mod() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, [3]))
	var mod := _mod(1)
	assert_bool(w.fit(0, mod)).is_true()
	assert_bool(w.can_fit(0, mod)).is_false()
	assert_str(w.fit_block_reason(0, mod)).contains("already fitted")
	assert_bool(w.fit(0, _mod(1))).is_true()
	assert_int(w.used_capacity(0)).is_equal(2)

# The ORDER of that clause, which is the difference between a useful sentence and a confusing one:
# dragging a fitted main-replacer into another space must be told it is already ON, not that
# something already replaces the main -- the something being itself.
func test_a_mod_already_on_the_weapon_is_named_before_the_clauses_it_would_collide_with() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, [1, 2, 3]))
	var replacer := _mod(1)
	replacer.replaces_main = WeaponAttackData.new()
	assert_bool(w.fit(0, replacer)).is_true()

	var reason := w.fit_block_reason(1, replacer)
	assert_str(reason).contains("already fitted")
	assert_str(reason).not_contains("replaces this weapon's main")
	# A DIFFERENT replacer is still refused by the main clause -- the new one narrowed nothing.
	var second := _mod(1)
	second.replaces_main = WeaponAttackData.new()
	assert_str(w.fit_block_reason(1, second)).contains("replaces this weapon's main")

# The mirror of fit, for a caller holding the mod rather than an index.
func test_unfit_takes_a_mod_off_whichever_space_holds_it() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, [1, 2, 3]))
	var mod := _mod(2)
	assert_bool(w.fit(2, mod)).is_true()
	assert_int(w.space_holding(mod)).is_equal(2)
	assert_bool(w.unfit(mod)).is_true()
	assert_int(w.space_holding(mod)).is_equal(-1)
	assert_int(w.used_capacity(2)).is_equal(0)
	assert_bool(w.unfit(mod)).is_false()   # nothing to take off is false, never a silent success

# --- What the array STORES (#624) ---

# The invariant `spaces` carries: one entry past the last space holding something, and nothing at
# all when nothing is fitted. The length is never a claim about how many spaces the weapon HAS --
# that is space_count(), off the template -- so a five-space weapon with one mod in space 3 stores
# three entries and reads its other two through the empty-space answer.
func test_a_weapon_stores_only_as_far_as_its_deepest_fitted_space() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, [1, 1, 1, 1, 1]))
	assert_int(w.spaces.size()).is_equal(0)

	var third := _mod(1)
	assert_bool(w.fit(2, third)).is_true()
	assert_int(w.spaces.size()).is_equal(3)
	assert_int(w.space_count()).is_equal(5)          # the template still says five
	assert_int(w.space(4).size()).is_equal(0)        # and the unstored ones read as empty

	var fifth := _mod(1)
	assert_bool(w.fit(4, fifth)).is_true()
	assert_int(w.spaces.size()).is_equal(5)
	assert_bool(w.unfit(fifth)).is_true()
	assert_int(w.spaces.size()).is_equal(3)          # back to the deepest that still holds one
	assert_int(w.space_holding(third)).is_equal(2)   # ...without disturbing the one that does

# Fitting and then taking it off leaves a weapon indistinguishable from one nobody ever touched --
# which is the whole of #624 at the model level, since that form is what the writer serializes.
# The fit is asserted as a CLAIM rather than left as setup: an unfit that silently did nothing
# would leave the array empty too, and read exactly like a successful one (#486's lesson).
func test_taking_the_last_mod_off_returns_the_weapon_to_its_unfitted_form() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, [1, 2, 3]))
	var mod := _mod(2)
	assert_bool(w.fit(1, mod)).is_true()
	assert_int(w.used_capacity(1)).is_equal(2)       # the fit LANDED -- the case's teeth
	assert_int(w.spaces.size()).is_equal(2)

	assert_bool(w.unfit(mod)).is_true()
	assert_array(w.spaces).override_failure_message(
		"an emptied weapon kept %d entries" % w.spaces.size()).is_empty()

# A READ IS A READ. Every one of these grew the array before #624, so weighing a weapon or drawing
# its fitting card changed what it would save -- and a mod-less variant then wrote three empty
# spaces that #486's migration guard read as three mods lost.
func test_no_read_grows_the_array() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, [1, 2, 3]))
	var mod := _mod(1)
	assert_int(w.get_effective_weight()).is_equal(0)
	assert_array(w.active_modules(null)).is_empty()
	assert_int(w.space_holding(mod)).is_equal(-1)
	assert_bool(w.can_fit(2, mod)).is_true()
	for i in range(w.space_count()):
		assert_int(w.used_capacity(i)).is_equal(0)
		assert_int(w.space(i).size()).is_equal(0)
	assert_array(w.spaces).override_failure_message(
		"a read grew the array to %d entries" % w.spaces.size()).is_empty()

# The throwaway a read gets for an unstored space must not be one SHARED object -- a const Array is
# read-only and that flag travels with an assignment (#486), and one shared instance would let two
# weapons see each other's mods.
func test_two_reads_of_an_unstored_space_are_not_the_same_array() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, [1, 2, 3]))
	var first := w.space(0)
	assert_bool(first.is_read_only()).is_false()
	first.append(_mod(1))                            # writing to a throwaway reaches nothing
	assert_int(w.space(0).size()).is_equal(0)
	assert_int(w.used_capacity(0)).is_equal(0)

# A mod authors no proficiency requirement: what it NEEDS is decided by its size against this
# weapon's capacities, since proficiency N activates spaces 1..N.
func test_what_a_mod_needs_is_the_lowest_space_big_enough_to_hold_it() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, [1, 2, 3]))
	assert_int(w.lowest_space_for(_mod(1))).is_equal(0)
	assert_int(w.lowest_space_for(_mod(2))).is_equal(1)
	assert_int(w.lowest_space_for(_mod(3))).is_equal(2)
	assert_int(w.lowest_space_for(_mod(4))).is_equal(-1)

# THE INTRINSIC CLAIM, and the case with teeth for it: asking can_fit instead would read "needs
# space 2" for a size-1 mod the moment space 1 filled, and read 1 again when it emptied -- a fact
# about the weapon's fill dressed up as a fact about the mod.
func test_what_a_mod_needs_does_not_move_when_a_space_fills() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, [1, 2, 3]))
	assert_bool(w.fit(0, _mod(1))).is_true()   # space 0 is now full
	assert_int(w.lowest_space_for(_mod(1))).is_equal(0)

# A weapon nobody holds has nobody's proficiency to be reduced by -- the fitting card can open one
# out of the stash, and zero would have rendered its every fitted mod inert.
func test_a_weapon_nobody_holds_reads_every_space_as_active() -> void:
	var w := WeaponInstance.make(_template(0, {}, 0, [1, 2, 3]))
	w.fit(2, _mod(1))
	assert_int(w.active_space_count(null)).is_equal(3)
	assert_int(w.active_modules(null).size()).is_equal(1)
