# PLAY API PARITY (#1236): every member of every feature list the game has declares how the headless
# Play API answers it -- a bridge command, a readout, never, or a gap the issue owes -- and every claim
# a row makes is checked against the code. The ledger is tests/support/parity_ledger.gd, and its
# header says what each stance means.
#
# WHY THIS IS A LAW. The game gained capture, group move, the rescue bank and the whole pre-mission
# screen, and the Play API learned each 3 to 14 weeks later, from a playtest that hit the hole. Nothing
# was wrong at either end; nothing joined them. test_bridge_exposes_every_verb.gd checks session ->
# bridge, and nothing checked game -> session.
#
# A miss is fixed in the LEDGER (and in play/ when the answer is "it can"), never by editing this
# suite. A gap keeps it green on purpose: what it buys is that the feature's own diff has to write the
# row, so it is seen there.
extends GdUnitTestSuite

const Ledger := preload("res://tests/support/parity_ledger.gd")


func test_every_member_declares_its_play_api_stance() -> void:
	var missing: Array[String] = Ledger.undeclared("play")
	assert_array(missing).override_failure_message(
		("The game has these and nothing says whether the headless Play API can do or see them:\n  %s\n"
		+ "Declare each in tests/support/parity_ledger.gd: cmd(\"verb\") or covered(file, token) if it "
		+ "can, never(reason) if it never should, gap(\"#46\", note) if it is owed.")
		% "\n  ".join(missing)).is_empty()


func test_no_play_row_is_stale_or_restates_its_axis() -> void:
	var stale: Array[String] = Ledger.stale_rows("play")
	assert_array(stale).override_failure_message(
		"Rows the ledger should drop or move:\n  %s" % "\n  ".join(stale)).is_empty()


func test_every_play_claim_holds() -> void:
	var wrong: Array[String] = Ledger.false_claims("play")
	assert_array(wrong).override_failure_message(
		("These ledger rows claim something the code no longer says:\n  %s\n"
		+ "Either the Play API lost it (restore it, or make the row a gap) or the row names the wrong place.")
		% "\n  ".join(wrong)).is_empty()


# A ring verb that queues an action type says so rather than naming a command twice; that type's own
# row must then be one the Play API actually covers.
func test_a_ring_verb_deferring_to_its_action_type_finds_a_covered_row() -> void:
	var types: Dictionary = Ledger.action_types()["rows"]
	var ring: Dictionary = Ledger.ring_verbs()
	var label: Callable = ring["label"]
	var bad: Array[String] = []
	for verb: Variant in ring["rows"]:
		var stance: Dictionary = ring["rows"][verb].get("play", {})
		if stance.get("stance", -1) != Ledger.Stance.ACTION_TYPE:
			continue
		var target: Dictionary = types.get(stance["type"], {}).get("play", {})
		if target.get("stance", -1) != Ledger.Stance.COVERED:
			bad.append("%s defers to %s, which has no covered Play row"
					% [label.call(verb), BaseAction.ActionType.keys()[stance["type"]]])
	assert_array(bad).override_failure_message("\n".join(bad)).is_empty()


# The lose-condition axis is covered WHOLE because the board view prints MissionRules.defeat_reason,
# so the claim is only as good as that wording existing for every member.
func test_every_lose_condition_has_the_wording_the_board_view_prints() -> void:
	var axis: Dictionary = Ledger.lose_conditions()
	var label: Callable = axis["label"]
	var silent: Array[String] = []
	for condition: Variant in axis["members"]:
		if MissionRules.defeat_reason(condition).is_empty():
			silent.append(label.call(condition))
	assert_array(silent).override_failure_message(
		"MissionRules.defeat_reason has no words for %s, so the board view's FAIL IF line is blank"
		% ", ".join(silent)).is_empty()


# The machinery, on an axis made up for the purpose: the checks above pass vacuously if these do not
# fire.
func test_the_tripwire_fires_on_a_made_up_axis() -> void:
	var fake: Array[Dictionary] = [{
		"name": "fake", "members": ["kept", "new", "gapped", "unreasoned"],
		"label": func(m: Variant) -> String: return String(m),
		"rows": {
			"kept": {"play": Ledger.covered(Ledger.BRIDGE, "this token is in no bridge")},
			"gapped": {"play": Ledger.gap("46", "")},
			"unreasoned": {"play": Ledger.never("  ")},
			"gone": {"play": Ledger.cmd("move")},
		},
	}, {
		"name": "whole", "members": ["a"], "label": func(m: Variant) -> String: return String(m),
		"play_all": Ledger.cmd("move"),
		"rows": {"a": {"play": Ledger.cmd("move")}},
	}]
	assert_array(Ledger.undeclared("play", fake)).contains_exactly(["fake: new"])
	assert_int(Ledger.stale_rows("play", fake).size()).is_equal(2)   # "gone", and the restated "a"
	# The bogus token, the gap's bad issue AND its empty note, and the blank reason.
	assert_int(Ledger.false_claims("play", fake).size()).is_equal(4)
	assert_int(Ledger.gaps("play", fake).size()).is_equal(1)


func test_the_ledger_is_not_vacuous() -> void:
	for axis: Dictionary in Ledger.axes():
		assert_int((axis["members"] as Array).size()).override_failure_message(
			"%s enumerated nothing -- its member source has rotted" % axis["name"]).is_greater(0)
	# Reflection, the one member source a rename could silently empty.
	assert_bool(Ledger.outcome_fields()["members"].has("damage")).is_true()
	assert_array(Ledger.axes_stating_nothing("play")).is_empty()
