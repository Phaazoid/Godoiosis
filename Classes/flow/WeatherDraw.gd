extends Object
class_name WeatherDraw

# The mission start's weather draw (#1509). A board may offer a SET of weathers
# (ScenarioData.weather_odds: kind -> relative weight), and one is drawn when a mission starts. Pure and
# static, so both hosts ask it: MissionController's fresh-start doors and the Play API's load and
# restart -- PreMissionPhase.replay_for/kept_by_restart's shape.
#
# THE ONE ROLL ON THE RULE SIDE. Law #1 is about combat: this draw happens before any order exists and
# is shown before the player commits (dev ruling, #1509). Nothing after it rolls, and nothing re-derives
# it: a save, a report and a telemetry run record the RESULT (ScenarioData.weather).
#
# EMPTY odds = no draw: the mission starts under the board's own weather. That is a locked board, and
# every board saved before #1509 is one.

const NONE := -1   # at_start's `kept` on a fresh start: nothing to keep


# The weathers a board offers, in enum order, so a seed means one thing however the set was authored or
# saved. A weight of 0 or less offers nothing.
static func offered(odds: Dictionary[Weather.Kind, int]) -> Array[Weather.Kind]:
	var kinds: Array[Weather.Kind] = []
	for kind: Weather.Kind in odds:
		if odds[kind] > 0:
			kinds.append(kind)
	kinds.sort()
	return kinds


# Does a mission start on this board draw at all? False is a locked board.
static func draws(odds: Dictionary[Weather.Kind, int]) -> bool:
	return not offered(odds).is_empty()


# The roll itself: one weighted pick, or `standing` when nothing is offered.
static func draw(odds: Dictionary[Weather.Kind, int], standing: Weather.Kind,
		rng: RandomNumberGenerator) -> Weather.Kind:
	var kinds := offered(odds)
	var total := 0
	for kind: Weather.Kind in kinds:
		total += odds[kind]
	if total <= 0:
		return standing
	var pick := rng.randi_range(1, total)
	for kind: Weather.Kind in kinds:
		pick -= odds[kind]
		if pick <= 0:
			return kind
	return standing   # unreachable: the walk spends exactly the total


# The weather a mission START stands under, on both hosts. A restart passes the weather it is leaving as
# `kept`, and keeps it (#1509 ruling 2: Retry, Restart and Reset Loadout keep the draw) unless the
# reloaded board no longer offers it. A fresh start passes NONE, so it always draws.
static func at_start(odds: Dictionary[Weather.Kind, int], standing: Weather.Kind, rng: RandomNumberGenerator,
		kept: int = NONE) -> Weather.Kind:
	if kept != NONE and offered(odds).has(kept as Weather.Kind):
		return kept as Weather.Kind
	return draw(odds, standing, rng)


# Why a driver may not name this weather as the draw (the Play API's `weather` argument), or "". A
# drawing board takes any weather it offers; a locked board only its own.
static func pick_block_reason(odds: Dictionary[Weather.Kind, int], standing: Weather.Kind,
		kind: Weather.Kind) -> String:
	if not draws(odds):
		if kind == standing:
			return ""
		return "this board is locked to %s" % Weather.display_name(standing)
	if offered(odds).has(kind):
		return ""
	return "this board draws from %s" % odds_text(odds)


# The set as the player and the dev read it: "Clear 40%, Mist 20%, Rain 40%".
static func odds_text(odds: Dictionary[Weather.Kind, int]) -> String:
	var kinds := offered(odds)
	var total := 0
	for kind: Weather.Kind in kinds:
		total += odds[kind]
	var parts: Array[String] = []
	for kind: Weather.Kind in kinds:
		parts.append("%s %d%%" % [Weather.display_name(kind), roundi(100.0 * odds[kind] / total)])
	return ", ".join(parts)


# The set keyed by kind NAME, for a record read outside this build (telemetry): a stable value.
static func odds_by_name(odds: Dictionary[Weather.Kind, int]) -> Dictionary:
	var named := {}
	for kind: Weather.Kind in offered(odds):
		named[Weather.name_of(kind)] = odds[kind]
	return named
