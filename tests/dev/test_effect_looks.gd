# THE ATTACK EDITOR'S LOOK SECTION (#900) -- a section that exists only when the loaded attack
# carries an element with an attack-scoped effect, and a page of override rows under it.
#
# What is worth pinning is what a glance at the panel cannot confirm. That the section APPEARS AND
# GOES is the wire: relevance is the resource's answer (hidden_fields) applied live off `changed`,
# so a case holds a node across the edit and asserts on that same node -- the only way to tell a
# reflow from a redraw. That the heading goes WITH its rows is the half #825 did not need, because
# no section could be empty until this one.
#
# The rows themselves are a PROJECTION of GameKnobs.CLASS_KNOBS, so the laws here are about the two
# halves agreeing: every element declared lookable has rows, every group named has a sub-tab, and a
# saved look holds no key that names a row nobody has any more.
#
# NOTHING HERE TOUCHES SHIPPED CONTENT (the content razor): every attack is built, and the one case
# needing a file on disk writes it under user://.
extends GdUnitTestSuite

# preload, never load(): a per-test load() reloads the 5 MB mesh library every case (#621).
const SCENE: PackedScene = preload("res://Scenes/Battle3D/Battle3D.tscn")

# The one file any case here writes, into the real library dir because that is the only place the
# catalog looks. Removed in after_test as well as where it is written.
const PROBE_LOOK := "__test_probe_fire_look"
const PROBE_PATH := EffectLookCatalog.LIBRARY_DIR + PROBE_LOOK + ".tres"

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
	# FALSE orphans, not a leak (tests/README.md #162): populate() tears its rows down with
	# remove_child + queue_free, and a parentless-pending node is what the monitor counts.
	await await_idle_frame()
	get_tree().root.remove_child(_scene)
	_scene.free()
	if FileAccess.file_exists(PROBE_PATH):
		DirAccess.remove_absolute(PROBE_PATH)


# --- helpers -------------------------------------------------------------------------------

func _open(attack: AttackData) -> void:
	_editor._mode = AttackEditorTool.Mode.WEAPON_ATTACK
	_editor.current = attack
	_editor._loaded_name = ""
	_editor._stage_fields()
	_editor.populate()


func _shock_attack() -> WeaponAttackData:
	var attack := WeaponAttackData.new()
	attack.display_name = "Probe Shock"
	attack.elemental_damage_type = Elemental.Element.SHOCK
	return attack


func _all_of(node: Node, klass: String, found: Array[Node]) -> Array[Node]:
	for child in node.get_children():
		if child.is_class(klass):
			found.append(child)
		_all_of(child, klass, found)
	return found


func _labels() -> PackedStringArray:
	var texts: PackedStringArray = []
	for node in _all_of(_editor.editor_container, "Label", []):
		texts.append((node as Label).text)
	return texts


# The Label carrying this text, or null. Visibility is asked of it rather than of the string,
# because a hidden row is still IN the tree -- hiding is a reflow, never a rebuild.
func _label(text: String) -> Label:
	for node in _all_of(_editor.editor_container, "Label", []):
		if (node as Label).text == text:
			return node as Label
	return null


func _checkbox(text: String) -> CheckBox:
	for node in _all_of(_editor.editor_container, "CheckBox", []):
		if (node as CheckBox).text == text:
			return node as CheckBox
	return null


# --- the section only exists where it applies -----------------------------------------------

const SECTION := "What its element looks like"


func test_an_ordinary_attack_gets_no_look_section() -> void:
	_open(WeaponAttackData.new())

	var heading := _label(SECTION)
	assert_bool(heading == null or not heading.visible).override_failure_message(
		"a sword swing is offered a section for an elemental effect it does not have"
	).is_true()


func test_a_shock_attack_gets_one() -> void:
	_open(_shock_attack())

	var heading := _label(SECTION)
	assert_object(heading).override_failure_message(
		"the look section was never drawn for an authored shock attack").is_not_null()
	assert_bool(heading.visible).is_true()
	assert_bool(_labels().has("Shock look")).override_failure_message(
		"the section drew no picker for the element the attack carries").is_true()


