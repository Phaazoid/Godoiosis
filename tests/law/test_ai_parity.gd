# AI PARITY (#1236): every member of every feature list the game has declares how the archetype AI
# answers it -- covered (and where), never, or a gap #117 owes -- and every claim a row makes is checked
# against the code. The ledger is tests/support/parity_ledger.gd.
#
# WHY THIS IS A LAW. The verb axis was already pinned (test_ai_action_coverage.gd) and never drifted.
# What drifted was the SCORE not pricing a new consequence -- Crisis read as zero, limbs, deposits,
# watch lanes -- found by playtest 4 days to 6 weeks after the feature shipped. Nearly every new
# mechanic arrives as a ResolvedOutcome field or a ResolvedPlan list, so those are rows here.
#
# A miss is fixed in the LEDGER, never by editing this suite. A gap keeps it green on purpose (the AI
# is permanently behind, #117); what it buys is that the feature's own diff has to write the row.
extends GdUnitTestSuite

const Ledger := preload("res://tests/support/parity_ledger.gd")
const H := preload("res://tests/support/squad_fixtures.gd")


func test_every_member_declares_its_ai_stance() -> void:
	var missing: Array[String] = Ledger.undeclared("ai")
	assert_array(missing).override_failure_message(
		("The game has these and nothing says whether the AI accounts for them:\n  %s\n"
		+ "Declare each in tests/support/parity_ledger.gd: covered(file, token) if it does, "
		+ "never(reason) if it never should, gap(\"#117\", note) if it is owed.")
		% "\n  ".join(missing)).is_empty()


func test_no_ai_row_is_stale_or_restates_its_axis() -> void:
	var stale: Array[String] = Ledger.stale_rows("ai")
	assert_array(stale).override_failure_message(
		"Rows the ledger should drop or move:\n  %s" % "\n  ".join(stale)).is_empty()


func test_every_ai_claim_holds() -> void:
	var wrong: Array[String] = Ledger.false_claims("ai")
	assert_array(wrong).override_failure_message(
		("These ledger rows claim something the code no longer says:\n  %s\n"
		+ "Either the AI lost it (restore it, or make the row a gap) or the row names the wrong place.")
		% "\n  ".join(wrong)).is_empty()


# A ring verb that queues an action type answers through AIArchetype's tables, which
# test_ai_action_coverage.gd pins per archetype -- so the type has to be one those tables cover.
func test_a_ring_verb_deferring_to_its_action_type_names_a_main_action() -> void:
	var ring: Dictionary = Ledger.ring_verbs()
	var label: Callable = ring["label"]
	var bad: Array[String] = []
	for verb: Variant in ring["rows"]:
		var stance: Dictionary = ring["rows"][verb].get("ai", {})
		if stance.get("stance", -1) == Ledger.Stance.ACTION_TYPE \
				and not BaseAction.MAIN_ACTION_TYPES.has(stance["type"]):
			bad.append("%s defers to %s, which no AIArchetype table covers"
					% [label.call(verb), BaseAction.ActionType.keys()[stance["type"]]])
	assert_array(bad).override_failure_message("\n".join(bad)).is_empty()


# Declaring a verb in an archetype's priority list is half the job: queue_main_action must have a
# builder arm for it, or the walk hits its push_error at runtime -- which reds nothing.
func test_every_verb_an_archetype_tries_has_a_builder() -> void:
	var body: String = Ledger.function_body(Ledger.TACTICS, "static func queue_main_action(")
	assert_str(body).override_failure_message("AITactics.queue_main_action not found").is_not_empty()
	var tried := {}
	for archetype: Variant in AIArchetype.MAIN_ACTION_PRIORITY:
		for type: Variant in AIArchetype.MAIN_ACTION_PRIORITY[archetype]:
			tried[type] = true
	var unbuilt: Array[String] = []
	for type: Variant in tried:
		var name: String = BaseAction.ActionType.keys()[type]
		if not body.contains("BaseAction.ActionType.%s:" % name):
			unbuilt.append(name)
	assert_int(tried.size()).is_greater(0)
	assert_array(unbuilt).override_failure_message(
		("An archetype tries %s, and AITactics.queue_main_action has no arm to build it: add one, "
		+ "or move the verb to MAIN_ACTION_NEVER.") % ", ".join(unbuilt)).is_empty()


# A tile state's AI row says whether standing on it HARMS. The AI avoids ending on ground that does
# through _is_hazard, which asks RulesService.occupant_damage_for -- so the row is checked against
# that rule, and _is_hazard against still asking it.
func test_a_tile_states_hazard_row_agrees_with_the_rule() -> void:
	var body: String = Ledger.function_body(Ledger.TACTICS, "static func _is_hazard(")
	assert_bool(body.contains("occupant_damage_for")).override_failure_message(
		"AITactics._is_hazard no longer asks RulesService.occupant_damage_for, so no hazard row means anything").is_true()
	var sm: SquadManager = H.make_manager(self)
	var unit: Unit = H.spawn_solo(self, sm, Team.Faction.ENEMY, Vector2i(0, 0))
	var axis: Dictionary = Ledger.tile_states()
	var label: Callable = axis["label"]
	var wrong: Array[String] = []
	for state: Variant in axis["rows"]:
		var stance: Dictionary = axis["rows"][state].get("ai", {})
		if not stance.has("harms"):
			if stance.get("stance", -1) != Ledger.Stance.GAP:
				wrong.append("%s: say hazard() or harmless(reason), or gap() if the AI cannot see how it harms"
						% label.call(state))
			continue
		var states: Array[Terrain.TileState] = [state]
		var harms: bool = RulesService.occupant_damage_for(unit, states) > 0
		if harms != bool(stance["harms"]):
			wrong.append("%s is declared %s, and standing on it %s"
					% [label.call(state), "a hazard" if stance["harms"] else "harmless",
					"does damage" if harms else "does none"])
	assert_array(wrong).override_failure_message("\n".join(wrong)).is_empty()


# A gas or a weather declared inert has no rules at all. The day one gains some, this reds, because
# the AI's row was written about a look.
func test_a_gas_declared_inert_has_no_rules() -> void:
	_assert_inert_has_no_rules(Ledger.gases(), func(kind: Variant) -> bool: return GasRules.for_kind(kind) != null)


func test_a_weather_declared_inert_has_no_rules() -> void:
	_assert_inert_has_no_rules(Ledger.weathers(),
		func(kind: Variant) -> bool: return WeatherRules.for_kind(kind) != null)


func _assert_inert_has_no_rules(axis: Dictionary, has_rules: Callable) -> void:
	var label: Callable = axis["label"]
	var wrong: Array[String] = []
	for kind: Variant in axis["rows"]:
		var stance: Dictionary = axis["rows"][kind].get("ai", {})
		if stance.get("inert", false) and has_rules.call(kind):
			wrong.append("%s is declared inert, and it has rules now -- say what the AI does about them" % label.call(kind))
	assert_array(wrong).override_failure_message("\n".join(wrong)).is_empty()


func test_the_tripwire_fires_on_a_made_up_axis() -> void:
	var fake: Array[Dictionary] = [{
		"name": "fake", "members": ["kept", "new"],
		"label": func(m: Variant) -> String: return String(m),
		"rows": {"kept": {"ai": Ledger.covered(Ledger.TACTICS, "this token is in no tactic")}},
	}]
	assert_array(Ledger.undeclared("ai", fake)).contains_exactly(["fake: new"])
	assert_int(Ledger.false_claims("ai", fake).size()).is_equal(1)


func test_the_ledger_is_not_vacuous() -> void:
	assert_array(Ledger.axes_stating_nothing("ai")).is_empty()
