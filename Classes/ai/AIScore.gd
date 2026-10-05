extends RefCounted
class_name AIScore

# What a resolved plan is worth to one side (#1220): the AI's whole notion of "better", built by
# AITactics._score_plan. Six terms compared LEXICOGRAPHICALLY, never summed -- a lower term speaks
# only when every higher one ties exactly, which is what makes each a ruling rather than a weight.
#
# The order is the dev's (rulings on #117, 2026-10-04/05): a mission-ending kill above everything,
# then removals, squad breaks, saves, damage, and what engaging costs us last. Every term is NET --
# for the side being scored, against it otherwise -- so a marginal is one plan's score minus another.

var mission := 0    # protected units killed while the mission says they must survive (#572)
var removals := 0   # units taken off their feet, per victim
var splits := 0     # units knocked out of their squad (#761)
var saves := 0      # bodies a heal stabilised that nobody could have rescued this turn
var damage := 0     # damage dealt plus HP actually restored; overkill and overheal worth nothing
var taken := 0      # damage our side takes from reactions; LOWER is better


static func of(mission_term: int, removal_term: int, split_term: int, save_term: int, damage_term: int,
		taken_term: int) -> AIScore:
	var out := AIScore.new()
	out.mission = mission_term
	out.removals = removal_term
	out.splits = split_term
	out.saves = save_term
	out.damage = damage_term
	out.taken = taken_term
	return out


static func zero() -> AIScore:
	return AIScore.new()


func minus(other: AIScore) -> AIScore:
	return of(mission - other.mission, removals - other.removals, splits - other.splits,
			saves - other.saves, damage - other.damage, taken - other.taken)


func beats(other: AIScore) -> bool:
	if mission != other.mission:
		return mission > other.mission
	if removals != other.removals:
		return removals > other.removals
	if splits != other.splits:
		return splits > other.splits
	if saves != other.saves:
		return saves > other.saves
	if damage != other.damage:
		return damage > other.damage
	return taken < other.taken


func _to_string() -> String:
	return "(mission %d, removals %d, splits %d, saves %d, damage %d, taken %d)" % [
			mission, removals, splits, saves, damage, taken]
