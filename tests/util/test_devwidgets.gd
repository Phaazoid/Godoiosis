# Pure-logic guard for the dev-tools reflection editor's enum-hint parsing
# (Classes/dev/DevWidgets.parse_enum_hint). When scaling_stat (since retired, #59) / weapon_type /
# elemental_damage_type became int-backed enums (#7, #28), the editor rendered them
# as number spinners instead of name dropdowns; the fix routes int+PROPERTY_HINT_ENUM
# props through an OptionButton built from this parse. Covers BOTH forms Godot emits:
# contiguous 0-based enums ("A,B,C") and explicit/non-sequential values ("A:0,B:5").
#
# Pure static call — no nodes built — so this stays orphan-clean.
extends GdUnitTestSuite

func test_parses_contiguous_zero_based_hint() -> void:
	var entries := DevWidgets.parse_enum_hint("MHP,STR,LDR,WIL,DEX")
	assert_int(entries.size()).is_equal(5)
	assert_str(entries[0]["name"]).is_equal("MHP")
	assert_int(entries[0]["value"]).is_equal(0)
	assert_str(entries[4]["name"]).is_equal("DEX")
	assert_int(entries[4]["value"]).is_equal(4)

func test_parses_explicit_values_hint() -> void:
	# Non-sequential values must be read from after the colon, not inferred from index.
	var entries := DevWidgets.parse_enum_hint("NONE:0,FIRE:1,SHOCK:7")
	assert_int(entries.size()).is_equal(3)
	assert_str(entries[2]["name"]).is_equal("SHOCK")
	assert_int(entries[2]["value"]).is_equal(7)

func test_empty_hint_yields_no_entries() -> void:
	assert_int(DevWidgets.parse_enum_hint("").size()).is_equal(0)


# --- add_stat_dict (#74) ---
#
# Builds nodes, unlike the pure-parse cases above, so each case auto_frees its container.
#
# The rule worth pinning is that ZERO MEANS ABSENT: this widget edits a SPARSE delta dictionary,
# where "no entry" and "+0" are the same fact. Storing the zero would grow a saved .tres one key
# per stat nobody touched, and every reader uses .get(stat, 0) so the two are indistinguishable
# at read time -- which is exactly why only the FILE can show the difference.
#
# THE CONTAINER MUST BE IN THE TREE, and it is not decoration: a Range outside the scene tree
# takes a programmatic `value =` silently -- the property updates and value_changed never fires --
# so a detached container makes both cases below pass against a widget that writes nothing.
# Measured 4.7.1, detached vs in-tree, after a first probe run inside SceneTree._init lied about
# the in-tree case too (nothing is wired up that early).

func _spinboxes(node: Node) -> Array[SpinBox]:
	var found: Array[SpinBox] = []
	for child in node.get_children():
		var spin := child as SpinBox
		if spin != null:
			found.append(spin)
		found.append_array(_spinboxes(child))
	return found

# The row order is STAT_DEFAULTS' own, which is what add_stat_dict iterates -- derived rather than
# a literal index, so appending a stat to the enum cannot silently re-aim these cases.
func _row_for(stat: Stats.Stat) -> int:
	return Stats.STAT_DEFAULTS.keys().find(stat)

func test_a_stat_dict_row_writes_the_value_it_is_given() -> void:
	var box: VBoxContainer = auto_free(VBoxContainer.new())
	add_child(box)   # see the header: a detached Range never fires value_changed
	var values: Dictionary[Stats.Stat, int] = {}
	DevWidgets.add_stat_dict(box, "Modifiers", values)

	var spins := _spinboxes(box)
	assert_int(spins.size()).is_equal(Stats.STAT_DEFAULTS.size())   # one per stat, no more
	spins[_row_for(Stats.Stat.PER)].value = 4
	assert_int(values.get(Stats.Stat.PER, 0)).is_equal(4)
	assert_int(values.size()).is_equal(1)   # and it wrote ONLY that stat

func test_setting_a_stat_dict_row_back_to_zero_erases_the_key() -> void:
	var box: VBoxContainer = auto_free(VBoxContainer.new())
	add_child(box)   # see the header: a detached Range never fires value_changed
	var values: Dictionary[Stats.Stat, int] = {Stats.Stat.STR: 3}
	DevWidgets.add_stat_dict(box, "Modifiers", values)

	var spins := _spinboxes(box)
	assert_float(spins[_row_for(Stats.Stat.STR)].value).is_equal(3.0)   # shows what it was handed
	spins[_row_for(Stats.Stat.STR)].value = 0
	assert_bool(values.has(Stats.Stat.STR)).is_false()
