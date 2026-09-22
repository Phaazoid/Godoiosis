# "Can this authored attack actually be fired?" -- AttackLint (#473), BoardLint's shape: one rule,
# read by the Attack Editor before it saves and again here over everything shipped.
#
# The teeth cases build their own broken attacks rather than pointing at content, so they answer
# whether the LINT works regardless of what is on disk; the sweep then asks the shipped set. Split
# that way on purpose -- a sweep alone passes just as happily against a lint that finds nothing.
#
# Nothing here pins authored content (tests/README.md #9): the sweep asserts a PROPERTY every
# attack must have, never a range, a count or a name, and its non-vacuity guards are failure
# MESSAGES rather than thresholds.
extends GdUnitTestSuite

const P := preload("res://tests/support/shape_fixtures.gd")


func _manhattan(max_range: int, min_range: int) -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	P.point(attack, max_range, min_range)
	attack.display_name = "Probe"
	return attack


func test_a_min_range_above_max_range_is_found_and_named() -> void:
	var findings := AttackLint.check(_manhattan(2, 8))
	assert_array(findings).is_not_empty()
	assert_int(findings[0]["severity"]).is_equal(AttackLint.Severity.BLOCKS)
	var text: String = findings[0]["text"]
	assert_str(text).contains("NO cells")
	# The hint names the actual pair, so the reader does not have to go find it.
	assert_str(text).contains("Min Range (8)")
	assert_str(text).contains("Max Range (2)")


func test_an_ordinary_range_pair_is_clean() -> void:
	assert_array(AttackLint.check(_manhattan(2, 2))).is_empty()


func test_the_rule_is_selects_no_cells_and_not_min_above_max() -> void:
	# A self-anchored attack has no ring at all. It is judged by the same question, which is the
	# point of asking Reach rather than reading the numbers -- and the hint says which half.
	var attack := WeaponAttackData.new()
	P.line(attack, 0)
	var findings := AttackLint.check(attack)
	assert_array(findings).is_not_empty()
	assert_str(findings[0]["text"]).contains("stamp is empty")


func test_an_empty_stamp_at_range_is_blocked_as_landing_nowhere() -> void:
	# The ring is intact, so the reaches-anything check passes; the stamp is what is empty (#803).
	var attack := _manhattan(2, 1)
	attack.attack_shape = P.shape([] as Array[Vector2i])
	var findings := AttackLint.check(attack)
	assert_int(findings.size()).is_equal(1)
	assert_int(findings[0]["severity"]).is_equal(AttackLint.Severity.BLOCKS)
	assert_str(findings[0]["text"]).contains("lands on no cells")


