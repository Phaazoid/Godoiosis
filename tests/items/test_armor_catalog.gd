# Pins ArmorCatalog (#65) and the authored armor roster: the dev-authored Resources/Armor/
# fixtures scan into a flat name -> ArmorData map, the same shape WeaponCatalog/RuneCatalog
# give the unit editor. Also pins each piece's designed identity -- these three are the first
# real armor content, and each exists to exercise a different half of the model.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


func test_get_editable_finds_the_authored_armors() -> void:
	var armors := ArmorCatalog.get_editable()
	assert_dict(armors).contains_keys(["Bulwark Plate", "Ballast Harness", "Insulated Weave", "Riveted Mail"])


func test_entries_are_armor_data() -> void:
	var armors := ArmorCatalog.get_editable()
	for name in armors:
		assert_object(armors[name]).is_instanceof(ArmorData)


func test_missing_directory_returns_empty_not_null() -> void:
	# Mirrors WeaponCatalog._scan's guard -- a fresh checkout before any armor is authored
	# should read as "nothing yet", never crash.
	assert_dict(ArmorCatalog.get_variants()).is_not_null()


# --- Bulwark Plate: the CON-gated heavy piece, scaled term + flat term ---

func test_bulwark_plate_gates_on_high_con() -> void:
	var plate: ArmorData = ArmorCatalog.get_editable()["Bulwark Plate"]
	var frail: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 7})
	var mighty: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(1, 0), {Stats.Stat.CON: 8})
	assert_bool(plate.can_equip(frail)).is_false()    # one short of the gate
	assert_bool(plate.can_equip(mighty)).is_true()


func test_bulwark_plate_pays_scaled_plus_flat() -> void:
	# def_power 3 at CON 8 -> round(3 * 8 * 0.2) = 5, plus the un-scaled flat 1 = 6.
	var plate: ArmorData = ArmorCatalog.get_editable()["Bulwark Plate"]
	var mighty: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 8})
	mighty.worn_armor = plate
	assert_int(mighty.get_effective_def()).is_equal(6)


# --- Ballast Harness: the inverted gate (a stat CEILING, not a floor) ---

func test_ballast_harness_gates_out_the_nimble() -> void:
	var harness: ArmorData = ArmorCatalog.get_editable()["Ballast Harness"]
	var nimble: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.DEX: 5})
	var lumbering: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(1, 0), {Stats.Stat.DEX: 4})
	assert_bool(harness.can_equip(nimble)).is_false()   # one OVER the ceiling
	assert_bool(harness.can_equip(lumbering)).is_true()


func test_ballast_harness_has_no_flat_term() -> void:
	var harness: ArmorData = ArmorCatalog.get_editable()["Ballast Harness"]
	var wearer: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 5, Stats.Stat.DEX: 3})
	wearer.worn_armor = harness
	assert_int(wearer.get_effective_def()).is_equal(2)   # round(2 * 5 * 0.2), no flat term


# --- Insulated Weave: pays in immunity, not DEF ---

func test_insulated_weave_grants_no_def_and_no_gate() -> void:
	var weave: ArmorData = ArmorCatalog.get_editable()["Insulated Weave"]
	var anyone: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 0, Stats.Stat.DEX: 9})
	assert_bool(weave.can_equip(anyone)).is_true()
	anyone.worn_armor = weave
	assert_int(anyone.get_effective_def()).is_equal(0)


func test_insulated_weave_blocks_shock_only() -> void:
	var weave: ArmorData = ArmorCatalog.get_editable()["Insulated Weave"]
	assert_bool(weave.blocks_element(Elemental.Element.SHOCK)).is_true()
	assert_bool(weave.blocks_element(Elemental.Element.FIRE)).is_false()


func test_the_def_armors_block_nothing() -> void:
	var armors := ArmorCatalog.get_editable()
	for name in ["Bulwark Plate", "Ballast Harness", "Riveted Mail"]:
		var piece: ArmorData = armors[name]
		assert_bool(piece.blocks_element(Elemental.Element.SHOCK)).is_false()


