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


# A PATH shape at range (#1056, #1079): its stamp is empty and its tiles are the ones its paths visit.
func _pathed_attack(paths: Array[Array]) -> WeaponAttackData:
	var attack := _manhattan(2, 1)
	attack.attack_shape = P.pathed(paths)
	attack.attack_shape.display_name = "Probe Shape"
	return attack


func test_a_shape_with_malformed_paths_is_blocked_and_named() -> void:
	# #1056. Only a hand edit breaks the pair, and #1057 will walk it, so it refuses the save.
	var attack := _pathed_attack([[Vector2i(0, -1), Vector2i(0, -2)] as Array[Vector2i]] as Array[Array])
	attack.attack_shape.path_lengths = [3] as Array[int]
	var blocks := AttackLint.check(attack).filter(func(f: Dictionary) -> bool:
		return f["severity"] == AttackLint.Severity.BLOCKS)
	assert_int(blocks.size()).is_equal(1)
	var text: String = blocks[0]["text"]
	assert_str(text).contains("Probe Shape")
	assert_str(text).contains("malformed paths")


func test_a_path_shape_with_sound_paths_is_clean() -> void:
	# Its stamp is EMPTY, so this is also the case that the lands-anywhere check asks the shape's
	# tiles rather than its stamp -- asked of the stamp, every path shape would be blocked.
	var attack := _pathed_attack([[Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -1)] as Array[Vector2i]] as Array[Array])
	assert_array(AttackLint.check(attack)).is_empty()


# #1057: a self-anchored single-target swing with Hits Self whose path visits the attacker's own
# tile always stops there -- the wielder is always standing on it -- so what follows never lands.
func test_a_hits_self_swing_through_its_own_tile_degrades_and_says_where() -> void:
	var through := [Vector2i(0, 0), Vector2i(0, -1)] as Array[Vector2i]
	var attack := _pathed_attack([through] as Array[Array])
	attack.max_range = 0
	attack.swing = true
	attack.hits_self = true
	var found := AttackLint.check(attack)
	assert_int(found.size()).is_equal(1)
	assert_int(found[0]["severity"]).is_equal(AttackLint.Severity.DEGRADES)
	var text: String = found[0]["text"]
	assert_str(text).contains("path 1")
	assert_str(text).contains("step 1")


# The same path is clean without Hits Self (the wielder is passed through) and without Swing (a true
# AoE walks no path at all).
func test_a_swing_through_its_own_tile_is_clean_without_hits_self_or_swing() -> void:
	var through := [Vector2i(0, 0), Vector2i(0, -1)] as Array[Vector2i]
	var attack := _pathed_attack([through] as Array[Array])
	attack.max_range = 0
	attack.swing = true
	assert_array(AttackLint.check(attack)).is_empty()
	attack.hits_self = true
	attack.swing = false
	assert_array(AttackLint.check(attack)).is_empty()


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


# --- who carries an attack (#473, #1371) ------------------------------------------------------

func _carrier_names(rows: Array[Dictionary]) -> Array[String]:
	var names: Array[String] = []
	for row in rows:
		names.append(row["carrier"])
	return names


func _texts(rows: Array[Dictionary]) -> Array[String]:
	var texts: Array[String] = []
	for row in rows:
		texts.append(AttackLint.carrier_text(row))
	return texts


func _named(name: String) -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.display_name = name
	return attack


# Every saved attack a family or a mod on disk names reports that carrier. A property of the walk
# over whatever ships, never a list of who carries what; the catalogs are scanned once and passed.
func test_carriers_round_trips_against_every_family_and_mod() -> void:
	var templates := WeaponCatalog.get_templates()
	var mods := WeaponModCatalog.get_mods()
	var runes := RuneCatalog.get_variants()
	assert_bool(templates.is_empty()).override_failure_message(
		"no weapon families scanned -- the scan is broken, not the content").is_false()
	# [catalog key, the attacks it names directly] -- a list, so a mod sharing a family's name cannot
	# overwrite it.
	var named: Array[Array] = []
	for key in templates:
		named.append([key, (templates[key] as WeaponData).attacks()])
	for key in mods:
		var mod: WeaponModData = mods[key]
		var attacks: Array[WeaponAttackData] = mod.granted_attacks.duplicate()
		attacks.append(mod.replaces_main)
		named.append([key, attacks])
	var checked := 0
	for pair in named:
		var key: String = pair[0]
		for carried: WeaponAttackData in pair[1]:
			if carried == null or carried.resource_path == "":
				continue
			checked += 1
			var carriers := _carrier_names(AttackLint.carriers_among(carried, templates, mods, runes))
			assert_array(carriers).override_failure_message(
				"%s names %s, which does not report it" % [key, carried.display_name]).contains([key])
	assert_bool(checked == 0).override_failure_message(
		"no family carries a saved attack, so nothing was actually checked").is_false()


