extends Object
class_name MissionSummary

# #200's record, as a PROJECTION over a MissionLog's events (#53) -- one pure function, so the
# balance summary and the raw log can never disagree, and so a stored summary is only ever a cache
# of what the events already say (the Worker's `summary` column; `events` stays the authority).
#
# Everything here is counted from the log, never from the live board: it runs at seal, and it runs
# again at the launch sweep over a file the process never sealed.
#
# The RECONCILIATION block is the point of the first query. `net_hp_loss` is what the turn_start
# snapshots say a faction lost; `attributed_damage` - `attributed_heal` is what the pass and
# turn_effects lines account for; `unattributed` is the gap. A gap is a damage channel the log does
# not carry (a downed clock expiring kills at 1 HP outside any hit), or a bug -- either way it is
# the number to read before trusting anything else in here.

const PLAYER := "PLAYER"
const ACTIVE := "ACTIVE"


static func of(events: Array[Dictionary]) -> Dictionary:
	var start := _first(events, "mission_start")
	var end := _first(events, "mission_end")
	var snapshots := _all(events, "turn_start")
	var faction_of := _faction_index(events)

	var last_round := 0
	var last_ms := 0
	for e: Dictionary in events:
		last_round = maxi(last_round, int(e.get("round", 0)))
		last_ms = maxi(last_ms, int(e.get("t_ms", 0)))

	# --- orders the player gave, and took back, outside a running pass ---
	var queued := 0
	var cancelled := 0
	for e: Dictionary in _all(events, "order_queued"):
		if e.get("faction") == PLAYER and not bool(e.get("during_pass", false)):
			queued += 1
	for e: Dictionary in _all(events, "order_cancelled"):
		if e.get("faction") == PLAYER and not bool(e.get("during_pass", false)):
			cancelled += 1

	# --- what resolved, and what it cost whom ---
	var passes := 0
	var usage := {}          # action type -> count, player orders resolved (holds excluded)
	var attacks_used := {}   # attack name -> count
	var units_used := {}     # unit name -> count of orders
	var damage_to := {}      # target faction -> damage landed on it, every source
	var heal_to := {}        # target faction -> HP restored
	var damage_by := {}      # actor faction -> damage landed on OTHER factions
	var turn_of_last_damage := 0
	for e: Dictionary in _all(events, "pass"):
		passes += 1
		if e.get("faction") == PLAYER:
			for order: Dictionary in e.get("orders", []):
				if bool(order.get("hold", false)):
					continue
				_bump(usage, str(order.get("type", "")))
				_bump(units_used, _name_of(order.get("unit")))
				var attack := str(order.get("attack", ""))
				if attack != "":
					_bump(attacks_used, attack)
		for hit: Dictionary in e.get("hits", []):
			if bool(hit.get("skipped", false)):
				continue
			var damage := int(hit.get("damage", 0))
			var heal := int(hit.get("heal", 0))
			var target_faction := str(faction_of.get(_id_of(hit.get("target")), ""))
			var actor_faction := str(faction_of.get(_id_of(hit.get("actor")), ""))
			if damage > 0:
				_add(damage_to, target_faction, damage)
				if actor_faction != target_faction:
					_add(damage_by, actor_faction, damage)
				turn_of_last_damage = maxi(turn_of_last_damage, int(e.get("round", 0)))
			if heal > 0:
				_add(heal_to, target_faction, heal)
	for e: Dictionary in _all(events, "turn_effects"):
		for hit: Dictionary in e.get("hits", []):
			var damage := int(hit.get("damage", 0))
			if damage > 0:
				_add(damage_to, str(faction_of.get(_id_of(hit.get("unit")), "")), damage)
				turn_of_last_damage = maxi(turn_of_last_damage, int(e.get("round", 0)))

	# --- attrition ---
	var downs := {}
	var deaths := {}
	var turn_of_first_down := 0
	for e: Dictionary in _all(events, "unit_downed"):
		var faction := str(e.get("faction", ""))
		_bump(downs, faction)
		if faction == PLAYER and turn_of_first_down == 0:
			turn_of_first_down = int(e.get("round", 0))
	for e: Dictionary in _all(events, "unit_died"):
		_bump(deaths, str(e.get("faction", "")))

	# What the snapshots say each faction lost, net of healing, a unit that vanished counting its
	# last HP as lost. The end-of-mission vitals are the final frame.
	var frames: Array[Dictionary] = snapshots.duplicate()
	if not end.is_empty():
		frames.append(end)
	var net_loss := {}
	for i in range(1, frames.size()):
		var prev := _by_id(frames[i - 1].get("units", []))
		var cur := _by_id(frames[i].get("units", []))
		for id: int in prev:
			var before: Dictionary = prev[id]
			var hp_after := int((cur[id] as Dictionary).get("hp", 0)) if cur.has(id) else 0
			var delta := int(before.get("hp", 0)) - hp_after
			if delta != 0:
				_add(net_loss, str(before.get("faction", "")), delta)

	# --- how it ended ---
	var end_units: Array = []
	if not end.is_empty():
		end_units = end.get("units", [])
	elif not snapshots.is_empty():
		end_units = snapshots.back().get("units", [])
	var standing := 0
	var hp_pct := {}
	for u: Dictionary in end_units:
		if u.get("faction") != PLAYER:
			continue
		if u.get("state") == ACTIVE:
			standing += 1
		var hp_max := int(u.get("hp_max", 0))
		hp_pct[str(u.get("name", ""))] = (100 * int(u.get("hp", 0)) / hp_max) if hp_max > 0 else 0

	# --- the denominator ---
	var offered_units: Array[String] = []
	var offered_weapons: Array[String] = []
	for u: Dictionary in start.get("roster", []):
		offered_units.append(str(u.get("name", "")))
		var weapon: Variant = u.get("weapon")
		if weapon is Dictionary and str(weapon.get("name", "")) != "":
			offered_weapons.append(str(weapon.get("name")))

	var seconds: float = float(end.get("seconds", last_ms / 1000.0))

	return {
		"scenario": start.get("scenario", ""),
		"build": start.get("build", ""),
		# Carried into the summary, not just the events: this is the row that gets indexed, so the
		# separation has to be available where the querying happens.
		"sandbox": bool(start.get("sandbox", false)),
		"dev_mode": bool(start.get("dev_mode", false)),
		"resumed": bool(start.get("resumed", false)),
		# WE INFERRED THIS ENDING RATHER THAN WATCHING IT (#53 slice 4b) -- a run the launch sweep
		# finished because the process that opened it died. Here for `sandbox`'s reason above: the
		# outcome of a swept run is a deduction, and the row that gets queried has to say so.
		"swept": bool(end.get("swept", false)),
		"outcome": end.get("outcome", "INTERRUPTED"),
		"failed_by": end.get("failed_by", "NONE"),
		"rounds": last_round,
		"seconds": seconds,
		"passes": passes,
		"orders_queued": queued,
		"orders_cancelled": cancelled,
		"usage": usage,
		"attacks_used": attacks_used,
		"units_used": units_used,
		"offered_units": offered_units,
		"offered_weapons": offered_weapons,
		"damage_dealt": int(damage_by.get(PLAYER, 0)),
		"damage_taken": int(damage_to.get(PLAYER, 0)),
		"recovery": int(heal_to.get(PLAYER, 0)),
		"downs": downs,
		"deaths": deaths,
		"turn_of_first_down": turn_of_first_down,
		"turn_of_last_damage": turn_of_last_damage,
		"units_standing": standing,
		"hp_pct_at_end": hp_pct,
		"reconciliation": _reconcile(net_loss, damage_to, heal_to),
	}