# --- Riveted Mail: no gate, but a live stat tax ---

func test_riveted_mail_is_ungated_and_taxes_dex() -> void:
	var mail: ArmorData = ArmorCatalog.get_editable()["Riveted Mail"]
	var anyone: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 0, Stats.Stat.DEX: 9})
	assert_bool(mail.can_equip(anyone)).is_true()          # the tradeoff IS the cost, not a gate
	assert_int(mail.stat_modifiers[Stats.Stat.DEX]).is_equal(-1)


func test_riveted_mail_scales_off_con_with_no_flat_term() -> void:
	var mail: ArmorData = ArmorCatalog.get_editable()["Riveted Mail"]
	var wearer: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 5})
	wearer.worn_armor = mail
	assert_int(wearer.get_effective_def()).is_equal(4)     # round(4 * 5 * 0.2), nothing flat


# --- the mechanical tooltip readout (#44) ---

func test_mechanical_text_itemizes_both_def_terms() -> void:
	# "DEF 6" is meaningless without saying 6 for WHOM -- the scaled term rides the wearer's CON,
	# so the readout has to show the arithmetic, not just the total.
	var plate: ArmorData = ArmorCatalog.get_editable()["Bulwark Plate"]
	var mighty: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 8})
	var text := plate.mechanical_text(mighty)

	assert_str(text).contains("DEF 6")
	assert_str(text).contains("CON 8")     # the wearer's actual stat, not a printed constant
	assert_str(text).contains("CON 8+")    # ...and the gate, which happens to read the same


func test_mechanical_text_follows_the_wearer() -> void:
	# The same piece reads differently on different bodies. A readout that didn't change here
	# would be quietly lying to whoever is deciding whether to put it on.
	var plate: ArmorData = ArmorCatalog.get_editable()["Bulwark Plate"]
	var strong: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 8})
	var stronger: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(1, 0), {Stats.Stat.CON: 10})
	assert_str(plate.mechanical_text(strong)).is_not_equal(plate.mechanical_text(stronger))


func test_mechanical_text_reports_the_stat_tax() -> void:
	var mail: ArmorData = ArmorCatalog.get_editable()["Riveted Mail"]
	var wearer: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 5})
	assert_str(mail.mechanical_text(wearer)).contains("DEX -1")


func test_mechanical_text_reports_immunity_for_a_zero_def_piece() -> void:
	# The Weave's entire value is invisible in the DEF number -- if the readout didn't name the
	# immunity it would look like a strictly worthless item.
	var weave: ArmorData = ArmorCatalog.get_editable()["Insulated Weave"]
	var wearer: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 5})
	var text := weave.mechanical_text(wearer)

	assert_str(text).contains("DEF 0")
	assert_str(text).contains("Shock")


func test_mechanical_text_omits_what_does_not_apply() -> void:
	# An ungated, untaxing, non-immune piece says only what it does -- no empty "Requires:" lines.
	var harness: ArmorData = ArmorCatalog.get_editable()["Ballast Harness"]
	var wearer: Unit = H.spawn_unit(self, Team.Faction.ENEMY, Vector2i(0, 0), {Stats.Stat.CON: 5, Stats.Stat.DEX: 3})
	var text := harness.mechanical_text(wearer)

	assert_str(text).not_contains("While worn")
	assert_str(text).not_contains("Immune to")
	assert_str(text).contains("DEX 4 or less")   # but it DOES state its gate


func test_only_riveted_mail_taxes_a_stat() -> void:
	# The other three pay their costs as gates or as forgone DEF, never as a live stat drain.
	var armors := ArmorCatalog.get_editable()
	for name in ["Bulwark Plate", "Ballast Harness", "Insulated Weave"]:
		var piece: ArmorData = armors[name]
		assert_bool(piece.stat_modifiers.is_empty()).is_true()