func test_an_attack_with_no_file_has_no_carriers() -> void:
	assert_array(AttackLint.carriers_of(WeaponAttackData.new())).is_empty()
	assert_array(AttackLint.carriers_of(null)).is_empty()


# The issue's own case: a family-less attack a mod hands over is carried, by the mod, and says so.
func test_an_attack_only_a_mod_grants_is_carried_by_that_mod() -> void:
	var lob := _named("Lob")
	var mod := WeaponModData.new()
	mod.granted_attacks = [lob] as Array[WeaponAttackData]
	var rows := AttackLint.carriers_among(lob, {}, {"Scope": mod}, {})
	assert_array(_texts(rows)).contains_exactly(["Scope (mod: grants it)"])
	assert_int(rows[0]["kind"]).is_equal(AttackLint.Carrier.MOD)


# A mod's replacement main is carried, and so is ITS empowered form -- effective_main applies the
# supercharge after the replacement.
func test_a_mods_replacement_main_and_its_empowered_form_are_carried() -> void:
	var charged := _named("Charged")
	var snipe := _named("Snipe")
	snipe.empowered_form = charged
	var mod := WeaponModData.new()
	mod.replaces_main = snipe
	var mods := {"Sniper": mod}
	var for_main := _texts(AttackLint.carriers_among(snipe, {}, mods, {}))
	assert_array(for_main).contains_exactly(["Sniper (mod: replaces the main)"])
	var for_form := _texts(AttackLint.carriers_among(charged, {}, mods, {}))
	assert_array(for_form).contains_exactly(["Sniper (mod: the replacement main's empowered form)"])


# effective_main empowers the MAIN and nothing else, so the same form hung on an extra or a grant is
# never fired -- and must still read as the orphan it is.
func test_only_a_mains_empowered_form_is_carried() -> void:
	var charged := _named("Charged")
	var spray := _named("Spray")
	spray.empowered_form = charged
	var spitter := WeaponData.new()
	spitter.main_attack = spray
	var on_main := _texts(AttackLint.carriers_among(charged, {"Spitter": spitter}, {}, {}))
	assert_array(on_main).contains_exactly(["Spitter (family: the main's empowered form)"])

	var side := _named("Side")
	side.empowered_form = charged
	var other := WeaponData.new()
	other.main_attack = _named("Plain")
	other.extra_attacks = [side] as Array[WeaponAttackData]
	var mod := WeaponModData.new()
	mod.granted_attacks = [side] as Array[WeaponAttackData]
	assert_array(AttackLint.carriers_among(charged, {"Other": other}, {"Grant": mod}, {})).override_failure_message(
		"an extra's or a grant's empowered form is never fired, but was reported carried").is_empty()


# A payload goes off whatever level it sits at, so the carrier of the attack at the top of the chain
# carries every one below it.
func test_a_payload_any_depth_below_a_carried_attack_is_carried() -> void:
	var deep := _named("Deep")
	var mid := _named("Mid")
	mid.payload = deep
	var thrown := _named("Thrown")
	thrown.payload = mid
	var mod := WeaponModData.new()
	mod.granted_attacks = [thrown] as Array[WeaponAttackData]
	var texts := _texts(AttackLint.carriers_among(deep, {}, {"Lobber": mod}, {}))
	assert_array(texts).contains_exactly(["Lobber (mod: dropped by Thrown)"])


