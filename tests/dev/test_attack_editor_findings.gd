# What the Attack Editor SAYS about AttackLint's DEGRADES tier: the save line and the extras list.
#
# The save line is an ORDERING bug's guard. _refuse_unfireable says the warning BEFORE the write, and
# DevWidgets.save_over clears the line once a save lands (#168), so a check of the line before the save
# passes against the bug. Every case here reads the line AFTER the write, through the real door: the
# Save As button (the save with no confirm), and the Update and family handlers the confirm calls.
#
# NOTHING HERE TOUCHES SHIPPED CONTENT. Every attack and family is synthetic. Update writes under
# user://; Save As can only write into the real library folder, so its file is removed in after_test
# as well as named so nothing could mistake it (test_shape_library.gd's precedent).
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")

const SAVE_AS_NAME := "__test_save_line"
const SAVE_AS_PATH := WeaponAttackCatalog.LIBRARY_DIR + SAVE_AS_NAME + ".tres"
const UPDATE_PATH := "user://__test_save_line_update.tres"
const FAMILY_PATH := "user://__test_save_line_family.tres"
const MAIN_PATH := "user://__test_save_line_main.tres"

var _scene: Node3D
var _editor: AttackEditorTool


func before_test() -> void:
	_scene = SCENE.instantiate() as Node3D
	_scene.auto_play = false
	get_tree().root.add_child(_scene)
	await await_idle_frame()
	var dev_overlay := _scene.get_node("Main/DevOverlay") as DevOverlay
	_editor = dev_overlay.get_node("%Attack Editor") as AttackEditorTool


func after_test() -> void:
	get_tree().root.remove_child(_scene)
	_scene.free()
	for path in [SAVE_AS_PATH, UPDATE_PATH, FAMILY_PATH, MAIN_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


# A weapon attack whose blend totals 60: DEGRADES, never BLOCKS, so every save below goes through.
func _off_blend(attack_name: String) -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.display_name = attack_name
	attack.scaling_blend = {Stats.Stat.STR: 60}
	return attack


func _open(attack: WeaponAttackData) -> void:
	_editor._mode = AttackEditorTool.Mode.WEAPON_ATTACK
	_editor.current_template = null
	_editor.current = attack
	_editor._stage_fields()
	_editor.populate()


func _only_warning(attack: AttackData) -> String:
	var findings := AttackLint.check(attack)
	assert_int(findings.size()).override_failure_message(
		"the probe attack should carry exactly one finding, so the expected line below means something"
	).is_equal(1)
	assert_int(findings[0]["severity"]).is_equal(AttackLint.Severity.DEGRADES)
	return findings[0]["text"]


func _save_as() -> void:
	_editor.name_input.text = SAVE_AS_NAME
	_editor.save_as_button.pressed.emit()
	assert_bool(FileAccess.file_exists(SAVE_AS_PATH)).override_failure_message(
		"Save As wrote nothing, so the line below says nothing about a landed save").is_true()


# --- Save As: no confirm, so the line after the write is the only one the dev ever sees -----------

func test_a_save_as_with_a_warning_says_the_save_and_the_warning() -> void:
	_open(_off_blend("Loaded Name"))

	_save_as()

	var warning := _only_warning(_editor.current)
	assert_str(_editor.status_label.text).override_failure_message(
		"a landed Save As lost its DEGRADES warning: the line reads '%s'" % _editor.status_label.text
	).is_equal("Saved %s -- %s" % [SAVE_AS_NAME, warning])


# The warning names the attack, and a Save As renames it first: judged before the rename, the line
# would say the save under one name and the fault under the other.
func test_a_save_as_warning_names_the_new_file_not_the_loaded_one() -> void:
	_open(_off_blend("Loaded Name"))

	_save_as()

	assert_str(_editor.status_label.text).not_contains("Loaded Name")


func test_a_clean_save_as_says_only_the_save() -> void:
	var clean := WeaponAttackData.new()
	clean.display_name = "Clean"
	assert_array(AttackLint.check(clean)).override_failure_message(
		"a fresh weapon attack is no longer lint-clean, so this case proves nothing").is_empty()
	_open(clean)

	_save_as()

	assert_str(_editor.status_label.text).is_equal("Saved %s" % SAVE_AS_NAME)


# --- Update: the warning shows while the confirm is open, and has to come back after the Yes -----

func test_an_update_with_a_warning_says_the_save_and_the_warning() -> void:
	var attack := _off_blend("Updated")
	_open(attack)

	_editor._update_confirmed(UPDATE_PATH)

	assert_bool(FileAccess.file_exists(UPDATE_PATH)).is_true()
	assert_str(_editor.status_label.text).is_equal("Saved Updated -- %s" % _only_warning(attack))


func test_a_family_update_says_its_mains_warning() -> void:
	var main := _off_blend("Probe Main")
	var family := WeaponData.new()
	family.display_name = "Probe Family"
	family.main_attack = main
	_editor._mode = AttackEditorTool.Mode.FAMILY
	_editor.current_template = family
	_editor.current = main
	_editor._loaded_name = "Probe Family"
	_editor._stage_fields()
	_editor.populate()

	_editor._update_family_confirmed(FAMILY_PATH, MAIN_PATH)

	assert_bool(FileAccess.file_exists(FAMILY_PATH)).is_true()
	assert_str(_editor.status_label.text).is_equal("Saved Probe Family -- %s" % _only_warning(main))


# --- The extras list: each finding in its own words -----------------------------------------------

# The row used to carry one fixed phrase per tier, so a look fault read "blend does not total 100%".
# Every finding the lint returns for an extra must appear as its own sentence.
func test_each_extra_lists_its_findings_in_the_lints_own_words() -> void:
	var loose_look := WeaponAttackData.new()
	loose_look.display_name = "Loose Look"
	loose_look.effect_looks[Elemental.Element.SHOCK] = EffectLook.new()
	var family := WeaponData.new()
	family.display_name = "Probe Family"
	family.extra_attacks.append(_off_blend("Off Blend"))
	family.extra_attacks.append(loose_look)
	_editor._mode = AttackEditorTool.Mode.FAMILY
	_editor.current_template = family
	_editor.current = null
	_editor._loaded_name = "Probe Family"
	_editor.populate()

	var shown: Array[String] = []
	for child in _editor.editor_container.get_children():
		if child is Label:
			shown.append((child as Label).text)
	for extra: WeaponAttackData in family.extra_attacks:
		var findings := AttackLint.check(extra)
		assert_bool(findings.is_empty()).override_failure_message(
			"%s carries no finding, so this case proves nothing about it" % extra.display_name).is_false()
		for finding in findings:
			var line := "%s: %s" % [AttackLint.severity_word(finding), finding["text"]]
			assert_bool(shown.has(line)).override_failure_message(
				"%s's finding is not listed under it: '%s'" % [extra.display_name, line]).is_true()
	assert_bool(shown.any(func(text: String) -> bool: return text.contains("blend does not total"))) \
		.override_failure_message("the old fixed phrase is still drawn").is_false()
