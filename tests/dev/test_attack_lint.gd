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


func _manhattan(max_range: int, min_range: int) -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	var pattern := ManhattanRangePattern.new()
	pattern.max_range = max_range
	pattern.min_range = min_range
	attack.attack_pattern = pattern
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
	# A directional pattern has no min/max at all. It is judged by the same question, which is the
	# point of asking Reach rather than reading a pattern's numbers.
	var attack := WeaponAttackData.new()
	var pattern := ForwardLinePattern.new()
	pattern.length = 0
	attack.attack_pattern = pattern
	assert_array(AttackLint.check(attack)).is_not_empty()


func test_a_pattern_less_attack_is_fireable_rather_than_flagged() -> void:
	# Bare fists reach adjacency through Reach's own fallback -- flagging them would be a false
	# positive, and is exactly what reading the pattern instead of Reach would produce.
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
