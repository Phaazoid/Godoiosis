# The Air & gas page (#1534): the air's and the gases' balance numbers, tuned live. Every tunable number
# has a row, and each kind of row moves the rule it names, read back through the rule's own reader one
# hop away (the no-placebo law, tests/dev/test_moods_tool.gd's shape). Every edit re-resolves the plan.
#
# The rules files are SHARED cached objects, so every case puts back what it moved before it asserts.
# Expectations are derived from the files, never a literal: the numbers are the dev's to tune.
extends GdUnitTestSuite

const H := preload("res://tests/support/squad_fixtures.gd")


# Stands in for game.gd: logs the doors the page re-derives through, in the order it calls them.
class StubSquads:
	extends RefCounted
	var active_squad = null


class StubHover:
	extends RefCounted
	var calls: Array[String]

	func _init(sink: Array[String]) -> void:
		calls = sink

	func refresh() -> void:
		calls.append("hover")


class StubGame:
	extends RefCounted
	var squad_manager := StubSquads.new()
	var calls: Array[String] = []
	var hover_presenter: StubHover

	func _init() -> void:
		hover_presenter = StubHover.new(calls)

	func refresh_action_queue(_squad) -> void:
		calls.append("plan")

	func drop_threat_field() -> void:
		calls.append("threats")

	func refresh_mission_status() -> void:
		calls.append("status")


func _page(game = null) -> AirGasTool:
	var page := AirGasTool.new()
	add_child(page)
	auto_free(page)
	page.init(game)
	return page


# The first gas with a rules file, in kind order.
func _any_gas() -> Gas.Kind:
	for kind: Gas.Kind in Gas.Kind.values():
		if GasRules.for_kind(kind) != null:
			return kind
	assert_bool(false).override_failure_message("fixture: no gas has a rules file").is_true()
	return Gas.Kind.STEAM


# A gas whose state is held while standing in it AND pairs with a COH change (smoke today), found, not named.
func _blinding_gas() -> Gas.Kind:
	for kind: Gas.Kind in Gas.Kind.values():
		var rules := GasRules.for_kind(kind)
		if rules != null and rules.while_standing and rules.state != Elemental.State.NONE \
				and Elemental.paired_stat_mods(rules.state).has(Stats.Stat.COH):
			return kind
	assert_bool(false).override_failure_message(
			"fixture: no gas gives a COH-changing state while standing in it").is_true()
	return Gas.Kind.SMOKE


func test_every_tunable_number_has_a_row() -> void:
	var page := _page()
	var air := _labels(page)
	for id: String in Atmosphere.SUBSTANCES:
		var said := SubstanceCatalog.name_of(id)
		for label: String in [said + ": Normal %", said + ": points per step"]:
			assert_bool(air.has(label)).override_failure_message("the air has no '%s' row" % label).is_true()
	var listed := 0
	for kind: Gas.Kind in Gas.Kind.values():
		var rules := GasRules.for_kind(kind)
		if rules == null:
			continue
		listed += 1
		page.show_entry(kind)
		var shown := _labels(page)
		var want: Array[String] = ["Rounds per level", "Damage at Thin", "Damage at Medium", "Damage at Thick"]
		for id: String in Atmosphere.SUBSTANCES:
			want.append(SubstanceCatalog.name_of(id))
		for stat: Stats.Stat in Elemental.paired_stat_mods(rules.state):
			want.append("%s: %s change" % [Elemental.state_display_name(rules.state), Stats.Stat.keys()[stat]])
		for label: String in want:
			assert_bool(shown.has(label)).override_failure_message(
					"%s has no '%s' row" % [Gas.name_of(kind), label]).is_true()
		assert_bool(shown.has("From level")).override_failure_message(
				"%s: a From level row exactly when it gives a state" % Gas.name_of(kind)).is_equal(
				rules.state != Elemental.State.NONE)
	assert_int(listed).override_failure_message("fixture: no gas has a rules file").is_greater(0)


