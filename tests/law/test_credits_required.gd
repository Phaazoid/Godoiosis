# The credits DATA law (#139). The screen-side property — that every required row reaches the
# player — lives in tests/ui/test_credits_screen.gd; this is the half that keeps it from passing
# vacuously.
#
# WHY THIS SUITE EXISTS AT ALL. The UI case loops over Credits.required_entries(). Delete the
# `required` flags and that loop iterates zero times and goes GREEN, having asserted nothing, on
# the exact change that drops a licence condition out of the build. An empty collection satisfying
# a for-loop is the same shape as a Packed*Array passing assert_array().is_empty() (#629): the
# assertion is real, the input is not.
#
# Content is NOT pinned here. No case names a person or counts rows — those are authored values
# the dev may re-word or add to. What is pinned is the SHAPE: required rows exist, and each one
# carries what an attribution needs to be one.
extends GdUnitTestSuite


func test_at_least_one_credit_is_a_licence_condition() -> void:
	# The guard on the UI suite. Two grants were made on condition of attribution as of 2026-09-12
	# (Sara Shen; Jamie Brownhill / World of Solaria) -- but this asserts "some", never "two", so
	# resolving or adding a grant is not a test edit.
	assert_int(Credits.required_entries().size()).override_failure_message(
		"no credit is marked required, so test_every_required_credit_is_on_the_page asserts " +
		"nothing -- if a licence condition was genuinely lifted, say so on #139 first") \
		.is_greater(0)


func test_every_required_credit_can_actually_be_rendered_as_one() -> void:
	# A required row with no name credits nobody; one with no detail drops the handle or link the
	# grant asked for. Either satisfies the UI loop while failing the terms.
	for entry: Dictionary in Credits.required_entries():
		assert_str(String(entry.get("name", ""))).override_failure_message(
			"a required credit has no name").is_not_empty()
		assert_str(String(entry.get("detail", ""))).override_failure_message(
			"required credit '%s' carries no attribution detail -- a grant conditioned on a " % entry.get("name", "")
			+ "name AND a link is not satisfied by the name").is_not_empty()


func test_every_entry_declares_the_keys_the_screen_reads() -> void:
	# CreditsScreen reads name/role/detail/required off every row. A row missing one renders blank
	# rather than failing, so the omission is invisible in play.
	var rows: Array[Dictionary] = Credits.all_entries()
	assert_int(rows.size()).override_failure_message("the credits table is empty").is_greater(0)
	for entry: Dictionary in rows:
		for key: String in ["name", "role", "detail", "required"]:
			assert_bool(entry.has(key)).override_failure_message(
				"a credits row is missing the '%s' key: %s" % [key, str(entry)]).is_true()
		assert_str(String(entry.get("name", ""))).override_failure_message(
			"a credits row has no name: %s" % str(entry)).is_not_empty()


func test_every_section_the_enum_declares_has_a_name() -> void:
	# The screen titles each section from SECTION_NAMES. A new enum member without a row there
	# renders a section with no heading.
	for section: Credits.Section in Credits.Section.values():
		assert_bool(Credits.SECTION_NAMES.has(section)).override_failure_message(
			"Credits.Section member %d has no SECTION_NAMES entry" % section).is_true()
