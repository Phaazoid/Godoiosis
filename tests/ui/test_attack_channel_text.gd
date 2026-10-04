# AttackChannelText.ally_line (#1083): when an attack says whether it hits allies, and which word it
# uses. Plus the card's gas line (#508) at the bottom. Pure, no scene: the rule is a function of the attack's own footprint and targets. The two
# surfaces that draw it are pinned where they draw -- the battle ring in test_menu_catalogue_rows, the
# rune card in test_rune_detail_card.
#
# Every attack is BUILT here, never loaded: the content razor, and what Resources/ holds is the dev's.
extends GdUnitTestSuite


func _attack(shape: AttackShape) -> AttackData:
	var attack := AttackData.new()
	attack.display_name = "Probe"
	attack.attack_shape = shape
	return attack


func _stamp(cells: Array[Vector2i]) -> AttackShape:
	var shape := AttackShape.new()
	shape.stamp = cells
	return shape


func _row() -> AttackShape:
	var cells: Array[Vector2i] = [Vector2i(-1, 0), Vector2i.ZERO, Vector2i(1, 0)]
	return _stamp(cells)


func test_an_area_attack_says_splashes_or_spares() -> void:
	var sweep := _attack(_row())
	assert_str(AttackChannelText.ally_line(sweep, true)).is_equal("Splashes allies")
	assert_str(AttackChannelText.ally_line(sweep, false)).is_equal("Spares allies")


# Single-target means ONE CELL, whichever way it is authored: no shape at all, or a one-tile stamp.
# Both say nothing either way (dev, 2026-09-28) -- hitting an ally there is a choice of aim.
func test_a_one_cell_attack_says_nothing_either_way() -> void:
	var one_tile: Array[Vector2i] = [Vector2i(0, -1)]
	for attack: AttackData in [_attack(null), _attack(_stamp(one_tile))]:
		assert_str(AttackChannelText.ally_line(attack, true)).is_empty()
		assert_str(AttackChannelText.ally_line(attack, false)).is_empty()


# A single-target SWING is not one cell: its path crosses cells an ally can stand on, and hits_allies
# decides whether that ally is struck or passed through (#1054 ruling 8). So it speaks.
func test_a_single_target_swing_speaks_because_its_path_can_hold_an_ally() -> void:
	var shape := AttackShape.new()
	var path: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, -2), Vector2i(0, -3)]
	var lengths: Array[int] = [3]
	shape.path_cells = path
	shape.path_lengths = lengths
	var lance := _attack(shape)
	lance.swing = true
	assert_bool(lance.is_single_target_swing()).override_failure_message(
		"fixture: this has to be a single-target swing to ask the question").is_true()
	assert_str(AttackChannelText.ally_line(lance, false)).is_equal("Spares allies")


# A map-only attack hits nobody at all (#1135), so "Spares allies" would be true and misleading.
func test_a_map_only_area_says_nothing() -> void:
	var scorch := _attack(_row())
	scorch.targets = EquippableData.TargetMode.MAP
	assert_str(AttackChannelText.ally_line(scorch, true)).is_empty()
	assert_str(AttackChannelText.ally_line(scorch, false)).is_empty()


func test_no_attack_says_nothing() -> void:
	assert_str(AttackChannelText.ally_line(null, true)).is_empty()


# The cards' list carries the same line through the same function: an area attack lists Spares, and a
# one-cell attack authored to hit allies lists nothing about them.
func test_the_cards_list_carries_the_ally_line() -> void:
	var none: Array[Elemental.Element] = []
	var sweep_lines := AttackChannelText.lines(_attack(_row()), 0, none, false, false)
	assert_bool(sweep_lines.has("Spares allies")).override_failure_message(
		"the list never carried the ally line: %s" % [sweep_lines]).is_true()

	var zap_lines := AttackChannelText.lines(_attack(null), 0, none, false, true)
	for line: String in zap_lines:
		assert_str(line).override_failure_message(
			"a one-cell attack's list still speaks about allies: %s" % [zap_lines]).not_contains("allies")


# An attack that leaves gas names it on the card (#508); one that leaves none says nothing about gas.
# Asked by the gas's own name rather than the sentence, which is the dev's to reword.
func test_the_cards_list_names_the_gas_an_attack_leaves() -> void:
	var none: Array[Elemental.Element] = []
	var steam := Gas.display_name(Gas.Kind.STEAM)
	var steamer := _attack(null)
	steamer.gas_amount = 3
	var named := false
	for line: String in AttackChannelText.lines(steamer, 0, none, false, false):
		named = named or line.contains(steam)
	assert_bool(named).override_failure_message("the card never says the attack leaves steam").is_true()
	for line: String in AttackChannelText.lines(_attack(null), 0, none, false, false):
		assert_str(line).not_contains(steam)