func test_the_normal_and_step_rows_move_the_steps_a_reading_reads() -> void:
	var id: String = Atmosphere.SUBSTANCES[0]
	var said := SubstanceCatalog.name_of(id)
	var rules := AtmosphereRules.authored()
	var normal_was := Atmosphere.normal_of(id)
	var step_was := Atmosphere.step_of(id)
	var reading: Dictionary[String, int] = {id: normal_was + step_was}
	var before := Atmosphere.steps_of(id, reading)
	var page := _page()
	_slider_after(page, said + ": Normal %").value = normal_was + step_was
	var after_normal := Atmosphere.steps_of(id, reading)
	rules.normal[id] = normal_was
	_slider_after(page, said + ": points per step").value = step_was * 2
	var after_step := Atmosphere.steps_of(id, reading)
	rules.step[id] = step_was
	assert_int(before).override_failure_message("fixture: one step above Normal does not read +1").is_equal(1)
	assert_int(after_normal).override_failure_message("the Normal row moved and the reading did not").is_equal(0)
	assert_int(after_step).override_failure_message("the step row moved and the reading did not").is_equal(0)


func test_a_gas_s_air_and_scald_rows_move_what_its_cell_does() -> void:
	var kind := _any_gas()
	var rules := GasRules.for_kind(kind)
	var air_was := rules.air.duplicate()
	var damage_was := rules.damage.duplicate()
	var id: String = Atmosphere.SUBSTANCES[0]
	var packed := Gas.with_level(0, kind, Gas.Level.THICK)
	var page := _page()
	page.show_entry(kind)
	var air_now := int(rules.air.get(id, 0))
	var points := air_now + 3 if air_now + 3 <= 50 else air_now - 3
	_slider_after(page, SubstanceCatalog.name_of(id)).value = points
	var air_after := int(GasRules.air_of(packed).get(id, 0))
	var scald_now := GasRules.scald_at(kind, Gas.Level.THICK)
	var scald := scald_now - 1 if scald_now > 0 else 1
	_slider_after(page, "Damage at Thick").value = scald
	var scald_after := GasRules.scald_at(kind, Gas.Level.THICK)
	rules.air = air_was
	rules.damage = damage_was
	assert_int(air_after).override_failure_message("the air row moved and the cell's air did not").is_equal(
			points * Gas.Level.THICK)
	assert_int(scald_after).override_failure_message("the scald row moved and the scald did not").is_equal(scald)


func test_from_level_moves_who_the_gas_gives_its_state_to() -> void:
	var kind := _blinding_gas()
	var rules := GasRules.for_kind(kind)
	var was := rules.state_from
	# A level the move changes the answer at: just under the threshold, or Thin moved past.
	var level: int = was - 1 if was > Gas.Level.THIN else Gas.Level.THIN
	var moved_to: int = level if was > Gas.Level.THIN else Gas.Level.MEDIUM
	var packed := Gas.with_level(0, kind, level)
	var before := GasRules.states_while_standing(packed).has(rules.state)
	var page := _page()
	page.show_entry(kind)
	var picker := _option_after(page, "From level")
	var index := AirGasTool.LEVELS.find(moved_to as Gas.Level)
	picker.select(index)
	picker.item_selected.emit(index)
	var after := GasRules.states_while_standing(packed).has(rules.state)
	var landed := rules.state_from
	rules.state_from = was
	assert_int(landed).override_failure_message("the From level picker did not write the rules").is_equal(moved_to)
	assert_bool(after).override_failure_message("From level moved and who holds the state did not").is_not_equal(before)


func test_the_state_change_row_moves_the_leash() -> void:
	var kind := _blinding_gas()
	var state := GasRules.for_kind(kind).state
	var state_rules := StateRules.for_state(state)
	var was := state_rules.stat_mods.duplicate()
	var change := int(state_rules.stat_mods[Stats.Stat.COH])
	var target := change - 1 if change > -10 else change + 1
	var leader: Unit = H.spawn_unit(self, Team.Faction.PLAYER, Vector2i.ZERO, {Stats.Stat.COH: 12}, false)
	var packed := Gas.with_level(0, kind, Gas.MAX_LEVEL)
	var before := SquadCohesion.reach_in(leader.state, packed)
	var page := _page()
	page.show_entry(kind)
	_slider_after(page, "%s: COH change" % Elemental.state_display_name(state)).value = target
	var after := SquadCohesion.reach_in(leader.state, packed)
	state_rules.stat_mods = was
	assert_int(before).override_failure_message("fixture: the leash is floored, so a change cannot show").is_greater(1)
	assert_int(after - before).override_failure_message("the state's row moved and the leash did not").is_equal(
			target - change)


