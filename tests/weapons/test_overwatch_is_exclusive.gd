# The OVERWATCH EXCLUSIVITY rule (#590, docs/design/standing-reactions.md): `can_overwatch` is not a
# capability bolted onto a fireable attack, it is what the attack IS (dev, 2026-08-27: "when I check
# the 'can overwatch' box, I expect to get an attack that is an overwatch, and only an overwatch").
#
# Every case here asks one question from a different surface, because that is exactly how the bug
# shipped: the capability was read correctly at ONE surface (the menu's Overwatch rows) while the
# attack stayed in the fireable list at every other, so it kept a firing twin under the same name
# and build_tree's duplicate guard ate the watch row. A rule read by more than one surface has to be
# justified at every surface, so each case names the surface it speaks for.
#
# Nothing here asserts what shipped content contains -- the Carbine's own watch rides
# test_weapon_template_lint.gd's sweep, which fails any template whose main cannot fire.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


# One ordinary main plus one watch-only extra -- #590's own fixture, and the shape the Carbine ships.
func _weapon_with_a_watch() -> WeaponInstance:
	var weapon := H.make_weapon(4)
	weapon.template.main_attack.display_name = "Shot"
	var watch := WeaponAttackData.new()
	watch.display_name = "Line Snipe"
	watch.can_overwatch = true
	weapon.template.extra_attacks = [watch]
	return weapon


func _armed_unit() -> Unit:
	var unit := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)
	unit.equipped_weapon = _weapon_with_a_watch()
	return unit


func _watch_of(unit: Unit) -> AttackData:
	return (unit.get_equipped_weapon() as WeaponInstance).template.extra_attacks[0]


func _names(attacks: Array) -> Array[String]:
	var out: Array[String] = []
	for attack: AttackData in attacks:
		out.append(attack.display_name)
	return out


# ==============================================================================
#  The two views are disjoint
# ==============================================================================

# THE rule. Both halves in one case deliberately: "it is watchable" and "it is not fireable" are the
# same sentence since #590, and a case asserting only the first is what the build already had.
func test_a_watch_attack_is_watchable_and_not_selectable() -> void:
	var unit := _armed_unit()
	var watch := _watch_of(unit)

	assert_array(unit.overwatch_attacks()).override_failure_message(
			"the watch attack is not in the watch view at all").contains([watch])
	assert_array(unit.get_selectable_attacks()).override_failure_message(
			"the watch attack is still offered to FIRE -- it kept the twin whose name ate its row"
			).not_contains([watch])


# The Weapon Action submenu's own list, which is where the collision actually landed: the fire row
# is built from this and listed FIRST, so a watch attack left here is the row that survives.
func test_a_watch_attack_is_not_a_weapon_secondary() -> void:
	var unit := _armed_unit()
	assert_array(unit.get_weapon_secondary_attacks()).override_failure_message(
			"the watch attack still lists as a fireable secondary").not_contains([_watch_of(unit)])


# The main is untouched -- the rule takes watch attacks OUT of the fire view, it does not empty it.
# Without this, a mutant filtering everything out of selectable_attacks passes the two cases above.
func test_the_fireable_main_survives_the_filter() -> void:
	var unit := _armed_unit()
	assert_array(_names(unit.get_selectable_attacks())).contains(["Shot"])
	assert_object(unit.get_default_attack()).is_same(
			(unit.get_equipped_weapon() as WeaponInstance).template.main_attack)
	assert_bool(unit.has_any_fireable_attack()).is_true()


# The AI reads get_selectable_attacks() to pick something to FIRE (AITactics), then hands the winner
# to AttackAction.declare. A watch attack reaching that list is an enemy firing a standing watch as
# an ordinary shot -- and no AI-side wiring was added for this, which is the point: the filter sits
# at the surface the AI already shares with the player.
func test_the_ai_candidate_list_holds_no_watch_attack() -> void:
	var unit := _armed_unit()
	var watch := _watch_of(unit)
	for candidate: AttackData in unit.get_selectable_attacks():
		assert_object(candidate).override_failure_message(
				"the AI would probe a watch attack as a firing candidate").is_not_same(watch)


# ==============================================================================
#  A MOD moves an attack between the views
# ==============================================================================

# The capability is asked through effective_can_overwatch, never the raw flag, so a granting mod
# MOVES an ordinary attack out of the fire view rather than leaving it in both -- which is the same
# collision arriving by the other door.
func test_a_granting_mod_moves_the_attack_out_of_the_fire_view() -> void:
	var unit := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)
	var weapon := H.make_weapon(4)
	var granted := WeaponAttackData.new()
	granted.display_name = "Line Snipe"
	var mod := WeaponModData.new()
	mod.display_name = "Line Sniper"
	mod.granted_attacks = [granted]
	weapon.space(0).append(mod)
	unit.equipped_weapon = weapon

	assert_array(unit.get_selectable_attacks()).override_failure_message(
			"the granted attack never arrived -- the fixture is not exercising the rule"
			).contains([granted])
	assert_array(unit.overwatch_attacks()).is_empty()

	mod.can_overwatch_override = WeaponModData.Override.ON
	assert_array(unit.overwatch_attacks()).override_failure_message(
			"an ON override did not make the attack watchable").contains([granted])
	assert_array(unit.get_selectable_attacks()).override_failure_message(
			"an ON override left the attack fireable too -- the views are not disjoint"
			).not_contains([granted])


# OFF beats ON whatever space each mod sits in (#413's composition, unchanged), so a revoking mod
# hands a watch attack BACK to the fire view rather than leaving it reachable from neither.
func test_a_revoking_mod_hands_the_attack_back_to_the_fire_view() -> void:
	var unit := _armed_unit()
	var weapon := unit.get_equipped_weapon() as WeaponInstance
	var mod := WeaponModData.new()
	mod.display_name = "Safety Governor"
	mod.can_overwatch_override = WeaponModData.Override.OFF
	weapon.space(0).append(mod)

	assert_array(unit.overwatch_attacks()).is_empty()
	assert_array(unit.get_selectable_attacks()).override_failure_message(
			"a revoked watch attack is usable by nobody -- it fell out of both views"
			).contains([_watch_of(unit)])


# ==============================================================================
#  A rune's carvings answer the same way
# ==============================================================================

# The rule lives on EquippableData, so a watch CARVING leaves the Transmutation rows exactly as a
# watch attack leaves the Weapon Action ones. Same collision otherwise, since a carving's fire row
# and its watch row would wear one name in one bucket.
func test_a_watch_carving_leaves_the_transmutation_list() -> void:
	var unit := H.spawn_unit(self, Team.Faction.PLAYER, Vector2i(0, 0), {}, false)
	var rune := RuneData.new()
	var carving := TransmutationData.new()
	carving.display_name = "Warding Sight"
	rune.inscriptions = [carving]
	unit.equipped_weapon = rune

	assert_array(unit.get_transmutation_choices()).override_failure_message(
			"the carving never listed -- the fixture is not exercising the rule").contains([carving])

	carving.can_overwatch = true
	assert_array(unit.get_transmutation_choices()).override_failure_message(
			"a watch carving still lists as something to channel").not_contains([carving])
	assert_array(unit.overwatch_attacks()).override_failure_message(
			"a watch carving is watchable by nobody").contains([carving])
