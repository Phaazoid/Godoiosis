# MissionSummary (#53) -- #200's record as a pure projection over a synthetic event list. No
# scene, no nodes: the function reads Dictionaries the recorder wrote, so the fixture IS the
# contract, spelled the way MissionLog spells it.
#
# The reconciliation case is the one that matters: the snapshots say what a faction lost, the
# hits say what was accounted for, and the gap between them is the first number to read off a
# real row. It is pinned in both directions -- zero when every hit is written, non-zero when one
# is not -- because a check that can only pass proves nothing.
extends GdUnitTestSuite

const A := 101   # the player's unit
const B := 202   # the enemy


static func _ref(id: int, name: String) -> Dictionary:
	return {"id": id, "name": name}


static func _unit(id: int, name: String, faction: String, hp: int, hp_max: int, state := "ACTIVE") -> Dictionary:
	return {"id": id, "name": name, "faction": faction, "hp": hp, "hp_max": hp_max, "state": state}


static func _line(seq: int, round: int, event: String, fields: Dictionary) -> Dictionary:
	var out := {"seq": seq, "t_ms": seq * 1000, "round": round, "event": event}
	out.merge(fields)
	return out


# One short mission: A hits B for 6, the ground burns B for 2, B goes down, B hits A for 5, A wins.
static func _events() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.append(_line(0, 1, "mission_start", {
		"scenario": "res://Scenarios/missions/Test.tres", "build": "0.0.0", "resumed": false,
		"roster": [
			{"id": A, "name": "Aldin", "faction": "PLAYER", "weapon": {"name": "Sabre", "family": "CHAINSWORD", "mods": []}},
			{"id": B, "name": "Brigand", "faction": "ENEMY", "weapon": null},
		],
	}))
	out.append(_line(1, 1, "turn_start", {"faction": "PLAYER", "units": [
		_unit(A, "Aldin", "PLAYER", 20, 20), _unit(B, "Brigand", "ENEMY", 10, 10)]}))
	out.append(_line(2, 1, "order_queued", {"faction": "PLAYER", "during_pass": false,
		"order": {"unit": _ref(A, "Aldin"), "type": "ATTACK"}}))
	out.append(_line(3, 1, "order_cancelled", {"faction": "PLAYER", "during_pass": false,
		"unit": _ref(A, "Aldin"), "type": "ATTACK"}))
	out.append(_line(4, 1, "pass", {"faction": "PLAYER",
		"orders": [
			{"unit": _ref(A, "Aldin"), "type": "MOVE", "hold": true},
			{"unit": _ref(A, "Aldin"), "type": "ATTACK", "attack": "Slash"},
			{"unit": _ref(A, "Aldin"), "type": "RALLY"},
		],
		"hits": [{"kind": "attack", "actor": _ref(A, "Aldin"), "target": _ref(B, "Brigand"),
			"damage": 6, "heal": 0, "skipped": false}],
		"cell_effects": []}))
	out.append(_line(5, 1, "turn_effects", {"faction": "ENEMY",
		"hits": [{"unit": _ref(B, "Brigand"), "state": "BURNING", "damage": 2}]}))
	out.append(_line(6, 2, "turn_start", {"faction": "PLAYER", "units": [
		_unit(A, "Aldin", "PLAYER", 20, 20), _unit(B, "Brigand", "ENEMY", 2, 10)]}))
	out.append(_line(7, 2, "unit_downed", _unit(B, "Brigand", "ENEMY", 1, 10, "DOWNED")))
	out.append(_line(8, 2, "pass", {"faction": "ENEMY", "orders": [],
		"hits": [{"kind": "counter", "actor": _ref(B, "Brigand"), "target": _ref(A, "Aldin"),
			"damage": 5, "heal": 0, "skipped": false}],
		"cell_effects": []}))
	out.append(_line(9, 2, "mission_end", {"outcome": "VICTORY", "failed_by": "NONE", "seconds": 9.0,
		"units": [_unit(A, "Aldin", "PLAYER", 15, 20), _unit(B, "Brigand", "ENEMY", 1, 10, "DOWNED")]}))
	return out


func test_the_ending_and_the_clock() -> void:
	var s := MissionSummary.of(_events())
	assert_str(str(s.get("outcome"))).is_equal("VICTORY")
	assert_str(str(s.get("failed_by"))).is_equal("NONE")
	assert_int(int(s.get("rounds"))).is_equal(2)
	assert_float(float(s.get("seconds"))).is_equal(9.0)
	assert_int(int(s.get("passes"))).is_equal(2)