# The missing wire: an edit the rules hear but the open plan, the HUD, the enemy ranges and the hover
# (the leash ring under a still pointer) never do. The hover repaints AFTER the re-resolve it draws from.
func test_every_kind_of_edit_re_resolves_the_plan() -> void:
	var game := StubGame.new()
	var page := _page(game)
	var id: String = Atmosphere.SUBSTANCES[0]
	var air_rules := AtmosphereRules.authored()
	var normal_was := Atmosphere.normal_of(id)
	var kind := _blinding_gas()
	var rules := GasRules.for_kind(kind)
	var hold_was := rules.hold_rounds
	var air_was := rules.air.duplicate()
	var state_rules := StateRules.for_state(rules.state)
	var mods_was := state_rules.stat_mods.duplicate()
	var edits: Array[Array] = []   # each edit's own slice of the call log
	var seen := 0
	_slider_after(page, SubstanceCatalog.name_of(id) + ": Normal %").value = normal_was + 1
	edits.append(game.calls.slice(seen))
	seen = game.calls.size()
	page.show_entry(kind)
	_slider_after(page, "Rounds per level").value = 1 if hold_was != 1 else 2
	edits.append(game.calls.slice(seen))
	seen = game.calls.size()
	_slider_after(page, SubstanceCatalog.name_of(id)).value = int(rules.air.get(id, 0)) + 1
	edits.append(game.calls.slice(seen))
	seen = game.calls.size()
	_slider_after(page, "%s: COH change" % Elemental.state_display_name(rules.state)).value = \
			int(mods_was[Stats.Stat.COH]) + 1
	edits.append(game.calls.slice(seen))
	air_rules.normal[id] = normal_was
	rules.hold_rounds = hold_was
	rules.air = air_was
	state_rules.stat_mods = mods_was
	var names := ["a Normal row", "a field row", "a sparse row", "a state row"]
	for i in edits.size():
		var calls: Array = edits[i]
		var doors := [calls.count("plan"), calls.count("threats"), calls.count("status"), calls.count("hover")]
		assert_array(doors).override_failure_message(
				"%s did not re-resolve the plan, the enemy ranges, the HUD and the hover once each: %s"
				% [names[i], calls]).is_equal([1, 1, 1, 1])
		assert_bool(calls.find("plan") < calls.find("hover")).override_failure_message(
				"%s repainted the hover before the re-resolve it draws from: %s" % [names[i], calls]).is_true()


func test_reset_puts_the_disk_back_and_greys() -> void:
	var kind := _any_gas()
	var rules := GasRules.for_kind(kind)
	var disk := (DevWidgets.saved_copy(rules.resource_path) as GasRules).hold_rounds
	var page := _page()
	page.show_entry(kind)
	var greyed_clean := page._reset.disabled
	var target := disk + 1 if disk < 4 else disk - 1
	_slider_after(page, "Rounds per level").value = target
	var moved := rules.hold_rounds
	var lit := not page._reset.disabled and page.has_unsaved_changes() and page._save.text != "Save"
	page._reset.pressed.emit()
	var back := rules.hold_rounds
	rules.hold_rounds = disk   # leave the cache as found, even when red
	assert_bool(greyed_clean).override_failure_message("Reset is live on a clean page").is_true()
	assert_int(moved).override_failure_message("the slider did not move the live rules").is_equal(target)
	assert_bool(lit).override_failure_message("an edit left Save and Reset unmarked").is_true()
	assert_int(back).override_failure_message("Reset did not put the disk's value back").is_equal(disk)
	assert_bool(page.has_unsaved_changes()).override_failure_message("Reset left the page marked").is_false()
	assert_bool(page._reset.disabled).override_failure_message("Reset stayed live after putting the disk back").is_true()


func _labels(root: Node) -> Array[String]:
	var out: Array[String] = []
	for node in root.find_children("*", "Label", true, false):
		out.append((node as Label).text)
	return out


# The slider in the row whose label reads `label`.
func _slider_after(root: Node, label: String) -> HSlider:
	for node in root.find_children("*", "Label", true, false):
		if (node as Label).text != label:
			continue
		for sibling in node.get_parent().get_children():
			if sibling is HSlider:
				return sibling
	assert_bool(false).override_failure_message("the page drew no '%s' slider" % label).is_true()
	return null


func _option_after(root: Node, label: String) -> OptionButton:
	for node in root.find_children("*", "Label", true, false):
		if (node as Label).text != label:
			continue
		for sibling in node.get_parent().get_children():
			if sibling is OptionButton:
				return sibling
	assert_bool(false).override_failure_message("the page drew no '%s' picker" % label).is_true()
	return null