# Per faction: what the snapshots say was lost against what the hits account for.
static func _reconcile(net_loss: Dictionary, damage_to: Dictionary, heal_to: Dictionary) -> Dictionary:
	var factions := {}
	for key in net_loss:
		factions[key] = true
	for key in damage_to:
		factions[key] = true
	for key in heal_to:
		factions[key] = true
	var out := {}
	for faction in factions:
		var lost := int(net_loss.get(faction, 0))
		var damage := int(damage_to.get(faction, 0))
		var heal := int(heal_to.get(faction, 0))
		out[faction] = {
			"net_hp_loss": lost,
			"attributed_damage": damage,
			"attributed_heal": heal,
			"unattributed": lost - (damage - heal),
		}
	return out


# --- readers over the event list ---

static func _first(events: Array[Dictionary], kind: String) -> Dictionary:
	for e: Dictionary in events:
		if e.get("event") == kind:
			return e
	return {}


static func _all(events: Array[Dictionary], kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in events:
		if e.get("event") == kind:
			out.append(e)
	return out


# Unit id -> faction name, from every line that names both. The roster and the snapshots cover
# everyone who was ever on the board; a hit names only ids.
static func _faction_index(events: Array[Dictionary]) -> Dictionary:
	var index := {}
	for e: Dictionary in events:
		var kind := str(e.get("event", ""))
		if kind == "mission_start":
			for u: Dictionary in e.get("roster", []):
				index[_id_of(u)] = u.get("faction", "")
		elif kind == "turn_start" or kind == "mission_end":
			for u: Dictionary in e.get("units", []):
				index[_id_of(u)] = u.get("faction", "")
		elif kind == "unit_downed" or kind == "unit_died":
			index[_id_of(e)] = e.get("faction", "")
	return index


static func _by_id(units: Variant) -> Dictionary:
	var out := {}
	if units is Array:
		for u: Dictionary in units:
			out[_id_of(u)] = u
	return out


static func _id_of(ref: Variant) -> int:
	if ref is Dictionary:
		return int(ref.get("id", 0))
	return 0


static func _name_of(ref: Variant) -> String:
	if ref is Dictionary:
		return str(ref.get("name", ""))
	return ""


static func _bump(counts: Dictionary, key: String) -> void:
	_add(counts, key, 1)


static func _add(totals: Dictionary, key: String, amount: int) -> void:
	totals[key] = int(totals.get(key, 0)) + amount