func test_orders_the_player_gave_and_took_back() -> void:
	var s := MissionSummary.of(_events())
	assert_int(int(s.get("orders_queued"))).is_equal(1)
	assert_int(int(s.get("orders_cancelled"))).is_equal(1)


func test_usage_counts_resolved_player_orders_and_skips_the_hold_filler() -> void:
	var s := MissionSummary.of(_events())
	var usage: Dictionary = s.get("usage")
	assert_int(int(usage.get("ATTACK", 0))).is_equal(1)
	assert_int(int(usage.get("RALLY", 0))).is_equal(1)
	assert_bool(usage.has("MOVE")).override_failure_message("a hold filler is not an order anyone gave").is_false()
	assert_int(int((s.get("attacks_used") as Dictionary).get("Slash", 0))).is_equal(1)
	assert_int(int((s.get("units_used") as Dictionary).get("Aldin", 0))).is_equal(2)


func test_the_denominator_is_what_the_roster_offered() -> void:
	var s := MissionSummary.of(_events())
	assert_array(s.get("offered_units")).contains_exactly(["Aldin", "Brigand"])
	assert_array(s.get("offered_weapons")).contains_exactly(["Sabre"])


func test_damage_is_split_by_who_took_it() -> void:
	var s := MissionSummary.of(_events())
	assert_int(int(s.get("damage_dealt"))).is_equal(6)
	assert_int(int(s.get("damage_taken"))).is_equal(5)
	assert_int(int(s.get("recovery"))).is_equal(0)
	assert_int(int(s.get("turn_of_last_damage"))).is_equal(2)


func test_attrition_and_the_ending_state() -> void:
	var s := MissionSummary.of(_events())
	assert_int(int((s.get("downs") as Dictionary).get("ENEMY", 0))).is_equal(1)
	assert_int(int(s.get("turn_of_first_down"))).override_failure_message(
		"only a PLAYER down counts as the player's first down").is_equal(0)
	assert_int(int(s.get("units_standing"))).is_equal(1)
	assert_int(int((s.get("hp_pct_at_end") as Dictionary).get("Aldin", -1))).is_equal(75)


func test_every_written_hit_reconciles_against_the_snapshots() -> void:
	var s := MissionSummary.of(_events())
	var rec: Dictionary = s.get("reconciliation")
	var enemy: Dictionary = rec.get("ENEMY")
	assert_int(int(enemy.get("net_hp_loss"))).is_equal(9)          # 10 -> 2 -> 1
	assert_int(int(enemy.get("attributed_damage"))).is_equal(8)    # 6 hit + 2 burn
	assert_int(int(enemy.get("unattributed"))).override_failure_message(
		"the 2 -> 1 step is the down, written as a state change and not as a hit").is_equal(1)
	var player: Dictionary = rec.get("PLAYER")
	assert_int(int(player.get("net_hp_loss"))).is_equal(5)
	assert_int(int(player.get("attributed_damage"))).is_equal(5)
	assert_int(int(player.get("unattributed"))).is_equal(0)


func test_a_hit_the_log_dropped_shows_as_a_gap() -> void:
	var events := _events()
	events.remove_at(8)   # the enemy's counter never gets written
	var s := MissionSummary.of(events)
	var player: Dictionary = (s.get("reconciliation") as Dictionary).get("PLAYER")
	assert_int(int(player.get("attributed_damage"))).is_equal(0)
	assert_int(int(player.get("unattributed"))).override_failure_message(
		"a channel the log does not carry must show as a gap, never as silence").is_equal(5)


func test_a_skipped_hit_counts_nothing() -> void:
	var events := _events()
	var pass_line: Dictionary = events[8]
	(pass_line.get("hits")[0] as Dictionary)["skipped"] = true
	var s := MissionSummary.of(events)
	assert_int(int(s.get("damage_taken"))).is_equal(0)


func test_an_interrupted_log_still_summarises() -> void:
	var events := _events()
	events.resize(7)   # died with the process after the second turn_start
	var s := MissionSummary.of(events)
	assert_str(str(s.get("outcome"))).is_equal("INTERRUPTED")
	assert_int(int(s.get("rounds"))).is_equal(2)
	assert_int(int(s.get("units_standing"))).override_failure_message(
		"with no mission_end the last snapshot is the ending state").is_equal(1)
	assert_float(float(s.get("seconds"))).is_equal(6.0)


func test_an_empty_log_summarises_to_nothing() -> void:
	var s := MissionSummary.of([])
	assert_str(str(s.get("outcome"))).is_equal("INTERRUPTED")
	assert_int(int(s.get("rounds"))).is_equal(0)
	assert_int(int(s.get("passes"))).is_equal(0)
	assert_bool((s.get("reconciliation") as Dictionary).is_empty()).is_true()
