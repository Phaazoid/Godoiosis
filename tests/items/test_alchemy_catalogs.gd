# "Does everything authored under Resources/ actually reach the game?" -- the alchemy catalogs
# REFUSE content that breaks its own rules (RuneData.is_legal, TransmutationData.is_legal) with a
# push_error and a skip, and until now nothing asked. `SteamRune.tres` shipped illegal for months:
# it printed "steam: illegal under the two-knob rune rules" twice per dev-tools test case while
# every suite stayed green, because gdUnit4 does NOT red a case on push_error (measured 2026-08-25:
# 22 errors over 11 cases of tests/dev/test_prototype_editor.gd, verdict 0).
#
# THE FAULT IS AN ABSENCE, not an invalid entry -- get_variants() `continue`s past a refusal, so a
# broken rune is simply missing from the dictionary it hands back. So each case reads the
# PRE-refusal listing (the same ResourceCatalog door the catalog itself opens, off the catalog's own
# DIR constant) and asks which names the catalog dropped. Asking is_legal() here instead would be a
# COPY of today's refusal reason, free to go stale the day a catalog grows a second one.
#
# Loads real .tres on purpose -- tests/README.md rule 4's declared shape for a content law, as
# test_weapon_template_lint.gd and test_attack_lint.gd already do. Nothing here asserts what the
# content CONTAINS: no size, temper, sigil or count (rule 9's content razor). The claim is only that
# the shipped set survives its own catalog, and the non-vacuity guards are messages, not thresholds.
extends GdUnitTestSuite


# The names the catalog scanned but did not serve.
func _dropped(on_disk: Dictionary, served: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	for name: String in on_disk:
		if not served.has(name):
			missing.append(name)
	return missing


func test_every_shipped_rune_reaches_the_rune_catalog() -> void:
	var on_disk := ResourceCatalog.by_name(RuneCatalog.VARIANT_DIR, RuneData)
	assert_bool(on_disk.is_empty()).override_failure_message(
		"no rune files scanned -- the scan is broken, not the content").is_false()
	var dropped := _dropped(on_disk, RuneCatalog.get_variants())
	assert_array(dropped).override_failure_message(
		("RuneCatalog refused %s -- a refused rune is missing from every equip list, and its "
		+ "push_error prints on every catalog scan. Re-author it legal (RuneData.is_legal: both "
		+ "knobs plus the temper rule) or delete the file.") % ", ".join(dropped)
	).is_empty()


func test_every_shipped_carving_reaches_the_carving_catalog() -> void:
	var on_disk := ResourceCatalog.by_name(TransmutationCatalog.CARVING_DIR, TransmutationData)
	assert_bool(on_disk.is_empty()).override_failure_message(
		"no carving files scanned -- the scan is broken, not the content").is_false()
	var dropped := _dropped(on_disk, TransmutationCatalog.get_all())
	assert_array(dropped).override_failure_message(
		("TransmutationCatalog refused %s -- a refused carving cannot be offered for inscription "
		+ "by the rune editor. Re-author it legal (TransmutationData.is_legal: base-element sigils "
		+ "only, within the largest circle cap) or delete the file.") % ", ".join(dropped)
	).is_empty()