# A carving may drop a weapon attack (the payload picker offers both), so a rune is a carrier too.
func test_a_carvings_payload_is_carried_by_its_rune() -> void:
	var shrapnel := _named("Shrapnel")
	var burst := TransmutationData.new()
	burst.display_name = "Burst"
	burst.payload = shrapnel
	var rune := RuneData.new()
	rune.inscriptions = [burst] as Array[TransmutationData]
	var rows := AttackLint.carriers_among(shrapnel, {}, {}, {"Ember": rune})
	assert_array(_texts(rows)).contains_exactly(["Ember (rune: dropped by Burst)"])
	assert_int(rows[0]["kind"]).is_equal(AttackLint.Carrier.RUNE)


func test_a_template_says_family_or_prototype_and_main_or_extra() -> void:
	var swing := _named("Swing")
	var base := WeaponData.new()
	base.main_attack = swing
	var jaw := WeaponData.new()
	jaw.is_prototype = true
	jaw.main_attack = _named("Bite")
	jaw.extra_attacks = [swing] as Array[WeaponAttackData]
	var texts := _texts(AttackLint.carriers_among(swing, {"Sword": base, "The Jaw": jaw}, {}, {}))
	assert_array(texts).contains_exactly_in_any_order(["Sword (family: main)", "The Jaw (prototype: extra)"])


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


# ==============================================================================
#  A carving's empowered form (#695): every finding DEGRADES
# ==============================================================================

func _formed(recipe := "Break(F, A) + Push(F2)") -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = "Probe"
	t.recipe = recipe
	P.point(t, 2, 2)
	t.empowered = EmpoweredForm.new()
	t.empowered.power_bonus = -1
	return t


