# Pure-logic guard for the dev-tools reflection editor's enum-hint parsing
# (Classes/Util/DevWidgets.parse_enum_hint). When scaling_stat / weapon_type /
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