func test_a_stamp_beyond_the_aimed_cell_is_clean() -> void:
	var attack := _manhattan(2, 1)
	var plus: Array[Vector2i] = [Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
	attack.attack_shape = P.shape(plus)
	assert_array(AttackLint.check(attack)).is_empty()


func test_a_shape_with_malformed_paths_is_blocked_and_named() -> void:
	# #1056. Only a hand edit breaks the pair, and #1057 will walk it, so it refuses the save.
	var attack := P.stamped(WeaponAttackData.new(), 0, [Vector2i(0, -1)] as Array[Vector2i])
	attack.attack_shape.display_name = "Probe Shape"
	attack.attack_shape.path_cells = [Vector2i(0, -1), Vector2i(0, -1)] as Array[Vector2i]
	attack.attack_shape.path_lengths = [3] as Array[int]
	var blocks := AttackLint.check(attack).filter(func(f: Dictionary) -> bool:
		return f["severity"] == AttackLint.Severity.BLOCKS)
	assert_int(blocks.size()).is_equal(1)
	var text: String = blocks[0]["text"]
	assert_str(text).contains("Probe Shape")
	assert_str(text).contains("malformed paths")


func test_a_shape_with_sound_paths_is_not_flagged() -> void:
	var attack := P.stamped(WeaponAttackData.new(), 0, [Vector2i(0, -1)] as Array[Vector2i])
	attack.attack_shape.path_cells = [Vector2i(0, -1), Vector2i(0, -1)] as Array[Vector2i]
	attack.attack_shape.path_lengths = [2] as Array[int]
	var texts: Array[String] = []
	for finding in AttackLint.check(attack):
		texts.append(finding["text"])
	assert_array(texts.filter(func(t: String) -> bool: return t.contains("paths"))).is_empty()


func test_a_shapeless_attack_is_fireable_rather_than_flagged() -> void:
	# A shapeless attack covers the cell it is aimed at, and bare fists reach adjacency through
	# Reach own fallback -- flagging either would be a false positive, and is exactly what reading
	# the numbers instead of asking Reach would produce.
	assert_array(AttackLint.check(WeaponAttackData.new())).is_empty()
	assert_array(AttackLint.check(null)).is_empty()


func test_every_shipped_attack_can_be_aimed_somewhere() -> void:
	var mains := WeaponAttackCatalog.get_mains()
	var library := WeaponAttackCatalog.get_library()
	assert_bool(mains.is_empty()).override_failure_message(
		"no main attacks scanned -- the scan is broken, not the content").is_false()
	var broken: Array[String] = []
	for source: Dictionary in [mains, library]:
		for key in source:
			var attack: WeaponAttackData = source[key]
			for finding: Dictionary in AttackLint.check(attack):
				broken.append("%s: %s" % [key, finding["text"]])
	assert_array(broken).is_empty()


func test_carriers_round_trips_against_every_family() -> void:
	var templates := WeaponCatalog.get_templates()
	assert_bool(templates.is_empty()).override_failure_message(
		"no weapon families scanned -- the scan is broken, not the content").is_false()
	var checked := 0
	for key in templates:
		var family: WeaponData = templates[key]
		for carried: WeaponAttackData in family.attacks():
			if carried == null or carried.resource_path == "":
				continue
			checked += 1
			assert_array(AttackLint.carriers_of(carried)).contains([key])
	assert_bool(checked == 0).override_failure_message(
		"no family carries a saved attack, so nothing was actually checked").is_false()


func test_an_attack_with_no_file_has_no_carriers() -> void:
	assert_array(AttackLint.carriers_of(WeaponAttackData.new())).is_empty()
	assert_array(AttackLint.carriers_of(null)).is_empty()


# --- damage kind (#424): NONE is a rule, never an authoring ---

func test_a_damaging_attack_stored_as_none_is_blocked_and_named() -> void:
	var attack := _manhattan(2, 2)
	attack.damage_kind = AttackData.Kind.NONE
	var findings := AttackLint.check(attack)
	assert_array(findings).is_not_empty()
	assert_int(findings[0]["severity"]).is_equal(AttackLint.Severity.BLOCKS)
	assert_str(findings[0]["text"]).contains("Probe")
	assert_str(findings[0]["text"]).contains("None")


func test_none_on_a_heal_is_the_rule_and_not_a_fault() -> void:
	var attack := _manhattan(2, 2)
	attack.heals = true
	attack.damage_kind = AttackData.Kind.NONE
	assert_array(AttackLint.check(attack)).is_empty()


func test_none_on_a_no_damage_attack_is_clean() -> void:
	var attack := _manhattan(2, 2)
	attack.deals_no_damage = true
	attack.damage_kind = AttackData.Kind.NONE
	assert_array(AttackLint.check(attack)).is_empty()


func test_an_authored_kind_is_clean() -> void:
	var attack := _manhattan(2, 2)
	attack.damage_kind = AttackData.Kind.CORROSION
	assert_array(AttackLint.check(attack)).is_empty()


# --- a look that has come loose from the attack wearing it (#900) -----------------------------

func _shock() -> WeaponAttackData:
	var attack := _manhattan(2, 2)   # a range the lint is happy with, so only the look can red
	attack.elemental_damage_type = Elemental.Element.SHOCK
	return attack


func _look(element: Elemental.Element) -> EffectLook:
	var look := EffectLook.new()
	look.element = element
	return look


# The picker only ever offers matching looks, so a mismatch means the .tres was hand-edited or an
# element was retyped underneath it -- and the effect would play another element's numbers.
func test_a_look_authored_for_another_element_is_reported() -> void:
	var attack := _shock()
	attack.effect_looks[Elemental.Element.SHOCK] = _look(Elemental.Element.FIRE)

	var findings := AttackLint.check(attack)

	assert_int(findings.size()).override_failure_message(
		"a shock slot holding a fire look passed the lint").is_equal(1)
	assert_int(findings[0]["severity"]).override_failure_message(
		"a mismatched look was reported as BLOCKS -- it must not be, or the one panel that can "
		+ "repair it is refused the save. The attack still fires; it just does not look like its file"
	).is_equal(AttackLint.Severity.DEGRADES)


# A slot for an element the attack no longer carries is never read. Harmless in itself, and the tell
# that the element moved and somebody's authored look went quiet.
func test_a_look_for_an_element_the_attack_does_not_carry_is_reported() -> void:
	var attack := _manhattan(2, 2)   # no element at all, and a range the lint is happy with
	attack.effect_looks[Elemental.Element.SHOCK] = _look(Elemental.Element.SHOCK)

	var findings := AttackLint.check(attack)

	assert_int(findings.size()).override_failure_message(
		"a look nothing will ever read passed the lint").is_equal(1)
	assert_str(findings[0]["text"]).contains("carries no")


func test_a_matching_look_on_an_attack_that_carries_it_is_clean() -> void:
	var attack := _shock()
	attack.effect_looks[Elemental.Element.SHOCK] = _look(Elemental.Element.SHOCK)

	assert_array(AttackLint.check(attack)).override_failure_message(
		"a correctly attached look was reported as a fault").is_empty()