# Only the form's rows: a bare fixture carving may draw unrelated findings of its own.
func _form_rows(attack: TransmutationData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in AttackLint.check(attack):
		if String(row["text"]).contains("mpowered form"):
			out.append(row)
	return out


func _all_degrade(rows: Array[Dictionary]) -> void:
	for row in rows:
		assert_int(row["severity"]).override_failure_message(
			"a form finding must never block the panel that repairs it: %s" % row["text"]) \
			.is_equal(AttackLint.Severity.DEGRADES)


func test_a_sound_carving_form_is_clean() -> void:
	var carving := _formed()
	carving.empowered.attack_shape = P.shape([Vector2i.ZERO, Vector2i.UP, Vector2i.DOWN] as Array[Vector2i])
	assert_array(_form_rows(carving)).is_empty()


func test_a_form_that_changes_nothing_degrades() -> void:
	var carving := _formed()
	carving.empowered.power_bonus = 0
	var rows := _form_rows(carving)
	assert_int(rows.size()).is_equal(1)
	assert_str(rows[0]["text"]).contains("changes nothing")
	_all_degrade(rows)


func test_a_form_requiring_an_element_the_recipe_never_uses_degrades() -> void:
	var carving := _formed()
	carving.empowered.requires.assign([Elemental.Element.FIRE, Elemental.Element.WATER])
	var rows := _form_rows(carving)
	assert_int(rows.size()).is_equal(1)
	assert_str(rows[0]["text"]).contains("Water")
	_all_degrade(rows)


func test_a_form_on_a_carving_that_delivers_nothing_degrades_until_ticked() -> void:
	var carving := _formed("Quicken(F)")
	assert_array(carving.damage_elements()).override_failure_message(
		"fixture: this recipe must deliver nothing").is_empty()
	var rows := _form_rows(carving)
	assert_int(rows.size()).is_equal(1)
	assert_str(rows[0]["text"]).contains("never fire")
	_all_degrade(rows)

	carving.empowered.requires.assign([Elemental.Element.FIRE])
	assert_array(_form_rows(carving)).override_failure_message(
		"a ticked checklist still read as a form that never fires").is_empty()


func test_a_form_with_swing_and_no_shape_degrades() -> void:
	var carving := _formed()
	carving.empowered.swing = true
	var rows := _form_rows(carving)
	assert_int(rows.size()).is_equal(1)
	assert_str(rows[0]["text"]).contains("Swing")
	_all_degrade(rows)


# The form's own geometry is the base's checks asked of the derived carving, re-filed as DEGRADES.
func test_a_forms_empty_stamp_degrades_rather_than_blocks() -> void:
	var carving := _formed()
	carving.empowered.attack_shape = P.shape([] as Array[Vector2i])
	var rows: Array[Dictionary] = []
	for row in AttackLint.check(carving):
		if String(row["text"]).begins_with("Empowered form:"):
			rows.append(row)
	assert_int(rows.size()).is_equal(1)
	assert_str(rows[0]["text"]).contains("lands on no cells")
	_all_degrade(rows)


# --- a carving carries a body only with a Push (#1637, loosened by #1621) ----------------------
#
# The shove stays authored (verbs never move geometry), and the lint flags a carving that shoves with
# no Push in its recipe. Shoving is not Air's alone (#1621): air, water, rock and a blast's flame may
# all carry a body. Only that clause says " shoves ".

func _carving(recipe: String, knockback: int) -> TransmutationData:
	var t := TransmutationData.new()
	t.display_name = "Probe"
	t.recipe = recipe
	P.point(t, 2, 2)
	t.knockback = knockback
	return t


func _shove_rows(attack: AttackData) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in AttackLint.check(attack):
		if String(row["text"]).contains(" shoves "):
			out.append(row)
	return out


# Air, flame, water and rock, and a Push that is not the recipe's last step.
func test_a_carving_that_pushes_anything_may_shove() -> void:
	for recipe in ["Push(A2)", "Push(F2)", "Push(3W2)", "Push(2E2)", "Push(A2) + Pull(A2)"]:
		var carving := _carving(recipe, 1)
		assert_bool(carving.parsed().is_legal()).override_failure_message(
			"%s did not parse -- the fixture is broken, not the lint" % recipe).is_true()
		assert_array(_shove_rows(carving)).override_failure_message(
			"%s pushes something, yet its shove was flagged" % recipe).is_empty()


func test_a_carving_that_shoves_with_no_push_at_all_degrades() -> void:
	var rows := _shove_rows(_carving("Bind(F, F) + Spread(F2)", 1))
	assert_int(rows.size()).is_equal(1)
	assert_str(rows[0]["text"]).is_equal("Probe shoves 1 tile, but its recipe has no Push to carry anyone.")
	_all_degrade(rows)


# The form keeps its base's recipe, so a shove only the form adds is flagged on the form.
func test_a_shove_only_the_empowered_form_adds_is_flagged_on_the_form() -> void:
	var carving := _carving("Bind(F, F) + Spread(F2)", 0)
	carving.empowered = EmpoweredForm.new()
	carving.empowered.knockback_bonus = 1
	var rows := _shove_rows(carving)
	assert_int(rows.size()).is_equal(1)
	assert_str(rows[0]["text"]).is_equal(
		"Probe's empowered form shoves 1 tile, but its recipe has no Push to carry anyone.")
	_all_degrade(rows)


# Fireblast's shape: a base that pushes flame and shoves nobody, a form that adds the shove.
func test_a_form_may_shove_when_its_base_has_a_push() -> void:
	var carving := _carving("Push(F2)", 0)
	carving.empowered = EmpoweredForm.new()
	carving.empowered.knockback_bonus = 1
	assert_array(_shove_rows(carving)).is_empty()


func test_a_carving_that_shoves_nobody_is_not_flagged() -> void:
	assert_array(_shove_rows(_carving("Bind(F, F) + Spread(F2)", 0))).is_empty()


# A weapon's shove has no recipe to answer to: Blowback's kind of attack shoves freely.
func test_a_weapon_attacks_shove_is_never_flagged() -> void:
	var attack := _manhattan(1, 1)
	attack.knockback = 1
	assert_array(_shove_rows(attack)).is_empty()


func test_no_shipped_carving_shoves_without_a_push() -> void:
	var carvings := TransmutationCatalog.get_all()
	assert_bool(carvings.is_empty()).override_failure_message(
		"no carvings scanned -- the scan is broken, not the content").is_false()
	var offenders: Array[String] = []
	for key in carvings:
		for row in _shove_rows(carvings[key]):
			offenders.append("%s: %s" % [key, row["text"]])
	assert_array(offenders).is_empty()