# THE WIRE, and the reason the heading is derived rather than declared: the section's rows hide off
# `changed` like every other row, and a title left standing over nothing is what this asserts is not
# happening. Held ACROSS the edit, so a rebuild would fail the assertion rather than pass it.
func test_the_section_goes_when_the_element_does() -> void:
	var attack := _shock_attack()
	_open(attack)
	var heading := _label(SECTION)
	assert_bool(heading.visible).is_true()

	attack.elemental_damage_type = Elemental.Element.NONE
	attack.emit_changed()

	assert_bool(heading.visible).override_failure_message(
		"the heading stayed up over a section whose every row had hidden"
	).is_false()


func test_the_section_comes_back_when_the_element_does() -> void:
	var attack := WeaponAttackData.new()
	_open(attack)
	var heading := _label(SECTION)

	attack.elemental_damage_type = Elemental.Element.SHOCK
	attack.emit_changed()

	assert_bool(heading.visible).override_failure_message(
		"the section could hide and could not come back, so hiding has a side effect"
	).is_true()


# A CARVING's element is DERIVED -- Fire plus Quickening resolves to SHOCK -- so the section is
# offered on the thing the rule produces rather than on a field somebody typed.
func test_a_carving_that_resolves_to_shock_is_offered_the_section_too() -> void:
	var carving := TransmutationData.new()
	carving.display_name = "Probe Rune"
	carving.sigils = [Elemental.Element.FIRE] as Array[Elemental.Element]
	carving.flourishes = [Flourish.Type.QUICKENING] as Array[Flourish.Type]
	assert_array(carving.authored_elements()).override_failure_message(
		"Fire + Quickening stopped resolving to SHOCK, so this case is testing nothing"
	).contains([Elemental.Element.SHOCK])

	_editor._mode = AttackEditorTool.Mode.TRANSMUTATION
	_editor.current = carving
	_editor._loaded_name = ""
	_editor._stage_fields()
	_editor.populate()

	assert_bool(_labels().has("Shock look")).override_failure_message(
		"a carving that fires shock cannot author what its shock looks like").is_true()


# --- the rows, and what an inherit tick DOES ------------------------------------------------

# An attack with a look but no opinions draws every row of its element, each inheriting.
func _with_look(overrides: Dictionary = {}) -> EffectLook:
	var attack := _shock_attack()
	var look := EffectLook.new()
	look.element = Elemental.Element.SHOCK
	look.overrides = overrides
	attack.effect_looks[Elemental.Element.SHOCK] = look
	_open(attack)
	return look


func test_a_picked_look_draws_every_row_its_element_owns() -> void:
	_with_look()
	var rows := GameKnobs.look_rows(Elemental.Element.SHOCK)
	assert_int(rows.size()).override_failure_message(
		"SHOCK has no rows at all, so this case is testing nothing").is_greater(10)

	var missing: Array[String] = []
	for knob: Dictionary in rows:
		if _checkbox("%s - inherit" % knob["label"]) == null:
			missing.append(knob["label"])
	assert_array(missing).override_failure_message(
		"rows the Game tab offers are unreachable in the attack editor: %s" % str(missing)
	).is_empty()


# An inheriting row SHOWS what it falls back to. A row that cannot name its default sends you to
# the other panel to find out what you are about to override -- ObjectTool's own rule.
func test_an_inheriting_row_says_what_it_inherits() -> void:
	_with_look()
	var shown := false
	for text in _labels():
		if text.begins_with("    inherits "):
			shown = true
			break
	assert_bool(shown).override_failure_message(
		"no row says what it falls back to").is_true()


# Unticking adopts the value the row RESOLVES to, so turning an override on never moves the effect
# by itself. The same invariant ObjectTool's own unticking keeps.
func test_unticking_inherit_adopts_the_value_the_row_already_resolved_to() -> void:
	var look := _with_look()
	var before: float = ArcLightning.bolt_life

	_checkbox("Bolt lifetime - inherit").toggled.emit(false)

	assert_bool(look.overrides.has("bolt_life")).override_failure_message(
		"unticking inherit wrote no override at all").is_true()
	assert_float(float(look.overrides["bolt_life"])).override_failure_message(
		"unticking inherit moved the value, so switching a row to authored changes the effect"
	).is_equal_approx(before, 0.001)


# Re-ticking ERASES rather than writing a sentinel -- the whole reason this storage has none, and
# what makes a row authored to its own default still an override.
func test_re_ticking_inherit_erases_the_key_rather_than_storing_one() -> void:
	var look := _with_look({"bolt_life": 9.0})

	_checkbox("Bolt lifetime - inherit").toggled.emit(true)

	assert_bool(look.overrides.has("bolt_life")).override_failure_message(
		"inheriting again left a key behind, so the file records an opinion nobody has"
	).is_false()


# A slider hands back a float whatever the value's kind is, so an INT row has to be coerced -- from
# the storage's own type, never from a list of which rows are ints.
func test_an_int_row_is_stored_as_an_int() -> void:
	var look := _with_look({"bolt_segments": 6})

	_editor._set_look_value(look, "bolt_segments", 8.7)

	assert_int(typeof(look.overrides["bolt_segments"])).override_failure_message(
		"a float landed in a row whose value is a whole number").is_equal(TYPE_INT)
	assert_int(int(look.overrides["bolt_segments"])).is_equal(8)


# --- the picker only offers what fits the slot ----------------------------------------------

# A slot offered another element's look is exactly the mismatch AttackLint reports, so the control
# refuses to create it: the picker lists this element's looks and nothing else.
#
# Asked of the FILTER over a library built here rather than of the catalog over a file written into
# Resources/ -- the content razor, and the scan half is ResourceCatalog's own answer, pinned there.
func test_the_picker_lists_only_looks_authored_for_its_own_element() -> void:
	var fire := EffectLook.new()
	fire.element = Elemental.Element.FIRE
	var shock := EffectLook.new()
	shock.element = Elemental.Element.SHOCK
	var library := {"a fire look": fire, "a shock look": shock}

	var offered := EffectLookCatalog.matching(library, Elemental.Element.SHOCK)

	assert_bool(offered.has("a shock look")).override_failure_message(
		"a shock slot was not offered a shock look, so the filter refuses everything").is_true()
	assert_bool(offered.has("a fire look")).override_failure_message(
		"a shock slot was offered a look authored for fire").is_false()


# ...and the picker the panel builds asks THAT question rather than listing the whole library. The
# wire between the two halves above, and the one a case over a pure filter cannot see.
#
# IT HAS TO WRITE A FILE, and the reason is worth stating: the look folder is empty until the dev
# saves his first one, so a case reading the live catalog would find nothing and pass whatever the
# slot listed. test_shape_library.gd's Save As case sets the precedent of writing into the real
# library dir; the cleanup is in after_test as well as inline, so a case that dies part-way cannot
# leave the tree dirty.
func test_the_slots_picker_asks_for_its_own_element() -> void:
	var fire := EffectLook.new()
	fire.display_name = PROBE_LOOK
	fire.element = Elemental.Element.FIRE
	# The folder does not exist until the first look is saved -- DevWidgets.save_over makes it on the
	# real path, and ResourceSaver on its own does not.
	DirAccess.make_dir_recursive_absolute(EffectLookCatalog.LIBRARY_DIR)
	assert_int(ResourceSaver.save(fire, PROBE_PATH)).override_failure_message(
		"could not write a probe look, so the filter below proves nothing").is_equal(OK)

	_open(_shock_attack())
	var field: LibraryField = _editor._looks[Elemental.Element.SHOCK]
	var listed: Dictionary = field.list.call()

	assert_bool(EffectLookCatalog.get_library().has(PROBE_LOOK)).override_failure_message(
		"the catalog cannot see the probe at all, so the filter below proves nothing").is_true()
	assert_bool(listed.has(PROBE_LOOK)).override_failure_message(
		"the shock slot's picker offered a look authored for fire").is_false()


# A NEW look is stamped with the slot's element, so the panel structurally cannot author the
# mismatch in the first place.
func test_a_new_look_is_stamped_with_the_element_it_was_made_for() -> void:
	_open(_shock_attack())
	var field: LibraryField = _editor._looks[Elemental.Element.SHOCK]

	var fresh := field.make.call() as EffectLook

	assert_int(fresh.element).override_failure_message(
		"a look made in a shock slot does not say it is a shock look").is_equal(Elemental.Element.SHOCK)


# --- the two halves agree --------------------------------------------------------------------

# EffectLook.LOOKABLE is what SHIPPING code reads (the editor asks which sections to draw);
# GameKnobs.LOOK_GROUPS is what the DEV side reads (which rows each has). They are two files because
# one must not import the other, which is exactly why they can drift.
func test_every_lookable_element_has_rows_and_every_element_with_rows_is_lookable() -> void:
	var rowless: Array[String] = []
	for element: Elemental.Element in EffectLook.LOOKABLE:
		if GameKnobs.look_rows(element).is_empty():
			rowless.append(Elemental.display_name(element))
	assert_array(rowless).override_failure_message(
		"an element is offered a look section with no rows under it: %s" % str(rowless)).is_empty()

	var unlisted: Array[String] = []
	for element: Elemental.Element in GameKnobs.LOOK_GROUPS:
		if not EffectLook.is_lookable(element):
			unlisted.append(Elemental.display_name(element))
	assert_array(unlisted).override_failure_message(
		"rows are declared for an element no attack can author: %s" % str(unlisted)).is_empty()


# Every group a look draws must resolve to a sub-tab, or the Game tab would draw those same rows
# nowhere -- the law test_game_knobs.gd keeps for the table as a whole, asked of this projection.
func test_every_look_group_has_a_sub_tab() -> void:
	var homeless: Array[String] = []
	for element: Elemental.Element in GameKnobs.LOOK_GROUPS:
		for group: String in GameKnobs.LOOK_GROUPS[element]:
			if not GameKnobs.GROUP_TABS.has(group):
				homeless.append(group)
	assert_array(homeless).override_failure_message(
		"a look group has no tab: %s" % str(homeless)).is_empty()


# A group named here that names no ROW is the other direction, and it is how a group rename goes
# quiet: the section simply stops being offered, with nothing to say so.
func test_every_look_group_names_at_least_one_row() -> void:
	var empty: Array[String] = []
	for element: Elemental.Element in GameKnobs.LOOK_GROUPS:
		for group: String in GameKnobs.LOOK_GROUPS[element]:
			var found := false
			for knob: Dictionary in GameKnobs.CLASS_KNOBS:
				if knob.get("group", "") == group:
					found = true
					break
			if not found:
				empty.append(group)
	assert_array(empty).override_failure_message(
		"a look group names no knob at all: %s" % str(empty)).is_empty()


# --- a key nobody reads -----------------------------------------------------------------------

# The one failure this storage has that no panel can show you: a knob RENAME leaves an orphaned key
# behind, and an orphan draws no row, so the file quietly carries an override nothing reads.
func test_a_key_naming_no_live_row_is_reported() -> void:
	var look := EffectLook.new()
	look.element = Elemental.Element.SHOCK
	look.overrides = {"bolt_life": 1.0, "bolt_lenght": 1.0}

	var stale := GameKnobs.stale_look_keys(look)

	assert_array(stale).override_failure_message(
		"a misspelled key was accepted as a live row").contains(["bolt_lenght"])
	assert_bool(stale.has("bolt_life")).override_failure_message(
		"a key that DOES name a row was reported stale").is_false()


# The library sweep, per FILE rather than per attack: a shared look would otherwise be counted once
# per wearer and one nothing wears would never be checked at all. It is VACUOUS while the folder is
# empty, which it is until the dev saves his first look -- so the assertion below is about the
# sweep working, and the message says which state it ran in.
func test_no_saved_look_holds_a_key_that_names_nothing() -> void:
	var library := EffectLookCatalog.get_library()
	var broken: Array[String] = []
	for key in library:
		var look: EffectLook = library[key]
		for stale in GameKnobs.stale_look_keys(look):
			broken.append("%s: %s" % [key, stale])
	assert_array(broken).override_failure_message(
		"a saved look holds overrides nothing reads (scanned %d file(s)): %s" % [library.size(), str(broken)]
	).is_empty()
